---
name: sdk-migration
description: Replace boto3 SDK calls with Azure SDK equivalents — Python and Node.js/TypeScript package mapping, import paths, client instantiation, authentication, and runtime gotchas
---

# SDK Migration Skill

## Purpose

Replace every boto3 (Python) and `@aws-sdk` (Node.js/TypeScript) API call with the correct Azure SDK equivalent, ensuring no AWS SDK dependencies remain in refactored output files.

## When to Use

When rewriting Lambda source files that contain boto3 or `@aws-sdk` calls.

## Process

1. Scan the Lambda source for all AWS SDK usage:
   ```bash
   grep -n "boto3\.\|@aws-sdk\|import boto3" source-app/app-code/lambda/<function>/app.py
   ```
2. For each call, apply the mapping table below.
3. Replace the import block at the top of the file.
4. Update `outputs/azure-functions/requirements.txt` with Azure packages needed.
5. Run validation: `grep -rn "boto3\|@aws-sdk" outputs/azure-functions/` must return no matches.

---

## Python Runtime Gotchas (Read First)

**Python 3.13 is NOT supported** by Azure Functions v4 — it crashes the worker process with a `0xC0000005` Access Violation. Supported versions: **Python 3.9, 3.10, 3.11 only**.

```bash
# Always create .venv using Python 3.11
python3.11 -m venv .venv

# If Python 3.11 is not installed (Linux):
sudo apt install python3.11 python3.11-venv
```

Azure Functions Core Tools must be v4:
```bash
npm install -g azure-functions-core-tools@4
```

---

## Reserved Environment Variable Names

The following names are **reserved by the Azure Functions host** — using them causes silent overrides or runtime failures:

| Reserved Name | Use Instead |
|---|---|
| `CONTAINER_NAME` | `BLOB_CONTAINER_NAME` |
| `WEBSITE_*` (any prefix) | Choose a non-WEBSITE_ prefix |
| `FUNCTIONS_*` (any prefix) | Choose a non-FUNCTIONS_ prefix |
| `AzureWebJobs*` (any prefix) | Choose a non-AzureWebJobs prefix |

When renaming env vars during migration, also update: application code, Key Vault secret names, Bicep parameter files (app settings section), and GitHub Actions secrets.

---

## SDK Mappings — Python (boto3 → Azure SDK)

### Storage: S3 → Azure Blob Storage

```python
# BEFORE (boto3)
import boto3
s3_client = boto3.client('s3', region_name='us-east-1')

def upload_file(bucket_name: str, key: str, body: bytes) -> None:
    s3_client.put_object(Bucket=bucket_name, Key=key, Body=body)

def download_file(bucket_name: str, key: str) -> bytes:
    response = s3_client.get_object(Bucket=bucket_name, Key=key)
    return response['Body'].read()

# AFTER (azure-storage-blob)
import os
from azure.storage.blob import BlobServiceClient
from azure.identity import DefaultAzureCredential

blob_service_client = BlobServiceClient(
    account_url=f"https://{os.environ['AZURE_STORAGE_ACCOUNT_NAME']}.blob.core.windows.net",
    credential=DefaultAzureCredential()
)

def upload_file(container_name: str, blob_name: str, body: bytes) -> None:
    blob_client = blob_service_client.get_blob_client(container=container_name, blob=blob_name)
    blob_client.upload_blob(body, overwrite=True)

def download_file(container_name: str, blob_name: str) -> bytes:
    blob_client = blob_service_client.get_blob_client(container=container_name, blob=blob_name)
    return blob_client.download_blob().readall()
```

### NoSQL Database: DynamoDB → Cosmos DB

```python
# BEFORE (boto3)
import boto3
dynamodb = boto3.resource('dynamodb', region_name='us-east-1')
table = dynamodb.Table('orders')

def get_item(order_id: str) -> dict:
    response = table.get_item(Key={'orderId': order_id})
    return response.get('Item', {})

def put_item(item: dict) -> None:
    table.put_item(Item=item)

# AFTER (azure-cosmos)
import os
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential

cosmos_client = CosmosClient(
    url=os.environ['AZURE_COSMOS_ENDPOINT'],
    credential=DefaultAzureCredential()
)
container = cosmos_client.get_database_client(os.environ['COSMOS_DB']).get_container_client('orders')

def get_item(order_id: str) -> dict:
    return container.read_item(item=order_id, partition_key=order_id)

def put_item(item: dict) -> None:
    container.upsert_item(body=item)
```

### Messaging: SQS → Azure Service Bus

