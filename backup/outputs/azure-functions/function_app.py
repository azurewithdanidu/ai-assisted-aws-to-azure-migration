"""
Azure Functions v2 — Image Upload Application
Rewritten from AWS Lambda handlers (upload, list, view, delete).

Python 3.11 | Azure Functions v2 decorator model | DefaultAzureCredential
No boto3. No storage-account keys in code.
"""

import json
import logging
import os
import uuid
from datetime import datetime, timezone, timedelta

import azure.functions as func
from azure.identity import DefaultAzureCredential
from azure.storage.blob import (
    BlobServiceClient,
    BlobSasPermissions,
    generate_blob_sas,
)

# ---------------------------------------------------------------------------
# Module-level logger
# ---------------------------------------------------------------------------
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Function App — auth_level is ANONYMOUS because user authentication is
# enforced by Function App Authentication (Entra ID EasyAuth), not function keys.
# ---------------------------------------------------------------------------
app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def _get_blob_service_client() -> BlobServiceClient:
    """Return a BlobServiceClient authenticated via DefaultAzureCredential."""
    endpoint = os.environ["AZURE_STORAGE_BLOB_ENDPOINT"]
    credential = DefaultAzureCredential()
    return BlobServiceClient(account_url=endpoint, credential=credential)


def _get_storage_account_name() -> str:
    """Extract the storage account name from the blob endpoint env var."""
    account_name = os.environ.get("AZURE_STORAGE_ACCOUNT_NAME")
    if account_name:
        return account_name
    # Fall back: parse from endpoint URL  https://<account>.blob.core.windows.net
    endpoint = os.environ["AZURE_STORAGE_BLOB_ENDPOINT"]
    return endpoint.split("//")[1].split(".")[0]


def _sas_expiry_seconds() -> int:
    return int(os.environ.get("SAS_EXPIRATION_SECONDS", 3600))


def _cors_headers() -> dict:
    return {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
    }


def _generate_read_sas(blob_name: str) -> str:
    """Generate a short-lived read SAS URL for the given blob."""
    account_name = _get_storage_account_name()
    container_name = os.environ.get("IMAGES_CONTAINER_NAME", "images")
    expiry_seconds = _sas_expiry_seconds()

    # User delegation key requires a BlobServiceClient with token credential
    service_client = _get_blob_service_client()
    start = datetime.now(timezone.utc)
    expiry = start + timedelta(seconds=expiry_seconds)

    user_delegation_key = service_client.get_user_delegation_key(
        key_start_time=start,
        key_expiry_time=expiry,
    )

    sas_token = generate_blob_sas(
        account_name=account_name,
        container_name=container_name,
        blob_name=blob_name,
        user_delegation_key=user_delegation_key,
        permission=BlobSasPermissions(read=True),
        expiry=expiry,
    )

    endpoint = os.environ["AZURE_STORAGE_BLOB_ENDPOINT"].rstrip("/")
    return f"{endpoint}/{container_name}/{blob_name}?{sas_token}"


# ---------------------------------------------------------------------------
# upload_function  — POST /api/upload
# ---------------------------------------------------------------------------

