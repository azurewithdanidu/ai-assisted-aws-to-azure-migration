"""Azure Functions app — image-upload service.

Consolidates the four original AWS Lambda handlers into a single Python v2
programming-model Function App. All routes are HTTP-triggered with
`auth_level=FUNCTION`; the `api` route prefix is configured in `host.json`.

Route map (final URL = `https://<funcapp>/api/<route>`):
    POST   /upload                       -> upload  (UploadFunction)
    GET    /files                        -> list_files (ListFilesFunction)
    GET    /files/{fileId}/view-url      -> get_view_url (GetViewUrlFunction)
    DELETE /files/{fileId}               -> delete_file (DeleteFileFunction)
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
    URL_EXPIRATION_SECONDS,
    get_blob_client,
    get_container_client,
    json_headers,
    make_sas_url,
)

logger = logging.getLogger(__name__)

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

MAX_LIST_RESULTS_DEFAULT = 50


def _json_response(status: int, payload: dict) -> func.HttpResponse:
    return func.HttpResponse(
        body=json.dumps(payload),
        status_code=status,
        headers=json_headers(),
    )


def _error(status: int, message: str, **extra) -> func.HttpResponse:
    body = {"error": message}
    body.update(extra)
    return _json_response(status, body)


# ---------------------------------------------------------------------------
# 6.1  UploadFunction  ->  POST /api/upload
# ---------------------------------------------------------------------------
@app.route(route="upload", methods=["POST"])
def upload(req: func.HttpRequest) -> func.HttpResponse:
    """Generate a User Delegation SAS URL for uploading a new image blob."""
    try:
        try:
            body = req.get_json()
        except ValueError:
            body = {}

        file_name = body.get("fileName")
        file_type = body.get("fileType", "image/jpeg")
        description = body.get("description", "")
        tags = body.get("tags", [])

        if not file_name:
            return _error(400, "fileName is required")

        file_id = str(uuid.uuid4())
        timestamp = datetime.now(timezone.utc).isoformat()
        blob_name = f"{file_id}/{file_name}"

        metadata = {
            "uploaddate": timestamp,
            "originalfilename": file_name,
        }
        if description:
            metadata["description"] = description

        blob_tags = {}
        if tags:
            for i, tag in enumerate(tags):
                blob_tags[f"tag{i}"] = str(tag)

        # SAS permissions: create + write are required for a single-shot PUT Blob.
        permissions = BlobSasPermissions(write=True, create=True)
        upload_url = make_sas_url(
            blob_name=blob_name,
            permissions=permissions,
            ttl_seconds=URL_EXPIRATION_SECONDS,
            content_type=file_type,
        )

        # Headers the client MUST send when PUT-ing the blob with this SAS.
        required_headers = {
            "x-ms-blob-type": "BlockBlob",
            "x-ms-blob-content-type": file_type,
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
                "expiresIn": URL_EXPIRATION_SECONDS,
                "message": (
                    "Use HTTP PUT to upload the file body to uploadUrl with the "
                    "given requiredHeaders."
                ),
            },
        )

    except AzureError as e:
        logger.exception("Azure SDK error generating upload SAS")
        return _error(500, "Failed to generate upload URL", details=str(e))
    except Exception as e:  # pragma: no cover
        logger.exception("Unhandled error in upload")
        return _error(500, "Internal server error", details=str(e))


# ---------------------------------------------------------------------------
# 6.2  ListFilesFunction  ->  GET /api/files
# ---------------------------------------------------------------------------
@app.route(route="files", methods=["GET"])
def list_files(req: func.HttpRequest) -> func.HttpResponse:
    """List blobs in the images container with per-blob read SAS view URLs."""
    try:
        prefix = req.params.get("prefix", "") or None
        try:
            max_keys = int(req.params.get("maxKeys", MAX_LIST_RESULTS_DEFAULT))
        except (TypeError, ValueError):
            max_keys = MAX_LIST_RESULTS_DEFAULT

        container = get_container_client()

        files = []
        iterator = container.list_blobs(
            name_starts_with=prefix, include=["metadata", "tags"]
        )

        truncated = False
        for index, blob in enumerate(iterator):
            if index >= max_keys:
                truncated = True
                break

            blob_name = blob.name
            if blob_name.endswith("/"):
                continue

            metadata = blob.metadata or {}
            file_name = metadata.get(
                "originalfilename", blob_name.split("/")[-1]
            )

            tags_dict = getattr(blob, "tags", None) or {}
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
                    ttl_seconds=URL_EXPIRATION_SECONDS,
                )
            except AzureError:
                logger.exception("Failed to generate SAS for %s", blob_name)
                continue

            files.append(
                {
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
                    "urlExpiresIn": URL_EXPIRATION_SECONDS,
                }
            )

        return _json_response(
            200,
            {"files": files, "count": len(files), "isTruncated": truncated},
        )

    except AzureError as e:
        logger.exception("Azure SDK error listing blobs")
        return _error(500, "Failed to retrieve files", details=str(e))
    except Exception as e:  # pragma: no cover
        logger.exception("Unhandled error in list_files")
        return _error(500, "Internal server error", details=str(e))


# ---------------------------------------------------------------------------
# 6.3  GetViewUrlFunction  ->  GET /api/files/{fileId}/view-url
# ---------------------------------------------------------------------------
@app.route(route="files/{fileId}/view-url", methods=["GET"])
def get_view_url(req: func.HttpRequest) -> func.HttpResponse:
    """Return a read-only SAS view URL for the first blob under `{fileId}/`."""
    try:
        file_id = req.route_params.get("fileId")
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

        blob_name = match.name
        metadata = match.metadata or {}

        content_type = "unknown"
        if match.content_settings and match.content_settings.content_type:
            content_type = match.content_settings.content_type

        last_modified_iso = (
            match.last_modified.isoformat() if match.last_modified else None
        )

        view_url = make_sas_url(
            blob_name=blob_name,
            permissions=BlobSasPermissions(read=True),
            ttl_seconds=URL_EXPIRATION_SECONDS,
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
                "expiresIn": URL_EXPIRATION_SECONDS,
            },
        )

    except AzureError as e:
        logger.exception("Azure SDK error generating view SAS")
        return _error(500, "Failed to generate view URL", details=str(e))
    except Exception as e:  # pragma: no cover
        logger.exception("Unhandled error in get_view_url")
        return _error(500, "Internal server error", details=str(e))


# ---------------------------------------------------------------------------
# 6.4  DeleteFileFunction  ->  DELETE /api/files/{fileId}
# ---------------------------------------------------------------------------
@app.route(route="files/{fileId}", methods=["DELETE"])
def delete_file(req: func.HttpRequest) -> func.HttpResponse:
    """Delete every blob whose name starts with `{fileId}/`."""
    try:
        file_id = req.route_params.get("fileId")
        if not file_id:
            return _error(400, "fileId is required")

        container = get_container_client()
        matches = list(container.list_blobs(name_starts_with=f"{file_id}/"))

        if not matches:
            return _error(404, "File not found")

        deleted_keys = []
        for blob in matches:
            try:
                get_blob_client(blob.name).delete_blob(delete_snapshots="include")
                deleted_keys.append(blob.name)
            except ResourceNotFoundError:
                logger.info("Blob already gone: %s", blob.name)

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
    except Exception as e:  # pragma: no cover
        logger.exception("Unhandled error in delete_file")
        return _error(500, "Internal server error", details=str(e))
