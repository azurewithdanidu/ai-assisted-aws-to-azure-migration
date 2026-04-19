import azure.functions as func
import itertools
import json
import logging
import os
import uuid
from datetime import datetime, timedelta, timezone

from azure.identity import DefaultAzureCredential
from azure.storage.blob import (
    BlobServiceClient,
    BlobSasPermissions,
    generate_blob_sas,
)

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

# ---------------------------------------------------------------------------
# Configuration — read from environment (NEVER use CONTAINER_NAME; it is
# reserved by the Azure Functions host).
# ---------------------------------------------------------------------------
BLOB_CONTAINER_NAME: str = os.environ["BLOB_CONTAINER_NAME"]
STORAGE_ACCOUNT_NAME: str = os.environ["AZURE_STORAGE_ACCOUNT_NAME"]
URL_EXPIRATION: int = int(os.environ.get("URL_EXPIRATION", "3600"))

# Single credential instance reused across invocations (thread-safe).
_credential = DefaultAzureCredential()

# CORS header included in every response for local-dev compatibility.
# Production CORS is configured at siteConfig.cors in the Bicep template.
CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
}


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def _blob_service_client() -> BlobServiceClient:
    return BlobServiceClient(
        account_url=f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net",
        credential=_credential,
    )


def _get_udk_and_expiry(bsc: BlobServiceClient, expiry_seconds: int):
    """
    Obtain a UserDelegationKey (UDK) and its expiry datetime.
    The UDK is used in place of a storage account key so that no secret
    ever appears in code or environment variables.
    The calling identity must have the 'Storage Blob Delegator' role on
    the storage account.
    """
    start = datetime.now(timezone.utc)
    expiry = start + timedelta(seconds=expiry_seconds)
    udk = bsc.get_user_delegation_key(start, expiry)
    return udk, expiry


def _make_sas_url(
    blob_name: str,
    permission: BlobSasPermissions,
    udk,
    expiry: datetime,
) -> str:
    """Build a fully-qualified HTTPS SAS URL for *blob_name*."""
    sas_token = generate_blob_sas(
        account_name=STORAGE_ACCOUNT_NAME,
        container_name=BLOB_CONTAINER_NAME,
        blob_name=blob_name,
        user_delegation_key=udk,
        permission=permission,
        expiry=expiry,
    )
    return (
        f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net"
        f"/{BLOB_CONTAINER_NAME}/{blob_name}?{sas_token}"
    )


# ---------------------------------------------------------------------------
# POST /api/upload  →  upload_image
# Replaces: app-code/lambda/upload/upload_handler.py  (S3 presigned POST)
# ---------------------------------------------------------------------------

@app.route(route="upload", methods=["POST"])
def upload_image(req: func.HttpRequest) -> func.HttpResponse:
    """
    Return a SAS write URL so the caller can PUT the image directly to
    Azure Blob Storage.  This replaces the S3 generate_presigned_post flow;
    the client must use an HTTP PUT (not a multipart POST) to upload.

    Request body (JSON):
      fileName    – required; original file name (e.g. "photo.jpg")
      fileType    – MIME type (default: "image/jpeg")
      description – optional free-text description
      tags        – optional list of tag strings (stored as blob tags)
    """
    try:
        try:
            body = json.loads(req.get_body().decode("utf-8") or "{}")
        except (ValueError, UnicodeDecodeError):
            body = {}

        file_name: str = body.get("fileName", "")
        file_type: str = body.get("fileType", "image/jpeg")
        description: str = body.get("description", "")

        if not file_name:
            return func.HttpResponse(
                json.dumps({"error": "fileName is required"}),
                status_code=400,
                headers=CORS_HEADERS,
            )

        file_id = str(uuid.uuid4())
        timestamp = datetime.now(timezone.utc).isoformat()
        blob_name = f"{file_id}/{file_name}"

        bsc = _blob_service_client()
        udk, expiry = _get_udk_and_expiry(bsc, URL_EXPIRATION)
        upload_url = _make_sas_url(
            blob_name, BlobSasPermissions(write=True, create=True), udk, expiry
        )

        # Metadata the client should attach as x-ms-meta-* headers on the PUT
        metadata_to_set = {
            "uploaddate": timestamp,
            "originalfilename": file_name,
        }
        if description:
            metadata_to_set["description"] = description

        return func.HttpResponse(
            json.dumps({
                "uploadUrl": upload_url,
                "uploadMethod": "PUT",
                "fileId": file_id,
                "blobName": blob_name,
                "expiresIn": URL_EXPIRATION,
                "contentType": file_type,
                "metadata": metadata_to_set,
                "message": (
                    "PUT the file body to uploadUrl. "
                    "Required headers: x-ms-blob-type: BlockBlob, "
                    "Content-Type: <MIME type>. "
                    "Optional: set x-ms-meta-* headers to persist file metadata."
                ),
            }),
            status_code=200,
            headers=CORS_HEADERS,
        )

    except Exception:
        logging.exception("upload_image failed")
        return func.HttpResponse(
            json.dumps({"error": "Failed to generate upload URL"}),
            status_code=500,
            headers=CORS_HEADERS,
        )


