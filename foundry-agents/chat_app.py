"""
Chat interface for the AWS-to-Azure migration agents.

Copilot-Chat-style web UI with full tool execution loop — delegates to specialist
agents, executes write_artifact / update_task_plan / read_storage_artifact calls,
and streams all events to the browser via Server-Sent Events.

Start:
    cd foundry-agents
    .venv/bin/python chat_app.py
    # Open http://localhost:8000
"""
from __future__ import annotations

import asyncio
import json
import sys
import threading
import time
from pathlib import Path
from typing import AsyncGenerator

import uvicorn
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, StreamingResponse
from pydantic import BaseModel

sys.path.insert(0, str(Path(__file__).resolve().parent))
import config

ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_DIR = ROOT / "outputs"

# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------

app = FastAPI(title="Migration Agent Chat")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Azure AI client (one per request thread)
# ---------------------------------------------------------------------------

from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential


def get_client() -> AIProjectClient:
    return AIProjectClient(
        endpoint=config.PROJECT_ENDPOINT,
        credential=DefaultAzureCredential(),
    )


# ---------------------------------------------------------------------------
# Tool implementations  (sync — called inside worker thread)
# ---------------------------------------------------------------------------

def tool_write_artifact(path: str, content: str) -> str:
    # Strip leading "outputs/" prefix so path is relative to OUTPUTS_DIR
    rel = path.lstrip("/")
    if rel.startswith("outputs/"):
        rel = rel[len("outputs/"):]
    out = OUTPUTS_DIR / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(content, encoding="utf-8")
    return f"Written {len(content)} chars → {out.relative_to(ROOT)}"


def tool_update_task_plan(phase: str, status: str, task: str = "", note: str = "") -> str:
    plan_path = OUTPUTS_DIR / "migration-task-plan.md"
    existing = plan_path.read_text(encoding="utf-8") if plan_path.exists() else "# Migration Task Plan\n"
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    entry = f"\n**[{ts}] Phase {phase} — {status}**"
    if task:
        entry += f": {task}"
    if note:
        entry += f"\n> {note}"
    plan_path.write_text(existing + entry + "\n", encoding="utf-8")
    return f"Task plan updated: Phase {phase} → {status}"


def tool_read_storage_artifact(path: str) -> str:
    """Read an artifact — tries Azure Blob Storage first, then local files."""
    MAX = 12_000

    # 1. Azure Blob Storage (when STORAGE_ACCOUNT_NAME is configured)
    if config.STORAGE_ACCOUNT_NAME:
        try:
            from azure.storage.blob import BlobServiceClient
            bsc = BlobServiceClient(
                account_url=f"https://{config.STORAGE_ACCOUNT_NAME}.blob.core.windows.net",
                credential=DefaultAzureCredential(),
            )
            for container in [config.SOURCE_APP_CONTAINER, config.OUTPUTS_CONTAINER]:
                try:
                    blob = bsc.get_blob_client(container=container, blob=path.lstrip("/"))
                    data = blob.download_blob().readall().decode("utf-8", errors="replace")
                    return data[:MAX] + ("\n[truncated]" if len(data) > MAX else "")
                except Exception:
                    continue
        except Exception:
            pass  # fall through to local

    # 2. Local filesystem fallback
    for base in [OUTPUTS_DIR, ROOT / "source-app", ROOT]:
        candidate = base / path.lstrip("/")
        if candidate.exists() and candidate.is_file():
            try:
                data = candidate.read_text(encoding="utf-8", errors="replace")
                return data[:MAX] + ("\n[truncated]" if len(data) > MAX else "")
            except Exception as e:
                return f"Error reading {candidate}: {e}"

    # List what's available as a hint
    listing: list[str] = []
    for base in [OUTPUTS_DIR / "aws-migration-artifacts", ROOT / "source-app"]:
        if base.exists():
            for f in sorted(base.rglob("*")):
                if f.is_file():
                    listing.append(str(f.relative_to(ROOT)))
    hint = "\nAvailable files:\n" + "\n".join(listing[:40]) if listing else ""
    return f"Not found: {path}{hint}"


# ---------------------------------------------------------------------------
# Unified tool dispatcher
# ---------------------------------------------------------------------------

def execute_tool(name: str, args: dict, client, oa, emit) -> str:
    if name == "write_artifact":
        return tool_write_artifact(args.get("path", ""), args.get("content", ""))
    if name == "update_task_plan":
        return tool_update_task_plan(
            args.get("phase", "?"),
            args.get("status", "?"),
            args.get("task", ""),
            args.get("note", ""),
        )
    if name == "read_storage_artifact":
        return tool_read_storage_artifact(args.get("path", ""))
    if name.startswith("delegate_to_"):
        agent_key = name[len("delegate_to_"):].replace("_", "-")
        agent_id = config.AGENT_IDS.get(agent_key, "")
        if not agent_id:
            return f"Agent '{agent_key}' not found in config.AGENT_IDS"
        return invoke_agent(client, oa, agent_id, args.get("task", ""), emit=emit)
    return f"Unknown tool: {name}"


