"""
Conversation fixtures for PM behaviour and deploy-command eval suites.
"""

# ---------------------------------------------------------------------------
# Query used across PM signed-in scenarios
# ---------------------------------------------------------------------------

SIGNED_IN_QUERY = "Already signed in to azure using cli"

# ---------------------------------------------------------------------------
# PM signed-in fixtures
# ---------------------------------------------------------------------------

GOOD_PM_SIGNED_IN_RESPONSE = """\
Great, since you're already signed in I'll discover your active subscription automatically.

Running:
  az account show --output json

This returns the active subscription details including subscriptionId, tenantId, and displayName.

I'll default the deployment region to **australiaeast** unless you specify otherwise.

Proceeding with Phase 2 — Azure Architecture Design now.
"""

BAD_PM_SIGNED_IN_STALLS = """\
Sure! To proceed, could you provide your Azure subscription ID?
I need the subscription ID to continue with the migration.
Once you share the subscription ID I can move forward.
"""

BAD_PM_MANY_QUESTIONS = """\
Before I start, I have a few questions:
1. What is your Azure subscription ID?
2. Which region would you like to deploy to?
3. Do you have an existing resource group?
4. Should I skip the AWS discovery phase?
5. What naming prefix would you like for resources?
"""

BAD_PM_INVOKES_AWS_DISCOVERY = """\
I'll begin with Phase 1: AWS Discovery.
Invoking @aws-discovery to scan your AWS environment and produce the inventory.
After aws discovery completes I will design the Azure architecture.
"""

# ---------------------------------------------------------------------------
# Deploy command fixtures
# ---------------------------------------------------------------------------

GOOD_DEPLOY_RESPONSE = """\
Deploying the infrastructure using the subscription-scoped template:

  az deployment sub create \\
    --location australiaeast \\
    --template-file outputs/bicep-templates/main.bicep \\
    --parameters @outputs/bicep-templates/parameters/dev.bicepparam

After deployment completes, run what-if to preview any future changes:

  az deployment sub what-if \\
    --location australiaeast \\
    --template-file outputs/bicep-templates/main.bicep \\
    --parameters @outputs/bicep-templates/parameters/dev.bicepparam
"""

BAD_DEPLOY_GROUP_CREATE = """\
Deploying the infrastructure:

  az deployment group create \\
    --resource-group rg-myapp-dev \\
    --template-file outputs/bicep-templates/main.bicep \\
    --parameters @outputs/bicep-templates/parameters/dev.bicepparam
"""

BAD_DEPLOY_NO_LOCATION = """\
Deploying the infrastructure using the subscription-scoped template:

  az deployment sub create \\
    --template-file outputs/bicep-templates/main.bicep \\
    --parameters @outputs/bicep-templates/parameters/dev.bicepparam
"""

# ---------------------------------------------------------------------------
# Expectation maps
# (True = fixture should pass all checks; False = fixture should fail ≥1 check)
# ---------------------------------------------------------------------------

PM_SIGNED_IN_EXPECTATIONS: dict[str, bool] = {
    "GOOD_PM_SIGNED_IN_RESPONSE": True,
    "BAD_PM_SIGNED_IN_STALLS": False,
    "BAD_PM_MANY_QUESTIONS": False,
    "BAD_PM_INVOKES_AWS_DISCOVERY": False,
}

DEPLOY_EXPECTATIONS: dict[str, bool] = {
    "GOOD_DEPLOY_RESPONSE": True,
    "BAD_DEPLOY_GROUP_CREATE": False,
    "BAD_DEPLOY_NO_LOCATION": False,
}