@app.route(route="upload", methods=["POST"], auth_level=func.AuthLevel.ANONYMOUS)
def upload_function(req: func.HttpRequest) -> func.HttpResponse:
    """
    Generate an upload SAS URL (PUT) for a new blob.

    Request body (JSON):
        fileName   (required) – original file name
        fileType   (optional, default image/jpeg)
        description (optional)
        tags       (optional array of strings)

    Response (JSON):
        uploadUrl        – blob SAS URL the frontend must PUT to
        fileId           – newly generated UUID
        blobName         – full blob path  {fileId}/{fileName}
        expiresIn        – SAS lifetime in seconds
        requiredHeaders  – headers the frontend MUST include on the PUT
        metadata         – metadata dict for reference
    """
    logger.info("upload_function invoked")

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
            return func.HttpResponse(
                body=json.dumps({"error": "fileName is required"}),
                status_code=400,
                headers=_cors_headers(),
                mimetype="application/json",
            )

        # Unique identifiers
        file_id = str(uuid.uuid4())
        timestamp = datetime.now(timezone.utc).isoformat()
        blob_name = f"{file_id}/{file_name}"

        container_name = os.environ.get("IMAGES_CONTAINER_NAME", "images")
        account_name = _get_storage_account_name()
        expiry_seconds = _sas_expiry_seconds()

        # User delegation SAS with create+write permissions
        service_client = _get_blob_service_client()
        start = datetime.now(timezone.utc)
        expiry = start + timedelta(seconds=expiry_seconds)

        user_delegation_key = service_client.get_user_delegation_key(
            key_start_time=start,
            key_expiry_time=expiry,
        )

        sas_token = generate_blob_sas(
            account_name=account_name,
            container_name=container_name,
            blob_name=blob_name,
            user_delegation_key=user_delegation_key,
            permission=BlobSasPermissions(create=True, write=True),
            expiry=expiry,
            content_type=file_type,
        )

        endpoint = os.environ["AZURE_STORAGE_BLOB_ENDPOINT"].rstrip("/")
        upload_url = f"{endpoint}/{container_name}/{blob_name}?{sas_token}"

        # Required headers the frontend must pass on its PUT request
        required_headers: dict = {
            "x-ms-blob-type": "BlockBlob",
            "x-ms-blob-content-type": file_type,
            "x-ms-meta-uploaddate": timestamp,
            "x-ms-meta-originalfilename": file_name,
        }
        if description:
            required_headers["x-ms-meta-description"] = description
        if tags:
            tag_string = "&".join([f"tag{i}={tag}" for i, tag in enumerate(tags)])
            required_headers["x-ms-tags"] = tag_string

        metadata = {
            "uploaddate": timestamp,
            "originalfilename": file_name,
        }
        if description:
            metadata["description"] = description

        logger.info("Generated upload SAS for blob %s", blob_name)

        return func.HttpResponse(
            body=json.dumps(
                {
                    "uploadUrl": upload_url,
                    "fileId": file_id,
                    "blobName": blob_name,
                    "expiresIn": expiry_seconds,
                    "requiredHeaders": required_headers,
                    "metadata": metadata,
                }
            ),
            status_code=200,
            headers=_cors_headers(),
            mimetype="application/json",
        )

    except Exception as exc:
        logger.exception("upload_function error: %s", exc)
        return func.HttpResponse(
            body=json.dumps(
                {"error": "Failed to generate upload URL", "details": str(exc)}
            ),
            status_code=500,
            headers=_cors_headers(),
            mimetype="application/json",
        )


# ---------------------------------------------------------------------------
# list_function  — GET /api/files
# ---------------------------------------------------------------------------

