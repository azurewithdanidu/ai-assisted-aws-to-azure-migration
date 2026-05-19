"""
Azure Function: update_task_plan
Reads/updates migration-task-plan.json in Blob Storage — replaces the
local migration-task-plan.md writes used by the VS Code Copilot agents.
"""
import json
import logging
import os
from datetime import datetime, timezone

import azure.functions as func
from azure.identity import ManagedIdentityCredential
from azure.storage.blob import BlobServiceClient

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

STORAGE_ACCOUNT = os.environ["STORAGE_ACCOUNT_NAME"]
OUTPUTS_CONTAINER = os.environ.get("OUTPUTS_CONTAINER", "migration-outputs")
PLAN_BLOB = "migration-task-plan.json"

VALID_STATUSES = {"IN_PROGRESS", "COMPLETED", "FAILED"}


def _get_plan_blob():
    url = f"https://{STORAGE_ACCOUNT}.blob.core.windows.net"
    service = BlobServiceClient(account_url=url, credential=ManagedIdentityCredential())
    return service.get_blob_client(container=OUTPUTS_CONTAINER, blob=PLAN_BLOB)


def _load_plan(blob) -> dict:
    try:
        data = blob.download_blob().readall()
        return json.loads(data)
    except Exception:
        return {"last_updated": "", "phases": {}}


def _save_plan(blob, plan: dict) -> None:
    plan["last_updated"] = datetime.now(timezone.utc).isoformat()
    blob.upload_blob(json.dumps(plan, indent=2).encode("utf-8"), overwrite=True)


@app.route(route="update_task_plan", methods=["POST"])
def update_task_plan(req: func.HttpRequest) -> func.HttpResponse:
    body = req.get_json()
    phase: str | None = body.get("phase")
    status: str | None = body.get("status")
    task: str | None = body.get("task")
    note: str | None = body.get("note")

    if not phase or status not in VALID_STATUSES:
        return func.HttpResponse(
            f"'phase' required and 'status' must be one of {VALID_STATUSES}", status_code=400
        )

    try:
        blob = _get_plan_blob()
        plan = _load_plan(blob)

        if phase not in plan["phases"]:
            plan["phases"][phase] = {"status": "NOT_STARTED", "tasks": {}, "notes": []}

        phase_entry = plan["phases"][phase]
        phase_entry["status"] = status

        if task:
            phase_entry["tasks"][task] = {
                "status": status,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }

        if note:
            phase_entry["notes"].append({
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "note": note,
            })

        _save_plan(blob, plan)
        logging.info("update_task_plan: phase=%s status=%s task=%s", phase, status, task)
        return func.HttpResponse(
            json.dumps({"phase": phase, "status": status}), status_code=200
        )
    except Exception as exc:
        logging.exception("update_task_plan failed")
        return func.HttpResponse(f"Error: {exc}", status_code=500)
