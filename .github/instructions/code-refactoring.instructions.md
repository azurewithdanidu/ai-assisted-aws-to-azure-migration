---
name: code-refactoring-instructions
description: Custom instructions for Code Refactor Agent
applyTo: code-refactor
---

# Code Refactor Agent - Custom Instructions

> **IGNORE THE `backup/` FOLDER** — Never read from or write to the `backup/` directory. All output must go to `outputs/azure-functions/`.

## Business Logic Preservation Rules

### Golden Rule
**NEVER modify business logic** - The refactored code must behave identically to the original code.
- Use the detailed design document for reference and guidance in outoputs/azure-architecture-output/

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


> For SDK-specific error handling equivalence, testing patterns, and PR template structure — refer to the `code-refactor` skill.