@app.route(route="files", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)
def list_function(req: func.HttpRequest) -> func.HttpResponse:
    """
    List blobs in the images container with metadata, tags, and read SAS URLs.

    Query parameters:
        prefix   (optional) – blob name prefix filter
        maxKeys  (optional, default 50) – maximum results

    Response (JSON):
        files        – array of file objects
        count        – number of files returned
        isTruncated  – whether there are more results
    """
    logger.info("list_function invoked")

    try:
        prefix = req.params.get("prefix", "")
        max_keys = int(req.params.get("maxKeys", 50))

        container_name = os.environ.get("IMAGES_CONTAINER_NAME", "images")
        service_client = _get_blob_service_client()
        container_client = service_client.get_container_client(container_name)

        # Page through blobs — stop after max_keys items
        blobs_page = container_client.list_blobs(
            name_starts_with=prefix if prefix else None,
        ).by_page(results_per_page=max_keys)

        try:
            first_page = next(blobs_page)
        except StopIteration:
            first_page = []

        blob_items = list(first_page)
        is_truncated = blobs_page.continuation_token is not None

        if not blob_items:
            return func.HttpResponse(
                body=json.dumps({"files": [], "count": 0, "isTruncated": False}),
                status_code=200,
                headers=_cors_headers(),
                mimetype="application/json",
            )

        files = []
        for blob in blob_items[:max_keys]:
            blob_name: str = blob.name

            # Skip folder markers
            if blob_name.endswith("/"):
                continue

            try:
                blob_client = container_client.get_blob_client(blob_name)

                # Properties (content type, metadata, size, last_modified)
                props = blob_client.get_blob_properties()
                blob_metadata = props.metadata or {}
                content_type = (
                    props.content_settings.content_type
                    if props.content_settings
                    else "unknown"
                )

                # Tags
                blob_tags: dict = {}
                try:
                    blob_tags = blob_client.get_blob_tags() or {}
                except Exception:
                    pass
                tag_values = list(blob_tags.values())

                # Derived fields
                file_id = blob_name.split("/")[0] if "/" in blob_name else blob_name
                file_name_field = blob_metadata.get(
                    "originalfilename", blob_name.split("/")[-1]
                )
                last_modified_iso = (
                    blob.last_modified.isoformat() if blob.last_modified else ""
                )
                upload_date = blob_metadata.get("uploaddate", last_modified_iso)

                # Read SAS
                view_url = _generate_read_sas(blob_name)

                files.append(
                    {
                        "fileId": file_id,
                        "s3Key": blob_name,          # semantic equivalent kept for API compat
                        "fileName": file_name_field,
                        "fileType": content_type or "unknown",
                        "size": blob.size,
                        "lastModified": last_modified_iso,
                        "uploadDate": upload_date,
                        "description": blob_metadata.get("description", ""),
                        "tags": tag_values,
                        "viewUrl": view_url,
                        "urlExpiresIn": _sas_expiry_seconds(),
                    }
                )

            except Exception as inner_exc:
                logger.warning("Error processing blob %s: %s", blob_name, inner_exc)
                continue

        return func.HttpResponse(
            body=json.dumps(
                {"files": files, "count": len(files), "isTruncated": is_truncated}
            ),
            status_code=200,
            headers=_cors_headers(),
            mimetype="application/json",
        )

    except Exception as exc:
        logger.exception("list_function error: %s", exc)
        return func.HttpResponse(
            body=json.dumps(
                {"error": "Failed to retrieve files", "details": str(exc)}
            ),
            status_code=500,
            headers=_cors_headers(),
            mimetype="application/json",
        )


# ---------------------------------------------------------------------------
# view_function  — GET /api/files/{fileId}/view-url
# ---------------------------------------------------------------------------

