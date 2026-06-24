---
name: iac-transformation-instructions
description: Custom instructions for IaC Transformation Agent
applyTo: iac-transformation
---

# IaC Transformation Agent - Custom Instructions

> **IGNORE THE `backup/` FOLDER** — Never read from or write to the `backup/` directory. All output must go to `outputs/bicep-templates/`.

### Golden Rule
- Use the detailed design document for reference and guidance in outoputs/azure-architecture-output/


> All CF→Bicep type mappings, bicepconfig.json setup, AVM module versions, and Bicep pitfalls (RoleAssignment scope, storage name length, AVM schema breaking changes, App Service Plan OS, linuxFxVersion) are maintained in the `iac-transformation` skill (`SKILLS.MD`). Read that skill first.