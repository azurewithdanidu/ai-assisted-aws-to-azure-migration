"""
function_app.py — Azure Functions (Python v2 programming model)
Image Upload Service — refactored from 4 AWS Lambda functions

AWS Lambda → Azure Functions mapping:
  upload_handler.lambda_handler   → upload_function   POST /api/upload
  list_handler.lambda_handler     → list_files_function GET /api/files
  view_handler.lambda_handler     → get_view_url_function GET /api/files/{fileId}/view-url
  delete_handler.lambda_handler   → delete_file_function DELETE /api/files/{fileId}

Auth:
  AWS IAM SigV4 → Azure Function key (x-functions-key header)

Storage:
  boto3 S3 → azure-storage-blob with DefaultAzureCredential (Managed Identity)
  S3 presigned POST → Azure Blob SAS URL (PUT method)
  S3 presigned GET  → Azure Blob SAS URL (read permission)
  S3 object metadata → Azure Blob metadata (x-ms-meta-* headers)
  S3 object tags     → x-ms-meta-tags (comma-separated, stored in blob metadata)

Environment variables:
  BUCKET_NAME            → STORAGE_ACCOUNT_NAME + CONTAINER_NAME
  URL_EXPIRATION         → URL_EXPIRATION_SECONDS
"""

import json
import logging
import os
import uuid
from datetime import datetime, timedelta, timezone

import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobSasPermissions, BlobServiceClient, generate_blob_sas

# =============================================================================
# App and environment configuration
# =============================================================================

app = func.FunctionApp()

STORAGE_ACCOUNT_NAME = os.environ["STORAGE_ACCOUNT_NAME"]
CONTAINER_NAME = os.environ.get("BLOB_CONTAINER_NAME", "images")
URL_EXPIRATION_SECONDS = int(os.environ.get("URL_EXPIRATION_SECONDS", "3600"))

# Shared CORS + JSON headers for all responses
RESPONSE_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, x-functions-key",
}

# =============================================================================
# Helpers
# =============================================================================


def _blob_service_client() -> BlobServiceClient:
    """Create BlobServiceClient using Managed Identity (DefaultAzureCredential).
    Replaces: boto3.client('s3') with access keys / IAM role.
    """
    return BlobServiceClient(
        account_url=f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net",
        credential=DefaultAzureCredential(),
    )


def _get_user_delegation_key(client: BlobServiceClient, expiry: datetime):
    """Get a user-delegation key for SAS generation via Managed Identity.
    Replaces: account-key-based presigned URL signing.
    """
    start = datetime.now(timezone.utc) - timedelta(minutes=5)  # 5-min buffer
    return client.get_user_delegation_key(start, expiry)


def _sas_url(blob_name: str, permission: BlobSasPermissions, expiry: datetime, udk) -> str:
    """Generate a full Azure Blob SAS URL.
    Replaces: s3_client.generate_presigned_url() / generate_presigned_post().
    """
    token = generate_blob_sas(
        account_name=STORAGE_ACCOUNT_NAME,
        container_name=CONTAINER_NAME,
        blob_name=blob_name,
        user_delegation_key=udk,
        permission=permission,
        expiry=expiry,
    )
    return (
        f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net"
        f"/{CONTAINER_NAME}/{blob_name}?{token}"
    )


def _error(message: str, details: str = "", status: int = 500) -> func.HttpResponse:
    body = {"error": message}
    if details:
        body["details"] = details
    return func.HttpResponse(json.dumps(body), status_code=status, headers=RESPONSE_HEADERS)


def _options_response() -> func.HttpResponse:
    """Return 200 for CORS preflight."""
    return func.HttpResponse(status_code=200, headers=RESPONSE_HEADERS)


# =============================================================================
# POST /api/upload
# Returns an Azure Blob SAS URL for direct PUT upload + required headers.
#
# AWS equivalent: upload_handler.py
#   s3.generate_presigned_post()  →  SAS URL with write+create permission
#   Presigned POST (multipart)    →  SAS URL (client PUTs file directly)
#   S3 object metadata            →  requiredHeaders (x-ms-meta-* / x-ms-blob-type)
# =============================================================================