# ---------------------------------------------------------------------------
# Core agent invocation with full tool loop
# ---------------------------------------------------------------------------

MAX_TURNS = 20


def extract_text(response) -> str:
    parts: list[str] = []
    for item in response.output:
        if hasattr(item, "content"):
            for c in item.content:
                if hasattr(c, "text"):
                    parts.append(c.text)
        elif hasattr(item, "text"):
            parts.append(item.text)
    return "\n".join(filter(None, parts))


def get_tool_calls(response) -> list:
    return [item for item in response.output if getattr(item, "type", None) == "function_call"]


def invoke_agent(
    client: AIProjectClient,
    oa,
    agent_id: str,
    task: str,
    emit=None,
    depth: int = 0,
) -> str:
    """Invoke a deployed agent with a task, running its full tool loop."""
    agent_name, version_str = agent_id.rsplit(":", 1)

    if emit:
        emit({"type": "thinking", "agent": agent_name, "action": task[:80]})

    # Load agent instructions from Foundry
    try:
        v = client.agents.get_version(agent_name, version_str)
        instructions = v.definition.instructions
    except Exception as e:
        return f"Error loading agent {agent_id}: {e}"

    messages: str | list = task
    prev_id: str | None = None

    for turn in range(MAX_TURNS):
        try:
            kwargs: dict = {
                "model": config.MODEL_DEPLOYMENT,
                "instructions": instructions,
                "input": messages,
            }
            if prev_id:
                kwargs["previous_response_id"] = prev_id
            response = oa.responses.create(**kwargs)
            prev_id = response.id
        except Exception as e:
            if emit:
                emit({"type": "error", "agent": agent_name, "content": str(e)})
            return f"API error in {agent_name} (turn {turn}): {e}"

        tool_calls = get_tool_calls(response)
        if not tool_calls:
            text = extract_text(response)
            if emit:
                emit({"type": "message", "agent": agent_name, "content": text})
            return text

        # Execute all tool calls in this turn
        tool_results: list[dict] = []
        for tc in tool_calls:
            try:
                args = json.loads(tc.arguments) if tc.arguments else {}
            except json.JSONDecodeError:
                args = {}

            summary = args.get("path") or args.get("task", "")[:60] or tc.name
            if emit:
                emit({
                    "type": "tool",
                    "agent": agent_name,
                    "name": tc.name,
                    "status": "calling",
                    "summary": summary,
                })

            result = execute_tool(tc.name, args, client, oa, emit)

            if emit:
                emit({
                    "type": "tool",
                    "agent": agent_name,
                    "name": tc.name,
                    "status": "done",
                    "summary": result[:120],
                })

            tool_results.append({
                "type": "function_call_output",
                "call_id": tc.call_id,
                "output": result,
            })

        messages = tool_results

    return f"[Agent {agent_name} reached max turns ({MAX_TURNS})]"


# ---------------------------------------------------------------------------
# SSE streaming  (bridges sync worker thread → async FastAPI response)
# ---------------------------------------------------------------------------

class ChatRequest(BaseModel):
    message: str
    agent_id: str = ""


async def stream_chat(request: ChatRequest) -> AsyncGenerator[str, None]:
    loop = asyncio.get_running_loop()
    q: asyncio.Queue = asyncio.Queue()

    agent_id = request.agent_id or config.AGENT_IDS.get("migration-project-manager", "")
    if not agent_id:
        yield f"data: {json.dumps({'type': 'error', 'content': 'No agent configured. Run create_agents.py first.'})}\n\n"
        return

    def sync_emit(evt: dict) -> None:
        loop.call_soon_threadsafe(q.put_nowait, evt)

    def run_in_thread() -> None:
        try:
            client = get_client()
            oa = client.get_openai_client()
            invoke_agent(client, oa, agent_id, request.message, emit=sync_emit)
        except Exception as e:
            sync_emit({"type": "error", "content": str(e)})
        finally:
            sync_emit(None)  # sentinel → end stream

    threading.Thread(target=run_in_thread, daemon=True).start()

    while True:
        evt = await q.get()
        if evt is None:
            break
        yield f"data: {json.dumps(evt)}\n\n"

    yield 'data: {"type":"done"}\n\n'


# ---------------------------------------------------------------------------
# REST endpoints
# ---------------------------------------------------------------------------