```python
# BEFORE (boto3)
import boto3
sqs = boto3.client('sqs')
sqs.send_message(QueueUrl=os.environ['QUEUE_URL'], MessageBody=json.dumps(payload))

# AFTER (azure-servicebus)
import os, json
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from azure.identity import DefaultAzureCredential

credential = DefaultAzureCredential()
with ServiceBusClient(os.environ['SERVICE_BUS_NAMESPACE'], credential) as sb_client:
    with sb_client.get_queue_sender(os.environ['QUEUE_NAME']) as sender:
        sender.send_messages(ServiceBusMessage(json.dumps(payload)))
```

### Secrets: Secrets Manager → Key Vault app setting reference

```python
# BEFORE (boto3)
import boto3
sm = boto3.client('secretsmanager')
secret = sm.get_secret_value(SecretId='my-secret')['SecretString']

# AFTER — no SDK call needed at runtime
# The secret is injected via Key Vault reference in app settings (set in Bicep):
#   MY_SECRET = @Microsoft.KeyVault(SecretUri=https://<kv>.vault.azure.net/secrets/my-secret/)
secret = os.environ['MY_SECRET']   # Azure resolves the KV reference automatically
```

### Lambda Handler → Azure Function Handler

```python
# BEFORE (AWS Lambda)
def handler(event, context):
    try:
        result = process(event)
        return {'statusCode': 200, 'body': json.dumps(result)}
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

# AFTER (Azure Functions v2 Python)
import azure.functions as func
import json

app = func.FunctionApp()

@app.function_name(name="HttpTrigger")
@app.route(route="process", methods=["GET", "POST"])
def http_trigger(req: func.HttpRequest) -> func.HttpResponse:
    try:
        result = process(req)
        return func.HttpResponse(json.dumps(result), status_code=200, mimetype="application/json")
    except Exception as e:
        return func.HttpResponse(json.dumps({'error': str(e)}), status_code=500, mimetype="application/json")
```

---

## SDK Mappings — Node.js / TypeScript (@aws-sdk → @azure)

### Storage: S3 → Azure Blob Storage

```typescript
// BEFORE (@aws-sdk)
import { S3Client, GetObjectCommand, PutObjectCommand } from "@aws-sdk/client-s3";
const s3Client = new S3Client({ region: "us-east-1" });

async function uploadFile(bucket: string, key: string, body: Buffer): Promise<void> {
    await s3Client.send(new PutObjectCommand({ Bucket: bucket, Key: key, Body: body }));
}
async function downloadFile(bucket: string, key: string): Promise<string> {
    const r = await s3Client.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
    return r.Body?.toString() ?? '';
}

// AFTER (@azure/storage-blob)
import { BlobServiceClient } from "@azure/storage-blob";
import { DefaultAzureCredential } from "@azure/identity";

const blobServiceClient = new BlobServiceClient(
    `https://${process.env.AZURE_STORAGE_ACCOUNT_NAME}.blob.core.windows.net`,
    new DefaultAzureCredential()
);

async function uploadFile(container: string, blob: string, body: Buffer): Promise<void> {
    const blockBlobClient = blobServiceClient.getContainerClient(container).getBlockBlobClient(blob);
    await blockBlobClient.upload(body, body.length);
}
async function downloadFile(container: string, blob: string): Promise<string> {
    const blockBlobClient = blobServiceClient.getContainerClient(container).getBlockBlobClient(blob);
    return (await blockBlobClient.download()).contentAsText ?? '';
}
```

### NoSQL Database: DynamoDB → Cosmos DB

```typescript
// BEFORE (@aws-sdk)
import { DynamoDBDocumentClient, GetCommand, PutCommand } from "@aws-sdk/lib-dynamodb";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
const docClient = DynamoDBDocumentClient.from(new DynamoDBClient({ region: "us-east-1" }));

async function getItem(id: string) {
    return (await docClient.send(new GetCommand({ TableName: "orders", Key: { orderId: id } }))).Item;
}

// AFTER (@azure/cosmos)
import { CosmosClient } from "@azure/cosmos";
import { DefaultAzureCredential } from "@azure/identity";

const container = new CosmosClient({
    endpoint: process.env.AZURE_COSMOS_ENDPOINT!,
    aadCredentials: new DefaultAzureCredential()
}).database("mydb").container("orders");

async function getItem(id: string) {
    return (await container.item(id).read()).resource;
}
async function putItem(item: Record<string, unknown>) {
    await container.items.create(item);
}
```

### Events: EventBridge → Azure Event Grid

```typescript
// BEFORE (@aws-sdk)
import { EventBridgeClient, PutEventsCommand } from "@aws-sdk/client-eventbridge";
const eventBridge = new EventBridgeClient({ region: "us-east-1" });

async function publishEvent(type: string, detail: object): Promise<void> {
    await eventBridge.send(new PutEventsCommand({
        Entries: [{ Source: "my-service", DetailType: type, Detail: JSON.stringify(detail), EventBusName: "default" }]
    }));
}

