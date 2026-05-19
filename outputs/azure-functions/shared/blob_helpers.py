"""Shared Blob Storage helpers for the image-upload Azure Functions app.

Replaces the boto3 S3 client and pre-signed URL flow used by the original AWS
Lambda functions with an Azure Storage Blob + User Delegation SAS flow
authenticated via DefaultAzureCredential (resolves to System-assigned Managed
Identity in Azure, or AZURE_CLIENT_ID / az login locally).

Environment variables consumed:
    STORAGE_ACCOUNT_NAME    — Azure Storage account name (no .blob.core.windows.net)
    BLOB_CONTAINER_NAME     — Blob container name (default: images)
                              NOTE: do NOT use CONTAINER_NAME — it is reserved by
                              the Azure Functions host and will cause a crash.
    URL_EXPIRATION          — SAS token lifetime in seconds (default: 3600)
    CORS_ALLOWED_ORIGIN     — Value for Access-Control-Allow-Origin (default: *)
"""

from __future__ import annotations

import logging
import os
import threading
from datetime import datetime, timedelta, timezone
from typing import Optional

from azure.core.exceptions import AzureError  # noqa: F401 — re-exported for callers
from azure.identity import DefaultAzureCredential
from azure.storage.blob import (
    BlobSasPermissions,  # noqa: F401 — re-exported for callers
    BlobServiceClient,
    UserDelegationKey,
    generate_blob_sas,
)

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

STORAGE_ACCOUNT_NAME: str = os.environ["STORAGE_ACCOUNT_NAME"]
BLOB_CONTAINER_NAME: str = os.environ.get("BLOB_CONTAINER_NAME", "images")
URL_EXPIRATION: int = int(os.environ.get("URL_EXPIRATION", "3600"))
CORS_ALLOWED_ORIGIN: str = os.environ.get("CORS_ALLOWED_ORIGIN", "*")

_ACCOUNT_URL = f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net"

# ---------------------------------------------------------------------------
# Thread-safe singletons
# ---------------------------------------------------------------------------

_credential_lock = threading.Lock()
_credential: Optional[DefaultAzureCredential] = None

_client_lock = threading.Lock()
_blob_service_client: Optional[BlobServiceClient] = None

_udk_lock = threading.Lock()
_user_delegation_key: Optional[UserDelegationKey] = None
_user_delegation_key_expiry: Optional[datetime] = None

# User Delegation Keys live up to 7 days; request 6-day keys and refresh
# whenever less than 1 hour of validity remains.
_UDK_LIFETIME = timedelta(days=6)
_UDK_REFRESH_BEFORE = timedelta(hours=1)


def _get_credential() -> DefaultAzureCredential:
    global _credential
    if _credential is None:
        with _credential_lock:
            if _credential is None:
                _credential = DefaultAzureCredential()
    return _credential


def get_blob_service_client() -> BlobServiceClient:
    """Return a process-wide singleton BlobServiceClient using Managed Identity."""
    global _blob_service_client
    if _blob_service_client is None:
        with _client_lock:
            if _blob_service_client is None:
                _blob_service_client = BlobServiceClient(
                    account_url=_ACCOUNT_URL,
                    credential=_get_credential(),
                )
    return _blob_service_client


def _get_user_delegation_key() -> UserDelegationKey:
    """Return a cached User Delegation Key, refreshing when near expiry."""
    global _user_delegation_key, _user_delegation_key_expiry

    now = datetime.now(timezone.utc)
    if (
        _user_delegation_key is not None
        and _user_delegation_key_expiry is not None
        and _user_delegation_key_expiry - now > _UDK_REFRESH_BEFORE
    ):
        return _user_delegation_key

    with _udk_lock:
        now = datetime.now(timezone.utc)
        if (
            _user_delegation_key is None
            or _user_delegation_key_expiry is None
            or _user_delegation_key_expiry - now <= _UDK_REFRESH_BEFORE
        ):
            start = now - timedelta(minutes=5)   # clock-skew buffer
            expiry = now + _UDK_LIFETIME
            _user_delegation_key = get_blob_service_client().get_user_delegation_key(
                key_start_time=start,
                key_expiry_time=expiry,
            )
            _user_delegation_key_expiry = expiry
            logger.info("Refreshed user delegation key (expires %s)", expiry.isoformat())
        return _user_delegation_key


def make_sas_url(
    blob_name: str,
    permissions: BlobSasPermissions,
    ttl_seconds: Optional[int] = None,
    content_type: Optional[str] = None,
) -> str:
    """Generate a full HTTPS URL with a User Delegation SAS for a single blob.

    Uses DefaultAzureCredential (Managed Identity in Azure, service principal /
    az-login locally) — no storage account key is ever required or stored.
    """
    ttl = ttl_seconds if ttl_seconds is not None else URL_EXPIRATION
    expiry = datetime.now(timezone.utc) + timedelta(seconds=ttl)

    sas_kwargs: dict = dict(
        account_name=STORAGE_ACCOUNT_NAME,
        container_name=BLOB_CONTAINER_NAME,
        blob_name=blob_name,
        user_delegation_key=_get_user_delegation_key(),
        permission=permissions,
        expiry=expiry,
        protocol="https",
    )
    if content_type is not None:
        sas_kwargs["content_type"] = content_type

    sas_token = generate_blob_sas(**sas_kwargs)
    return f"{_ACCOUNT_URL}/{BLOB_CONTAINER_NAME}/{blob_name}?{sas_token}"


def get_container_client():
    """Return a ContainerClient for the configured images container."""
    return get_blob_service_client().get_container_client(BLOB_CONTAINER_NAME)


def get_blob_client(blob_name: str):
    """Return a BlobClient for a specific blob in the images container."""
    return get_blob_service_client().get_blob_client(
        container=BLOB_CONTAINER_NAME, blob=blob_name
    )


# ---------------------------------------------------------------------------
# HTTP response helpers
# ---------------------------------------------------------------------------

CORS_HEADERS = {
    "Access-Control-Allow-Origin": CORS_ALLOWED_ORIGIN,
    "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization, x-ms-blob-type",
}


def json_headers() -> dict:
    return {"Content-Type": "application/json", **CORS_HEADERS}


__all__ = [
    "AzureError",
    "BLOB_CONTAINER_NAME",
    "BlobSasPermissions",
    "CORS_HEADERS",
    "STORAGE_ACCOUNT_NAME",
    "URL_EXPIRATION",
    "get_blob_client",
    "get_blob_service_client",
    "get_container_client",
    "json_headers",
    "make_sas_url",
]
