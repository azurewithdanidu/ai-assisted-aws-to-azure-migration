# Quick Start Guide - Custom AI Migration Agents

**Last Updated:** December 10, 2024

---

## 🚀 5-Minute Quick Start

### Step 1: Verify Installation
All agents are in `.github/` directory:
```
✅ .github/agents/aws-discovery.agent.md
✅ .github/agents/azure-architect.agent.md
✅ .github/agents/code-refactor.agent.md
✅ .github/agents/iac-transformation.agent.md
✅ .github/agents/deployment-validation.agent.md
```

### Step 2: Open GitHub Copilot Chat
In VS Code, use keyboard shortcut: `Ctrl+Shift+I` (or `Cmd+Shift+I` on Mac)

### Step 3: Run Your First Agent
Copy and paste into Copilot Chat:

```
@aws-discovery Discover all AWS resources and create a complete inventory with dependency analysis
```

## 📋 Agent Reference

### Agent 1: AWS Discovery
**Time:** 15-30 minutes  
**Output:** Inventory, diagrams, assessment  
**Command:**
```
@aws-discovery Discover all resources in AWS account and create inventory
```

### Agent 2: Azure Architect
**Time:** 30-60 minutes  
**Output:** Bicep templates, cost analysis, service mappings  
**Command:**
```
@azure-architect Design Azure architecture and generate Bicep templates
```

### Agent 3: Code Refactor
**Time:** 15-30 minutes per service  
**Output:** Refactored code, tests, pull request  
**Command:**
```
@code-refactor Refactor [service-name] Lambda to Azure Functions and SDKs
```

### Agent 4: IaC Transformation
**Time:** 30-45 minutes  
**Output:** Bicep files, updated pipeline, scripts  
**Command:**
```
@iac-transformation Convert CloudFormation to Bicep and update Buildkite pipeline
```

### Agent 5: Deployment Validation
**Time:** 15-20 minutes  
**Output:** Validation report, compliance scorecard, recommendations  
**Command:**
```
@deployment-validation Validate Azure deployment and run compliance checks
```

## 🔄 Typical Migration Workflow

### 1️⃣ **Discovery** (30 min)
- Scan AWS for all resources
- Understand current architecture
- Assess complexity

### 2️⃣ **Design** (60 min)
- Map services to Azure
- Design architecture
- Generate Bicep templates

### 3️⃣ **Refactor Code** (30+ min)
- Update SDK imports
- Change authentication
- Update tests
- Create pull requests

### 4️⃣ **Transform IaC** (45 min)
- Convert CloudFormation to Bicep
- Update deployment pipeline
- Create rollback scripts

### 5️⃣ **Validate** (20 min)
- Pre-deployment checks
- Security validation
- Performance comparison
- Cost verification

**Total Time:** ~4-5 hours for complete migration

## 💡 Tips for Success

### Before Running Agents

✅ **Prepare:**
- Ensure AWS credentials configured
- Ensure Azure credentials configured
- Have latest VS Code + Copilot
- Test on non-production first

### When Running Agents

✅ **Do:**
- Read output carefully
- Review recommendations
- Test in staging first
- Document decisions
- Create checkpoints (git commits)

❌ **Don't:**
- Skip validation steps
- Deploy to production without testing
- Assume 100% automation
- Ignore warnings
- Skip security review

## 📁 Output Files Organization

After running agents, outputs are typically in:
```
migration-artifacts/
├── aws-inventory.json              (from Discovery)
├── architecture-diagram.mmd        (from Discovery)
├── dependency-matrix.csv           (from Discovery)
├── migration-assessment.md         (from Discovery)
│
├── azure-infrastructure/           (from Architect)
│   ├── main.bicep
│   ├── modules/
│   └── parameters/
├── architecture-diagram-azure.mmd
├── cost-comparison.md
├── service-mapping.md
│
├── [service].ts / [service].py    (from Code Refactor)
├── package.json / requirements.txt (updated)
│
├── .buildkite/pipeline.yml        (updated)
├── scripts/
│   ├── validate-deployment.sh
│   ├── deploy.sh
│   └── rollback.sh
│
└── validation-report.md           (from Validation)
```

## 🔐 Security Checklist

Before deployment, verify:
- [ ] No hardcoded credentials
- [ ] Managed Identity configured
- [ ] Private endpoints for PaaS
- [ ] Security groups/NSGs configured
- [ ] Key Vault setup
- [ ] RBAC roles assigned
- [ ] Encryption enabled

## 💰 Cost Verification

Before production deployment:
- [ ] Actual costs within 15% of projection
- [ ] Reserved instances applied
- [ ] Auto-scaling configured
- [ ] Unused resources removed
- [ ] Data tiering implemented

