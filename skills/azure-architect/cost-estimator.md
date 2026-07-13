---
name: cost-estimator
description: Fetch real Azure Retail Prices API data (no auth) for any Azure service in the target architecture and emit defensible per-SKU costs into cost-comparison.md. Read before any cost output.
---

# Cost Estimator Skill

## Purpose

Replace hand-estimated costs in `outputs/azure-architecture-output/cost-comparison.md` with real SKU prices sourced directly from the Azure Retail Prices API for **any Azure service** in the target architecture. Every number in the output must trace back to an API-returned `retailPrice` field.

---

## Azure Retail Prices API

**Base URL:** `https://prices.azure.com/api/retail/prices`  
**Auth:** None required.  
**Method:** HTTP GET with OData `$filter` query parameter.  
**Response schema:**

```json
{
  "BillingCurrency": "USD",
  "Items": [
    {
      "retailPrice": 0.182,
      "unitPrice": 0.182,
      "unitOfMeasure": "1 Hour",
      "currencyCode": "USD",
      "skuName": "Premium",
      "productName": "Premium Functions",
      "meterName": "Premium vCPU Duration",
      "serviceName": "Functions",
      "serviceFamily": "Compute",
      "armRegionName": "australiaeast",
      "type": "Consumption"
    }
  ],
  "NextPageLink": null,
  "Count": 2
}
```

**OData filter fields available:**

| Field | Description | Example value |
|---|---|---|
| `armRegionName` | Azure region ARM name | `australiaeast`, `eastus`, `westeurope` |
| `serviceName` | Top-level service name | `Functions`, `Storage`, `SQL Database` |
| `serviceFamily` | Broad category | `Compute`, `Storage`, `Networking`, `Databases` |
| `productName` | Specific product within a service | `Premium Functions`, `Blob Storage` |
| `skuName` | Tier or redundancy variant | `EP1`, `Hot LRS`, `General Purpose` |
| `meterName` | Individual billing dimension | `Premium vCPU Duration`, `Hot LRS Data Stored` |
| `priceType` | Pricing model | `Consumption`, `Reservation`, `DevTest` |
| `currencyCode` | Currency | `USD` |
| `type` | Alias for priceType | `Consumption` |

---

## Universal Discovery Workflow

Use this process for **every service** in the target architecture, regardless of service type.

### Step 1 — Discover available product names

Start broad. If you don't know the exact `productName`, query by `serviceName` or a `contains()` substring match:

```
GET https://prices.azure.com/api/retail/prices?$filter=armRegionName eq '<region>' and serviceName eq '<service>'
```

Or by substring when the service name is uncertain:

```
GET https://prices.azure.com/api/retail/prices?$filter=armRegionName eq '<region>' and contains(productName,'<keyword>')
```

Scan the returned `Items` to identify the correct `productName`, `skuName`, and `meterName` values for the tier you are costing.

> **If `Count` is 0:** The service may be global (no per-region meter), or the product name differs from the portal display name. Drop `armRegionName` and add `currencyCode eq 'USD'` instead, then re-query.

### Step 2 — Narrow to the exact meter

Refine the filter to `productName eq '<exact value>'` and check all returned `meterName` values. A single product typically has multiple meters (e.g., vCPU hours, memory hours, data stored, read ops, write ops). Identify every meter that applies to the workload.

```
GET https://prices.azure.com/api/retail/prices?$filter=armRegionName eq '<region>' and productName eq '<exact product name>' and priceType eq 'Consumption'
```

### Step 3 — Extract and calculate

For each relevant meter:
1. Read `retailPrice` and `unitOfMeasure` from the response.
2. Estimate monthly units from workload assumptions (hours, GB, operations, etc.).
3. Multiply: `retailPrice × estimated_units = monthly_cost`.
4. Tag the row `API ✓` in the output table.

### Step 4 — Handle pagination