# ---------------------------------------------------------------------------
# GET /api/files  →  list_files
# Replaces: app-code/lambda/list/list_handler.py  (S3 list_objects_v2)
# ---------------------------------------------------------------------------

@app.route(route="files", methods=["GET"])
def list_files(req: func.HttpRequest) -> func.HttpResponse:
    """
    List blobs in the container (up to *maxKeys*) with per-blob SAS read URLs.

    Query parameters:
      prefix  – name prefix filter (optional)
      maxKeys – maximum items to return (default 50)
    """
    try:
        prefix: str = req.params.get("prefix", "")
        try:
            max_keys = int(req.params.get("maxKeys", "50"))
        except ValueError:
            max_keys = 50

        bsc = _blob_service_client()
        container_client = bsc.get_container_client(BLOB_CONTAINER_NAME)

        # Fetch max_keys+1 entries so we can detect truncation without a
        # full container scan.
        blobs_iter = container_client.list_blobs(
            name_starts_with=prefix if prefix else None,
        )
        sampled = list(itertools.islice(blobs_iter, max_keys + 1))
        is_truncated = len(sampled) > max_keys
        blobs_to_process = [b for b in sampled[:max_keys] if not b.name.endswith("/")]

        # Obtain one UDK shared across all per-blob SAS-URL generations.
        udk, expiry = _get_udk_and_expiry(bsc, URL_EXPIRATION)

        files = []
        for blob in blobs_to_process:
            blob_name = blob.name
            try:
                blob_client = container_client.get_blob_client(blob_name)
                props = blob_client.get_blob_properties()
                metadata = props.metadata or {}

                view_url = _make_sas_url(
                    blob_name, BlobSasPermissions(read=True), udk, expiry
                )

                try:
                    raw_tags = blob_client.get_blob_tags() or {}
                    tags = list(raw_tags.values())
                except Exception:
                    tags = []

                files.append({
                    "fileId": blob_name.split("/")[0] if "/" in blob_name else blob_name,
                    "blobName": blob_name,
                    "fileName": metadata.get(
                        "originalfilename", blob_name.split("/")[-1]
                    ),
                    "fileType": props.content_settings.content_type or "unknown",
                    "size": blob.size,
                    "lastModified": blob.last_modified.isoformat(),
                    "uploadDate": metadata.get(
                        "uploaddate", blob.last_modified.isoformat()
                    ),
                    "description": metadata.get("description", ""),
                    "tags": tags,
                    "viewUrl": view_url,
                    "urlExpiresIn": URL_EXPIRATION,
                })
            except Exception:
                logging.warning("Skipping blob %s", blob_name, exc_info=True)

        return func.HttpResponse(
            json.dumps({
                "files": files,
                "count": len(files),
                "isTruncated": is_truncated,
            }),
            status_code=200,
            headers=CORS_HEADERS,
        )

    except Exception:
        logging.exception("list_files failed")
        return func.HttpResponse(
            json.dumps({"error": "Failed to retrieve files"}),
            status_code=500,
            headers=CORS_HEADERS,
        )