@app.route(
    route="files/{fileId}/view-url",
    methods=["GET"],
    auth_level=func.AuthLevel.ANONYMOUS,
)
def view_function(req: func.HttpRequest) -> func.HttpResponse:
    """
    Return a short-lived read SAS URL for a specific file.

    Path parameter:
        fileId – the UUID segment used as the blob name prefix

    Response (JSON):
        fileId, blobName, fileName, fileType, description,
        uploadDate, size, viewUrl, expiresIn
    """
    logger.info("view_function invoked")

    try:
        file_id = req.route_params.get("fileId")

        if not file_id:
            return func.HttpResponse(
                body=json.dumps({"error": "fileId is required"}),
                status_code=400,
                headers=_cors_headers(),
                mimetype="application/json",
            )

        container_name = os.environ.get("IMAGES_CONTAINER_NAME", "images")
        service_client = _get_blob_service_client()
        container_client = service_client.get_container_client(container_name)

        # Find the first blob whose name starts with {fileId}/
        # list_blobs returns an ItemPaged — iterate to get the first item only.
        prefix = f"{file_id}/"
        matching = []
        for blob in container_client.list_blobs(name_starts_with=prefix):
            matching.append(blob)
            break  # only need the first one

        if not matching:
            return func.HttpResponse(
                body=json.dumps({"error": "File not found"}),
                status_code=404,
                headers=_cors_headers(),
                mimetype="application/json",
            )

        blob_item = matching[0]
        blob_name = blob_item.name

        blob_client = container_client.get_blob_client(blob_name)
        props = blob_client.get_blob_properties()
        blob_metadata = props.metadata or {}

        content_type = (
            props.content_settings.content_type
            if props.content_settings
            else "unknown"
        )
        last_modified_iso = (
            blob_item.last_modified.isoformat() if blob_item.last_modified else ""
        )
        upload_date = blob_metadata.get("uploaddate", last_modified_iso)
        file_name_field = blob_metadata.get("originalfilename", blob_name.split("/")[-1])
        description = blob_metadata.get("description", "")

        view_url = _generate_read_sas(blob_name)
        expiry_seconds = _sas_expiry_seconds()

        logger.info("Generated view SAS for blob %s", blob_name)

        return func.HttpResponse(
            body=json.dumps(
                {
                    "fileId": file_id,
                    "blobName": blob_name,
                    "fileName": file_name_field,
                    "fileType": content_type or "unknown",
                    "description": description,
                    "uploadDate": upload_date,
                    "size": blob_item.size,
                    "viewUrl": view_url,
                    "expiresIn": expiry_seconds,
                }
            ),
            status_code=200,
            headers=_cors_headers(),
            mimetype="application/json",
        )

    except Exception as exc:
        logger.exception("view_function error: %s", exc)
        return func.HttpResponse(
            body=json.dumps(
                {"error": "Failed to generate view URL", "details": str(exc)}
            ),
            status_code=500,
            headers=_cors_headers(),
            mimetype="application/json",
        )


# ---------------------------------------------------------------------------
# delete_function  — DELETE /api/files/{fileId}
# ---------------------------------------------------------------------------

@app.route(
    route="files/{fileId}",
    methods=["DELETE"],
    auth_level=func.AuthLevel.ANONYMOUS,
)
def delete_function(req: func.HttpRequest) -> func.HttpResponse:
    """
    Delete all blobs whose name starts with {fileId}/.

    Path parameter:
        fileId – the UUID prefix segment

    Response (JSON):
        message      – human-readable confirmation
        fileId       – the fileId that was deleted
        deletedKeys  – list of blob names that were deleted
    """
    logger.info("delete_function invoked")

    try:
        file_id = req.route_params.get("fileId")

        if not file_id:
            return func.HttpResponse(
                body=json.dumps({"error": "fileId is required"}),
                status_code=400,
                headers=_cors_headers(),
                mimetype="application/json",
            )

        container_name = os.environ.get("IMAGES_CONTAINER_NAME", "images")
        service_client = _get_blob_service_client()
        container_client = service_client.get_container_client(container_name)

        prefix = f"{file_id}/"
        blobs_to_delete = list(container_client.list_blobs(name_starts_with=prefix))

        if not blobs_to_delete:
            return func.HttpResponse(
                body=json.dumps({"error": "File not found"}),
                status_code=404,
                headers=_cors_headers(),
                mimetype="application/json",
            )

        deleted_keys = []
        for blob in blobs_to_delete:
            blob_client = container_client.get_blob_client(blob.name)
            blob_client.delete_blob(delete_snapshots="include")
            deleted_keys.append(blob.name)
            logger.info("Deleted blob %s", blob.name)

        return func.HttpResponse(
            body=json.dumps(
                {
                    "message": "File(s) deleted successfully",
                    "fileId": file_id,
                    "deletedKeys": deleted_keys,
                }
            ),
            status_code=200,
            headers=_cors_headers(),
            mimetype="application/json",
        )

    except Exception as exc:
        logger.exception("delete_function error: %s", exc)
        return func.HttpResponse(
            body=json.dumps(
                {"error": "Failed to delete file", "details": str(exc)}
            ),
            status_code=500,
            headers=_cors_headers(),
            mimetype="application/json",
        )
