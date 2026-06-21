---
name: lambda-to-functions
description: Rewrite AWS Lambda handlers as Azure Functions — trigger types, handler signatures, response shapes, and host.json configuration
---

# Lambda-to-Functions Skill

## Purpose

Rewrite each AWS Lambda function as an Azure Function with the correct trigger, binding, Python handler signature, and response shape — while preserving 100% of the original business logic.

## When to Use

For every Lambda function listed in `design-document.md` Section 6.

## Process

1. Read the original Lambda handler from `source-app/app-code/lambda/<function>/app.py`.
2. Read `outputs/azure-architecture-output/design-document.md` Section 6 for the target trigger type.
3. Apply the trigger mapping below.
4. Replace the Lambda handler body with the Azure equivalent, preserving all business logic.
5. Write output to `outputs/azure-functions/<function_name>/function_app.py`.
6. Update `outputs/azure-functions/requirements.txt` with Azure SDK packages.
7. Ensure `outputs/azure-functions/host.json` exists with correct runtime version.

**Trigger mappings:**

```python
# Lambda HTTP (API Gateway) → Azure Functions HTTP trigger
import azure.functions as func

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

@app.route(route="upload", methods=["POST"])
def upload_handler(req: func.HttpRequest) -> func.HttpResponse:
    # business logic here
    return func.HttpResponse(body='{"status": "ok"}', status_code=200, mimetype="application/json")
```

```python
# Lambda scheduled (CloudWatch Events) → Azure Functions Timer trigger
@app.timer_trigger(schedule="0 */5 * * * *", arg_name="timer", run_on_startup=False)
def scheduled_handler(timer: func.TimerRequest) -> None:
    # business logic here
    pass
```

```python
# Lambda S3 event → Azure Functions Blob trigger
@app.blob_trigger(arg_name="blob", path="uploads/{name}", connection="STORAGE_CONNECTION")
def blob_handler(blob: func.InputStream) -> None:
    data = blob.read()
    # business logic here
```

```python
# Lambda SQS → Azure Functions Service Bus Queue trigger
@app.service_bus_queue_trigger(
    arg_name="msg",
    queue_name="my-queue",
    connection="SERVICE_BUS_CONNECTION"
)
def queue_handler(msg: func.ServiceBusMessage) -> None:
    body = msg.get_body().decode("utf-8")
    # business logic here
```

**Required `host.json`:**
```json
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": { "isEnabled": true }
    }
  },
  "extensionBundle": {
    "id": "Microsoft.Azure.Functions.ExtensionBundle",
    "version": "[4.*, 5.0.0)"
  }
}
```

**Required `requirements.txt` base:**
```
azure-functions
azure-identity
azure-storage-blob
azure-keyvault-secrets
```

## Rules

- **Never import boto3 in output files.**
- **Always use `DefaultAzureCredential`** for downstream service access — see `.github/skills/agents/shared/azure-auth-patterns.md`.
- **Always use `os.environ["VAR_NAME"]`** for environment variables — same pattern as Lambda, different variable names.
- **Never use `context.log()` or Lambda `print()` for logging** — use `logging.getLogger(__name__).info(...)`.
- **Python version must be 3.9–3.11** — never 3.12+ (Azure Functions v4 constraint).
- **Never modify files in `source-app/`** — read only.
- **Preserve 100% of business logic** — only the trigger/response/SDK patterns change.

## Output

- `outputs/azure-functions/<function_name>/function_app.py` — syntactically valid Python, no boto3 imports
- `outputs/azure-functions/requirements.txt` — includes `azure-functions` and all Azure SDK packages
- `outputs/azure-functions/host.json` — valid JSON with extensionBundle version 4.x