# ---------------------------------------------------------------------------
# GET /api/files/{fileId}/view-url  →  get_view_url
# Replaces: app-code/lambda/view/view_handler.py  (S3 presigned GET)
# ---------------------------------------------------------------------------

@app.route(route="files/{fileId}/view-url", methods=["GET"])
def get_view_url(req: func.HttpRequest) -> func.HttpResponse:
    """
    Return a SAS read URL for the blob identified by *fileId*.

    Route parameters:
      fileId – UUID that forms the name prefix of the target blob
               (e.g. the blob "abc123/photo.jpg" has fileId "abc123")
    """
    try:
        file_id = req.route_params.get("fileId", "")
        if not file_id:
            return func.HttpResponse(
                json.dumps({"error": "fileId is required"}),
                status_code=400,
                headers=CORS_HEADERS,
            )

        bsc = _blob_service_client()
        container_client = bsc.get_container_client(BLOB_CONTAINER_NAME)

        # Take only the first match — mirrors Lambda's MaxKeys=1 behaviour.
        blobs = list(
            itertools.islice(
                container_client.list_blobs(name_starts_with=f"{file_id}/"), 1
            )
        )
        if not blobs:
            return func.HttpResponse(
                json.dumps({"error": "File not found"}),
                status_code=404,
                headers=CORS_HEADERS,
            )

        blob = blobs[0]
        blob_name = blob.name
        blob_client = container_client.get_blob_client(blob_name)
        props = blob_client.get_blob_properties()
        metadata = props.metadata or {}

        udk, expiry = _get_udk_and_expiry(bsc, URL_EXPIRATION)
        view_url = _make_sas_url(blob_name, BlobSasPermissions(read=True), udk, expiry)

        return func.HttpResponse(
            json.dumps({
                "fileId": file_id,
                "blobName": blob_name,
                "fileName": metadata.get(
                    "originalfilename", blob_name.split("/")[-1]
                ),
                "fileType": props.content_settings.content_type or "unknown",
                "description": metadata.get("description", ""),
                "uploadDate": metadata.get(
                    "uploaddate", blob.last_modified.isoformat()
                ),
                "size": blob.size,
                "viewUrl": view_url,
                "expiresIn": URL_EXPIRATION,
            }),
            status_code=200,
            headers=CORS_HEADERS,
        )

    except Exception:
        logging.exception("get_view_url failed")
        return func.HttpResponse(
            json.dumps({"error": "Failed to generate view URL"}),
            status_code=500,
            headers=CORS_HEADERS,
        )


# ---------------------------------------------------------------------------
# DELETE /api/files/{fileId}  →  delete_file
# Replaces: app-code/lambda/delete/delete_handler.py  (S3 delete_object)
# ---------------------------------------------------------------------------

@app.route(route="files/{fileId}", methods=["DELETE"])
def delete_file(req: func.HttpRequest) -> func.HttpResponse:
    """
    Delete all blobs whose name begins with '{fileId}/'.

    Route parameters:
      fileId – UUID prefix of the blob(s) to delete
    """
    try:
        file_id = req.route_params.get("fileId", "")
        if not file_id:
            return func.HttpResponse(
                json.dumps({"error": "fileId is required"}),
                status_code=400,
                headers=CORS_HEADERS,
            )

        bsc = _blob_service_client()
        container_client = bsc.get_container_client(BLOB_CONTAINER_NAME)

        blobs = list(
            container_client.list_blobs(name_starts_with=f"{file_id}/")
        )
        if not blobs:
            return func.HttpResponse(
                json.dumps({"error": "File not found"}),
                status_code=404,
                headers=CORS_HEADERS,
            )

        deleted_blobs = []
        for blob in blobs:
            container_client.get_blob_client(blob.name).delete_blob()
            deleted_blobs.append(blob.name)

        return func.HttpResponse(
            json.dumps({
                "message": "File(s) deleted successfully",
                "fileId": file_id,
                "deletedBlobs": deleted_blobs,
            }),
            status_code=200,
            headers=CORS_HEADERS,
        )

    except Exception:
        logging.exception("delete_file failed")
        return func.HttpResponse(
            json.dumps({"error": "Failed to delete file"}),
            status_code=500,
            headers=CORS_HEADERS,
        )