If `NextPageLink` is not null, follow it to retrieve additional pages before selecting the correct meter.

### Step 5 — Handle services with no regional meter

Some services (Static Web Apps, Private Link, Azure DNS, Front Door, CDN) are globally priced. Drop `armRegionName` and filter by `currencyCode eq 'USD'` only. Note this in the Assumptions section of the output.

---

## Service Catalog — Filter Reference

Quick-reference starting queries for common Azure services. All examples use `australiaeast`; substitute your deployment region.

### Compute

| Service | Starting filter |
|---|---|
| Functions — Premium (EP1/EP2/EP3) | `productName eq 'Premium Functions' and armRegionName eq '<region>'` |
| Functions — Flex Consumption | `contains(productName,'Flex Consumption') and armRegionName eq '<region>'` |
| Functions — Consumption (pay-per-call) | `productName eq 'Functions' and armRegionName eq '<region>'` |
| App Service (Basic/Standard/Premium) | `serviceName eq 'Azure App Service' and armRegionName eq '<region>'` |
| Container Apps | `contains(productName,'Container Apps') and armRegionName eq '<region>'` |
| Azure Kubernetes Service (AKS) | `serviceName eq 'Azure Kubernetes Service' and armRegionName eq '<region>'` |
| Azure Container Instances | `serviceName eq 'Container Instances' and armRegionName eq '<region>'` |
| Virtual Machines (e.g. D2s_v3) | `serviceName eq 'Virtual Machines' and armRegionName eq '<region>' and contains(skuName,'D2s')` |
| Azure Batch | `serviceName eq 'Azure Batch' and armRegionName eq '<region>'` |

### Storage

| Service | Starting filter |
|---|---|
| Blob Storage — Hot LRS | `contains(productName,'Blob Storage') and skuName eq 'Hot LRS' and armRegionName eq '<region>'` |
| Blob Storage — Cool LRS | `contains(productName,'Blob Storage') and skuName eq 'Cool LRS' and armRegionName eq '<region>'` |
| Blob Storage — Archive LRS | `contains(productName,'Blob Storage') and skuName eq 'Archive LRS' and armRegionName eq '<region>'` |
| Azure Files — LRS | `contains(productName,'Azure Files') and contains(skuName,'LRS') and armRegionName eq '<region>'` |
| Azure Data Lake Storage Gen2 | `contains(productName,'Azure Data Lake Storage') and armRegionName eq '<region>'` |
| Azure Disk (Managed — P10/P20/P30) | `serviceName eq 'Storage' and contains(skuName,'P10') and armRegionName eq '<region>'` |
| Azure NetApp Files | `serviceName eq 'Azure NetApp Files' and armRegionName eq '<region>'` |

### Databases

| Service | Starting filter |
|---|---|
| Azure SQL Database (General Purpose) | `contains(productName,'SQL Database') and contains(skuName,'General Purpose') and armRegionName eq '<region>'` |
| Azure SQL Database (Business Critical) | `contains(productName,'SQL Database') and contains(skuName,'Business Critical') and armRegionName eq '<region>'` |
| Azure SQL Managed Instance | `contains(productName,'SQL Managed Instance') and armRegionName eq '<region>'` |
| Azure Database for PostgreSQL Flexible | `contains(productName,'Azure Database for PostgreSQL') and contains(skuName,'Flexible') and armRegionName eq '<region>'` |
| Azure Database for MySQL Flexible | `contains(productName,'Azure Database for MySQL') and armRegionName eq '<region>'` |
| Azure Cosmos DB (NoSQL) | `contains(productName,'Cosmos DB') and armRegionName eq '<region>'` |
| Azure Cache for Redis | `contains(productName,'Cache for Redis') and armRegionName eq '<region>'` |
| Azure SQL Elastic Pool | `contains(productName,'SQL Database Elastic Pool') and armRegionName eq '<region>'` |

### Networking

