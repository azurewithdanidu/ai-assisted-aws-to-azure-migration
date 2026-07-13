"""
Azure Functions — Image Upload Service
Python v2 programming model (decorator-based, single-file)

Replaces four AWS Lambda handlers with equivalent Azure Functions:
  upload_function    POST   /api/upload
  list_function      GET    /api/files
  view_url_function  GET    /api/files/{fileId}/view-url
  delete_function    DELETE /api/files/{fileId}

Auth: System-Assigned Managed Identity → DefaultAzureCredential()
      Storage Blob Data Contributor role on the Storage Account
SAS:  User-delegation SAS (no account key required)

Required App Settings:
  STORAGE_ACCOUNT_NAME        — Storage Account name (Key Vault reference)
  AZURE_STORAGE_CONTAINER_NAME — Blob container name (default: images)
  URL_EXPIRATION               — SAS / view URL expiry in seconds (default: 3600)
"""

import json
import logging
import os
import uuid
from datetime import datetime, timedelta, timezone

import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobSasPermissions, BlobServiceClient, generate_blob_sas

# ─── Module-level configuration (resolved once per worker cold-start) ─────────

STORAGE_ACCOUNT_NAME: str = os.environ["STORAGE_ACCOUNT_NAME"]
CONTAINER_NAME: str = os.environ.get("AZURE_STORAGE_CONTAINER_NAME", "images")
URL_EXPIRATION: int = int(os.environ.get("URL_EXPIRATION", 3600))

# DefaultAzureCredential resolves Managed Identity in Azure, and
# environment / CLI credentials locally.
_credential = DefaultAzureCredential()

_blob_service_client = BlobServiceClient(
    account_url=f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net",
    credential=_credential,
)

# ─── CORS response headers ────────────────────────────────────────────────────

_CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
}

# ─── SAS helper ──────────────────────────────────────────────────────────────


def _generate_sas_url(blob_name: str, permissions: BlobSasPermissions) -> str:
    """Return a full HTTPS SAS URL for *blob_name* with the given *permissions*.

    Uses a user-delegation key so no storage account key is needed.
    """
    now = datetime.now(timezone.utc)
    # Subtract 5 min to tolerate clock skew between Function workers and Azure Storage
    key_start = now - timedelta(minutes=5)
    key_expiry = now + timedelta(seconds=URL_EXPIRATION)

    delegation_key = _blob_service_client.get_user_delegation_key(key_start, key_expiry)

    sas_token = generate_blob_sas(
        account_name=STORAGE_ACCOUNT_NAME,
        container_name=CONTAINER_NAME,
        blob_name=blob_name,
        user_delegation_key=delegation_key,
        permission=permissions,
        expiry=key_expiry,
    )
    return (
        f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net"
        f"/{CONTAINER_NAME}/{blob_name}?{sas_token}"
    )


# ─── Azure Functions App ──────────────────────────────────────────────────────

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)


# ─────────────────────────────────────────────────────────────────────────────
# upload_function  POST /api/upload
# Replaces: source-app/app-code/lambda/upload/upload_handler.py
# ─────────────────────────────────────────────────────────────────────────────


@app.route(route="upload", methods=["POST"])
def upload_function(req: func.HttpRequest) -> func.HttpResponse:
    """Generate a user-delegation SAS URL (write + create) for direct PUT upload.

    Request body (JSON):
      {
        "fileName":    "image.jpg",        -- required
        "fileType":    "image/jpeg",       -- optional, default image/jpeg
        "description": "optional text",   -- optional
        "tags":        ["tag1", "tag2"]   -- optional
      }

    Response (200):
      {
        "uploadUrl":  "<sas-url>",         -- PUT target; expires in URL_EXPIRATION seconds
        "fileId":     "<uuid>",
        "blobName":   "<uuid>/<filename>",
        "metadata":   { "uploaddate": ..., "originalfilename": ..., ... },
        "expiresIn":  <seconds>,
        "message":    "<usage hint>"
      }

    Client upload instructions:
      PUT <uploadUrl>
      Headers: Content-Type: <fileType>
               x-ms-blob-type: BlockBlob
               x-ms-meta-uploaddate: <value>
               x-ms-meta-originalfilename: <value>
               x-ms-meta-description: <value>   (if present)
               x-ms-meta-tags: <comma-joined>   (if present)
    """
    try:
        body = req.get_json()
    except ValueError:
        body = {}

    file_name = body.get("fileName") if body else None
    file_type = (body.get("fileType") or "image/jpeg") if body else "image/jpeg"
    description = (body.get("description") or "") if body else ""
    tags: list = (body.get("tags") or []) if body else []

    if not file_name:
        return func.HttpResponse(
            json.dumps({"error": "fileName is required"}),
            status_code=400,
            headers=_CORS_HEADERS,
        )

    try:
        file_id = str(uuid.uuid4())
        timestamp = datetime.utcnow().isoformat()
        blob_name = f"{file_id}/{file_name}"

        # Build metadata dict — equivalent to S3 object metadata (x-amz-meta-*)
        metadata: dict = {
            "uploaddate": timestamp,
            "originalfilename": file_name,
        }
        if description:
            metadata["description"] = description
        if tags:
            # Store tags as a comma-joined string (no multi-value metadata in Blob Storage)
            metadata["tags"] = ",".join(str(t) for t in tags)

        upload_url = _generate_sas_url(
            blob_name,
            BlobSasPermissions(write=True, create=True),
        )

        return func.HttpResponse(
            json.dumps({
                "uploadUrl": upload_url,
                "fileId": file_id,
                "blobName": blob_name,
                "metadata": metadata,
                "expiresIn": URL_EXPIRATION,
                "message": (
                    "PUT the file binary to uploadUrl. "
                    "Set Content-Type and x-ms-blob-type: BlockBlob headers. "
                    "Pass each metadata entry as an x-ms-meta-<key> header."
                ),
            }),
            status_code=200,
            headers=_CORS_HEADERS,
        )

    except Exception as exc:
        logging.exception("upload_function: unexpected error")
        return func.HttpResponse(
            json.dumps({"error": "Failed to generate upload URL", "details": str(exc)}),
            status_code=500,
            headers=_CORS_HEADERS,
        )


