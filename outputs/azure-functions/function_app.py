"""Azure Functions app — image-upload photo gallery service.

Consolidates the four original AWS Lambda handlers into a single Python v2
programming-model Function App. All routes are HTTP-triggered.
The `api` route prefix is configured in host.json.

Route map (final URL = https://<funcapp>/api/<route>):
    POST   /api/upload                    -> upload_image   (replaces UploadFunction)
    GET    /api/files                     -> list_images    (replaces ListFilesFunction)
    GET    /api/files/{fileId}/view-url   -> get_view_url   (replaces GetViewUrlFunction)
    DELETE /api/files/{fileId}            -> delete_image   (replaces DeleteFileFunction)

Auth pattern:
    DefaultAzureCredential() — resolves to System-assigned Managed Identity in
    Azure (Storage Blob Data Contributor role required on the storage account).
    Locally, set AZURE_TENANT_ID + AZURE_CLIENT_ID + AZURE_CLIENT_SECRET in
    local.settings.json, or run `az login`.

Key migration changes from AWS Lambda:
    - boto3 S3 client          -> azure-storage-blob BlobServiceClient
    - IAM role / access keys   -> DefaultAzureCredential (Managed Identity)
    - S3 pre-signed POST       -> User Delegation SAS (PUT) URL
    - lambda_handler(event, context) -> @app.route decorated async function
    - event['body']            -> req.get_json()
    - event['pathParameters']  -> req.route_params
    - event['queryStringParameters'] -> req.params
    - {'statusCode':200, 'body':...} -> func.HttpResponse(body, status_code=200)
    - BUCKET_NAME env var      -> STORAGE_ACCOUNT_NAME + BLOB_CONTAINER_NAME
    - URL_EXPIRATION env var   -> URL_EXPIRATION (same name, same default 3600)
"""

from __future__ import annotations

import json
import logging
import uuid
from datetime import datetime, timezone

import azure.functions as func
from azure.core.exceptions import ResourceNotFoundError

from shared.blob_helpers import (
    AzureError,
    BlobSasPermissions,
    URL_EXPIRATION,
    get_blob_client,
    get_container_client,
    json_headers,
    make_sas_url,
)

logger = logging.getLogger(__name__)

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

_MAX_LIST_DEFAULT = 50


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _json_response(status: int, payload: dict) -> func.HttpResponse:
    return func.HttpResponse(
        body=json.dumps(payload),
        status_code=status,
        headers=json_headers(),
    )


def _error(status: int, message: str, **extra) -> func.HttpResponse:
    body: dict = {"error": message}
    body.update(extra)
    return _json_response(status, body)


# ---------------------------------------------------------------------------
# 6.1  upload_image  —  POST /api/upload
#      Replaces: UploadFunction (upload_handler.lambda_handler)
#
# AWS flow:  s3.generate_presigned_post(Bucket, Key, Fields, Conditions, ExpiresIn)
#            Returns url + fields dict; SPA uses multipart FormData POST.
#
# Azure flow: generate_blob_sas(... permission=write+create, user_delegation_key=...)
#             Returns a single PUT URL; SPA sends:
#               fetch(uploadUrl, { method:'PUT',
#                                  headers:{ 'x-ms-blob-type':'BlockBlob',
#                                            'Content-Type': fileType,
#                                            'x-ms-meta-uploaddate': ...,
#                                            'x-ms-meta-originalfilename': ... },
#                                  body: file })
# ---------------------------------------------------------------------------
@app.route(route="upload", methods=["POST"])
def upload_image(req: func.HttpRequest) -> func.HttpResponse:
    """Generate a User Delegation SAS PUT URL for uploading a new image blob."""
    try:
        try:
            body = req.get_json()
        except ValueError:
            body = {}

        file_name: str | None = body.get("fileName")
        file_type: str = body.get("fileType", "image/jpeg")
        description: str = body.get("description", "")
        tags: list = body.get("tags", [])

        if not file_name:
            return _error(400, "fileName is required")

        file_id = str(uuid.uuid4())
        timestamp = datetime.now(timezone.utc).isoformat()
        blob_name = f"{file_id}/{file_name}"

        # Metadata replaces x-amz-meta-* S3 object metadata.
        # The SPA must pass these as x-ms-meta-* headers during the PUT.
        metadata: dict[str, str] = {
            "uploaddate": timestamp,
            "originalfilename": file_name,
        }
        if description:
            metadata["description"] = description

        # Blob tags replace S3 object tags (x-amz-tagging).
        blob_tags: dict[str, str] = {}
        if tags:
            for i, tag in enumerate(tags):
                blob_tags[f"tag{i}"] = str(tag)

        # SAS with write=True + create=True allows a single-shot PUT Blob.
        permissions = BlobSasPermissions(write=True, create=True)
        upload_url = make_sas_url(
            blob_name=blob_name,
            permissions=permissions,
            ttl_seconds=URL_EXPIRATION,
            content_type=file_type,
        )

        # Inform the SPA exactly which headers it must include on the PUT.
        required_headers: dict[str, str] = {
            "x-ms-blob-type": "BlockBlob",
            "Content-Type": file_type,
        }
        for key, value in metadata.items():
            required_headers[f"x-ms-meta-{key}"] = value
        if blob_tags:
            required_headers["x-ms-tags"] = "&".join(
                f"{k}={v}" for k, v in blob_tags.items()
            )

        return _json_response(
            200,
            {
                "uploadUrl": upload_url,
                "uploadMethod": "PUT",
                "requiredHeaders": required_headers,
                "fileId": file_id,
                "blobName": blob_name,
                "expiresIn": URL_EXPIRATION,
                "message": (
                    "Use HTTP PUT to upload the file body to uploadUrl "
                    "with the given requiredHeaders."
                ),
            },
        )

    except AzureError as e:
        logger.exception("Azure SDK error generating upload SAS")
        return _error(500, "Failed to generate upload URL", details=str(e))
    except Exception as e:
        logger.exception("Unhandled error in upload_image")
        return _error(500, "Internal server error", details=str(e))