@app.route(route="upload", methods=["POST", "OPTIONS"], auth_level=func.AuthLevel.FUNCTION)
def upload_function(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return _options_response()

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
            return _error("fileName is required", status=400)

        # Replaces: uuid4() file_id + S3 key pattern "{file_id}/{file_name}"
        file_id = str(uuid.uuid4())
        timestamp = datetime.now(timezone.utc).isoformat()
        blob_name = f"{file_id}/{file_name}"

        client = _blob_service_client()
        expiry = datetime.now(timezone.utc) + timedelta(seconds=URL_EXPIRATION_SECONDS)
        udk = _get_user_delegation_key(client, expiry)

        # Replaces: s3.generate_presigned_post()
        # Azure uses a SAS URL with PUT (not multipart POST like S3)
        upload_url = _sas_url(blob_name, BlobSasPermissions(write=True, create=True), expiry, udk)

        return func.HttpResponse(
            json.dumps(
                {
                    # Client PUTs file body to this URL (replaces S3 presigned POST endpoint)
                    "uploadUrl": upload_url,
                    "fileId": file_id,
                    "blobName": blob_name,
                    "expiresIn": URL_EXPIRATION_SECONDS,
                    # Client must include these headers in the PUT request to Blob Storage
                    # Replaces: presigned POST 'fields' dict (Content-Type, x-amz-meta-*)
                    "requiredHeaders": {
                        "x-ms-blob-type": "BlockBlob",
                        "Content-Type": file_type,
                        "x-ms-meta-originalfilename": file_name,
                        "x-ms-meta-uploaddate": timestamp,
                        "x-ms-meta-description": description,
                        # Replaces: S3 object tagging (x-amz-tagging)
                        "x-ms-meta-tags": ",".join(tags) if tags else "",
                    },
                    "message": (
                        "PUT the file body directly to uploadUrl. "
                        "Include all requiredHeaders in the PUT request."
                    ),
                }
            ),
            status_code=200,
            headers=RESPONSE_HEADERS,
        )

    except Exception as exc:
        logging.error("upload_function error: %s", exc)
        return _error("Failed to generate upload URL", str(exc))


# =============================================================================
# GET /api/files
# Lists blobs with pre-signed view URLs and metadata.
#
# AWS equivalent: list_handler.py
#   s3.list_objects_v2()          →  container_client.list_blobs()
#   s3.head_object()              →  metadata included via include=['metadata']
#   s3.generate_presigned_url()   →  SAS URL with read permission
#   s3.get_object_tagging()       →  x-ms-meta-tags blob metadata (no extra call needed)
# =============================================================================


@app.route(route="files", methods=["GET", "OPTIONS"], auth_level=func.AuthLevel.FUNCTION)
def list_files_function(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return _options_response()

    try:
        # Replaces: queryStringParameters prefix + MaxKeys
        prefix = req.params.get("prefix", "")
        max_results = int(req.params.get("maxKeys", "50"))

        client = _blob_service_client()
        container_client = client.get_container_client(CONTAINER_NAME)

        expiry = datetime.now(timezone.utc) + timedelta(seconds=URL_EXPIRATION_SECONDS)
        udk = _get_user_delegation_key(client, expiry)

        list_kwargs: dict = {"include": ["metadata"]}
        if prefix:
            # Replaces: Prefix= in list_objects_v2
            list_kwargs["name_starts_with"] = prefix

        # Replaces: s3.list_objects_v2() → response['Contents']
        blobs = list(container_client.list_blobs(**list_kwargs))[:max_results]

        files = []
        for blob in blobs:
            blob_name = blob.name
            # Skip folder markers (same as original Lambda)
            if blob_name.endswith("/"):
                continue

            metadata = blob.metadata or {}
            file_name = metadata.get("originalfilename", blob_name.split("/")[-1])

            # Replaces: s3.get_object_tagging() — tags stored in blob metadata
            tags_raw = metadata.get("tags", "")
            tags = [t for t in tags_raw.split(",") if t] if tags_raw else []

            content_type = "unknown"
            if blob.content_settings and blob.content_settings.content_type:
                content_type = blob.content_settings.content_type

            last_modified_iso = (
                blob.last_modified.isoformat() if blob.last_modified else ""
            )

            # Replaces: s3.generate_presigned_url('get_object')
            view_url = _sas_url(blob_name, BlobSasPermissions(read=True), expiry, udk)

            files.append(
                {
                    # Replaces: s3_key.split('/')[0] → file_id prefix
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

        return func.HttpResponse(
            json.dumps(
                {
                    "files": files,
                    "count": len(files),
                    "isTruncated": False,
                }
            ),
            status_code=200,
            headers=RESPONSE_HEADERS,
        )

    except Exception as exc:
        logging.error("list_files_function error: %s", exc)
        return _error("Failed to retrieve files", str(exc))


# =============================================================================
# GET /api/files/{fileId}/view-url
# Returns a pre-signed read URL for a specific blob.
#
# AWS equivalent: view_handler.py
#   s3.list_objects_v2(Prefix=f"{file_id}/", MaxKeys=1) → list_blobs(name_starts_with=)
#   s3.head_object()                                     → metadata from list
#   s3.generate_presigned_url('get_object')              → SAS URL read
# =============================================================================


@app.route(
    route="files/{fileId}/view-url",
    methods=["GET", "OPTIONS"],
    auth_level=func.AuthLevel.FUNCTION,
)
def get_view_url_function(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return _options_response()

    try:
        file_id = req.route_params.get("fileId")
        if not file_id:
            return _error("fileId is required", status=400)

        client = _blob_service_client()
        container_client = client.get_container_client(CONTAINER_NAME)

        # Replaces: s3.list_objects_v2(Bucket=..., Prefix=f"{file_id}/", MaxKeys=1)
        blobs = list(
            container_client.list_blobs(
                name_starts_with=f"{file_id}/",
                include=["metadata"],
            )
        )

        if not blobs:
            return _error("File not found", status=404)

        blob = blobs[0]
        blob_name = blob.name
        metadata = blob.metadata or {}

        expiry = datetime.now(timezone.utc) + timedelta(seconds=URL_EXPIRATION_SECONDS)
        udk = _get_user_delegation_key(client, expiry)

        # Replaces: s3.generate_presigned_url('get_object')
        view_url = _sas_url(blob_name, BlobSasPermissions(read=True), expiry, udk)

        content_type = "unknown"
        if blob.content_settings and blob.content_settings.content_type:
            content_type = blob.content_settings.content_type

        last_modified_iso = blob.last_modified.isoformat() if blob.last_modified else ""

        return func.HttpResponse(
            json.dumps(
                {
                    "fileId": file_id,
                    "blobName": blob_name,
                    "fileName": metadata.get(
                        "originalfilename", blob_name.split("/")[-1]
                    ),
                    "fileType": content_type,
                    "description": metadata.get("description", ""),
                    "uploadDate": metadata.get("uploaddate", last_modified_iso),
                    "size": blob.size,
                    "viewUrl": view_url,
                    "expiresIn": URL_EXPIRATION_SECONDS,
                }
            ),
            status_code=200,
            headers=RESPONSE_HEADERS,
        )

    except Exception as exc:
        logging.error("get_view_url_function error: %s", exc)
        return _error("Failed to generate view URL", str(exc))


# =============================================================================
# DELETE /api/files/{fileId}
# Deletes all blobs with the given fileId prefix.
#
# AWS equivalent: delete_handler.py
#   s3.list_objects_v2(Prefix=f"{file_id}/")  →  list_blobs(name_starts_with=)
#   s3.delete_object(Key=obj['Key'])           →  container_client.delete_blob()
# =============================================================================


@app.route(
    route="files/{fileId}",
    methods=["DELETE", "OPTIONS"],
    auth_level=func.AuthLevel.FUNCTION,
)
def delete_file_function(req: func.HttpRequest) -> func.HttpResponse:
    if req.method == "OPTIONS":
        return _options_response()

    try:
        file_id = req.route_params.get("fileId")
        if not file_id:
            return _error("fileId is required", status=400)

        client = _blob_service_client()
        container_client = client.get_container_client(CONTAINER_NAME)

        # Replaces: s3.list_objects_v2(Bucket=..., Prefix=f"{file_id}/")
        blobs = list(container_client.list_blobs(name_starts_with=f"{file_id}/"))

        if not blobs:
            return _error("File not found", status=404)

        deleted_keys = []
        for blob in blobs:
            # Replaces: s3.delete_object(Bucket=..., Key=obj['Key'])
            container_client.delete_blob(blob.name)
            deleted_keys.append(blob.name)

        return func.HttpResponse(
            json.dumps(
                {
                    "message": "File(s) deleted successfully",
                    "fileId": file_id,
                    "deletedKeys": deleted_keys,
                }
            ),
            status_code=200,
            headers=RESPONSE_HEADERS,
        )

    except Exception as exc:
        logging.error("delete_file_function error: %s", exc)
        return _error("Failed to delete file", str(exc))