| Service | Starting filter |
|---|---|
| Private Endpoint (Virtual Network Private Link) | `contains(productName,'Private Link') and currencyCode eq 'USD'` |
| Azure DNS Private Zones | `contains(productName,'DNS') and armRegionName eq '<region>'` |
| Azure Front Door (Standard/Premium) | `contains(productName,'Azure Front Door') and currencyCode eq 'USD'` |
| Azure Application Gateway (v2) | `contains(productName,'Application Gateway') and armRegionName eq '<region>'` |
| Azure Load Balancer (Standard) | `contains(productName,'Load Balancer') and armRegionName eq '<region>'` |
| Azure VPN Gateway | `contains(productName,'VPN Gateway') and armRegionName eq '<region>'` |
| Azure ExpressRoute | `contains(productName,'ExpressRoute') and armRegionName eq '<region>'` |
| Azure Firewall | `contains(productName,'Azure Firewall') and armRegionName eq '<region>'` |
| Azure DDoS Protection Standard | `contains(productName,'DDoS') and armRegionName eq '<region>'` |
| Azure NAT Gateway | `contains(productName,'NAT Gateway') and armRegionName eq '<region>'` |
| Azure CDN | `contains(productName,'CDN') and currencyCode eq 'USD'` |
| Azure Bastion | `contains(productName,'Bastion') and armRegionName eq '<region>'` |
| Outbound Data Transfer | `contains(productName,'Bandwidth') and armRegionName eq '<region>'` |

### AI / Machine Learning

| Service | Starting filter |
|---|---|
| Azure OpenAI (GPT-4o, GPT-4, etc.) | `serviceName eq 'Azure OpenAI' and currencyCode eq 'USD'` |
| Azure AI Services (Cognitive Services) | `serviceName eq 'Cognitive Services' and armRegionName eq '<region>'` |
| Azure Machine Learning compute | `contains(productName,'Azure Machine Learning') and armRegionName eq '<region>'` |
| Azure AI Search | `contains(productName,'Search') and armRegionName eq '<region>'` |
| Azure AI Document Intelligence | `contains(productName,'Form Recognizer') and armRegionName eq '<region>'` |

### Integration & Messaging

| Service | Starting filter |
|---|---|
| Azure Service Bus (Standard/Premium) | `contains(productName,'Service Bus') and armRegionName eq '<region>'` |
| Azure Event Hubs | `contains(productName,'Event Hubs') and armRegionName eq '<region>'` |
| Azure Event Grid | `contains(productName,'Event Grid') and armRegionName eq '<region>'` |
| Azure API Management | `contains(productName,'API Management') and armRegionName eq '<region>'` |
| Azure Logic Apps | `contains(productName,'Logic Apps') and armRegionName eq '<region>'` |
| Azure Data Factory | `contains(productName,'Data Factory') and armRegionName eq '<region>'` |

### Security & Identity

| Service | Starting filter |
|---|---|
| Azure Key Vault (Standard) | `contains(productName,'Key Vault') and armRegionName eq '<region>'` |
| Azure Key Vault (Premium — HSM) | `contains(productName,'Key Vault') and contains(skuName,'Premium') and armRegionName eq '<region>'` |
| Azure Managed HSM | `contains(productName,'Managed HSM') and armRegionName eq '<region>'` |
| Microsoft Entra ID P1/P2 | `contains(productName,'Azure Active Directory') and currencyCode eq 'USD'` |
| Microsoft Defender for Cloud | `contains(productName,'Defender') and armRegionName eq '<region>'` |

### Management & Monitoring

| Service | Starting filter |
|---|---|
| Log Analytics (Pay-per-GB) | `contains(productName,'Log Analytics') and armRegionName eq '<region>'` |
| Application Insights (workspace-based) | Billed via Log Analytics — no separate meter |
| Azure Monitor Metrics | `contains(productName,'Azure Monitor') and armRegionName eq '<region>'` |
| Azure Automation | `contains(productName,'Automation') and armRegionName eq '<region>'` |
| Azure Backup | `contains(productName,'Backup') and armRegionName eq '<region>'` |
| Azure Site Recovery | `contains(productName,'Site Recovery') and armRegionName eq '<region>'` |

