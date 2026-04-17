---
name: code-refactoring-instructions
description: Custom instructions for Code Refactor Agent
applyTo: code-refactor
---

# Code Refactor Agent - Custom Instructions

## Business Logic Preservation Rules

### Golden Rule
**NEVER modify business logic** - The refactored code must behave identically to the original code.

### Input/Output Equivalence
- Same inputs must produce same outputs
- Error conditions must be handled identically
- Data transformations must be mathematically equivalent

### Example: Preserving Business Logic

```javascript
// DO NOT change the business logic, only the SDK calls

// ✅ CORRECT - Logic preserved, SDK changed
export async function calculateOrderTotal(items: any[]) {
  // Logic unchanged
  const subtotal = items.reduce((sum, item) => sum + (item.price * item.quantity), 0);
  const tax = subtotal * 0.1;
  const total = subtotal + tax;
  
  // Only SDK call changed
  await storageAccount.uploadFile('orders', `order-${Date.now()}.json`, JSON.stringify({
    subtotal, tax, total
  }));
  
  return total;
}

// ❌ WRONG - Changed business logic
export async function calculateOrderTotal(items: any[]) {
  // Changed calculation - WRONG!
  const subtotal = items.reduce((sum, item) => sum + (item.price * item.quantity * 1.1), 0);
  // ... rest of code
}
```

## Error Handling Equivalence

### Mapping AWS Errors to Azure Errors

| AWS Error | Azure Error | Handling |
|---|---|---|
| `NoSuchBucket` | `ContainerNotFound` | Same: throw "Container not found" |
| `NoSuchKey` | `BlobNotFound` | Same: throw "Blob not found" |
| `AccessDenied` | `AuthorizationPermissionMismatch` | Same: throw "Access denied" |
| `ThrottlingException` | `RequestRateTooLarge` | Same: retry with exponential backoff |
| `ServiceUnavailable` | `ServiceUnavailable` | Same: retry after delay |

### Example: Equivalent Error Handling

```javascript
// AWS Error Handling
export async function getS3Object(bucketName: string, key: string): Promise<Buffer> {
  try {
    const command = new GetObjectCommand({ Bucket: bucketName, Key: key });
    const response = await s3Client.send(command);
    return Buffer.from(response.Body);
  } catch (error: any) {
    if (error.Code === 'NoSuchBucket') {
      throw new Error(`Bucket ${bucketName} not found`);
    } else if (error.Code === 'NoSuchKey') {
      throw new Error(`Key ${key} not found`);
    } else if (error.Code === 'AccessDenied') {
      throw new Error('Access denied to bucket');
    }
    throw error;
  }
}

// Azure Error Handling - EQUIVALENT
export async function getBlobStorage(containerName: string, blobName: string): Promise<Buffer> {
  try {
    const containerClient = blobServiceClient.getContainerClient(containerName);
    const blockBlobClient = containerClient.getBlockBlobClient(blobName);
    const downloadBlockBlobResponse = await blockBlobClient.download();
    return downloadBlockBlobResponse.contentAsBuffer;
  } catch (error: any) {
    if (error.code === 'ContainerNotFound') {
      throw new Error(`Container ${containerName} not found`);
    } else if (error.code === 'BlobNotFound') {
      throw new Error(`Blob ${blobName} not found`);
    } else if (error.code === 'AuthorizationPermissionMismatch') {
      throw new Error('Access denied to container');
    }
    throw error;
  }
}

// Same error messages = same caller behavior
```

## Testing Requirements

### Unit Test Standards

Every refactored function must have:
1. **Happy path test** - Normal operation succeeds
2. **Error path tests** - Each error condition handled
3. **Edge case tests** - Boundary conditions
4. **Integration tests** - Service interaction verified

### Example Test Structure

```javascript
describe('Order Service - AWS to Azure Migration', () => {
  // UNIT TESTS - SDK mocked
  describe('uploadOrder (business logic)', () => {
    test('should calculate and upload order total', async () => {
      const order = { items: [{ price: 100, quantity: 2 }] };
      await uploadOrder(order);
      // Verify calculation: 2 * $100 = $200 subtotal
      // Verify upload called with correct data
    });
    
    test('should throw when container not found', async () => {
      containerMock.upload.rejects({ code: 'ContainerNotFound' });
      await expect(uploadOrder(order)).rejects.toThrow('Container not found');
    });
  });
  
  // INTEGRATION TESTS - Real Azure Storage (staging)
  describe('uploadOrder (integration)', () => {
    test('should actually upload to Azure Storage', async () => {
      const result = await uploadOrder(testOrder);
      const downloaded = await downloadOrder(result.id);
      expect(downloaded).toEqual(testOrder);
    });
  });
});
```

