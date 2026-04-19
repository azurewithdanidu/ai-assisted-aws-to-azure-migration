// renderers.js — File content renderers for the viewer modal
// This module is intentionally separate so Vite's HTML-aware import
// analysis does not misparse closing HTML tags in string literals.

// ── Security: HTML escape (local copy) ───────────────────────────
function escHtml(str) {
  if (typeof str !== 'string') return ''
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#039;')
}

// ── Inline markdown ───────────────────────────────────────────────
function inlineMarkdown(text) {
  return text
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1<' + '/strong>')
    .replace(/\*(.+?)\*/g,     '<em>$1<' + '/em>')
    .replace(/`([^`]+)`/g,     '<code class="inline-code">$1<' + '/code>')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '<span class="md-link">$1<' + '/span>')
}

// ── Markdown renderer ─────────────────────────────────────────────
export function renderMarkdown(md) {
  const lines = md.split('\n')
  let html = '', inTable = false, inCode = false, codeAccum = ''
  const cl = '<' // avoid Vite parsing closing tags in strings
  const CR = cl + '/'

  for (let i = 0; i < lines.length; i++) {
    const raw  = lines[i]
    const line = raw

    if (/^```/.test(line)) {
      if (!inCode) { inCode = true; codeAccum = ''; continue }
      html += cl + 'pre class="viewer-code">' + escHtml(codeAccum) + CR + 'pre>'
      inCode = false; continue
    }
    if (inCode) { codeAccum += raw + '\n'; continue }

    // Table
    if (/^\|/.test(line)) {
      if (!inTable) { html += cl + 'div class="viewer-table-wrap">' + cl + 'table>'; inTable = true }
      const isSep = /^[\|\s\-]+$/.test(line)
      if (isSep) continue
      const isHeader = lines[i + 1] && /^[\|\s\-]+$/.test(lines[i + 1])
      const tag = isHeader ? 'th' : 'td'
      const cells = line.split('|').map(s => s.trim()).filter(Boolean)
      html += cl + 'tr>' + cells.map(c => cl + tag + '>' + inlineMarkdown(c) + CR + tag + '>').join('') + CR + 'tr>'
      continue
    } else if (inTable) {
      html += CR + 'table>' + CR + 'div>'; inTable = false
    }

    const h = line.match(/^(#{1,4})\s+(.+)/)
    if (h) {
      const n = h[1].length
      html += cl + 'h' + n + ' class="md-h' + n + '">' + inlineMarkdown(h[2]) + CR + 'h' + n + '>'
      continue
    }

    if (/^---+$/.test(line.trim())) { html += cl + 'hr class="md-hr">'; continue }

    const li = line.match(/^[-*]\s+(.+)/)
    if (li) {
      html += cl + 'div class="md-li">' + cl + 'span class="md-bullet">\u2022' + CR + 'span>' + inlineMarkdown(li[1]) + CR + 'div>'
      continue
    }

    const nl = line.match(/^\d+\.\s+(.+)/)
    if (nl) {
      html += cl + 'div class="md-li">' + cl + 'span class="md-bullet">\u203a' + CR + 'span>' + inlineMarkdown(nl[1]) + CR + 'div>'
      continue
    }

    if (!line.trim()) { html += cl + 'div class="md-gap">' + CR + 'div>'; continue }

    html += cl + 'p class="md-p">' + inlineMarkdown(line) + CR + 'p>'
  }

  if (inTable) html += CR + 'table>' + CR + 'div>'
  if (inCode)  html += cl + 'pre class="viewer-code">' + escHtml(codeAccum) + CR + 'pre>'

  return cl + 'div class="viewer-md">' + html + CR + 'div>'
}