### Developer Tools & DevOps

| Service | Starting filter |
|---|---|
| Azure Static Web Apps | `contains(productName,'Static Web') and currencyCode eq 'USD'` |
| Azure Container Registry | `contains(productName,'Container Registry') and armRegionName eq '<region>'` |
| Azure DevOps (Pipelines, Artifacts) | `contains(productName,'Azure DevOps') and currencyCode eq 'USD'` |
| GitHub Actions (if on Azure billing) | Not in Retail Prices API — use GitHub billing |

---

## Handling Free Tiers and Tiered Pricing

Many services have free tiers or volume tiers. The API returns multiple `Items` for the same `meterName` with different `tierMinimumUnits`:

```json
[
  { "tierMinimumUnits": 0,       "retailPrice": 0.00,  "meterName": "Analytics Logs Data Ingestion" },
  { "tierMinimumUnits": 5,       "retailPrice": 3.34,  "meterName": "Analytics Logs Data Ingestion" }
]
```

**Rule:** Select the tier whose `tierMinimumUnits` is ≤ your estimated monthly consumption. For workloads that span multiple tiers, calculate the cost in each tier bracket and sum them.

---

## Reserved Instance / Savings Plan Pricing

To fetch Reserved pricing (1-year or 3-year) instead of pay-as-you-go:

```
GET https://prices.azure.com/api/retail/prices?$filter=<your filter> and priceType eq 'Reservation'
```

Include both Consumption and Reservation rows in the output table when the service supports reservations, so stakeholders can see the savings opportunity.

---

## Services That Are Free

The following services have **no billable meter** in the API. Record them as `$0.00 — Free` in the output table:

- **Azure Virtual Network (VNet)** — creation, maintenance, subnets, NSGs
- **Azure Resource Manager** — API calls, deployments, resource groups
- **Azure Managed Identity** — system-assigned and user-assigned
- **Azure RBAC** — role assignments
- **Azure Policy** — policy definitions and compliance scanning
- **Azure Active Directory (Free tier)** — basic identity, up to 50K objects

---

## Output Format

Write `outputs/azure-architecture-output/cost-comparison.md` using this structure. Adapt the rows to whatever services are in the target architecture — do not hard-code a fixed set of services.

```markdown
# Cost Comparison: <Source Cloud> vs Azure

> Prices fetched from Azure Retail Prices API (https://prices.azure.com/api/retail/prices).
> Retrieved: <ISO date>. Currency: USD. Target region: <armRegionName>.
> All `retailPrice` values are unmodified from the API response.

## SKU-Level Price Detail

| Service | SKU / Meter | `retailPrice` | Unit | Est. Units/Month | Est. Monthly (USD) | Source |
|---|---|---:|---|---:|---:|---|
| <Service Name> | <meterName> | $X.XX | <unitOfMeasure> | <N> | $X.XX | API ✓ |
| **<Service> subtotal** | | | | | **$X.XX** | |
| <Another Service> | <meterName> | $X.XX | <unitOfMeasure> | <N> | $X.XX | Estimated |
| ... | | | | | | |
| **Azure Total** | | | | | **$X.XX** | |

## Source vs Azure Summary

| Category | <Source Cloud> (Estimated) | Azure (API-Backed) | Delta |
|---|---:|---:|---:|
| Compute | $X | $X | ±$X |
| Storage | $X | $X | ±$X |
| Networking | $X | $X | ±$X |
| Monitoring | $X | $X | ±$X |
| Security | $X | $X | ±$X |
| <other categories as needed> | $X | $X | ±$X |
| **Total** | **$X** | **$X** | **±$X** |

## Annual Projection

| Metric | <Source Cloud> | Azure |
|---|---:|---:|
| Monthly run-rate | $X | $X |
| Annual run-rate | $X | $X |
| Annual delta | | ±$X |

## Cost Optimisation Levers

| Change | Approx. Saving | Trade-off |
|---|---:|---|
| <e.g. downgrade tier> | −$X/mo | <what you lose> |

## Assumptions

- List the filter query used for each service.
- List estimated monthly units for each meter (hours, GB, operations).
- Call out any services where `Count: 0` was returned and how you resolved it.
- Call out any free-tier boundaries that affect the estimate.
- State whether Reserved Instance pricing was considered.
```

