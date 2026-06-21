---
name: sdk-migration
description: Replace boto3 SDK calls with Azure SDK equivalents — package mapping, import paths, client instantiation, and authentication
---

# SDK Migration Skill

## Purpose

Replace every boto3 API call with the correct Azure SDK equivalent, ensuring no AWS SDK dependencies remain in refactored output files.

## When to Use

When rewriting Lambda source files that contain boto3 client or resource calls.

## Process

1. Scan the Lambda source file for all boto3 usage:
   ```bash
   grep -n "boto3\." source-app/app-code/lambda/<function>/app.py
   ```
2. For each boto3 call, apply the mapping table below.
3. Replace the import block at the top of the file.
4. Update `outputs/azure-functions/requirements.txt` with the Azure packages needed.

## SDK Mapping

### Storage (S3 → Blob Storage)

```python
# BEFORE (boto3)
import boto3
s3 = boto3.client('s3')
s3.put_object(Bucket='my-bucket', Key='file.txt', Body=data)
response = s3.get_object(Bucket='my-bucket', Key='file.txt')
content = response['Body'].read()

# AFTER (azure-storage-blob)
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

credential = DefaultAzureCredential()
blob_service = BlobServiceClient(
    account_url=f"https://{os.environ['STORAGE_ACCOUNT_NAME']}.blob.core.windows.net",
    credential=credential
)
container = blob_service.get_container_client(os.environ['CONTAINER_NAME'])
container.upload_blob('file.txt', data, overwrite=True)
blob = container.get_blob_client('file.txt')
content = blob.download_blob().readall()
```

### NoSQL Database (DynamoDB → Cosmos DB)

```python
# BEFORE (boto3)
import boto3
dynamo = boto3.resource('dynamodb')
table = dynamo.Table(os.environ['TABLE_NAME'])
table.put_item(Item={'pk': 'key', 'data': 'value'})
response = table.get_item(Key={'pk': 'key'})

# AFTER (azure-cosmos)
from azure.cosmos import CosmosClient
from azure.identity import DefaultAzureCredential

credential = DefaultAzureCredential()
client = CosmosClient(url=os.environ['COSMOS_ENDPOINT'], credential=credential)
container = client.get_database_client(os.environ['COSMOS_DB']).get_container_client(os.environ['COSMOS_CONTAINER'])
container.upsert_item({'id': 'key', 'data': 'value'})
item = container.read_item(item='key', partition_key='key')
```

### Messaging (SQS → Service Bus)

```python
# BEFORE (boto3)
import boto3
sqs = boto3.client('sqs')
sqs.send_message(QueueUrl=os.environ['QUEUE_URL'], MessageBody=json.dumps(payload))

# AFTER (azure-servicebus)
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from azure.identity import DefaultAzureCredential

credential = DefaultAzureCredential()
with ServiceBusClient(os.environ['SERVICE_BUS_NAMESPACE'], credential) as sb_client:
    with sb_client.get_queue_sender(os.environ['QUEUE_NAME']) as sender:
        sender.send_messages(ServiceBusMessage(json.dumps(payload)))
```

### Secrets (Secrets Manager → Key Vault reference)

```python
# BEFORE (boto3)
import boto3
sm = boto3.client('secretsmanager')
secret = sm.get_secret_value(SecretId='my-secret')['SecretString']

# AFTER — no SDK call needed at runtime
# The secret is injected via Key Vault reference in app settings:
# MY_SECRET = @Microsoft.KeyVault(SecretUri=https://<kv>.vault.azure.net/secrets/my-secret/)
secret = os.environ['MY_SECRET']  # Azure resolves the KV reference automatically
```

## Package Reference

| boto3 client | Azure package | Install |
|---|---|---|
| `s3` | `azure-storage-blob` | `pip install azure-storage-blob` |
| `dynamodb` | `azure-cosmos` | `pip install azure-cosmos` |
| `sqs` | `azure-servicebus` | `pip install azure-servicebus` |
| `secretsmanager` | Key Vault app setting reference (no package) | — |
| `sns` | `azure-eventgrid` | `pip install azure-eventgrid` |
| `ses` | `azure-communication-email` | `pip install azure-communication-email` |
| Auth (all) | `azure-identity` | `pip install azure-identity` |

## Rules

- **Never leave any `import boto3` in output files** — verify with `grep -n "boto3" <file>`.
- **Never use `ClientSecretCredential` or hardcoded keys** — always `DefaultAzureCredential`.
- **Never call Key Vault SDK at runtime for secrets** unless the secret changes frequently — prefer app setting Key Vault references.
- **Always update `requirements.txt`** with every new Azure package added.

## Output

- Refactored Python files with zero boto3 references
- `outputs/azure-functions/requirements.txt` listing all Azure SDK packages used
- `grep -rn "boto3" outputs/azure-functions/` returns no matches