// ── JSON renderer ─────────────────────────────────────────────────
export function renderJson(text) {
  try {
    const obj    = JSON.parse(text)
    const pretty = JSON.stringify(obj, null, 2)
    const safe   = pretty
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    // Colorize after escaping (patterns won't contain raw < > anymore)
    const SP = '<' + '/span>'
    const colored = safe
      .replace(/("[\w @\-\/.]+")\s*:/g,  '<span class="jk">$1' + SP + ':')
      .replace(/:\s*("(?:[^"\\]|\\.)*")/g, ': <span class="js">$1' + SP)
      .replace(/:\s*(\d+\.?\d*(?:e[+-]?\d+)?)\b/gi, ': <span class="jn">$1' + SP)
      .replace(/:\s*(true|false|null)\b/g, ': <span class="jb">$1' + SP)
    return '<pre class="viewer-code viewer-json">' + colored + '<' + '/pre>'
  } catch {
    return '<pre class="viewer-code">' + escHtml(text) + '<' + '/pre>'
  }
}

// ── CSV renderer ─────────────────────────────────────────────────
export function renderCsv(text) {
  const rows = text.trim().split('\n').map(r => r.split(',').map(c => c.replace(/^"|"$/g, '').trim()))
  if (!rows.length) return '<p>Empty file<' + '/p>'
  const [head, ...body] = rows
  const wrap  = document.createElement('div')
  wrap.className = 'viewer-table-wrap'
  const table = document.createElement('table')
  table.className = 'styled-table'
  const thead = document.createElement('thead')
  const hrow  = document.createElement('tr')
  head.forEach(h => { const th = document.createElement('th'); th.textContent = h; hrow.appendChild(th) })
  thead.appendChild(hrow)
  table.appendChild(thead)
  const tbody = document.createElement('tbody')
  body.forEach(row => {
    const tr = document.createElement('tr')
    row.forEach(c => { const td = document.createElement('td'); td.textContent = c; tr.appendChild(td) })
    tbody.appendChild(tr)
  })
  table.appendChild(tbody)
  wrap.appendChild(table)
  return wrap.outerHTML
}

// ── Mermaid renderer (returns placeholder HTML) ───────────────────
export function renderMermaid(text) {
  const encoded = encodeURIComponent(text)
  const cl = '<'
  const CR = cl + '/'
  return (
    cl + 'div class="mermaid-wrap" data-mmd="' + encoded + '">'
    + cl + 'div id="mermaid-target" class="mermaid-target">'
    + cl + 'div class="mermaid-loading">\u23f3 Rendering diagram\u2026' + CR + 'div>'
    + CR + 'div>'
    + cl + 'details class="mermaid-source">'
    + cl + 'summary>View source' + CR + 'summary>'
    + cl + 'pre class="viewer-code">' + escHtml(text) + CR + 'pre>'
    + CR + 'details>'
    + CR + 'div>'
  )
}

export async function mountMermaid(container) {
  const wrap = container.querySelector('[data-mmd]')
  if (!wrap) return
  const src = decodeURIComponent(wrap.dataset.mmd)
  const el  = wrap.querySelector('#mermaid-target')
  try {
    const { default: mermaid } = await import('https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs')
    mermaid.initialize({
      startOnLoad: false,
      theme: 'dark',
      themeVariables: {
        background: '#0f1629',
        primaryColor: '#1a2236',
        primaryTextColor: '#e8edf7',
        lineColor: '#8898b4'
      }
    })
    const uid = 'mmd-' + Date.now()
    const { svg } = await mermaid.render(uid, src)
    el.innerHTML = svg
  } catch (err) {
    el.innerHTML = '<p style="color:#ef4444">Diagram render failed: ' + escHtml(err.message) + '<' + '/p>'
  }
}

// ── Dispatch ──────────────────────────────────────────────────────
export function renderFileContent(path, text) {
  if (path.endsWith('.md'))    return renderMarkdown(text)
  if (path.endsWith('.json'))  return renderJson(text)
  if (path.endsWith('.csv'))   return renderCsv(text)
  if (path.endsWith('.mmd'))   return renderMermaid(text)
  return '<pre class="viewer-code">' + escHtml(text) + '<' + '/pre>'
}
