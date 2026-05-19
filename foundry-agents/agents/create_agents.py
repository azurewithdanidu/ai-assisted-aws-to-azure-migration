"""Creates all 7 Foundry Agent Service agents using azure-ai-projects v2.1.0.

Run once after deploying the Foundry resource:
    foundry-agents/.venv/bin/python foundry-agents/agents/create_agents.py

Saves agent IDs back to config.py for use by run_migration.py.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import (
    CodeInterpreterTool,
    FileSearchTool,
    FunctionTool,
    PromptAgentDefinition,
)
from azure.identity import DefaultAzureCredential

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import config
from agents.agent_definitions import (
    aws_discovery,
    azure_architect,
    code_refactor,
    deployment_validation,
    iac_transformation,
    migration_pm,
    pipeline_builder,
)

# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------

def get_client() -> AIProjectClient:
    return AIProjectClient(
        endpoint=config.PROJECT_ENDPOINT,
        credential=DefaultAzureCredential(),
    )


# ---------------------------------------------------------------------------
# Shared tool helpers
# ---------------------------------------------------------------------------

def _write_artifact_tool() -> FunctionTool:
    return FunctionTool(
        name="write_artifact",
        description=(
            "Write a text artifact to Azure Blob Storage. "
            "Use this for all output files (Bicep, Python, Mermaid, Markdown, JSON, CSV, YAML)."
        ),
        parameters={
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Relative output path, e.g. outputs/azure-functions/function_app.py",
                },
                "content": {
                    "type": "string",
                    "description": "Full text content of the file.",
                },
            },
            "required": ["path", "content"],
        },
        strict=False,
    )


def _update_task_plan_tool() -> FunctionTool:
    return FunctionTool(
        name="update_task_plan",
        description="Update the migration task plan stored in Azure Blob Storage.",
        parameters={
            "type": "object",
            "properties": {
                "phase": {"type": "string", "description": "Phase identifier, e.g. '1', '2', '3a'."},
                "status": {"type": "string", "enum": ["IN_PROGRESS", "COMPLETED", "FAILED"]},
                "task": {"type": "string", "description": "Optional: specific task name within the phase."},
                "note": {"type": "string", "description": "Optional: blocker or completion note."},
            },
            "required": ["phase", "status"],
        },
        strict=False,
    )


def _file_search_tool(vector_store_id: str) -> FileSearchTool:
    return FileSearchTool(vector_store_ids=[vector_store_id])


def _read_storage_artifact_tool() -> FunctionTool:
    return FunctionTool(
        name="read_storage_artifact",
        description=(
            "Read an artifact from Azure Blob Storage or the local outputs/source-app folder. "
            "Use as a fallback when AWS is not accessible — read existing discovery artifacts "
            "or source-app files to perform analysis without live AWS access."
        ),
        parameters={
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": (
                        "Relative path to read. Examples: "
                        "'outputs/aws-migration-artifacts/aws-inventory.json', "
                        "'source-app/app-code/template.yaml', "
                        "'source-app/lambda/upload/upload_handler.py'"
                    ),
                },
            },
            "required": ["path"],
        },
        strict=False,
    )


def _delegate_tool(agent_name: str, description: str) -> FunctionTool:
    """Delegate-to-specialist function tool for the PM agent."""
    fn_name = f"delegate_to_{agent_name.replace('-', '_')}"
    return FunctionTool(
        name=fn_name,
        description=f"Delegate a task to the {agent_name} specialist agent. {description}",
        parameters={
            "type": "object",
            "properties": {
                "task": {"type": "string", "description": "The specific task for the specialist agent."},
            },
            "required": ["task"],
        },
        strict=False,
    )


# ---------------------------------------------------------------------------
# Create all agents
# ---------------------------------------------------------------------------

def create_all_agents(client: AIProjectClient) -> dict[str, str]:
    """Creates all 7 agents and returns a name → 'name:version' map."""
    ids: dict[str, str] = {}
    write_fn = _write_artifact_tool()
    task_fn = _update_task_plan_tool()
    read_fn = _read_storage_artifact_tool()
    base_tools: list = [write_fn, task_fn, read_fn]
    code_tools: list = [write_fn, task_fn, read_fn, CodeInterpreterTool()]

    if config.VECTOR_STORE_ID:
        fs = _file_search_tool(config.VECTOR_STORE_ID)
        base_tools = base_tools + [fs]
        code_tools = code_tools + [fs]
    else:
        print("Note: VECTOR_STORE_ID not set — FileSearch tool skipped.")

    specialist_specs = [
        (aws_discovery,       code_tools),
        (azure_architect,     base_tools),
        (iac_transformation,  base_tools),
        (code_refactor,       code_tools),
        (pipeline_builder,    base_tools),
        (deployment_validation, base_tools),
    ]

    for defn, tools in specialist_specs:
        print(f"  Creating: {defn.NAME} ...", end=" ", flush=True)
        version = client.agents.create_version(
            defn.NAME,
            definition=PromptAgentDefinition(
                model=config.MODEL_DEPLOYMENT,
                instructions=defn.INSTRUCTIONS,
                tools=tools,
            ),
            description=defn.DESCRIPTION,
        )
        version_id = f"{version.name}:{version.version}"
        ids[defn.NAME] = version_id
        print(f"done  ({version_id}, status={version.status})")

    # PM agent with delegate tools pointing to each specialist
    pm_tools = [
        _delegate_tool(aws_discovery.NAME,       aws_discovery.DESCRIPTION),
        _delegate_tool(azure_architect.NAME,     azure_architect.DESCRIPTION),
        _delegate_tool(iac_transformation.NAME,  iac_transformation.DESCRIPTION),
        _delegate_tool(code_refactor.NAME,       code_refactor.DESCRIPTION),
        _delegate_tool(pipeline_builder.NAME,    pipeline_builder.DESCRIPTION),
        _delegate_tool(deployment_validation.NAME, deployment_validation.DESCRIPTION),
        task_fn,
    ]
    if config.VECTOR_STORE_ID:
        pm_tools.append(_file_search_tool(config.VECTOR_STORE_ID))

    print(f"  Creating: {migration_pm.NAME} ...", end=" ", flush=True)
    pm_version = client.agents.create_version(
        migration_pm.NAME,
        definition=PromptAgentDefinition(
            model=config.MODEL_DEPLOYMENT,
            instructions=migration_pm.INSTRUCTIONS,
            tools=pm_tools,
        ),
        description=migration_pm.DESCRIPTION,
    )
    pm_id = f"{pm_version.name}:{pm_version.version}"
    ids[migration_pm.NAME] = pm_id
    print(f"done  ({pm_id}, status={pm_version.status})")

    return ids


# ---------------------------------------------------------------------------
# Persist agent IDs back to config.py
# ---------------------------------------------------------------------------

def save_agent_ids(all_ids: dict[str, str]) -> None:
    config_path = Path(__file__).resolve().parents[1] / "config.py"
    src = config_path.read_text()
    for name, agent_id in all_ids.items():
        src = re.sub(
            rf'("{re.escape(name)}":\s*)"[^"]*"',
            rf'\1"{agent_id}"',
            src,
        )
    config_path.write_text(src)
    print(f"\nAgent IDs saved to {config_path}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    print(f"Connecting to: {config.PROJECT_ENDPOINT}")
    print(f"Model: {config.MODEL_DEPLOYMENT}")
    client = get_client()

    print("\nCreating agents ...")
    all_ids = create_all_agents(client)
    save_agent_ids(all_ids)

    print("\nAll agents deployed:")
    for name, agent_id in all_ids.items():
        print(f"  {name}: {agent_id}")


if __name__ == "__main__":
    main()
