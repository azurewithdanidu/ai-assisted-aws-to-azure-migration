---
name: sdk-migration
description: Replace AWS SDK calls with Azure SDK equivalents — Python (boto3), Node.js/TypeScript (@aws-sdk), and Java (AWS SDK v2) package mapping, client instantiation, authentication, and runtime gotchas
---

# SDK Migration Skill

## Purpose

Replace every boto3 (Python), `@aws-sdk` (Node.js/TypeScript), and AWS SDK v2 (Java) API call with the correct Azure SDK equivalent, ensuring no AWS SDK dependencies remain in refactored output files.

## When to Use

When rewriting Lambda source files or other application code that contains boto3, `@aws-sdk`, or `software.amazon.awssdk` imports.

## Process

1. Scan the source for all AWS SDK usage:
   ```bash
   # Python
   grep -n "boto3\.\|@aws-sdk\|import boto3" source-app/app-code/lambda/<function>/app.py
   # Node.js/TypeScript
   grep -rn "@aws-sdk" source-app/app-code/
   # Java
   grep -rn "software.amazon.awssdk" source-app/app-code/
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

## SDK Mappings — Java (AWS SDK v2 → Azure SDK for Java)

### Storage: S3 → Azure Blob Storage

```java
// BEFORE (AWS SDK v2)
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.*;
import software.amazon.awssdk.core.sync.RequestBody;

S3Client s3 = S3Client.builder().region(Region.US_EAST_1).build();

// Upload
s3.putObject(PutObjectRequest.builder().bucket(bucket).key(key).build(),
             RequestBody.fromBytes(data));

// Download
ResponseInputStream<GetObjectResponse> obj = s3.getObject(
    GetObjectRequest.builder().bucket(bucket).key(key).build());

// AFTER (azure-storage-blob)
import com.azure.storage.blob.*;
import com.azure.identity.DefaultAzureCredentialBuilder;

BlobServiceClient blobServiceClient = new BlobServiceClientBuilder()
    .endpoint("https://" + System.getenv("AZURE_STORAGE_ACCOUNT_NAME") + ".blob.core.windows.net")
    .credential(new DefaultAzureCredentialBuilder().build())
    .buildClient();

BlobClient blobClient = blobServiceClient
    .getBlobContainerClient(container)
    .getBlobClient(blobName);

// Upload
blobClient.upload(BinaryData.fromBytes(data), true);

// Download
byte[] downloaded = blobClient.downloadContent().toBytes();
```

### NoSQL Database: DynamoDB → Cosmos DB

```java
// BEFORE (AWS SDK v2)
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.*;

DynamoDbClient dynamo = DynamoDbClient.create();
Map<String, AttributeValue> key = Map.of("orderId", AttributeValue.fromS(id));
GetItemResponse response = dynamo.getItem(GetItemRequest.builder()
    .tableName("orders").key(key).build());

// AFTER (azure-cosmos)
import com.azure.cosmos.*;
import com.azure.cosmos.models.*;
import com.azure.identity.DefaultAzureCredentialBuilder;

CosmosClient cosmosClient = new CosmosClientBuilder()
    .endpoint(System.getenv("COSMOS_ENDPOINT"))
    .credential(new DefaultAzureCredentialBuilder().build())
    .buildClient();

CosmosContainer container = cosmosClient
    .getDatabase(System.getenv("COSMOS_DB"))
    .getContainer("orders");

// Read
CosmosItemResponse<OrderItem> response = container.readItem(id, new PartitionKey(id), OrderItem.class);
OrderItem item = response.getItem();

// Write
container.upsertItem(item);
```

### Messaging: SQS → Azure Service Bus

```java
// BEFORE (AWS SDK v2)
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;

SqsClient sqs = SqsClient.create();
sqs.sendMessage(SendMessageRequest.builder()
    .queueUrl(System.getenv("QUEUE_URL"))
    .messageBody(payload)
    .build());

// AFTER (azure-messaging-servicebus)
import com.azure.messaging.servicebus.*;
import com.azure.identity.DefaultAzureCredentialBuilder;

