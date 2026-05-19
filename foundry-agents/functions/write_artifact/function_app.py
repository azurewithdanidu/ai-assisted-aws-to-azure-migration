"""
Azure Function: write_artifact
Receives a path + content from a Foundry agent and writes it to Azure Blob Storage,
replacing local filesystem writes used by the VS Code Copilot agents.
"""
import logging
import os

import azure.functions as func
from azure.identity import ManagedIdentityCredential
from azure.storage.blob import BlobServiceClient

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

STORAGE_ACCOUNT = os.environ["STORAGE_ACCOUNT_NAME"]
OUTPUTS_CONTAINER = os.environ.get("OUTPUTS_CONTAINER", "migration-outputs")


def _get_blob_client(path: str):
    url = f"https://{STORAGE_ACCOUNT}.blob.core.windows.net"
    service = BlobServiceClient(account_url=url, credential=ManagedIdentityCredential())
    return service.get_blob_client(container=OUTPUTS_CONTAINER, blob=path)


@app.route(route="write_artifact", methods=["POST"])
def write_artifact(req: func.HttpRequest) -> func.HttpResponse:
    body = req.get_json()
    path: str | None = body.get("path")
    content: str | None = body.get("content")

    if not path or content is None:
        return func.HttpResponse("Missing 'path' or 'content'", status_code=400)

    # Normalise path — strip leading slash or 'outputs/' prefix duplication
    path = path.lstrip("/")

    try:
        blob = _get_blob_client(path)
        blob.upload_blob(content.encode("utf-8"), overwrite=True)
        logging.info("write_artifact: wrote %s (%d bytes)", path, len(content))
        return func.HttpResponse(f"Written: {path}", status_code=200)
    except Exception as exc:
        logging.exception("write_artifact failed for %s", path)
        return func.HttpResponse(f"Error: {exc}", status_code=500)