// AFTER (@azure/eventgrid)
import { EventGridPublisherClient, AzureKeyCredential } from "@azure/eventgrid";

const egClient = new EventGridPublisherClient(
    process.env.AZURE_EVENT_GRID_ENDPOINT!,
    "CloudEvent",
    new AzureKeyCredential(process.env.AZURE_EVENT_GRID_KEY!)
);

async function publishEvent(type: string, detail: object): Promise<void> {
    await egClient.send([{
        type: type,
        source: "/my-service",
        data: detail,
        dataContentType: "application/json"
    }]);
}
```

---

## Package Reference

### Python (requirements.txt)

| boto3 client | Azure package | pip command |
|---|---|---|
| `boto3` (s3) | `azure-storage-blob` | `pip install azure-storage-blob` |
| `boto3` (dynamodb) | `azure-cosmos` | `pip install azure-cosmos` |
| `boto3` (sqs) | `azure-servicebus` | `pip install azure-servicebus` |
| `boto3` (secretsmanager) | Key Vault app setting ref (no SDK) | — |
| `boto3` (sns) | `azure-eventgrid` | `pip install azure-eventgrid` |
| `boto3` (ses) | `azure-communication-email` | `pip install azure-communication-email` |
| Auth (all clients) | `azure-identity` | `pip install azure-identity` |

Minimum `requirements.txt` for an Azure Functions app:
```
azure-functions
azure-identity
azure-storage-blob
azure-cosmos
azure-servicebus
```

### Node.js (package.json)

| @aws-sdk package | @azure package |
|---|---|
| `@aws-sdk/client-s3` | `@azure/storage-blob` |
| `@aws-sdk/client-dynamodb`, `@aws-sdk/lib-dynamodb` | `@azure/cosmos` |
| `@aws-sdk/client-sqs` | `@azure/service-bus` |
| `@aws-sdk/client-eventbridge` | `@azure/eventgrid` |
| `@aws-sdk/client-secrets-manager` | No runtime dependency — use Key Vault app setting references |
| Auth (all) | `@azure/identity` |

---

## Environment Variable Mapping

| AWS Variable | Azure Replacement | Source |
|---|---|---|
| `AWS_REGION` | `AZURE_LOCATION` | App setting |
| `S3_BUCKET_NAME` | `AZURE_STORAGE_ACCOUNT_NAME` | App setting |
| `CONTAINER_NAME` | `BLOB_CONTAINER_NAME` | App setting (reserved name!) |
| `DYNAMODB_TABLE` | `COSMOS_ENDPOINT` + `COSMOS_DB` + `COSMOS_CONTAINER` | App settings |
| `SQS_QUEUE_URL` | `SERVICE_BUS_NAMESPACE` + `QUEUE_NAME` | App settings |
| `SECRET_NAME` | `MY_SECRET` (KV ref) | Key Vault reference |
| `AWS_ACCESS_KEY_ID` | Removed — use `DefaultAzureCredential` | N/A |
| `AWS_SECRET_ACCESS_KEY` | Removed — use `DefaultAzureCredential` | N/A |

---

## Error Code Equivalence

| AWS Error Code | Azure Equivalent | Notes |
|---|---|---|
| `NoSuchKey` | `BlobNotFound` (404) | Object/blob not found |
| `AccessDenied` | `AuthorizationPermissionMismatch` (403) | RBAC not assigned |
| `ResourceNotFoundException` | `CosmosHttpResponseError` (404) | Item not found |
| `ConditionalCheckFailedException` | `CosmosHttpResponseError` (412) | Optimistic concurrency failure |
| `ThrottlingException` | `HttpResponseError` (429) | Rate limited |
| `ServiceUnavailableException` | `ServiceRequestError` (503) | Transient error — retry |

---

## Rules

- **Never leave any `import boto3` or `@aws-sdk` in output files** — verify with `grep -rn "boto3\|@aws-sdk" outputs/azure-functions/`.
- **Never use `ClientSecretCredential` or hardcoded keys** — always `DefaultAzureCredential`.
- **Never call Key Vault SDK at runtime for secrets** unless the secret changes frequently — prefer app setting Key Vault references.
- **Never use `CONTAINER_NAME`** as an env var name — use `BLOB_CONTAINER_NAME` instead (reserved name).
- **Always update `requirements.txt`** with every new Azure package added.
- **Always use Python 3.11** — 3.12 and 3.13 are not supported by Azure Functions v4.

## Output

- Refactored Python/TypeScript files with zero boto3 / @aws-sdk references
- `outputs/azure-functions/requirements.txt` listing all Azure SDK packages used
- `grep -rn "boto3\|@aws-sdk" outputs/azure-functions/` returns no matches