## Pull Request Template Standards

### Required Sections

Every PR must include:

1. **Migration Summary** - What service was migrated
2. **Files Changed** - List of modified files
3. **Key Transformations** - SDK call examples
4. **Testing** - What tests were run
5. **Verification** - How parity was confirmed
6. **Breaking Changes** - Any breaking changes (usually none)
7. **Rollback Plan** - How to rollback if needed

### Example PR Format

```markdown
# Code Refactor: Order Service Lambda to Azure Functions

## Summary
Migrated order-processor Lambda function from AWS SDK to Azure SDK.
- Replaced AWS SDK with Azure SDK for storage and database
- Updated authentication to use Managed Identity
- All business logic preserved, behavior verified identical

## Files Changed
- `src/services/order-processor.ts` - SDK updates
- `src/services/__tests__/order-processor.test.ts` - Test updates
- `package.json` - Dependency updates
- `.env.example` - Environment variables

## Key Transformations

### S3 → Blob Storage
\`\`\`
BEFORE: await s3Client.send(new PutObjectCommand(...))
AFTER:  await blobClient.upload(...)
\`\`\`

### DynamoDB → Cosmos DB
\`\`\`
BEFORE: await documentClient.send(new PutCommand(...))
AFTER:  await container.items.create(...)
\`\`\`

## Testing Results
- Unit tests: 45/45 passing ✅
- Integration tests: 8/8 passing ✅
- Code coverage: 87% (maintained) ✅
- Performance: <5% variance ✅

## Verification
- [x] Behavior identical to original (tested with same data)
- [x] Error handling equivalent
- [x] Performance comparable
- [x] No hardcoded credentials
- [x] Managed Identity used
- [x] All imports resolve
```

## Code Style Maintenance

### Language-Specific Standards

**JavaScript/TypeScript:**
- Maintain existing indentation (2 spaces or 4 spaces)
- Preserve existing variable naming conventions
- Keep same error handling patterns
- Maintain existing code structure

**Python:**
- Follow PEP 8 standards
- Maintain existing import grouping
- Keep consistent docstring style
- Preserve existing type hints

**Go:**
- Follow Go fmt standards
- Maintain existing error handling patterns
- Keep same naming conventions
- Preserve existing code structure

### Example: Maintaining Code Style

```javascript
// Original AWS code style
const uploadFile = async (bucketName, key, body) => {
  const result = await s3Client.send(
    new PutObjectCommand({ Bucket: bucketName, Key: key, Body: body })
  );
  return result;
};

// Azure refactor - MAINTAIN STYLE
const uploadFile = async (containerName, blobName, body) => {
  const result = await blobServiceClient
    .getContainerClient(containerName)
    .getBlockBlobClient(blobName)
    .upload(body);
  return result;
};
```

## Validation Checklist

Before marking refactoring complete, verify:

### Code Quality
- [ ] No AWS SDK imports remain
- [ ] All Azure SDK imports added
- [ ] No hardcoded credentials anywhere
- [ ] DefaultAzureCredential used
- [ ] Code style consistent
- [ ] No linting errors
- [ ] All imports resolve

### Functional Equivalence
- [ ] All unit tests pass
- [ ] All integration tests pass
- [ ] All error paths tested
- [ ] Same input → same output
- [ ] Error messages same or equivalent
- [ ] Behavior verified identical

### Documentation
- [ ] Pull request has detailed description
- [ ] All changes documented
- [ ] Migration notes included
- [ ] Environment variables updated
- [ ] Dependencies updated in lock files
- [ ] Rollback plan documented

### Security
- [ ] No credentials in code
- [ ] Managed Identity configured
- [ ] No API keys hardcoded
- [ ] Secrets in Key Vault
- [ ] No debug credentials

## Common Refactoring Patterns

### Pattern 1: Simple Getter/Setter

```javascript
// Pattern: Simple data fetch and store

// AWS
async function getData(id) {
  const result = await dynamodb.send(new GetCommand({ Key: { id } }));
  return result.Item;
}

async function setData(id, data) {
  await dynamodb.send(new PutCommand({ Item: { id, ...data } }));
}

// Azure - Parallel structure
async function getData(id) {
  return await container.item(id).read();
}

async function setData(id, data) {
  await container.items.create({ id, ...data });
}
```

