"""
Entry point — starts a migration run using the Foundry Agent Service.

Usage:
    # Run end-to-end from Phase 1
    foundry-agents/.venv/bin/python foundry-agents/run_migration.py

    # Resume from a specific phase
    foundry-agents/.venv/bin/python foundry-agents/run_migration.py --phase architecture
    foundry-agents/.venv/bin/python foundry-agents/run_migration.py --phase parallel
    foundry-agents/.venv/bin/python foundry-agents/run_migration.py --phase validation

Prerequisites (run in order):
    1. foundry-agents/.venv/bin/python foundry-agents/upload/upload_source_app.py
    2. foundry-agents/.venv/bin/python foundry-agents/agents/create_agents.py
    3. foundry-agents/.venv/bin/python foundry-agents/run_migration.py
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

sys.path.insert(0, str(Path(__file__).resolve().parent))
import config

PHASE_PROMPTS: dict[str, str] = {
    "discovery": (
        "Start Phase 1 — AWS Discovery. "
        "Run the aws-discovery agent to scan the AWS account and produce all 4 output artifacts."
    ),
    "architecture": (
        "Start Phase 2 — Azure Architecture Design. "
        "The Phase 1 artifacts are available in the vector store. "
        "Run the azure-architect agent."
    ),
    "parallel": (
        "Start Phase 3 — Parallel execution. "
        "Run iac-transformation (3a), code-refactor (3b), and pipeline-builder-agent (3c) "
        "in parallel. All three must complete before proceeding."
    ),
    "validation": (
        "Start Phase 4 — Validation. "
        "Run the deployment-validation agent against all Phase 3 outputs."
    ),
    "all": (
        "Run the full AWS-to-Azure migration pipeline from the beginning: "
        "Phase 1 (Discovery) → Phase 2 (Architecture) → "
        "Phase 3a/3b/3c in parallel (IaC, Code Refactor, Pipeline) → "
        "Phase 4 (Validation). "
        "Track every phase in the task plan and stop immediately if a phase fails."
    ),
}


def get_client() -> AIProjectClient:
    return AIProjectClient(
        endpoint=config.PROJECT_ENDPOINT,
        credential=DefaultAzureCredential(),
    )


def extract_text(response) -> str:
    """Extract text content from a Responses API response object."""
    parts: list[str] = []
    for item in response.output:
        if hasattr(item, "content"):
            for c in item.content:
                if hasattr(c, "text"):
                    parts.append(c.text)
    return "\n".join(parts)


def get_agent_instructions(client: AIProjectClient, agent_id: str) -> str:
    """Retrieve stored instructions for a deployed agent version.
    
    agent_id format: 'name:version' e.g. 'migration-project-manager:1'
    """
    name, version = agent_id.rsplit(":", 1)
    version_details = client.agents.get_version(name, version)
    return version_details.definition.instructions


def run_migration(phase: str = "all") -> None:
    pm_id = config.AGENT_IDS.get("migration-project-manager")
    if not pm_id:
        raise SystemExit(
            "migration-project-manager agent ID not set in config.py.\n"
            "Run: foundry-agents/.venv/bin/python foundry-agents/agents/create_agents.py"
        )

    prompt = PHASE_PROMPTS.get(phase, PHASE_PROMPTS["all"])
    client = get_client()
    oa = client.get_openai_client()

    print(f"Fetching PM agent instructions ({pm_id}) ...")
    instructions = get_agent_instructions(client, pm_id)

    print(f"Sending prompt for phase='{phase}' to migration-project-manager ...")
    print(f"  Prompt: {prompt[:80]}...")
    print()

    response = oa.responses.create(
        model=config.MODEL_DEPLOYMENT,
        instructions=instructions,
        input=prompt,
    )

    output_text = extract_text(response)

    print("--- Agent output ---")
    print(output_text)
    print()
    print(f"Status: {response.status}")
    print(f"Response ID: {response.id}")

    if response.status == "completed":
        print("\nMigration run completed successfully.")
    else:
        print(f"\nMigration run ended with status: {response.status}")
        sys.exit(1)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the AWS-to-Azure migration pipeline")
    parser.add_argument(
        "--phase",
        choices=list(PHASE_PROMPTS.keys()),
        default="all",
        help="Phase to start from (default: all)",
    )
    args = parser.parse_args()
    run_migration(phase=args.phase)


if __name__ == "__main__":
    main()