## 📞 Common Issues & Quick Fixes

### Issue: Agent Not Responding
**Fix:** 
1. Restart VS Code
2. Check GitHub Copilot status
3. Verify agent files exist in `.github/agents/`

### Issue: "Unknown tool" error
**Fix:**
1. Verify agent name is correct (use `-` not spaces)
2. Check file is in correct directory
3. Restart Copilot

### Issue: Deployment Fails
**Fix:**
1. Run validation agent first
2. Check Azure credentials
3. Verify quotas available
4. Review error messages in deployment log

### Issue: Cost Higher Than Expected
**Fix:**
1. Check for unused resources
2. Verify auto-scaling not over-provisioning
3. Review data transfer costs
4. Check pricing region

## 🎯 Success Criteria

Migration is successful when:
✅ All resources deployed  
✅ Connectivity tests pass  
✅ Security validation passes  
✅ Performance within ±10% of AWS  
✅ Costs within 15% of projection  
✅ All tests passing  
✅ Monitoring configured  

## 📚 Documentation Map

| Document | Purpose | When to Use |
|---|---|---|
| `00-MASTER-INDEX.md` | Navigation | Get oriented |
| `01-EXECUTIVE-PRESENTATION.md` | Business case | Stakeholder briefing |
| `02-TECHNICAL-DEEP-DIVE.md` | Technical details | Deep understanding |
| `03-CUSTOM-AGENT-SPECIFICATIONS.md` | Agent specs | Detailed requirements |
| `04-DEMO-PLAN.md` | Demo workflow | Live demonstration |
| `05-AWS-INFRASTRUCTURE-SETUP.md` | AWS setup | Create test environment |
| `06-DEMO-EXECUTION-GUIDE.md` | Step-by-step demo | Run demonstration |
| `07-SERVICE-MAPPING-REFERENCE.md` | Service mapping | AWS → Azure lookup |
| `08-MCP-SERVER-INTEGRATION.md` | MCP setup | Configure tools |

## 🔗 Useful Shortcuts

**In VS Code with Copilot:**
- `@aws-discovery` → Start AWS discovery
- `@azure-architect` → Start architecture design
- `@code-refactor` → Start code refactoring
- `@iac-transformation` → Convert IaC
- `@deployment-validation` → Validate deployment

**Common agent commands:**
```
@aws-discovery Discover all AWS resources
@azure-architect Design Azure architecture
@code-refactor Refactor order-processor Lambda
@iac-transformation Convert CloudFormation templates
@deployment-validation Validate deployment
```

## 🎓 Learning Path

1. **Read** AGENTS-INSTALLATION-SUMMARY.md (10 min)
2. **Review** Agent specifications (30 min)
3. **Run** aws-discovery on test account (30 min)
4. **Review** Discovery output (15 min)
5. **Run** azure-architect (60 min)
6. **Review** Architecture output (15 min)
7. **Run** code-refactor on sample service (30 min)
8. **Run** iac-transformation (45 min)
9. **Run** deployment-validation (20 min)
10. **Review** Validation report (15 min)

**Total: ~4.5 hours to full proficiency**

## 📊 Metrics to Track

Monitor these during migration:
- **Time spent per phase** (compare to estimates)
- **Issues encountered** (document for future)
- **Rework required** (should decrease with practice)
- **Code coverage** (should maintain or improve)
- **Test pass rate** (should be 100%)
- **Security findings** (should resolve all)
- **Cost variance** (target: ±15% of projection)
- **Performance variance** (target: ±10% of AWS)

## 🚨 Emergency Contacts / Escalation

When stuck:
1. **Check instruction files** - Answer is usually there
2. **Review example invocations** - In agent files
3. **Check troubleshooting section** - In instruction files
4. **Review specification documents** - For detailed requirements
5. **Check demo execution guide** - For step-by-step walkthrough

## ✨ Pro Tips

💡 **Commit frequently** - Create git checkpoints after each agent run  
💡 **Review outputs** - Don't blindly accept agent suggestions  
💡 **Test incrementally** - Migrate one service at a time  
💡 **Document decisions** - Add comments explaining choices  
💡 **Validate thoroughly** - Use validation agent on staging first  
💡 **Monitor costs** - Watch actual spending vs projection  

---

## Status

✅ **All agents created and ready to use**  
✅ **Complete specifications provided**  
✅ **10 KB+ of documentation**  
✅ **Production-ready templates**  

**You're ready to start your migration!** 🎉

---

*Quick Start Guide | Version 1.0 | December 2024*