# ---------------------------------------------------------------------------
# 6.2  list_images  —  GET /api/files
#      Replaces: ListFilesFunction (list_handler.lambda_handler)
#
# AWS flow:  s3.list_objects_v2(Bucket, Prefix, MaxKeys)
#            s3.head_object(Bucket, Key) per file for metadata
#            s3.generate_presigned_url('get_object', ...) per file
#
# Azure flow: container_client.list_blobs(name_starts_with=prefix,
#                                         include=['metadata','tags'])
#             — metadata comes back inline; no extra head request needed
#             make_sas_url(blob_name, BlobSasPermissions(read=True)) per file
# ---------------------------------------------------------------------------
@app.route(route="files", methods=["GET"])
def list_images(req: func.HttpRequest) -> func.HttpResponse:
    """List blobs in the images container with per-blob read SAS view URLs."""
    try:
        prefix: str | None = req.params.get("prefix") or None
        try:
            max_keys = int(req.params.get("maxKeys", _MAX_LIST_DEFAULT))
        except (TypeError, ValueError):
            max_keys = _MAX_LIST_DEFAULT

        container = get_container_client()

        files: list[dict] = []
        truncated = False
        iterator = container.list_blobs(
            name_starts_with=prefix, include=["metadata", "tags"]
        )

        for index, blob in enumerate(iterator):
            if index >= max_keys:
                truncated = True
                break

            blob_name: str = blob.name
            # Skip folder-marker pseudo-blobs (mirroring the AWS handler).
            if blob_name.endswith("/"):
                continue

            metadata: dict = blob.metadata or {}
            file_name = metadata.get("originalfilename", blob_name.split("/")[-1])

            # Tags were stored as blob index tags (x-ms-tags); retrieve values.
            tags_dict: dict = getattr(blob, "tags", None) or {}
            tags = list(tags_dict.values())

            content_type = "unknown"
            if blob.content_settings and blob.content_settings.content_type:
                content_type = blob.content_settings.content_type

            last_modified_iso = (
                blob.last_modified.isoformat() if blob.last_modified else None
            )

            try:
                view_url = make_sas_url(
                    blob_name=blob_name,
                    permissions=BlobSasPermissions(read=True),
                    ttl_seconds=URL_EXPIRATION,
                )
            except AzureError:
                logger.exception("Failed to generate SAS for blob %s", blob_name)
                continue

            files.append(
                {
                    # fileId is the UUID prefix (the part before the first "/"),
                    # matching the original AWS handler's s3Key.split('/')[0] logic.
                    "fileId": blob_name.split("/")[0] if "/" in blob_name else blob_name,
                    "blobName": blob_name,
                    "fileName": file_name,
                    "fileType": content_type,
                    "size": blob.size,
                    "lastModified": last_modified_iso,
                    "uploadDate": metadata.get("uploaddate", last_modified_iso),
                    "description": metadata.get("description", ""),
                    "tags": tags,
                    "viewUrl": view_url,
                    "urlExpiresIn": URL_EXPIRATION,
                }
            )

        return _json_response(
            200,
            {"files": files, "count": len(files), "isTruncated": truncated},
        )

    except AzureError as e:
        logger.exception("Azure SDK error listing blobs")
        return _error(500, "Failed to retrieve files", details=str(e))
    except Exception as e:
        logger.exception("Unhandled error in list_images")
        return _error(500, "Internal server error", details=str(e))


