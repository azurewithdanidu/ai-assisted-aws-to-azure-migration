"""
Uploads source-app/ to a Foundry Agent Service vector store for File Search.

Run once before creating agents:
    python -m foundry_agents.upload.upload_source_app

The resulting vector_store_id is printed and must be saved into config.py.

Only text-readable files are uploaded (Python, HTML, YAML, JSON, Markdown, CSV, shell scripts).
Binary and __MACOSX artefacts are skipped.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential

ROOT = Path(__file__).resolve().parents[2]
SOURCE_APP = ROOT / "source-app"

# File extensions to include
INCLUDE_EXTENSIONS = {
    ".py", ".js", ".html", ".yaml", ".yml",
    ".json", ".md", ".csv", ".sh", ".txt",
}

# Paths to skip
SKIP_DIRS = {"__MACOSX", "__pycache__", ".git", "node_modules"}


def collect_files() -> list[Path]:
    files: list[Path] = []
    for path in SOURCE_APP.rglob("*"):
        if not path.is_file():
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if path.suffix.lower() not in INCLUDE_EXTENSIONS:
            continue
        files.append(path)
    return files


def main() -> None:
    sys.path.insert(0, str(ROOT))
    import config

    client = AIProjectClient(
        endpoint=config.PROJECT_ENDPOINT,
        credential=DefaultAzureCredential(),
    )
    oa = client.get_openai_client()

    files = collect_files()
    if not files:
        raise SystemExit(f"No source files found under {SOURCE_APP}")

    print(f"Uploading {len(files)} files from {SOURCE_APP} ...")

    # Create the vector store
    vector_store = oa.vector_stores.create(name="source-app")
    vector_store_id = vector_store.id
    print(f"Vector store created: {vector_store_id}")

    # Upload files in batches
    uploaded = 0
    for path in files:
        relative = path.relative_to(ROOT)
        try:
            with open(path, "rb") as fh:
                uploaded_file = oa.files.create(
                    file=(str(relative), fh, "text/plain"),
                    purpose="assistants",
                )
            oa.vector_stores.files.create(
                vector_store_id=vector_store_id,
                file_id=uploaded_file.id,
            )
            uploaded += 1
            print(f"  [{uploaded}/{len(files)}] {relative}")
        except Exception as exc:
            print(f"  SKIP {relative}: {exc}")

    print(f"\nDone — {uploaded}/{len(files)} files uploaded.")
    print(f"\nAdd this to config.py:\n  VECTOR_STORE_ID = \"{vector_store_id}\"")

    # Patch config.py automatically
    config_path = ROOT / "foundry-agents" / "config.py"
    src = config_path.read_text()
    src = re.sub(r'(VECTOR_STORE_ID\s*=\s*)"[^"]*"', f'\\1"{vector_store_id}"', src)
    config_path.write_text(src)
    print(f"config.py updated with VECTOR_STORE_ID.")


if __name__ == "__main__":
    main()
