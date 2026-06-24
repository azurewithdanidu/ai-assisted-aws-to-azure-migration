import './style.css'
import { renderFileContent, mountMermaid } from './renderers.js'

// ── Config ──────────────────────────────────────────────────────
const REFRESH_INTERVAL = 30 // seconds

// ── Artifacts per phase ──────────────────────────────────────────
// Each entry: { label, path, icon }  — path is relative to outputs/
const PHASE_ARTIFACTS = {
  '1': [
    { label: 'AWS Inventory',        path: 'aws-migration-artifacts/aws-inventory.json',          icon: '📦' },
    { label: 'Architecture Diagram', path: 'aws-migration-artifacts/architecture-diagram.mmd',    icon: '📐' },
    { label: 'Dependency Matrix',    path: 'aws-migration-artifacts/dependency-matrix.csv',       icon: '🔗' },
    { label: 'Migration Assessment', path: 'aws-migration-artifacts/migration-assessment.md',     icon: '📋' },
    { label: 'CloudFormation',       path: 'aws-migration-artifacts/cloudformation-template.yaml',icon: '🏗️' },
  ],
  '2': [
    { label: 'Design Document',      path: 'azure-architecture-output/design-document.md',        icon: '📝' },
    { label: 'Azure Diagram',        path: 'azure-architecture-output/architecture-diagram-azure.mmd', icon: '📐' },
    { label: 'Cost Comparison',      path: 'azure-architecture-output/cost-comparison.md',        icon: '💰' },
    { label: 'Service Mapping',      path: 'azure-architecture-output/service-mapping.md',        icon: '🗺️' },
  ],
}

// ── State ───────────────────────────────────────────────────────
let countdown = REFRESH_INTERVAL
let countdownTimer = null
let availableArtifacts = new Set()   // paths that actually exist on disk
let tokenUsageData = null

// Load artifact availability once at boot
async function loadArtifactAvailability() {
  try {
    const res  = await fetch('/api/artifacts')
    const list = await res.json()
    availableArtifacts = new Set(list.filter(a => a.exists).map(a => a.path))
  } catch { /* silently ignore — chips just won't show */ }
}

async function loadTokenUsageData() {
  try {
    const res = await fetch('/api/agent-token-usage')
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    tokenUsageData = await res.json()
  } catch {
    tokenUsageData = null
  }
}

// ── Status metadata ─────────────────────────────────────────────
const STATUS = {
  '✅': { label: 'Complete',     cls: 'complete',     icon: '✅' },
  '🔄': { label: 'In Progress', cls: 'in-progress',  icon: '🔄' },
  '⏳': { label: 'Not Started', cls: 'not-started',  icon: '⏳' },
  '❌': { label: 'Failed',      cls: 'failed',        icon: '❌' },
}

function getStatus(emoji) {
  return STATUS[emoji] ?? { label: emoji, cls: 'not-started', icon: emoji }
}