### Pattern 2: Collection Operations

```javascript
// Pattern: Scan/query with filters

// AWS
async function getOrdersByStatus(status) {
  const result = await dynamodb.send(new QueryCommand({
    IndexName: 'status-index',
    KeyConditionExpression: 'status = :status',
    ExpressionAttributeValues: { ':status': status }
  }));
  return result.Items;
}

// Azure - Parallel structure
async function getOrdersByStatus(status) {
  const query = "SELECT * FROM orders WHERE orders.status = @status";
  const { resources } = await container.items.query({
    query,
    parameters: [{ name: "@status", value: status }]
  }).fetchAll();
  return resources;
}
```

### Pattern 3: Error Handling with Retry

```javascript
// Pattern: Retry with exponential backoff

// AWS
async function retryableOperation() {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      return await s3Client.send(command);
    } catch (error) {
      if (error.Code === 'ThrottlingException' && attempt < 2) {
        await sleep(Math.pow(2, attempt) * 1000);
        continue;
      }
      throw error;
    }
  }
}

// Azure - Parallel structure
async function retryableOperation() {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      return await blobClient.upload(data);
    } catch (error) {
      if (error.code === 'RequestRateTooLarge' && attempt < 2) {
        await sleep(Math.pow(2, attempt) * 1000);
        continue;
      }
      throw error;
    }
  }
}
```

## Tips & Best Practices

✅ **Do:**
- Map error types and handle equivalently
- Update tests alongside code
- Use Managed Identity everywhere
- Store all secrets in Key Vault
- Maintain code style and structure
- Test both happy path and errors
- Document in pull request
- Verify parity thoroughly

❌ **Don't:**
- Change business logic
- Skip error handling
- Hardcode credentials
- Forget to update tests
- Change code structure unnecessarily
- Skip integration testing
- Merge without full testing
- Assume equivalent behavior

## Troubleshooting Common Issues

### Issue: Tests Fail After Refactor

**Cause:** SDK call semantics differ slightly

**Resolution:**
1. Compare error types between AWS and Azure
2. Check API response structures
3. Verify test mocks match Azure SDK behavior
4. Check for missing credentials/permissions

### Issue: Code Compiles But Behaves Differently

**Cause:** Logic change despite best efforts

**Resolution:**
1. Review side-by-side diff carefully
2. Check for changed conditionals
3. Verify transformation logic unchanged
4. Run original test suite against original code
5. Compare output byte-for-byte

### Issue: Managed Identity Fails

**Cause:** Incorrect configuration or permissions

**Resolution:**
1. Verify Managed Identity assigned to resource
2. Check role assignments on resources
3. Ensure Key Vault access policies updated
4. Verify MSI endpoint accessible

---

## Output Location

All refactored code **must** be written to the `outputs/` folder, mirroring the structure used by the IaC and architecture agents. Never write refactored output back into the `app-code/` source tree.

### Required Output Structure

```
outputs/
├── bicep-templates/          ← IaC (Bicep) — managed by iac-transformation agent
├── azure-architecture-output/ ← Architecture docs — managed by azure-architect agent
├── aws-migration-artifacts/  ← Discovery artifacts — managed by aws-discovery agent
├── azure-functions/          ← Refactored backend functions (Python / Node.js)
│   ├── function_app.py       ← Single-file Python v2 programming model
│   ├── requirements.txt      ← Azure SDK dependencies (replaces boto3/botocore)
│   ├── host.json             ← Azure Functions host config
│   └── local.settings.json   ← Local dev environment variables
└── static-web-app/           ← Refactored frontend / static web app
    └── app.html              ← Frontend with AWS SDK removed, plain fetch + x-functions-key
```

### Rules

- **Source** files are read-only references from `app-code/lambda/` (Python) or `app-code/lambda-functions/` (Node.js) and `app-code/build/` (frontend).
- **Target** for backend functions: `outputs/azure-functions/`
- **Target** for frontend / static web app code: `outputs/static-web-app/`
- Do **not** place outputs in `app-code/azure-functions/` or any other non-`outputs/` path.
- The `outputs/` folder is the single source of truth for all migration deliverables.

---

**Last Updated:** April 2026  
**Version:** 1.1