ServiceBusSenderClient sender = new ServiceBusClientBuilder()
    .fullyQualifiedNamespace(System.getenv("SERVICE_BUS_NAMESPACE"))
    .credential(new DefaultAzureCredentialBuilder().build())
    .sender()
    .queueName(System.getenv("QUEUE_NAME"))
    .buildClient();

sender.sendMessage(new ServiceBusMessage(payload));
sender.close();
```

### Secrets: Secrets Manager → Key Vault

```java
// BEFORE (AWS SDK v2)
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest;

SecretsManagerClient sm = SecretsManagerClient.create();
String secret = sm.getSecretValue(GetSecretValueRequest.builder()
    .secretId("my-secret").build()).secretString();

// AFTER (azure-security-keyvault-secrets)
import com.azure.security.keyvault.secrets.SecretClient;
import com.azure.security.keyvault.secrets.SecretClientBuilder;
import com.azure.identity.DefaultAzureCredentialBuilder;

SecretClient secretClient = new SecretClientBuilder()
    .vaultUrl("https://" + System.getenv("KEY_VAULT_NAME") + ".vault.azure.net")
    .credential(new DefaultAzureCredentialBuilder().build())
    .buildClient();

String secret = secretClient.getSecret("my-secret").getValue();

// Alternative: inject via Key Vault reference in app settings (preferred — zero SDK calls at runtime):
String secret = System.getenv("MY_SECRET"); // Azure resolves @Microsoft.KeyVault(...) reference
```

### Events: SNS → Azure Event Grid / Service Bus Topics

```java
// BEFORE (AWS SDK v2 — SNS publish)
import software.amazon.awssdk.services.sns.SnsClient;
import software.amazon.awssdk.services.sns.model.PublishRequest;

SnsClient sns = SnsClient.create();
sns.publish(PublishRequest.builder().topicArn(topicArn).message(payload).build());

// AFTER (azure-messaging-eventgrid — fan-out pattern)
import com.azure.messaging.eventgrid.*;
import com.azure.core.models.CloudEvent;
import com.azure.core.credential.AzureKeyCredential;

EventGridPublisherClient<CloudEvent> client = new EventGridPublisherClientBuilder()
    .endpoint(System.getenv("AZURE_EVENT_GRID_ENDPOINT"))
    .credential(new AzureKeyCredential(System.getenv("AZURE_EVENT_GRID_KEY")))
    .buildCloudEventPublisherClient();

client.sendEvent(new CloudEvent("/my-service", eventType, BinaryData.fromString(payload), "application/json"));
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
| `@aws-sdk/client-sns` | `@azure/eventgrid` |
| `@aws-sdk/client-kinesis` | `@azure/event-hubs` |
| `@aws-sdk/client-secrets-manager` | No runtime dependency — use Key Vault app setting references |
| Auth (all) | `@azure/identity` |

### Java (Maven pom.xml)

Use the **Azure SDK BOM** to manage all Azure SDK versions together:

```xml
<dependencyManagement>
  <dependencies>
    <dependency>
      <groupId>com.azure</groupId>
      <artifactId>azure-sdk-bom</artifactId>
      <version>1.2.26</version>
      <type>pom</type>
      <scope>import</scope>
    </dependency>
  </dependencies>
</dependencyManagement>
```

Then add only the clients you need (no version required when using BOM):

| AWS SDK v2 artifact | Azure SDK artifact | groupId |
|---|---|---|
| `s3` | `azure-storage-blob` | `com.azure` |
| `dynamodb` | `azure-cosmos` | `com.azure` |
| `sqs` | `azure-messaging-servicebus` | `com.azure` |
| `secretsmanager` | `azure-security-keyvault-secrets` | `com.azure` |
| `sns` | `azure-messaging-eventgrid` | `com.azure` |
| `kinesis` | `azure-messaging-eventhubs` | `com.azure` |
| Auth (all) | `azure-identity` | `com.azure` |

Minimum `pom.xml` dependencies for a migrated Java service:
```xml
<dependency><groupId>com.azure</groupId><artifactId>azure-identity</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-storage-blob</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-cosmos</artifactId></dependency>
<dependency><groupId>com.azure</groupId><artifactId>azure-messaging-servicebus</artifactId></dependency>
```

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

---

## Companion Scripts