# ─────────────────────────────────────────────────────────────────────────────
# list_function  GET /api/files
# Replaces: source-app/app-code/lambda/list/list_handler.py
# ─────────────────────────────────────────────────────────────────────────────


@app.route(route="files", methods=["GET"])
def list_function(req: func.HttpRequest) -> func.HttpResponse:
    """List blobs in the images container with read SAS URLs.

    Query parameters:
      prefix   (optional) — filter blobs by name prefix
      maxKeys  (optional, default 50) — maximum results to return

    Response (200):
      {
        "files": [
          {
            "fileId":      "<uuid>",
            "blobName":    "<uuid>/<filename>",
            "fileName":    "<original filename>",
            "fileType":    "<content-type>",
            "size":        <bytes>,
            "lastModified":"<ISO 8601>",
            "uploadDate":  "<ISO 8601>",
            "description": "<text>",
            "tags":        ["tag1", ...],
            "viewUrl":     "<read-sas-url>",
            "urlExpiresIn":<seconds>
          },
          ...
        ],
        "count": <int>
      }
    """
    prefix = req.params.get("prefix", "")
    try:
        max_keys = int(req.params.get("maxKeys", 50))
    except ValueError:
        max_keys = 50

    try:
        container_client = _blob_service_client.get_container_client(CONTAINER_NAME)

        list_kwargs: dict = {"include": ["metadata"]}
        if prefix:
            list_kwargs["name_starts_with"] = prefix

        # list_blobs returns an ItemPaged iterator; materialise up to max_keys
        all_blobs = container_client.list_blobs(**list_kwargs)
        blobs = []
        for blob in all_blobs:
            if len(blobs) >= max_keys:
                break
            blobs.append(blob)

        files = []
        for blob in blobs:
            # Skip folder marker objects (key ends with /)
            if blob.name.endswith("/"):
                continue

            try:
                blob_metadata = blob.metadata or {}
                file_id = blob.name.split("/")[0] if "/" in blob.name else blob.name
                file_name = blob_metadata.get(
                    "originalfilename", blob.name.split("/")[-1]
                )

                # Equivalent to generate_presigned_url('get_object', ...)
                read_url = _generate_sas_url(blob.name, BlobSasPermissions(read=True))

                tags_raw = blob_metadata.get("tags", "")
                tag_list = [t for t in tags_raw.split(",") if t] if tags_raw else []

                last_modified_iso = (
                    blob.last_modified.isoformat() if blob.last_modified else None
                )
                content_type = (
                    blob.content_settings.content_type
                    if blob.content_settings
                    else "unknown"
                )

                files.append({
                    "fileId": file_id,
                    "blobName": blob.name,
                    "fileName": file_name,
                    "fileType": content_type,
                    "size": blob.size,
                    "lastModified": last_modified_iso,
                    "uploadDate": blob_metadata.get("uploaddate", last_modified_iso),
                    "description": blob_metadata.get("description", ""),
                    "tags": tag_list,
                    "viewUrl": read_url,
                    "urlExpiresIn": URL_EXPIRATION,
                })

            except Exception as inner_exc:
                logging.warning("list_function: skipping blob %s — %s", blob.name, inner_exc)
                continue

        return func.HttpResponse(
            json.dumps({"files": files, "count": len(files)}),
            status_code=200,
            headers=_CORS_HEADERS,
        )

    except Exception as exc:
        logging.exception("list_function: unexpected error")
        return func.HttpResponse(
            json.dumps({"error": "Failed to retrieve files", "details": str(exc)}),
            status_code=500,
            headers=_CORS_HEADERS,
        )