@app.post("/api/chat")
async def chat(request: ChatRequest):
    return StreamingResponse(
        stream_chat(request),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@app.get("/api/status")
def status():
    plan_path = OUTPUTS_DIR / "migration-task-plan.md"
    plan_text = plan_path.read_text(encoding="utf-8") if plan_path.exists() else ""
    return {
        "agents": config.AGENT_IDS,
        "task_plan": plan_text,
        "model": config.MODEL_DEPLOYMENT,
        "endpoint": config.PROJECT_ENDPOINT,
    }


@app.get("/api/agents")
def agents_list():
    return [{"id": v, "name": k} for k, v in config.AGENT_IDS.items() if v]


@app.get("/api/files")
def list_files(folder: str = "outputs"):
    """List all files under a project subfolder (relative to ROOT)."""
    from fastapi import HTTPException
    clean = Path(folder).as_posix().lstrip("/")
    full = (ROOT / clean).resolve()
    if not str(full).startswith(str(ROOT)):
        raise HTTPException(status_code=403, detail="Access denied")
    if not full.exists():
        return {"files": []}
    files = []
    for p in sorted(full.rglob("*")):
        if p.is_file() and not any(part.startswith(".") for part in p.relative_to(ROOT).parts):
            files.append(str(p.relative_to(ROOT)))
    return {"files": files[:200]}


@app.get("/api/artifact")
def get_artifact(path: str):
    """Read a project file by relative path."""
    from fastapi import HTTPException
    clean = Path(path).as_posix().lstrip("/")
    full = (ROOT / clean).resolve()
    if not str(full).startswith(str(ROOT)):
        raise HTTPException(status_code=403, detail="Access denied")
    if not full.exists() or not full.is_file():
        raise HTTPException(status_code=404, detail=f"Not found: {clean}")
    content = full.read_text(errors="replace")[:60_000]
    return {"path": clean, "content": content, "size": full.stat().st_size}


@app.get("/", response_class=HTMLResponse)
def index():
    return HTMLResponse(HTML)


# ---------------------------------------------------------------------------
# Embedded frontend
# ---------------------------------------------------------------------------

HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Azure Migration Agent</title>
<script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
<style>
:root {
  --bg: #0d1117;
  --surface: #161b22;
  --card: #21262d;
  --border: #30363d;
  --text: #e6edf3;
  --muted: #8b949e;
  --accent: #388bfd;
  --azure: #0078d4;
  --green: #3fb950;
  --yellow: #d29922;
  --red: #f85149;
  --r: 8px;
  --font: -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: var(--bg); color: var(--text); font-family: var(--font); height: 100vh; display: flex; flex-direction: column; overflow: hidden; }

/* ── Header ── */
header {
  display: flex; align-items: center; gap: 12px;
  padding: 10px 20px; background: var(--surface);
  border-bottom: 1px solid var(--border); flex-shrink: 0;
}
header svg { flex-shrink: 0; }
header h1 { font-size: 15px; font-weight: 600; }
#agent-select {
  margin-left: 12px; background: var(--card); border: 1px solid var(--border);
  color: var(--text); padding: 4px 8px; border-radius: 4px; font-size: 13px; cursor: pointer;
  min-width: 210px; max-width: 280px;
}
.badge { margin-left: auto; font-size: 12px; color: var(--green); display: flex; align-items: center; gap: 5px; }
.badge::before { content: "●"; font-size: 8px; }

/* ── Layout ── */
main { display: flex; flex: 1; overflow: hidden; }

/* ── Sidebar ── */
aside {
  width: 230px; flex-shrink: 0; background: var(--surface);
  border-right: 1px solid var(--border); display: flex; flex-direction: column; overflow: hidden;
}
.sidebar-section { padding: 12px 14px 6px; font-size: 11px; font-weight: 600; text-transform: uppercase; color: var(--muted); letter-spacing: .5px; }
.sidebar-scroll { flex: 1; overflow-y: auto; }
.phase-item {
  display: flex; align-items: center; gap: 8px;
  padding: 5px 14px; font-size: 13px; color: var(--muted);
  cursor: pointer; border-radius: 4px; margin: 1px 6px;
}
.phase-item:hover { background: var(--card); color: var(--text); }
.phase-dot { width: 8px; height: 8px; border-radius: 50%; background: var(--border); flex-shrink: 0; }
.phase-dot.ok   { background: var(--green); }
.phase-dot.run  { background: var(--azure); animation: pulse 1.2s infinite; }
.phase-dot.fail { background: var(--red); }
@keyframes pulse { 0%,100%{ opacity:1; } 50%{ opacity:.3; } }
.divider { height: 1px; background: var(--border); margin: 6px 14px; }
.agent-row { display: flex; align-items: center; gap: 6px; padding: 4px 14px; font-size: 12px; color: var(--muted); cursor: pointer; border-radius: 4px; margin: 1px 6px; }
.agent-row:hover { background: var(--card); color: var(--text); }
.agent-row .dot { width: 6px; height: 6px; border-radius: 50%; background: var(--green); flex-shrink: 0; }
.agent-ver { margin-left: auto; font-size: 10px; color: var(--border); }