// ── Markdown Parser ──────────────────────────────────────────────
function parsePlan(text) {
  const lines = text.split('\n')
  const plan = { generated: null, lastUpdated: null, accountId: null, phases: [], blockers: [] }

  // ── Metadata ──
  for (const line of lines) {
    const g = line.match(/^Generated:\s*(.+)/);           if (g) plan.generated    = g[1].trim()
    const u = line.match(/^Last Updated:\s*(.+)/);        if (u) plan.lastUpdated  = u[1].trim()
    const a = line.match(/Account ID:\s*[`']?([^`'\n]+)/);if (a) plan.accountId    = a[1].trim()
  }

  // ── Phase summary table ──
  // Rows look like: | 1 — Discovery | aws-discovery | ✅ | 2026-04-18T00:05:00Z |
  let inSummary = false
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    if (/^##\s+Phase Summary/.test(line))                       { inSummary = true;  continue }
    if (inSummary && /^#{1,2}\s/.test(line))                    { inSummary = false; continue }
    if (!inSummary || !line.startsWith('|'))                    continue
    if (/Phase\s*\|.*Agent/i.test(line) || /^[\|\s\-]+$/.test(line)) continue

    const cols = line.split('|').map(s => s.trim()).filter(Boolean)
    if (cols.length < 3) continue

    // cols[0] = "1 — Discovery", "3a — IaC Transformation", etc.
    const m = cols[0].match(/^(\d+\w*)\s*[—–-]\s*(.+)$/)
    if (!m) continue

    plan.phases.push({
      id:          m[1],
      fullName:    cols[0],
      shortName:   m[2].trim(),
      agent:       cols[1],
      statusEmoji: cols[2],
      completedAt: cols[3] || '—',
      tasks:       [],
    })
  }

  // ── Detailed tasks ──
  let currentId  = null
  let inDetail   = false
  let inBlockers = false

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]

    if (/^##\s+Detailed Task List/.test(line)) { inDetail = true;   continue }
    if (/^##\s+Blockers/.test(line))           { inDetail = false; inBlockers = true; continue }
    if ((inDetail || inBlockers) && /^##\s/.test(line) && !/Detailed Task List|Blockers/.test(line)) {
      inDetail = false; inBlockers = false
    }

    if (inDetail) {
      const ph = line.match(/^###\s+Phase\s+(\d+\w*)\s*[—–-]\s*.+/)
      if (ph) { currentId = ph[1]; continue }

      if (currentId && /^-\s+\[[ xX]\]/.test(line)) {
        const done     = /\[[xX]\]/.test(line)
        const taskText = line.replace(/^-\s+\[[ xX]\]\s*/, '').trim()
        const phase    = plan.phases.find(p => p.id === currentId)
        if (phase) phase.tasks.push({ text: taskText, done })
      }
    }

    if (inBlockers && /^-\s+.+/.test(line)) {
      plan.blockers.push(line.replace(/^-\s+/, '').trim())
    }
  }

  return plan
}

// ── Helpers ──────────────────────────────────────────────────────
function pct(done, total) {
  return total === 0 ? 0 : Math.round((done / total) * 100)
}

function formatDate(iso) {
  if (!iso || iso === '—') return '—'
  const d = new Date(iso)
  if (isNaN(d.getTime())) return iso
  return d.toLocaleString('en-AU', { dateStyle: 'medium', timeStyle: 'short' })
}

function overallStats(phases) {
  let total = 0, done = 0
  for (const p of phases) {
    total += p.tasks.length
    done  += p.tasks.filter(t => t.done).length
  }
  return { total, done, pct: pct(done, total) }
}

// ── SVG Ring ─────────────────────────────────────────────────────
function renderRing(percentage) {
  const r     = 48
  const circ  = 2 * Math.PI * r
  const offset = circ - (percentage / 100) * circ
  const track  = '#2a3552'
  const fill   = percentage === 100 ? '#22c55e' : percentage > 0 ? '#3b82f6' : track
  return `
    <svg class="ring" viewBox="0 0 110 110" width="110" height="110">
      <circle cx="55" cy="55" r="${r}" fill="none" stroke="${track}" stroke-width="9"/>
      <circle cx="55" cy="55" r="${r}" fill="none" stroke="${fill}" stroke-width="9"
        stroke-dasharray="${circ.toFixed(1)}" stroke-dashoffset="${offset.toFixed(1)}"
        stroke-linecap="round" transform="rotate(-90 55 55)"
        style="transition:stroke-dashoffset .7s ease,stroke .4s"/>
      <text x="55" y="59" text-anchor="middle" fill="#e8edf7"
        font-size="20" font-weight="800" font-family="Inter,sans-serif">${percentage}%</text>
    </svg>`
}

// ── Render: Overview panel ────────────────────────────────────────
function renderOverview(stats, phases) {
  const phaseBars = phases.map(p => {
    const s    = getStatus(p.statusEmoji)
    const done = p.tasks.filter(t => t.done).length
    const total = p.tasks.length
    const pp   = pct(done, total)
    const label = total > 0 ? `${pp}%` : s.label
    return `
      <div class="mini-phase">
        <span class="mini-phase-name" title="${p.fullName}">${p.fullName}</span>
        <div class="mini-bar-wrap"><div class="mini-bar ${s.cls}" style="width:${pp}%"></div></div>
        <span class="mini-pct">${label}</span>
      </div>`
  }).join('')

  const badgeCls = stats.pct === 100 ? 'complete' : stats.pct > 0 ? 'in-progress' : 'not-started'

  return `
  <section class="section">
    <div class="progress-overview">
      <div class="progress-main">
        ${renderRing(stats.pct)}
        <div class="progress-numbers">
          <div class="prog-num">${stats.done}<span>/${stats.total}</span></div>
          <div class="prog-label">Tasks Complete</div>
          <div class="prog-bar-wrap">
            <div class="prog-bar" style="width:${stats.pct}%"></div>
          </div>
        </div>
      </div>
      <div class="phase-mini-bars">
        <p class="mini-title">Phase Progress</p>
        ${phaseBars}
      </div>
    </div>
  </section>`
}

function renderTokenUsage(data) {
  if (!data || !Array.isArray(data.phases) || data.phases.length === 0) return ''

  const rows = data.phases.map((p, i) => {
    const preview = escHtml(p.prompt.slice(0, 105).replace(/\s+/g, ' ') + (p.prompt.length > 105 ? '…' : ''))
    return `
      <tr>
        <td><span class="token-phase">${escHtml(p.phase)}</span></td>
        <td><code>${escHtml(p.agent)}</code></td>
        <td class="num">${p.promptWords}</td>
        <td class="num">${p.estimatedPromptTokens}</td>
        <td><input class="run-input" type="number" min="0" value="1" data-row="${i}" /></td>
        <td class="num row-total" id="rowTotal${i}">${p.estimatedPromptTokens}</td>
        <td title="${escHtml(p.prompt)}"><span class="prompt-preview">${preview}</span></td>
      </tr>`
  }).join('')

  return `
  <section class="section">
    <p class="section-title">Agent Prompt Token Usage (Estimated)</p>
    <div class="token-summary">
      <div class="token-kpi">
        <span class="kpi-label">Base Prompt Tokens</span>
        <span class="kpi-val" id="basePromptTokens">${data.totals.tokens}</span>
      </div>
      <div class="token-kpi">
        <span class="kpi-label">Projected Run Tokens</span>
        <span class="kpi-val" id="projectedPromptTokens">${data.totals.tokens}</span>
      </div>
      <div class="token-kpi">
        <span class="kpi-label">Rule</span>
        <span class="kpi-val small">${escHtml(data.tokenRule)}</span>
      </div>
    </div>
    <div class="token-table-wrap">
      <table class="token-table">
        <thead>
          <tr>
            <th>Phase</th>
            <th>Agent</th>
            <th>Words</th>
            <th>Prompt Tokens</th>
            <th>Runs</th>
            <th>Total</th>
            <th>Prompt Preview</th>
          </tr>
        </thead>
        <tbody>
          ${rows}
        </tbody>
      </table>
    </div>
  </section>`
}

// ── Render: Phase card ────────────────────────────────────────────
function renderPhaseCard(phase) {
  const s      = getStatus(phase.statusEmoji)
  const done   = phase.tasks.filter(t => t.done).length
  const total  = phase.tasks.length
  const pp     = pct(done, total)
  const hasTasks = total > 0

  const taskItems = phase.tasks.map(t => `
    <li class="task-item ${t.done ? 'done' : ''}">
      <span class="task-check">${t.done ? '✓' : ''}</span>
      <span class="task-text">${escHtml(t.text)}</span>
    </li>`).join('')

  return `
  <div class="phase-card ${s.cls}">
    <div class="card-header">
      <div class="card-id">Phase ${escHtml(phase.id)}</div>
      <div class="card-badge ${s.cls}">${s.icon} ${s.label}</div>
    </div>
    <h3 class="card-name">${escHtml(phase.shortName)}</h3>
    <p class="card-agent">Agent: <code>${escHtml(phase.agent)}</code></p>

    ${hasTasks ? `
    <div class="card-progress">
      <div class="card-prog-bar-wrap">
        <div class="card-prog-bar ${s.cls}" style="width:${pp}%"></div>
      </div>
      <span class="card-prog-text">${done}/${total}</span>
    </div>` : ''}

    ${phase.completedAt && phase.completedAt !== '—' ? `
    <p class="card-date">Completed: ${formatDate(phase.completedAt)}</p>` : ''}

    ${hasTasks ? `
    <button class="card-toggle" data-open="true">▼ Hide tasks</button>
    <ul class="task-list">${taskItems}</ul>
    ` : ''}

    ${renderArtifactChips(phase.id)}
  </div>`
}

// ── Render: Artifact chips ────────────────────────────────────────
function renderArtifactChips(phaseId) {
  const arts = PHASE_ARTIFACTS[phaseId] ?? []
  const avail = arts.filter(a => availableArtifacts.has(a.path))
  if (avail.length === 0) return ''
  const chips = avail.map(a => `
    <button class="artifact-chip" data-path="${escHtml(a.path)}" data-label="${escHtml(a.label)}">
      <span class="chip-icon">${a.icon}</span>
      <span class="chip-label">${escHtml(a.label)}</span>
      <span class="chip-ext">${extLabel(a.path)}</span>
    </button>`).join('')
  return `<div class="artifact-chips"><span class="chips-title">Artifacts</span>${chips}</div>`
}

function extLabel(path) {
  const m = path.match(/\.([a-z]+)$/i)
  return m ? m[1].toUpperCase() : ''
}

// ── Render: Phase grid ────────────────────────────────────────────
function renderPhaseGrid(phases) {
  return `
  <section class="section">
    <p class="section-title">Migration Phases</p>
    <div class="phase-grid">
      ${phases.map(renderPhaseCard).join('')}
    </div>
  </section>`
}

// ── Render: Blockers ──────────────────────────────────────────────
function renderBlockers(blockers) {
  const real = blockers.filter(b => b.toLowerCase() !== 'none' && b.trim())

  if (real.length === 0) {
    return `
    <section class="section">
      <div class="no-blockers">
        <span class="no-blockers-icon">✅</span>
        No blockers — migration is on track
      </div>
    </section>`
  }
  return `
  <section class="section">
    <p class="section-title blockers-title">⚠ Blockers (${real.length})</p>
    <div class="blockers-list">
      ${real.map(b => `<div class="blocker-item">❌ ${escHtml(b)}</div>`).join('')}
    </div>
  </section>`
}

// ── Render: Header ────────────────────────────────────────────────
function renderHeader(plan, stats) {
  const badgeCls = stats.pct === 100 ? 'complete' : stats.pct > 0 ? 'in-progress' : 'not-started'
  return `
  <header class="header">
    <div class="header-left">
      <div class="logo">
        <span class="logo-aws">AWS</span>
        <span class="logo-arrow">→</span>
        <span class="logo-azure">Azure</span>
      </div>
      <div class="header-titles">
        <h1>Migration Dashboard</h1>
        <p class="header-sub">Account: <code>${escHtml(plan.accountId ?? '—')}</code></p>
      </div>
    </div>
    <div class="header-right">
      <div class="overall-badge ${badgeCls}">
        <span class="badge-pct">${stats.pct}%</span>
        <span class="badge-label">Overall</span>
      </div>
      <button class="refresh-btn" id="refreshBtn">
        ↻ Refresh <span class="countdown" id="countdown">${countdown}s</span>
      </button>
    </div>
  </header>`
}

// ── Render: Footer ────────────────────────────────────────────────
function renderFooter(plan) {
  return `
  <footer class="footer">
    <span>Generated: ${formatDate(plan.generated)}</span>
    <span class="sep">·</span>
    <span>Updated: ${formatDate(plan.lastUpdated)}</span>
    <span class="sep">·</span>
    <span>Auto-refresh in <span id="countdown-foot">${countdown}s</span></span>
  </footer>`
}

// ── Main render ───────────────────────────────────────────────────
function render(plan) {
  const stats = overallStats(plan.phases)
  const app   = document.getElementById('app')

  app.innerHTML = `
    ${renderHeader(plan, stats)}
    <main class="main">
      ${renderOverview(stats, plan.phases)}
      ${renderTokenUsage(tokenUsageData)}
      ${renderPhaseGrid(plan.phases)}
      ${renderBlockers(plan.blockers)}
    </main>
    ${renderFooter(plan)}`

  // Wire up refresh button
  document.getElementById('refreshBtn')?.addEventListener('click', refreshNow)

  // Wire up toggle buttons
  document.querySelectorAll('.card-toggle').forEach(btn => {
    btn.addEventListener('click', () => {
      const list = btn.nextElementSibling
      const open = btn.dataset.open === 'true'
      list.classList.toggle('collapsed', open)
      btn.dataset.open = open ? 'false' : 'true'
      btn.textContent  = open ? '▶ Show tasks' : '▼ Hide tasks'
    })
  })

  // Wire up artifact chips
  document.querySelectorAll('.artifact-chip').forEach(btn => {
    btn.addEventListener('click', () => openViewer(btn.dataset.path, btn.dataset.label))
  })

  wireTokenUsageInputs()
}

function wireTokenUsageInputs() {
  if (!tokenUsageData || !Array.isArray(tokenUsageData.phases)) return
  const inputs = [...document.querySelectorAll('.run-input')]
  if (inputs.length === 0) return

  const refreshTotals = () => {
    let total = 0
    for (const input of inputs) {
      const idx = Number(input.dataset.row)
      const phase = tokenUsageData.phases[idx]
      if (!phase) continue
      const runs = Math.max(0, Number(input.value || 0))
      const rowTotal = runs * phase.estimatedPromptTokens
      const rowCell = document.getElementById(`rowTotal${idx}`)
      if (rowCell) rowCell.textContent = String(rowTotal)
      total += rowTotal
    }
    const projected = document.getElementById('projectedPromptTokens')
    if (projected) projected.textContent = String(total)
  }

  for (const input of inputs) {
    input.addEventListener('input', refreshTotals)
  }
  refreshTotals()
}

// ── Fetch + refresh cycle ──────────────────────────────────────────
async function load() {
  try {
    const res  = await fetch('/api/migration-plan')
    if (!res.ok) throw new Error(`HTTP ${res.status}: ${res.statusText}`)
    const text = await res.text()
    const plan = parsePlan(text)
    render(plan)
    startCountdown()
  } catch (err) {
    document.getElementById('app').innerHTML = `
      <div class="error">
        <h2>Failed to load migration plan</h2>
        <p>${escHtml(err.message)}</p>
        <button id="retryBtn">↻ Retry</button>
      </div>`
    document.getElementById('retryBtn')?.addEventListener('click', refreshNow)
  }
}

function startCountdown() {
  clearInterval(countdownTimer)
  countdown = REFRESH_INTERVAL
  countdownTimer = setInterval(() => {
    countdown--
    const el1 = document.getElementById('countdown')
    const el2 = document.getElementById('countdown-foot')
    if (el1) el1.textContent = `${countdown}s`
    if (el2) el2.textContent = `${countdown}s`
    if (countdown <= 0) {
      clearInterval(countdownTimer)
      load()
    }
  }, 1000)
}

function refreshNow() {
  clearInterval(countdownTimer)
  load()
}

// ── Security: HTML escape ─────────────────────────────────────────
function escHtml(str) {
  if (typeof str !== 'string') return ''
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#039;')
}

// ── File Viewer Modal ────────────────────────────────────────────
async function openViewer(path, label) {
  // Create overlay
  const overlay = document.createElement('div')
  overlay.className = 'viewer-overlay'
  overlay.innerHTML = `
    <div class="viewer-modal" role="dialog" aria-modal="true">
      <div class="viewer-header">
        <div class="viewer-title">
          <span class="viewer-icon">${fileIcon(path)}</span>
          <span>${escHtml(label)}</span>
          <code class="viewer-path">${escHtml(path)}</code>
        </div>
        <div class="viewer-actions">
          <button class="viewer-close" id="viewerClose" aria-label="Close">✕</button>
        </div>
      </div>
      <div class="viewer-body" id="viewerBody">
        <div class="viewer-loading"><div class="spinner"></div></div>
      </div>
    </div>`
  document.body.appendChild(overlay)
  requestAnimationFrame(() => overlay.classList.add('visible'))

  overlay.querySelector('#viewerClose').addEventListener('click', () => closeViewer(overlay))
  overlay.addEventListener('click', e => { if (e.target === overlay) closeViewer(overlay) })
  document.addEventListener('keydown', function esc(e) {
    if (e.key === 'Escape') { closeViewer(overlay); document.removeEventListener('keydown', esc) }
  })

  // Fetch & render
  try {
    const res  = await fetch('/api/artifact?path=' + encodeURIComponent(path))
    if (!res.ok) throw new Error('HTTP ' + res.status)
    const text = await res.text()
    const body = document.getElementById('viewerBody')
    body.innerHTML = renderFileContent(path, text)
    // Wrap tables generated by CSV
    body.querySelectorAll('.viewer-table-wrap table').forEach(t => t.classList.add('styled-table'))
    // Boot Mermaid if needed
    if (path.endsWith('.mmd')) mountMermaid(body)
  } catch (err) {
    document.getElementById('viewerBody').innerHTML =
      '<div class="viewer-error">Failed to load file: ' + escHtml(err.message) + '</div>'
  }
}

function closeViewer(overlay) {
  overlay.classList.remove('visible')
  setTimeout(() => overlay.remove(), 250)
}

function fileIcon(path) {
  if (path.endsWith('.json'))  return '{ }'
  if (path.endsWith('.mmd'))   return '📐'
  if (path.endsWith('.csv'))   return '📊'
  if (path.endsWith('.md'))    return '📄'
  if (path.endsWith('.yaml') || path.endsWith('.yml')) return '⚙️'
  return '📁'
}

// ── Boot ──────────────────────────────────────────────────────────
async function boot() {
  await loadArtifactAvailability()
  await loadTokenUsageData()
  load()
}
boot()
