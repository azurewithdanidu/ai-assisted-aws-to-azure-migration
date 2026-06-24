import { defineConfig } from 'vite'
import { readFileSync, existsSync } from 'node:fs'
import { resolve, dirname, extname } from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const OUTPUTS   = resolve(__dirname, '../outputs')
const PHASE_DELEGATION = resolve(__dirname, '../.github/skills/agents/migration-pm/phase-delegation.md')

// Allowlist of artifact paths (relative to OUTPUTS) that can be served
const ALLOWED_ARTIFACTS = new Set([
  'migration-task-plan.md',
  'aws-migration-artifacts/aws-inventory.json',
  'aws-migration-artifacts/architecture-diagram.mmd',
  'aws-migration-artifacts/cloudformation-template.yaml',
  'aws-migration-artifacts/dependency-matrix.csv',
  'aws-migration-artifacts/migration-assessment.md',
  'azure-architecture-output/design-document.md',
  'azure-architecture-output/architecture-diagram-azure.mmd',
  'azure-architecture-output/cost-comparison.md',
  'azure-architecture-output/service-mapping.md',
])

const MIME = {
  '.md':   'text/plain; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.yaml': 'text/plain; charset=utf-8',
  '.yml':  'text/plain; charset=utf-8',
  '.csv':  'text/csv; charset=utf-8',
  '.mmd':  'text/plain; charset=utf-8',
}

export default defineConfig({
  root: __dirname,
  plugins: [
    {
      name: 'artifacts-api',
      configureServer(server) {
        // GET /api/migration-plan  — shortcut for the task plan
        server.middlewares.use('/api/migration-plan', (_req, res) => {
          serveFile(resolve(OUTPUTS, 'migration-task-plan.md'), res)
        })

        // GET /api/artifact?path=<relative-path>
        server.middlewares.use('/api/artifact', (req, res) => {
          const url      = new URL(req.url, 'http://localhost')
          const rel      = url.searchParams.get('path') ?? ''
          const safe     = rel.replace(/\\/g, '/').replace(/\.\.\//g, '')
          if (!ALLOWED_ARTIFACTS.has(safe)) {
            res.statusCode = 403; res.end('Forbidden'); return
          }
          serveFile(resolve(OUTPUTS, safe), res)
        })

        // GET /api/artifacts  — list available artifacts with existence flag
        server.middlewares.use('/api/artifacts', (_req, res) => {
          const list = [...ALLOWED_ARTIFACTS].map(p => ({
            path:   p,
            exists: existsSync(resolve(OUTPUTS, p)),
          }))
          res.setHeader('Content-Type', 'application/json')
          res.end(JSON.stringify(list))
        })

        // GET /api/agent-token-usage  — estimated input token usage from phase prompts
        server.middlewares.use('/api/agent-token-usage', (_req, res) => {
          try {
            const text = readFileSync(PHASE_DELEGATION, 'utf-8')
            const phases = parseDelegationPrompts(text)
            const totals = phases.reduce((acc, p) => {
              acc.chars += p.promptChars
              acc.words += p.promptWords
              acc.tokens += p.estimatedPromptTokens
              return acc
            }, { chars: 0, words: 0, tokens: 0 })

            res.setHeader('Content-Type', 'application/json')
            res.end(JSON.stringify({
              source: '.github/skills/agents/migration-pm/phase-delegation.md',
              generatedAt: new Date().toISOString(),
              tokenRule: '~1 token per 4 chars',
              phases,
              totals,
            }))
          } catch (err) {
            res.statusCode = 500
            res.setHeader('Content-Type', 'application/json')
            res.end(JSON.stringify({ error: err.message }))
          }
        })
      }
    }
  ]
})

function parseDelegationPrompts(text) {
  const rows = []
  const re = /###\s+Phase\s+(.+?)\s+[—-]\s+.+?`@([^`]+)`[\s\S]*?\*\*Prompt:\*\*[\s\S]*?```([\s\S]*?)```/g
  let m
  while ((m = re.exec(text)) !== null) {
    const phaseLabel = m[1].trim()
    const agent = m[2].trim()
    const prompt = m[3].trim()
    const promptChars = prompt.length
    const promptWords = prompt.split(/\s+/).filter(Boolean).length

    rows.push({
      phase: phaseLabel,
      agent,
      prompt,
      promptChars,
      promptWords,
      estimatedPromptTokens: estimateTokens(prompt),
    })
  }
  return rows
}

function estimateTokens(text) {
  // Heuristic for GPT-family tokenization in mixed natural language prompts.
  return Math.max(1, Math.ceil(text.length / 4))
}

function serveFile(absPath, res) {
  try {
    const content = readFileSync(absPath, 'utf-8')
    const mime    = MIME[extname(absPath)] ?? 'text/plain; charset=utf-8'
    res.setHeader('Content-Type', mime)
    res.setHeader('Cache-Control', 'no-cache')
    res.end(content)
  } catch {
    res.statusCode = 404
    res.end('Not found')
  }
}
