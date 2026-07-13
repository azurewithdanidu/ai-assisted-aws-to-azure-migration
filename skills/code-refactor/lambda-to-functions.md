---
name: lambda-to-functions
description: Rewrite AWS Lambda handlers as Azure Functions — full trigger catalog covering HTTP, Timer, Blob, Service Bus, Cosmos DB Change Feed, Event Grid, Event Hubs, Durable Functions, SignalR, and Cognito migration guidance
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

## Complete Trigger Mapping Catalog

Map every Lambda trigger type to its Azure Functions equivalent using this catalog. Select the entry that matches the source trigger found in `aws-inventory.json`.

### HTTP API Gateway → HttpTrigger

```python
import azure.functions as func

app = func.FunctionApp(http_auth_level=func.AuthLevel.FUNCTION)

@app.route(route="<route>", methods=["GET", "POST"])
def http_handler(req: func.HttpRequest) -> func.HttpResponse:
    # business logic here
    return func.HttpResponse(body='{"status": "ok"}', status_code=200, mimetype="application/json")
```

### CloudWatch Events / EventBridge Scheduler → TimerTrigger

```python
# CRON note: Azure uses 6-part CRON (seconds minutes hours day month weekday)
# AWS "rate(5 minutes)"  → "0 */5 * * * *"
# AWS "cron(0 12 * * ? *)" → "0 0 12 * * *"
@app.timer_trigger(schedule="0 */5 * * * *", arg_name="timer", run_on_startup=False)
def scheduled_handler(timer: func.TimerRequest) -> None:
    # business logic here
    pass
```

### S3 Put/Delete event → BlobTrigger

```python
# Source path pattern: "<container>/{name}"
# Use output binding to write to a second container if the Lambda did so
@app.blob_trigger(arg_name="blob", path="<container>/{name}", connection="STORAGE_CONNECTION")
def blob_handler(blob: func.InputStream) -> None:
    data = blob.read()
    # business logic here
```

### SQS → Service Bus Queue trigger

```python
@app.service_bus_queue_trigger(
    arg_name="msg",
    queue_name="<queue-name>",
    connection="SERVICE_BUS_CONNECTION"
)
def queue_handler(msg: func.ServiceBusMessage) -> None:
    body = msg.get_body().decode("utf-8")
    # business logic here
```

### DynamoDB Streams → Cosmos DB Change Feed trigger

```python
# Requires: azure-cosmos in requirements.txt
# connection string app setting: COSMOS_CONNECTION
@app.cosmos_db_trigger(
    arg_name="documents",
    database_name="<db-name>",
    container_name="<container-name>",
    connection="COSMOS_CONNECTION",
    create_lease_container_if_not_exists=True
)
def cosmosdb_trigger(documents: func.DocumentList) -> None:
    for doc in documents:
        # business logic here — doc is a dict of the changed item
        pass
```

### SNS → Event Grid trigger (via Event Grid subscription)

```python
# Wire up an Event Grid subscription from your Event Grid topic to this function endpoint.
# The function receives CloudEvents or Event Grid schema events.
@app.event_grid_trigger(arg_name="event")
def eventgrid_handler(event: func.EventGridEvent) -> None:
    data = event.get_json()
    # business logic here
```

### Kinesis Data Streams → Event Hubs trigger

```python
# Requires: azure-eventhub in requirements.txt
# connection string app setting: EVENT_HUB_CONNECTION
@app.event_hub_message_trigger(
    arg_name="events",
    event_hub_name="<eventhub-name>",
    connection="EVENT_HUB_CONNECTION",
    cardinality="many"   # batch mode — use "one" for single-event processing
)
def eventhub_handler(events: func.EventHubEvent) -> None:
    for event in events:
        body = event.get_body().decode("utf-8")
        # business logic here
```

### Step Functions (start execution) → Durable Functions orchestration

```python
import azure.durable_functions as df

# Orchestrator function (replaces the Step Functions state machine definition)
@df.orchestrator
def orchestrator_function(context: df.DurableOrchestrationContext):
    result1 = yield context.call_activity("Step1", context.get_input())
    result2 = yield context.call_activity("Step2", result1)
    return result2

# Activity function (replaces each Lambda invoked by a state machine step)
@app.activity_trigger(input_name="input")
def Step1(input: dict) -> dict:
    # business logic here
    return {}

# Client function (replaces the Lambda that calls sfn.start_execution)
@app.route(route="start", methods=["POST"])
@app.durable_client_input(client_name="client")
async def http_start(req: func.HttpRequest, client) -> func.HttpResponse:
    instance_id = await client.start_new("orchestrator_function", client_input=req.get_json())
    return client.create_check_status_response(req, instance_id)
```