# ─────────────────────────────────────────────────────────────────────────────
# view_url_function  GET /api/files/{fileId}/view-url
# Replaces: source-app/app-code/lambda/view/view_handler.py
# ─────────────────────────────────────────────────────────────────────────────


@app.route(route="files/{fileId}/view-url", methods=["GET"])
def view_url_function(req: func.HttpRequest) -> func.HttpResponse:
    """Generate a read SAS URL for the first blob matching the fileId prefix.

    Route parameter: fileId

    Response (200):
      {
        "fileId":     "<uuid>",
        "blobName":   "<uuid>/<filename>",
        "fileName":   "<original filename>",
        "fileType":   "<content-type>",
        "description":"<text>",
        "uploadDate": "<ISO 8601>",
        "size":       <bytes>,
        "viewUrl":    "<read-sas-url>",
        "expiresIn":  <seconds>
      }
    """
    file_id = req.route_params.get("fileId")
    if not file_id:
        return func.HttpResponse(
            json.dumps({"error": "fileId is required"}),
            status_code=400,
            headers=_CORS_HEADERS,
        )

    try:
        container_client = _blob_service_client.get_container_client(CONTAINER_NAME)

        # Equivalent to list_objects_v2(Prefix=f"{file_id}/", MaxKeys=1)
        matching = list(
            container_client.list_blobs(
                name_starts_with=f"{file_id}/",
                include=["metadata"],
            )
        )

        if not matching:
            return func.HttpResponse(
                json.dumps({"error": "File not found"}),
                status_code=404,
                headers=_CORS_HEADERS,
            )

        blob = matching[0]
        blob_metadata = blob.metadata or {}

        # Equivalent to generate_presigned_url('get_object', ...)
        view_url = _generate_sas_url(blob.name, BlobSasPermissions(read=True))

        last_modified_iso = (
            blob.last_modified.isoformat() if blob.last_modified else None
        )
        content_type = (
            blob.content_settings.content_type if blob.content_settings else "unknown"
        )

        return func.HttpResponse(
            json.dumps({
                "fileId": file_id,
                "blobName": blob.name,
                "fileName": blob_metadata.get(
                    "originalfilename", blob.name.split("/")[-1]
                ),
                "fileType": content_type,
                "description": blob_metadata.get("description", ""),
                "uploadDate": blob_metadata.get("uploaddate", last_modified_iso),
                "size": blob.size,
                "viewUrl": view_url,
                "expiresIn": URL_EXPIRATION,
            }),
            status_code=200,
            headers=_CORS_HEADERS,
        )

    except Exception as exc:
        logging.exception("view_url_function: unexpected error")
        return func.HttpResponse(
            json.dumps({"error": "Failed to generate view URL", "details": str(exc)}),
            status_code=500,
            headers=_CORS_HEADERS,
        )


# ─────────────────────────────────────────────────────────────────────────────
# delete_function  DELETE /api/files/{fileId}
# Replaces: source-app/app-code/lambda/delete/delete_handler.py
# ─────────────────────────────────────────────────────────────────────────────


@app.route(route="files/{fileId}", methods=["DELETE"])
def delete_function(req: func.HttpRequest) -> func.HttpResponse:
    """Delete all blobs matching the fileId prefix.

    Route parameter: fileId

    Response (200):
      {
        "message":     "File(s) deleted successfully",
        "fileId":      "<uuid>",
        "deletedKeys": ["<uuid>/<filename>", ...]
      }
    """
    file_id = req.route_params.get("fileId")
    if not file_id:
        return func.HttpResponse(
            json.dumps({"error": "fileId is required"}),
            status_code=400,
            headers=_CORS_HEADERS,
        )

    try:
        container_client = _blob_service_client.get_container_client(CONTAINER_NAME)

        # Equivalent to list_objects_v2(Prefix=f"{file_id}/")
        matching = list(container_client.list_blobs(name_starts_with=f"{file_id}/"))

        if not matching:
            return func.HttpResponse(
                json.dumps({"error": "File not found"}),
                status_code=404,
                headers=_CORS_HEADERS,
            )

        deleted_keys = []
        for blob in matching:
            # Equivalent to delete_object(Bucket=..., Key=blob.name)
            container_client.delete_blob(blob.name)
            deleted_keys.append(blob.name)

        return func.HttpResponse(
            json.dumps({
                "message": "File(s) deleted successfully",
                "fileId": file_id,
                "deletedKeys": deleted_keys,
            }),
            status_code=200,
            headers=_CORS_HEADERS,
        )

    except Exception as exc:
        logging.exception("delete_function: unexpected error")
        return func.HttpResponse(
            json.dumps({"error": "Failed to delete file", "details": str(exc)}),
            status_code=500,
            headers=_CORS_HEADERS,
        )
