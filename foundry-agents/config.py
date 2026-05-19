"""
Foundry Agent Service configuration.
Deployed resource:
  /subscriptions/40668c14-2eac-4594-815f-e64abe2a25dd
  /resourceGroups/danidu-agentic-migrations
  /providers/Microsoft.CognitiveServices/accounts/danidu-agentic-migrations
"""

SUBSCRIPTION_ID = "40668c14-2eac-4594-815f-e64abe2a25dd"
RESOURCE_GROUP = "danidu-agentic-migrations"
FOUNDRY_ACCOUNT = "danidu-agentic-migrations"

# Project endpoint — update if using a Foundry project under the hub
# Format: https://<account>.services.ai.azure.com/api/projects/<project>
PROJECT_ENDPOINT = "https://danidu-agentic-migrations.services.ai.azure.com/api/projects/danidu-agentic-migrations"

# Model deployed in the Foundry project
MODEL_DEPLOYMENT = "gpt-4.1"

# Azure Blob Storage for outputs/ artifacts (replaces local filesystem writes)
# Set via environment variable or fill in after deploying storage
STORAGE_ACCOUNT_NAME = ""          # e.g. "danidumigrationstore"
OUTPUTS_CONTAINER = "migration-outputs"
SOURCE_APP_CONTAINER = "source-app"

# Vector store ID for File Search (created by upload/upload_source_app.py)
# Populated after running the upload script
VECTOR_STORE_ID = ""

# Agent resource IDs — populated by agents/create_agents.py after creation
AGENT_IDS: dict[str, str] = {
    "aws-discovery": "aws-discovery:5",
    "azure-architect": "azure-architect:2",
    "code-refactor": "code-refactor:2",
    "iac-transformation": "iac-transformation:2",
    "pipeline-builder-agent": "pipeline-builder-agent:2",
    "deployment-validation": "deployment-validation:2",
    "migration-project-manager": "migration-project-manager:1",
}