> **Durable Functions package:** Add `azure-functions-durable` to `requirements.txt`. Remove the `azure-durable-functions` package (different name).

### WebSocket API Gateway → Azure SignalR Service bindings

```python
# WebSocket push connections migrate to SignalR Service.
# Requires: azure-functions[signalr] in requirements.txt
@app.route(route="negotiate", methods=["POST"])
@app.generic_input_binding(arg_name="connectionInfo",
    type="signalRConnectionInfo",
    hub_name="<hub-name>",
    connection="SIGNALR_CONNECTION")
def negotiate(req: func.HttpRequest, connectionInfo) -> func.HttpResponse:
    return func.HttpResponse(connectionInfo)

# Broadcast from server:
@app.generic_output_binding(arg_name="signalRMessages",
    type="signalR",
    hub_name="<hub-name>",
    connection="SIGNALR_CONNECTION")
def broadcast(timer: func.TimerRequest, signalRMessages: func.Out[str]) -> None:
    signalRMessages.set(json.dumps([{"target": "newMessage", "arguments": ["Hello from Azure"]}]))
```

### Cognito triggers (Pre-SignUp, Post-Confirmation, etc.) → Custom auth middleware

> Cognito custom auth logic does not have a direct Azure Functions trigger equivalent. Migrate the logic to middleware in your application (MSAL.js or Microsoft.Identity.Web) or to B2C custom policies. Do not create a Functions trigger for this.

---

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

**Additional packages by trigger type** (include only what the source Lambda uses):

| Source trigger | Add to requirements.txt |
|---|---|
| SQS → Service Bus Queue | `azure-servicebus` |
| DynamoDB Streams → Cosmos DB | `azure-cosmos` |
| SNS → Event Grid | `azure-eventgrid` |
| Kinesis → Event Hubs | `azure-eventhub` |
| Step Functions → Durable Functions | `azure-functions-durable` |
| WebSocket → SignalR | `azure-functions[signalr]` |

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

---

## References

### Microsoft / Azure Documentation

| Topic | Link |
|---|---|
| Azure Functions Python developer guide | https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-python |
| Azure Functions v2 Python model | https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-python?tabs=get-started%2Casgi%2Capplication-level&pivots=python-mode-decorators |
| Azure Functions triggers and bindings | https://learn.microsoft.com/en-us/azure/azure-functions/functions-triggers-bindings |
| HTTP trigger reference | https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-http-webhook-trigger |
| Timer trigger reference | https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-timer |
| Blob trigger reference | https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-storage-blob-trigger |
| Service Bus trigger reference | https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-service-bus-trigger |
| Cosmos DB trigger reference | https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-cosmosdb-v2-trigger |
| Event Grid trigger reference | https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-event-grid-trigger |
| Event Hubs trigger reference | https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-event-hubs-trigger |
| Durable Functions overview | https://learn.microsoft.com/en-us/azure/azure-functions/durable/durable-functions-overview |
| SignalR Service bindings | https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-signalr-service |
| Azure Functions CRON expression syntax | https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-timer#ncrontab-expressions |
| host.json reference | https://learn.microsoft.com/en-us/azure/azure-functions/functions-host-json |
| Extension bundle versions | https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-register#extension-bundles |
| Supported Python versions | https://learn.microsoft.com/en-us/azure/azure-functions/supported-languages#languages-by-runtime-version |
| Azure Durable Functions — Python | https://learn.microsoft.com/en-us/azure/azure-functions/durable/quickstart-python-vscode |

### AWS Documentation

| Topic | Link |
|---|---|
| AWS Lambda Python developer guide | https://docs.aws.amazon.com/lambda/latest/dg/lambda-python.html |
| Lambda event source mappings | https://docs.aws.amazon.com/lambda/latest/dg/invocation-eventsourcemapping.html |
| Lambda triggers — full list | https://docs.aws.amazon.com/lambda/latest/dg/lambda-services.html |
| AWS Step Functions developer guide | https://docs.aws.amazon.com/step-functions/latest/dg/welcome.html |
| Amazon Cognito triggers | https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-identity-pools-working-with-aws-lambda-triggers.html |

### Best Practices

- **Never use Python 3.12+ with Azure Functions v4** — the worker crashes. Lock `.python-version` to `3.11` in your repository.
- **CRON is 6-part in Azure, 5-part in AWS:** AWS `rate(5 minutes)` = Azure `0 */5 * * * *` (6 fields, leading seconds). Missing the seconds field causes a silent schedule misfire.
- **Cognito triggers have no Azure Functions equivalent trigger** — move that logic to MSAL middleware or Azure AD B2C custom policies.
- **Extension bundles must be v4.x** — v3.x does not support the v2 Python programming model decorator syntax.