# ---------------------------------------------------------------------------
# 6.3  get_view_url  —  GET /api/files/{fileId}/view-url
#      Replaces: GetViewUrlFunction (view_handler.lambda_handler)
#
# AWS flow:  s3.list_objects_v2(Bucket, Prefix=f"{file_id}/", MaxKeys=1)
#            s3.head_object(Bucket, Key) for metadata
#            s3.generate_presigned_url('get_object', Params, ExpiresIn)
#
# Azure flow: container_client.list_blobs(name_starts_with=f"{file_id}/",
#                                         include=['metadata'])
#             — take first match; metadata inline; no extra head request
#             make_sas_url(blob_name, BlobSasPermissions(read=True))
# ---------------------------------------------------------------------------
@app.route(route="files/{fileId}/view-url", methods=["GET"])
def get_view_url(req: func.HttpRequest) -> func.HttpResponse:
    """Return a read-only SAS view URL for the first blob under {fileId}/."""
    try:
        file_id: str | None = req.route_params.get("fileId")
        if not file_id:
            return _error(400, "fileId is required")

        container = get_container_client()
        match = next(
            iter(
                container.list_blobs(
                    name_starts_with=f"{file_id}/", include=["metadata"]
                )
            ),
            None,
        )
        if match is None:
            return _error(404, "File not found")

        blob_name: str = match.name
        metadata: dict = match.metadata or {}

        content_type = "unknown"
        if match.content_settings and match.content_settings.content_type:
            content_type = match.content_settings.content_type

        last_modified_iso = (
            match.last_modified.isoformat() if match.last_modified else None
        )

        view_url = make_sas_url(
            blob_name=blob_name,
            permissions=BlobSasPermissions(read=True),
            ttl_seconds=URL_EXPIRATION,
        )

        return _json_response(
            200,
            {
                "fileId": file_id,
                "blobName": blob_name,
                "fileName": metadata.get(
                    "originalfilename", blob_name.split("/")[-1]
                ),
                "fileType": content_type,
                "description": metadata.get("description", ""),
                "uploadDate": metadata.get("uploaddate", last_modified_iso),
                "size": match.size,
                "viewUrl": view_url,
                "expiresIn": URL_EXPIRATION,
            },
        )

    except AzureError as e:
        logger.exception("Azure SDK error generating view SAS")
        return _error(500, "Failed to generate view URL", details=str(e))
    except Exception as e:
        logger.exception("Unhandled error in get_view_url")
        return _error(500, "Internal server error", details=str(e))


# ---------------------------------------------------------------------------
# 6.4  delete_image  —  DELETE /api/files/{fileId}
#      Replaces: DeleteFileFunction (delete_handler.lambda_handler)
#
# AWS flow:  s3.list_objects_v2(Bucket, Prefix=f"{file_id}/")
#            s3.delete_object(Bucket, Key) per object in response['Contents']
#
# Azure flow: container_client.list_blobs(name_starts_with=f"{file_id}/")
#             blob_client.delete_blob(delete_snapshots="include") per blob
#             ResourceNotFoundError caught and treated as already-deleted (idempotent).
# ---------------------------------------------------------------------------
@app.route(route="files/{fileId}", methods=["DELETE"])
def delete_image(req: func.HttpRequest) -> func.HttpResponse:
    """Delete every blob whose name starts with {fileId}/."""
    try:
        file_id: str | None = req.route_params.get("fileId")
        if not file_id:
            return _error(400, "fileId is required")

        container = get_container_client()
        matches = list(container.list_blobs(name_starts_with=f"{file_id}/"))

        if not matches:
            return _error(404, "File not found")

        deleted_keys: list[str] = []
        for blob in matches:
            try:
                get_blob_client(blob.name).delete_blob(delete_snapshots="include")
                deleted_keys.append(blob.name)
            except ResourceNotFoundError:
                # Blob already gone — treat as success (idempotent delete).
                logger.info("Blob already deleted: %s", blob.name)

        return _json_response(
            200,
            {
                "message": "File(s) deleted successfully",
                "fileId": file_id,
                "deletedKeys": deleted_keys,
            },
        )

    except AzureError as e:
        logger.exception("Azure SDK error deleting blob(s)")
        return _error(500, "Failed to delete file", details=str(e))
    except Exception as e:
        logger.exception("Unhandled error in delete_image")
        return _error(500, "Internal server error", details=str(e))
