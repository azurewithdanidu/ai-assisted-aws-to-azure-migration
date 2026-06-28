# Migration Task Plan
Generated: 2026-06-28T00:00:00Z
Last Updated: 2026-06-28T00:00:00Z

## Migration Scope

| Field | Value |
|---|---|
| AWS Account ID | 535002891143 |
| AWS Region | ap-southeast-2 |

## Status Legend
| Symbol | Meaning |
|---|---|
| ⏳ | Not started |
| 🔄 | In progress |
| ✅ | Complete |
| ❌ | Failed / Blocked |

## Phase Summary

| Phase | Agent | Status | Completed At |
|---|---|---|---|
| 1 — Discovery | aws-discovery | ⏳ | — |
| 2 — Architecture | azure-architect | ⏳ | — |
| 3a — IaC Transformation | iac-transformation | ⏳ | — |
| 3b — Code Refactor | code-refactor | ⏳ | — |
| 3c — Pipeline Build | pipeline-builder-agent | ⏳ | — |
| 3d — Deployment | azure-deployer | ⏳ | — |
| 4 — Validation | deployment-validation | ⏳ | — |

## Detailed Task List

### Phase 1 — AWS Discovery
- [ ] Discover all AWS services and regions
- [ ] Generate aws-inventory.json
- [ ] Generate architecture-diagram.mmd
- [ ] Generate dependency-matrix.csv
- [ ] Generate migration-assessment.md

### Phase 2 — Azure Architecture Design
- [ ] Map all AWS services to Azure equivalents
- [ ] Generate design-document.md (all 11 sections)
- [ ] Generate architecture-diagram-azure.mmd
- [ ] Generate cost-comparison.md
- [ ] Generate service-mapping.md

### Phase 3a — IaC Transformation
<!-- Populated from design-document.md Section 5 after Phase 2 -->
- [ ] Generate main.bicep
- [ ] Generate Bicep modules (to be detailed after Phase 2)
- [ ] Generate parameter files (dev / staging / prod)

### Phase 3b — Code Refactor
<!-- Populated from design-document.md Section 6 after Phase 2 -->
- [ ] Refactor Lambda functions to Azure Functions (to be detailed after Phase 2)
- [ ] Update requirements.txt
- [ ] Update host.json

### Phase 3c — Pipeline Build
<!-- Populated from design-document.md Section 11 after Phase 2 -->
- [ ] Create GitHub Actions workflows (to be detailed after Phase 2)
- [ ] Configure OIDC authentication
- [ ] Configure environment secrets

### Phase 4 — Validation
- [ ] Run pre-deployment checks
- [ ] Run post-deployment smoke tests
- [ ] Verify security compliance
- [ ] Produce validation-report.md

## Phase Metrics

| Phase | Agent | Duration | Tool Calls | Files Written |
|---|---|---|---|---|
| *(not yet run)* | | | | |

## Blockers
None