---

## Rules

1. **Never invent a price.** If the API returns `Count: 0`, broaden the filter and document the fallback query used.
2. **Always tag each row** with `API ✓` (price confirmed from API response) or `Estimated` (reasonable industry assumption with rationale).
3. **Always record the query used** in an Assumptions section or code comment so future runs can re-fetch the same data.
4. **Re-fetch before each output generation** — retail prices change. Stale embedded prices must not be copy-pasted from previous runs.
5. **Show subtotals** for multi-meter services (e.g., Functions has both vCPU and memory meters).
6. **If `NextPageLink` is non-null**, follow it to retrieve all pages before selecting the correct meter.
7. **Match on `meterName`**, not just `skuName` — multiple meters share the same `skuName` (e.g., "Premium" has both vCPU and Memory meters).
8. **Use `retailPrice`**, not `unitPrice` — they are usually identical for Consumption pricing but `retailPrice` is the public list price.

---

## References

### Microsoft / Azure Documentation

| Topic | Link |
|---|---|
| Azure Retail Prices API reference | https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices |
| Azure Retail Prices API — interactive explorer | https://prices.azure.com/api/retail/prices |
| Azure Cost Management documentation | https://learn.microsoft.com/en-us/azure/cost-management-billing/ |
| Azure Pricing Calculator | https://azure.microsoft.com/en-us/pricing/calculator/ |
| Azure Savings Plans | https://learn.microsoft.com/en-us/azure/cost-management-billing/savings-plan/savings-plan-compute-overview |
| Azure Reservations overview | https://learn.microsoft.com/en-us/azure/cost-management-billing/reservations/save-compute-costs-reservations |
| Azure Free tier services | https://azure.microsoft.com/en-us/pricing/free-services/ |
| Azure consumption APIs | https://learn.microsoft.com/en-us/azure/cost-management-billing/automate/consumption-api-overview |
| OData filter query syntax | https://learn.microsoft.com/en-us/azure/search/search-query-odata-filter |

### Best Practices

- **Always re-fetch prices at generation time** — the Retail Prices API is unauthenticated and fast. Embedded prices from previous runs become stale within weeks.
- **Tiered pricing requires per-bracket calculation:** Many Azure meters have `tierMinimumUnits` — always check for all tiers before assuming a flat rate.
- **`Count: 0` is a signal, not an error** — it means the filter is too narrow. Drop fields one at a time (`armRegionName`, then `skuName`) until you find the right meter. Document the fallback query in Assumptions.
- **Reservation pricing is always worth showing** for services with predictable baseline usage — 1-year reserved VMs and databases typically cost 30–40% less than pay-as-you-go.
- **AWS Cost Explorer exports** are the most accurate source of historical AWS spend — request them from the customer before estimating AWS baseline costs.

---

## Updating `cost-comparison.md`

1. Fetch all queries above using the `web` tool.
2. Parse the `Items` array and extract `retailPrice` for the meterName listed in each table.
3. Multiply by the usage estimate to produce `Est. Monthly (USD)`.
4. Populate the output table with the real numbers.
5. Record the retrieval date in the document header.
6. Mark the `migration-task-plan.md` row for this task as ✅ once the file is written.