| Script | Purpose |
|---|---|
| `scripts/scan-aws-sdk.ps1` | Scans output code for residual AWS SDK imports; exits 1 if any found |
| `scripts/scan-aws-sdk.sh` | Bash equivalent of the above |

Run after every refactoring pass to verify no AWS SDK references remain:

```powershell
./.github/skills/agents/code-refactor/scripts/scan-aws-sdk.ps1 -ScanPath "outputs/azure-functions"
```

Also wire into CI as a gate step before the deployment job:

```yaml
- name: Scan for AWS SDK residue
  run: pwsh .github/skills/agents/code-refactor/scripts/scan-aws-sdk.ps1
```

---

## References

### Microsoft / Azure Documentation

| Topic | Link |
|---|---|
| Azure SDK for Python overview | https://learn.microsoft.com/en-us/azure/developer/python/sdk/azure-sdk-overview |
| azure-storage-blob (Python) | https://learn.microsoft.com/en-us/python/api/overview/azure/storage-blob-readme |
| azure-cosmos (Python) | https://learn.microsoft.com/en-us/python/api/overview/azure/cosmos-readme |
| azure-servicebus (Python) | https://learn.microsoft.com/en-us/python/api/overview/azure/servicebus-readme |
| azure-eventgrid (Python) | https://learn.microsoft.com/en-us/python/api/overview/azure/eventgrid-readme |
| azure-eventhub (Python) | https://learn.microsoft.com/en-us/python/api/overview/azure/eventhub-readme |
| azure-identity (Python) | https://learn.microsoft.com/en-us/python/api/overview/azure/identity-readme |
| azure-keyvault-secrets (Python) | https://learn.microsoft.com/en-us/python/api/overview/azure/keyvault-secrets-readme |
| Azure SDK for JavaScript | https://learn.microsoft.com/en-us/azure/developer/javascript/sdk/azure-sdk-overview |
| @azure/storage-blob (JS/TS) | https://learn.microsoft.com/en-us/javascript/api/overview/azure/storage-blob-readme |
| @azure/cosmos (JS/TS) | https://learn.microsoft.com/en-us/javascript/api/overview/azure/cosmos-readme |
| @azure/service-bus (JS/TS) | https://learn.microsoft.com/en-us/javascript/api/overview/azure/service-bus-readme |
| Azure SDK for Java overview | https://learn.microsoft.com/en-us/azure/developer/java/sdk/overview |
| Azure SDK BOM (Java) | https://learn.microsoft.com/en-us/azure/developer/java/sdk/azure-sdk-library-package-index |
| Azure Functions reserved env vars | https://learn.microsoft.com/en-us/azure/azure-functions/functions-app-settings |
| Key Vault references in App Service | https://learn.microsoft.com/en-us/azure/app-service/app-service-key-vault-references |

### AWS Documentation

| Topic | Link |
|---|---|
| boto3 SDK reference | https://boto3.amazonaws.com/v1/documentation/api/latest/index.html |
| boto3 S3 client | https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3.html |
| boto3 DynamoDB resource | https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/dynamodb.html |
| boto3 SQS client | https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/sqs.html |
| boto3 Secrets Manager client | https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/secretsmanager.html |
| AWS SDK for JavaScript v3 | https://docs.aws.amazon.com/AWSJavaScriptSDK/v3/latest/ |
| AWS SDK for Java v2 | https://docs.aws.amazon.com/sdk-for-java/latest/developer-guide/home.html |

### Best Practices

- **Zero-tolerance for AWS SDK residue:** Run `grep -rn "boto3\|@aws-sdk\|software.amazon.awssdk" outputs/azure-functions/` as the final gate before declaring migration done.
- **Key Vault references over SDK:** For secrets that don't change at runtime, inject via `@Microsoft.KeyVault(SecretUri=...)` in app settings \u2014 no SDK call, no latency, no token refresh logic needed.
- **Azure SDK BOM for Java:** Always use the BOM to avoid version conflicts between Azure SDK artifacts \u2014 never specify individual artifact versions manually.
- **`DefaultAzureCredential` is environment-agnostic:** The same code runs on a developer's laptop (`az login`), in CI (environment credentials), and in Azure (managed identity). This is by design \u2014 never override it with `ManagedIdentityCredential` or `ClientSecretCredential`.