/* ── Detail Drawer ── */
.drawer-overlay {
  position: fixed; inset: 0; z-index: 100;
  background: rgba(0,0,0,.55); display: flex; align-items: stretch; justify-content: flex-end;
}
.drawer-overlay.hidden { display: none; }
.drawer {
  width: min(820px, 96vw); background: var(--surface); border-left: 1px solid var(--border);
  display: flex; flex-direction: column; overflow: hidden;
  animation: slideIn .2s ease;
}
@keyframes slideIn { from { transform: translateX(100%); } to { transform: translateX(0); } }
.drawer-head {
  display: flex; align-items: center; justify-content: space-between;
  padding: 12px 18px; border-bottom: 1px solid var(--border); flex-shrink: 0;
}
.drawer-head-title { font-weight: 600; font-size: 14px; }
.drawer-close {
  background: none; border: none; color: var(--muted); font-size: 18px;
  cursor: pointer; padding: 2px 8px; border-radius: 4px; line-height: 1;
}
.drawer-close:hover { background: var(--card); color: var(--text); }
.drawer-body { display: flex; flex: 1; overflow: hidden; }
.drawer-files {
  width: 220px; flex-shrink: 0; border-right: 1px solid var(--border);
  overflow-y: auto; padding: 8px 0;
}
.drawer-file-section {
  font-size: 10px; font-weight: 700; text-transform: uppercase; color: var(--border);
  padding: 10px 14px 3px; letter-spacing: .5px;
}
.drawer-file-item {
  padding: 5px 14px; font-size: 12px; cursor: pointer; color: var(--muted);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.drawer-file-item:hover { background: var(--card); color: var(--text); }
.drawer-file-item.active { background: #0078d420; color: var(--azure); border-left: 2px solid var(--azure); }
.drawer-content {
  flex: 1; overflow-y: auto; padding: 16px 20px;
  font-family: 'Consolas','Courier New',monospace; font-size: 12px; line-height: 1.65;
  white-space: pre-wrap; word-break: break-all; color: var(--text);
}
.drawer-content.rendered { font-family: var(--font); white-space: normal; font-size: 14px; }
.drawer-content.rendered h1,.drawer-content.rendered h2,.drawer-content.rendered h3 { margin: 14px 0 6px; }
.drawer-content.rendered p { margin: 0 0 8px; }
.drawer-content.rendered code { background: var(--card); padding: 1px 5px; border-radius: 3px; font-family: 'Consolas',monospace; font-size: 12px; }
.drawer-content.rendered pre { background: var(--bg); border: 1px solid var(--border); border-radius: 4px; padding: 10px; overflow-x: auto; margin: 8px 0; }
.drawer-content.rendered pre code { background: none; padding: 0; }
.drawer-content.rendered table { border-collapse: collapse; width: 100%; font-size: 13px; margin: 8px 0; }
.drawer-content.rendered th,.drawer-content.rendered td { border: 1px solid var(--border); padding: 5px 10px; }
.drawer-content.rendered th { background: var(--card); }
.drawer-agent-detail h2 { margin: 0 0 14px; font-size: 17px; }
.drawer-agent-detail dl { display: grid; grid-template-columns: 130px 1fr; gap: 6px 12px; margin-bottom: 18px; }
.drawer-agent-detail dt { color: var(--muted); font-size: 12px; align-self: center; }
.drawer-agent-detail dd { margin: 0; font-size: 13px; }

/* ── Chat panel ── */
#chat { flex: 1; display: flex; flex-direction: column; overflow: hidden; }
#messages { flex: 1; overflow-y: auto; padding: 20px; display: flex; flex-direction: column; gap: 14px; }
#messages::-webkit-scrollbar { width: 5px; }
#messages::-webkit-scrollbar-thumb { background: var(--border); border-radius: 3px; }

/* ── Message bubble ── */
.msg { display: flex; gap: 10px; max-width: 840px; width: 100%; }
.msg.user { align-self: flex-end; flex-direction: row-reverse; }
.avatar {
  width: 30px; height: 30px; border-radius: 50%;
  background: var(--card); border: 1px solid var(--border);
  display: flex; align-items: center; justify-content: center;
  font-size: 13px; flex-shrink: 0;
}
.msg.user .avatar { background: var(--azure); border-color: #1f4f7e; }
.msg-body { flex: 1; min-width: 0; }
.msg-head { font-size: 11px; color: var(--muted); margin-bottom: 3px; }
.bubble {
  background: var(--card); border: 1px solid var(--border);
  border-radius: var(--r); padding: 10px 14px;
  font-size: 14px; line-height: 1.6;
}
.msg.user .bubble { background: #1a3a5c; border-color: #1f4f7e; }
.bubble p { margin-bottom: 6px; }
.bubble p:last-child { margin-bottom: 0; }
.bubble code { background: var(--surface); padding: 1px 5px; border-radius: 3px; font-size: 12px; font-family: 'Consolas',monospace; }
.bubble pre { background: var(--surface); border: 1px solid var(--border); border-radius: 4px; padding: 10px; overflow-x: auto; margin: 8px 0; }
.bubble pre code { background: none; padding: 0; font-size: 12px; }
.bubble ul,.bubble ol { padding-left: 18px; margin: 4px 0; }
.bubble h1,.bubble h2,.bubble h3 { margin: 10px 0 5px; font-size: 14px; }

/* ── Tool call card ── */
.tool-card {
  margin: 5px 0; border: 1px solid var(--border); border-radius: 6px; overflow: hidden; font-size: 12px;
}
.tool-head {
  display: flex; align-items: center; gap: 7px;
  padding: 5px 10px; background: var(--surface); cursor: pointer; user-select: none;
}
.tool-head:hover { background: var(--bg); }
.t-icon { flex-shrink: 0; }
.t-name { font-weight: 600; color: var(--accent); }
.t-sum { color: var(--muted); flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.t-badge { font-size: 10px; padding: 1px 6px; border-radius: 10px; white-space: nowrap; }
.t-badge.calling { background: #d2992220; color: var(--yellow); }
.t-badge.done    { background: #3fb95020; color: var(--green); }
.t-badge.error   { background: #f8514920; color: var(--red); }
.tool-body { padding: 7px 10px; background: var(--bg); font-family: 'Consolas',monospace; font-size: 11px; color: var(--muted); display: none; white-space: pre-wrap; word-break: break-all; max-height: 200px; overflow-y: auto; }
.tool-card.open .tool-body { display: block; }

/* ── Thinking indicator ── */
.thinking { display: flex; gap: 10px; align-items: center; }
.dots span {
  display: inline-block; width: 5px; height: 5px;
  background: var(--muted); border-radius: 50%; margin: 0 2px;
  animation: bounce 1.4s infinite;
}
.dots span:nth-child(2) { animation-delay: .2s; }
.dots span:nth-child(3) { animation-delay: .4s; }
@keyframes bounce { 0%,60%,100%{ transform:translateY(0); } 30%{ transform:translateY(-5px); } }
.think-text { font-size: 12px; color: var(--muted); }

/* ── Quick actions ── */
.quick-bar { display: flex; gap: 7px; flex-wrap: wrap; padding: 8px 20px; border-top: 1px solid var(--border); }
.q-btn {
  background: var(--card); border: 1px solid var(--border); color: var(--muted);
  border-radius: 14px; padding: 4px 12px; font-size: 12px; cursor: pointer;
}
.q-btn:hover { border-color: var(--accent); color: var(--accent); }

/* ── Input area ── */
#input-row {
  display: flex; gap: 8px; align-items: flex-end;
  padding: 12px 20px; border-top: 1px solid var(--border); background: var(--surface);
}
#input-row textarea {
  flex: 1; background: var(--card); border: 1px solid var(--border);
  border-radius: var(--r); padding: 9px 12px;
  color: var(--text); font-family: var(--font); font-size: 14px;
  resize: none; min-height: 42px; max-height: 150px; line-height: 1.5; outline: none;
}
#input-row textarea:focus { border-color: var(--accent); }
#send { background: var(--azure); border: none; color: #fff; border-radius: var(--r); padding: 9px 18px; font-size: 14px; font-weight: 500; cursor: pointer; height: 42px; white-space: nowrap; }
#send:hover { background: #106ebe; }
#send:disabled { opacity: .5; cursor: default; }
</style>
</head>
<body>

<header>
  <svg width="26" height="26" viewBox="0 0 26 26" fill="none">
    <rect width="26" height="26" rx="4" fill="#0078d4"/>
    <path d="M5 19L10 7l4 8 3-5 4 9" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
  </svg>
  <h1>Azure Migration Agent</h1>
  <select id="agent-select"><option value="">🤖 Auto (Project Manager)</option></select>
  <div class="badge" id="badge">Connected</div>
</header>

<main>
  <aside>
    <div class="sidebar-section">Migration Status</div>
    <div class="sidebar-scroll">
      <div class="phase-item" onclick="openPhaseDrawer('1')"><div class="phase-dot" id="d-1"></div>Phase 1 · Discovery</div>
      <div class="phase-item" onclick="openPhaseDrawer('2')"><div class="phase-dot" id="d-2"></div>Phase 2 · Architecture</div>
      <div class="phase-item" onclick="openPhaseDrawer('3a')"><div class="phase-dot" id="d-3a"></div>Phase 3a · IaC</div>
      <div class="phase-item" onclick="openPhaseDrawer('3b')"><div class="phase-dot" id="d-3b"></div>Phase 3b · Code Refactor</div>
      <div class="phase-item" onclick="openPhaseDrawer('3c')"><div class="phase-dot" id="d-3c"></div>Phase 3c · Pipeline</div>
      <div class="phase-item" onclick="openPhaseDrawer('4')"><div class="phase-dot" id="d-4"></div>Phase 4 · Validation</div>
      <div class="divider"></div>
      <div class="sidebar-section">Agents</div>
      <div id="agent-list"></div>
    </div>
  </aside>

  <section id="chat">
    <div id="messages">
      <div class="msg">
        <div class="avatar">🤖</div>
        <div class="msg-body">
          <div class="msg-head">migration-project-manager</div>
          <div class="bubble">
            <p>Hello! I'm your <strong>Azure Migration Project Manager</strong>. I can orchestrate the full AWS-to-Azure migration pipeline, or you can talk directly to any specialist agent using the dropdown above.</p>
            <p>Use the quick actions below to get started, or type anything.</p>
          </div>
        </div>
      </div>
    </div>

    <div class="quick-bar">
      <button class="q-btn" onclick="q('Run the full AWS-to-Azure migration pipeline')">▶ Run full pipeline</button>
      <button class="q-btn" onclick="q('Run Phase 1 — AWS Discovery only')">🔍 Discovery</button>
      <button class="q-btn" onclick="q('Use storage failover — analyse the source-app folder and produce discovery artifacts')">📂 Discovery (storage fallback)</button>
      <button class="q-btn" onclick="q('What is the current migration status?')">📊 Status</button>
      <button class="q-btn" onclick="q('Show the Azure architecture design')">🏗 Architecture</button>
    </div>

    <div id="input-row">
      <textarea id="inp" placeholder="Ask the migration agent anything…" rows="1"></textarea>
      <button id="send" onclick="send()">Send ↑</button>
    </div>
  </section>
</main>

<!-- Detail Drawer -->
<div id="drawer" class="drawer-overlay hidden" onclick="if(event.target===this)closeDrawer()">
  <div class="drawer">
    <div class="drawer-head">
      <span class="drawer-head-title" id="drawer-title"></span>
      <button class="drawer-close" onclick="closeDrawer()" title="Close">✕</button>
    </div>
    <div class="drawer-body">
      <div class="drawer-files" id="drawer-files"></div>
      <div class="drawer-content" id="drawer-content"></div>
    </div>
  </div>
</div>

<script>
marked.setOptions({ breaks: true, gfm: true });

const $msg  = document.getElementById('messages');
const $inp  = document.getElementById('inp');
const $send = document.getElementById('send');
const $sel  = document.getElementById('agent-select');

// ── Auto-resize textarea ──────────────────────────────────────────────────
$inp.addEventListener('input', () => {
  $inp.style.height = 'auto';
  $inp.style.height = Math.min($inp.scrollHeight, 150) + 'px';
});
$inp.addEventListener('keydown', e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); send(); } });

// ── Status polling ────────────────────────────────────────────────────────
async function loadStatus() {
  try {
    const d = await (await fetch('/api/status')).json();
    renderAgentList(d.agents);
    updateDots(d.task_plan);
  } catch {
    document.getElementById('badge').textContent = 'Disconnected';
    document.getElementById('badge').style.color = 'var(--red)';
  }
}

async function loadAgentSelect() {
  try {
    const agents = await (await fetch('/api/agents')).json();
    if (!agents || agents.length === 0) {
      $sel.innerHTML = '<option value="">No agents deployed</option>';
      return;
    }
    $sel.innerHTML =
      '<option value="">🤖 Auto (Project Manager)</option>' +
      agents.map(a => `<option value="${a.id}">${a.name}</option>`).join('');
  } catch(e) {
    $sel.innerHTML = '<option value="">⚠ Could not load agents</option>';
    console.error('loadAgentSelect error:', e);
  }
}

function renderAgentList(ids) {
  document.getElementById('agent-list').innerHTML = Object.entries(ids)
    .filter(([,v]) => v)
    .map(([name, id]) => `
      <div class="agent-row" onclick="openAgentDrawer('${id}','${name}')">
        <div class="dot"></div>
        <span>${name}</span>
        <span class="agent-ver">${id.includes(':') ? 'v' + id.split(':')[1] : ''}</span>
      </div>`)
    .join('');
}

function updateDots(plan) {
  if (!plan) return;
  const map = { '1': 'd-1', '2': 'd-2', '3a': 'd-3a', '3b': 'd-3b', '3c': 'd-3c', '4': 'd-4' };
  for (const [p, id] of Object.entries(map)) {
    const el = document.getElementById(id);
    if (!el) continue;
    const re = new RegExp(`Phase ${p} [—–-] (COMPLETED|IN_PROGRESS|FAILED)`);
    const m = plan.match(re);
    if (!m) continue;
    el.className = 'phase-dot ' + (m[1] === 'COMPLETED' ? 'ok' : m[1] === 'IN_PROGRESS' ? 'run' : 'fail');
  }
}

// ── Current conversation state ────────────────────────────────────────────
let activeMsgs = {};   // agentName → {msgEl, bubbleEl}
let thinkingEl = null;

function addUserMsg(text) {
  const el = document.createElement('div');
  el.className = 'msg user';
  el.innerHTML = `
    <div class="avatar">👤</div>
    <div class="msg-body">
      <div class="msg-head">You</div>
      <div class="bubble">${text.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/\n/g,'<br>')}</div>
    </div>`;
  $msg.appendChild(el);
  scroll();
}

function getAgentBubble(agent) {
  if (activeMsgs[agent]) return activeMsgs[agent].bubbleEl;
  const msg = document.createElement('div');
  msg.className = 'msg';
  const uid = 'b-' + agent.replace(/[^a-z0-9]/gi, '_') + '-' + Date.now();
  msg.innerHTML = `
    <div class="avatar">🤖</div>
    <div class="msg-body">
      <div class="msg-head">${agent}</div>
      <div class="bubble" id="${uid}"></div>
    </div>`;
  $msg.appendChild(msg);
  const bubbleEl = document.getElementById(uid);
  activeMsgs[agent] = { msgEl: msg, bubbleEl };
  return bubbleEl;
}

function showThinking(agent, action) {
  removeThinking();
  thinkingEl = document.createElement('div');
  thinkingEl.className = 'thinking';
  thinkingEl.innerHTML = `
    <div class="avatar" style="width:30px;height:30px;border-radius:50%;background:var(--card);border:1px solid var(--border);display:flex;align-items:center;justify-content:center;font-size:13px;flex-shrink:0">🤖</div>
    <div>
      <div style="font-size:11px;color:var(--muted);margin-bottom:3px">${agent}</div>
      <div style="display:flex;align-items:center;gap:7px">
        <div class="dots"><span></span><span></span><span></span></div>
        <span class="think-text">${action || 'Thinking…'}</span>
      </div>
    </div>`;
  $msg.appendChild(thinkingEl);
  scroll();
}

function removeThinking() {
  if (thinkingEl) { thinkingEl.remove(); thinkingEl = null; }
}

function addToolCard(agent, name, status, summary) {
  removeThinking();
  const bubble = getAgentBubble(agent);

  // If card already exists (calling→done transition)
  const existing = bubble.querySelector(`[data-tool="${name}"][data-st="calling"]`);
  if (existing && status === 'done') {
    existing.dataset.st = 'done';
    existing.querySelector('.t-badge').textContent = '✓ done';
    existing.querySelector('.t-badge').className = 't-badge done';
    existing.querySelector('.t-sum').textContent = summary || '';
    existing.querySelector('.tool-body').textContent = summary || '';
    return;
  }

  const icon = name.startsWith('delegate_to_') ? '→' : name === 'write_artifact' ? '💾' : name === 'read_storage_artifact' ? '📂' : name === 'update_task_plan' ? '📋' : '⚙';
  const card = document.createElement('div');
  card.className = 'tool-card';
  card.dataset.tool = name;
  card.dataset.st = status;
  card.innerHTML = `
    <div class="tool-head" onclick="this.parentElement.classList.toggle('open')">
      <span class="t-icon">${icon}</span>
      <span class="t-name">${name}</span>
      <span class="t-sum">${summary || ''}</span>
      <span class="t-badge ${status}">${status === 'calling' ? '⏳ running' : '✓ done'}</span>
    </div>
    <div class="tool-body">${summary || ''}</div>`;
  bubble.appendChild(card);
  scroll();
}

function appendMarkdown(agent, content) {
  removeThinking();
  const bubble = getAgentBubble(agent);
  const div = document.createElement('div');
  div.innerHTML = marked.parse(content || '');
  bubble.appendChild(div);
  scroll();
  loadStatus();
}

function scroll() {
  setTimeout(() => { $msg.scrollTop = $msg.scrollHeight; }, 50);
}

// ── SSE event handler ─────────────────────────────────────────────────────
function handle(evt) {
  switch (evt.type) {
    case 'thinking': showThinking(evt.agent, evt.action); break;
    case 'tool':     addToolCard(evt.agent, evt.name, evt.status, evt.summary); break;
    case 'message':  appendMarkdown(evt.agent, evt.content); break;
    case 'error':    removeThinking(); appendMarkdown(evt.agent || 'system', `**Error:** ${evt.content}`); break;
    case 'done':
      removeThinking();
      $send.disabled = false;
      $send.textContent = 'Send ↑';
      break;
  }
}

// ── Send message ──────────────────────────────────────────────────────────
async function send() {
  const text = $inp.value.trim();
  if (!text || $send.disabled) return;

  addUserMsg(text);
  $inp.value = '';
  $inp.style.height = 'auto';
  activeMsgs = {};

  $send.disabled = true;
  $send.textContent = '⏳';

  const agentId = $sel.value || '';

  try {
    const res = await fetch('/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: text, agent_id: agentId }),
    });

    const reader = res.body.getReader();
    const dec = new TextDecoder();
    let buf = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      const lines = buf.split('\n');
      buf = lines.pop();
      for (const line of lines) {
        if (line.startsWith('data: ')) {
          try { handle(JSON.parse(line.slice(6))); } catch {}
        }
      }
    }
  } catch (e) {
    appendMarkdown('system', `**Connection error:** ${e.message}`);
    $send.disabled = false;
    $send.textContent = 'Send ↑';
  }
}

function q(text) { $inp.value = text; send(); }

// ── Detail Drawer ─────────────────────────────────────────────────────────
const PHASE_INFO = {
  '1':  { label: 'Phase 1 · Discovery',       folders: ['outputs/aws-migration-artifacts'] },
  '2':  { label: 'Phase 2 · Architecture',    folders: ['outputs/azure-architecture-output'] },
  '3a': { label: 'Phase 3a · IaC Transformation', folders: ['outputs/bicep-templates'] },
  '3b': { label: 'Phase 3b · Code Refactor',  folders: ['outputs/azure-functions'] },
  '3c': { label: 'Phase 3c · Pipeline',       folders: ['outputs'],
          filter: f => /\.(yml|yaml)$/i.test(f) },
  '4':  { label: 'Phase 4 · Validation',      folders: ['outputs'],
          filter: f => /validat/i.test(f) || f.endsWith('migration-task-plan.md') },
};

function closeDrawer() {
  document.getElementById('drawer').classList.add('hidden');
}

async function openPhaseDrawer(phase) {
  const info = PHASE_INFO[phase];
  if (!info) return;
  document.getElementById('drawer-title').textContent = info.label;
  const $files = document.getElementById('drawer-files');
  const $content = document.getElementById('drawer-content');
  $files.innerHTML = '<div style="padding:14px;color:var(--muted);font-size:12px">Loading…</div>';
  $content.textContent = '';
  $content.className = 'drawer-content';
  document.getElementById('drawer').classList.remove('hidden');

  const allFiles = [];
  for (const folder of info.folders) {
    try {
      const resp = await fetch('/api/files?folder=' + encodeURIComponent(folder));
      const data = await resp.json();
      let files = data.files || [];
      if (info.filter) files = files.filter(info.filter);
      allFiles.push(...files);
    } catch {}
  }

  if (allFiles.length === 0) {
    $files.innerHTML = '<div style="padding:14px;color:var(--muted);font-size:12px">No artifacts yet — run the pipeline first.</div>';
    $content.textContent = 'Run the pipeline to generate artifacts for this phase.';
    return;
  }

  // Group files by immediate parent folder for nicer display
  const groups = {};
  for (const f of allFiles) {
    const parts = f.split('/');
    const dir = parts.slice(0, -1).join('/') || '.';
    (groups[dir] = groups[dir] || []).push(f);
  }

  let html = '';
  for (const [dir, files] of Object.entries(groups)) {
    const label = dir === '.' ? 'root' : dir.split('/').pop();
    if (Object.keys(groups).length > 1)
      html += `<div class="drawer-file-section">${label}</div>`;
    for (const f of files) {
      const name = f.split('/').pop();
      html += `<div class="drawer-file-item" onclick="loadArtifact(this,'${f.replace(/\\/g,'\\\\').replace(/'/g,"\\'")}') " title="${f}">${name}</div>`;
    }
  }
  $files.innerHTML = html;

  // Auto-load first file
  const first = $files.querySelector('.drawer-file-item');
  if (first) first.click();
}

async function openAgentDrawer(agentId, agentName) {
  document.getElementById('drawer-title').textContent = '🤖 ' + agentName;
  document.getElementById('drawer-files').innerHTML = '';
  const $content = document.getElementById('drawer-content');
  $content.className = 'drawer-content rendered';
  $content.innerHTML = `
    <div class="drawer-agent-detail">
      <h2>${agentName}</h2>
      <dl>
        <dt>Version ID</dt><dd><code>${agentId}</code></dd>
        <dt>Status</dt><dd style="color:var(--green)">● Deployed</dd>
        <dt>Model</dt><dd><code>gpt-4.1</code></dd>
      </dl>
      <p style="color:var(--muted);font-size:13px">
        Select this agent in the dropdown to chat with it directly,
        or ask the Project Manager to delegate to it automatically.
      </p>
      <button class="q-btn" style="margin-top:10px" onclick="closeDrawer();$sel.value='${agentId}';$inp.focus()">
        Select this agent ↗
      </button>
    </div>`;
  document.getElementById('drawer').classList.remove('hidden');
}

async function loadArtifact(el, path) {
  document.querySelectorAll('.drawer-file-item').forEach(e => e.classList.remove('active'));
  el.classList.add('active');
  const $content = document.getElementById('drawer-content');
  $content.className = 'drawer-content';
  $content.textContent = 'Loading…';
  try {
    const resp = await fetch('/api/artifact?path=' + encodeURIComponent(path));
    if (!resp.ok) {
      $content.textContent = 'Error ' + resp.status + ': ' + (await resp.text());
      return;
    }
    const data = await resp.json();
    const text = data.content || '';
    const isMarkdown = /\.md$/i.test(path);
    const isMermaid  = /\.mmd$/i.test(path);
    if (isMarkdown) {
      $content.innerHTML = marked.parse(text);
      $content.className = 'drawer-content rendered';
    } else if (isMermaid) {
      $content.innerHTML =
        '<p style="color:var(--muted);font-size:11px;margin-bottom:8px">Mermaid diagram source:</p><pre>' +
        text.replace(/</g,'&lt;') + '</pre>';
      $content.className = 'drawer-content';
    } else {
      $content.textContent = text;
      $content.className = 'drawer-content';
    }
  } catch(e) {
    $content.textContent = 'Error: ' + e.message;
  }
}

// ── Init ──────────────────────────────────────────────────────────────────
loadStatus();
loadAgentSelect();
setInterval(loadStatus, 20000);
</script>
</body>
</html>
"""

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    print(f"\n  Migration Agent Chat  →  http://localhost:8000")
    print(f"  Endpoint : {config.PROJECT_ENDPOINT}")
    print(f"  Model    : {config.MODEL_DEPLOYMENT}\n")
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="warning")


if __name__ == "__main__":
    main()
