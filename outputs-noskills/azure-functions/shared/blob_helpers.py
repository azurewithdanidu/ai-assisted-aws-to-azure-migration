"""Shared Blob Storage helpers for the image-upload Azure Functions app.

Replaces the boto3 S3 client + presigned URL flow used by the original AWS Lambdas
with an Azure Storage Blob + User Delegation SAS flow authenticated via
`DefaultAzureCredential` (resolves to the User-Assigned Managed Identity in Azure
through `AZURE_CLIENT_ID`).
"""

from __future__ import annotations

import logging
import os
import threading
from datetime import datetime, timedelta, timezone
from typing import Optional

from azure.core.exceptions import AzureError
from azure.identity import DefaultAzureCredential
from azure.storage.blob import (
    BlobSasPermissions,
    BlobServiceClient,
    UserDelegationKey,
    generate_blob_sas,
)

logger = logging.getLogger(__name__)

# --- Environment ------------------------------------------------------------

STORAGE_ACCOUNT_NAME = os.environ["STORAGE_ACCOUNT_NAME"]
IMAGES_CONTAINER_NAME = os.environ["IMAGES_CONTAINER_NAME"]
URL_EXPIRATION_SECONDS = int(os.environ.get("URL_EXPIRATION_SECONDS", "3600"))

# CORS origin for SWA (set to "*" in dev).
CORS_ALLOWED_ORIGIN = os.environ.get("CORS_ALLOWED_ORIGIN", "*")

_ACCOUNT_URL = f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net"

# --- Singletons -------------------------------------------------------------

_credential_lock = threading.Lock()
_credential: Optional[DefaultAzureCredential] = None

_client_lock = threading.Lock()
_blob_service_client: Optional[BlobServiceClient] = None

_udk_lock = threading.Lock()
_user_delegation_key: Optional[UserDelegationKey] = None
_user_delegation_key_expiry: Optional[datetime] = None

# User Delegation Keys may live up to 7 days; refresh when within 1 hour of expiry.
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
    """Return a process-wide singleton `BlobServiceClient` using Managed Identity."""
    global _blob_service_client
    if _blob_service_client is None:
        with _client_lock:
            if _blob_service_client is None:
                _blob_service_client = BlobServiceClient(
                    account_url=_ACCOUNT_URL,
                    credential=_get_credential(),
                )
    return _blob_service_client


def get_user_delegation_key() -> UserDelegationKey:
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
            start = now - timedelta(minutes=5)
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
    """Generate a full HTTPS URL with a user-delegation SAS for a single blob."""
    ttl = ttl_seconds if ttl_seconds is not None else URL_EXPIRATION_SECONDS
    expiry = datetime.now(timezone.utc) + timedelta(seconds=ttl)

    sas_kwargs = dict(
        account_name=STORAGE_ACCOUNT_NAME,
        container_name=IMAGES_CONTAINER_NAME,
        blob_name=blob_name,
        user_delegation_key=get_user_delegation_key(),
        permission=permissions,
        expiry=expiry,
        protocol="https",
    )
    if content_type is not None:
        sas_kwargs["content_type"] = content_type

    sas_token = generate_blob_sas(**sas_kwargs)
    return f"{_ACCOUNT_URL}/{IMAGES_CONTAINER_NAME}/{blob_name}?{sas_token}"


def get_container_client():
    """Return a ContainerClient for the configured images container."""
    return get_blob_service_client().get_container_client(IMAGES_CONTAINER_NAME)


def get_blob_client(blob_name: str):
    """Return a BlobClient for a specific blob in the images container."""
    return get_blob_service_client().get_blob_client(
        container=IMAGES_CONTAINER_NAME, blob=blob_name
    )


# --- HTTP helpers -----------------------------------------------------------

CORS_HEADERS = {
    "Access-Control-Allow-Origin": CORS_ALLOWED_ORIGIN,
    "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization, x-ms-blob-type",
}


def json_headers() -> dict:
    return {"Content-Type": "application/json", **CORS_HEADERS}


__all__ = [
    "AzureError",
    "BlobSasPermissions",
    "CORS_HEADERS",
    "IMAGES_CONTAINER_NAME",
    "STORAGE_ACCOUNT_NAME",
    "URL_EXPIRATION_SECONDS",
    "get_blob_client",
    "get_blob_service_client",
    "get_container_client",
    "get_user_delegation_key",
    "json_headers",
    "make_sas_url",
]
