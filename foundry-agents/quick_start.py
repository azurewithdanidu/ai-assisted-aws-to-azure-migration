"""
Quick-start: deploy a single agent to Azure AI Foundry to verify connectivity.

Uses the azure-ai-projects v2 SDK (PromptAgentDefinition / create_version API).

Run from the repo root:
    az login
    python foundry-agents/quick_start.py

Prints the new agent version details and a direct portal link.
No prerequisites — vector store and Azure Functions are NOT required.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import config

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import PromptAgentDefinition, CodeInterpreterTool
from azure.identity import DefaultAzureCredential

from agents.agent_definitions import aws_discovery

# Agent name must be kebab-case, max 63 chars, alphanumeric + hyphens
AGENT_NAME = "aws-discovery"


def main() -> None:
    print(f"Connecting to: {config.PROJECT_ENDPOINT}")
    client = AIProjectClient(
        endpoint=config.PROJECT_ENDPOINT,
        credential=DefaultAzureCredential(),
    )

    print(f"Creating / updating agent '{AGENT_NAME}' ...")
    version = client.agents.create_version(
        AGENT_NAME,
        definition=PromptAgentDefinition(
            model=config.MODEL_DEPLOYMENT,
            instructions=aws_discovery.INSTRUCTIONS,
            tools=[CodeInterpreterTool()],
        ),
        description=aws_discovery.DESCRIPTION,
    )

    print(f"\nAgent deployed!")
    print(f"  Name:    {version.name}")
    print(f"  Version: {version.version}")
    print(f"  ID:      {version.id}")
    print(f"  Status:  {version.status}")
    print(
        f"\n  Portal: https://ai.azure.com/resource/agents"
        f"?subscription={config.SUBSCRIPTION_ID}"
        f"&resourceGroup={config.RESOURCE_GROUP}"
        f"&resource={config.FOUNDRY_ACCOUNT}"
    )

    # Persist the version ID to config.py so other scripts can reference it
    config_path = Path(__file__).parent / "config.py"
    src = config_path.read_text()
    src = src.replace(
        '"aws-discovery": ""',
        f'"aws-discovery": "{version.id}"',
    )
    config_path.write_text(src)
    print(f"\nconfig.py updated with agent version ID.")


if __name__ == "__main__":
    main()
