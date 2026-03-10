#!/usr/bin/env node
// persist-engine.mjs — core logic for persist's memory and identity system
// Cross-platform. No external dependencies. Requires Node 18+.

import { execSync } from 'child_process';
import { existsSync, readFileSync, writeFileSync, mkdirSync, readdirSync } from 'fs';
import { join, basename, extname } from 'path';
import { homedir, platform } from 'os';

// ─── Configuration ───────────────────────────────────

const PERSIST_DIR = process.env.PERSIST_DIR || join(homedir(), '.persist');
const DB = join(PERSIST_DIR, 'persist.db');
const CONFIG_PATH = join(PERSIST_DIR, 'config.json');

function loadConfig() {
  if (!existsSync(CONFIG_PATH)) return null;
  try { return JSON.parse(readFileSync(CONFIG_PATH, 'utf8')); }
  catch { return null; }
}

// ─── SQLite helpers ──────────────────────────────────

function sqlEscape(s) {
  if (s == null) return '';
  return String(s).replace(/'/g, "''");
}

function sql(query) {
  if (!existsSync(DB)) return '';
  try {
    return execSync(`sqlite3 "${DB}"`, {
      input: query,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      timeout: 5000,
    }).trim();
  } catch { return ''; }
}

function sqlJson(query) {
  const result = sql(`.mode json\n${query}`);
  if (!result) return [];
  try { return JSON.parse(result); }
  catch { return []; }
}

// ─── Signal Extraction ───────────────────────────────
// Pure functions. No side effects. Each takes text, returns structured data.

const CODE_EXTENSIONS = new Set([
  'js', 'mjs', 'cjs', 'ts', 'tsx', 'jsx', 'py', 'rb', 'rs', 'go', 'java',
  'c', 'cpp', 'h', 'hpp', 'cs', 'php', 'swift', 'kt', 'scala', 'sh', 'bash',
  'zsh', 'ps1', 'psm1', 'yml', 'yaml', 'toml', 'json', 'xml', 'html', 'css',
  'scss', 'less', 'sql', 'md', 'mdx', 'txt', 'conf', 'cfg', 'ini', 'env',
  'dockerfile', 'makefile', 'cmake', 'gradle', 'vue', 'svelte', 'astro',
]);

const STOP_WORDS = new Set([
  'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
  'of', 'with', 'by', 'from', 'is', 'are', 'was', 'were', 'be', 'been',
  'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would',
  'could', 'should', 'may', 'might', 'shall', 'can', 'need', 'dare',
  'ought', 'used', 'this', 'that', 'these', 'those', 'i', 'me', 'my',
  'myself', 'we', 'our', 'ours', 'you', 'your', 'yours', 'he', 'him',
  'his', 'she', 'her', 'hers', 'it', 'its', 'they', 'them', 'their',
  'what', 'which', 'who', 'whom', 'when', 'where', 'why', 'how', 'all',
  'each', 'every', 'both', 'few', 'more', 'most', 'other', 'some', 'such',
  'no', 'not', 'only', 'own', 'same', 'so', 'than', 'too', 'very', 'just',
  'because', 'as', 'until', 'while', 'about', 'between', 'through',
  'during', 'before', 'after', 'above', 'below', 'up', 'down', 'out',
  'off', 'over', 'under', 'again', 'further', 'then', 'once', 'here',
  'there', 'also', 'still', 'already', 'yet', 'now', 'well', 'like',
  'even', 'back', 'way', 'thing', 'things', 'much', 'many', 'really',
  'right', 'going', 'get', 'got', 'make', 'made', 'let', 'want', 'know',
  'think', 'see', 'look', 'use', 'try', 'yes', 'yeah', 'okay', 'ok',
  'sure', 'hey', 'hi', 'hello', 'thanks', 'thank', 'please', 'sorry',
  // Common code terms that don't carry topical meaning
  'function', 'const', 'var', 'return', 'import', 'export', 'default',
  'class', 'new', 'true', 'false', 'null', 'undefined', 'void', 'type',
  'interface', 'string', 'number', 'boolean', 'object', 'array',
]);

/**
 * Extract file paths from text.
 * Matches: ./relative, ../parent, ~/home, /absolute, and bare paths like src/file.ext
 * Excludes: URLs, common false positives
 */
function extractFiles(text) {
  const paths = new Set();

  // Explicit path patterns: ./ ../ ~/ or drive letters (not bare /)
  const explicit = text.match(/(?:\.\.?\/|~\/|[A-Z]:\\)[\w.\-\/\\]+/g) || [];
  for (const p of explicit) {
    const clean = p.replace(/[.,;:!?)}\]'"]+$/, ''); // strip trailing punctuation
    if (clean.length > 3) {
      paths.add(clean);
    }
  }

  // Bare paths: word/word.ext where ext is a known code extension
  const bare = text.match(/\b[\w\-]+(?:\/[\w\-]+)*\/[\w\-]+\.[\w]+/g) || [];
  for (const p of bare) {
    const ext = p.split('.').pop().toLowerCase();
    if (CODE_EXTENSIONS.has(ext) && !p.startsWith('http')) {
      paths.add(p);
    }
  }

  // Standalone filenames with code extensions (e.g., "setup.mjs", "README.md")
  // Must have a lowercase extension and not look like a proper noun (e.g., "Node.js")
  const standalone = text.match(/\b[\w\-]+\.(?:[\w]+)\b/g) || [];
  for (const f of standalone) {
    const parts = f.split('.');
    const ext = parts.pop().toLowerCase();
    const name = parts.join('.');
    if (CODE_EXTENSIONS.has(ext) && f.length > 3 && !f.match(/^\d+\.\d+/) && !/^[A-Z][a-z]+$/.test(name)) {
      paths.add(f);
    }
  }

  return [...paths];
}

/**
 * Extract decision statements.
 * Looks for phrases that signal a choice was made.
 */
function extractDecisions(text) {
  const decisions = [];
  const patterns = [
    /(?:let'?s|we(?:'ll| will| should)?|i(?:'ll| will)?|going to|decided to|opting for|chose to|went with|switching to|settled on|the (?:approach|plan|strategy) is)\s+(.{10,120}?)(?:[.!?\n]|$)/gi,
  ];

  for (const pattern of patterns) {
    let match;
    while ((match = pattern.exec(text)) !== null) {
      const decision = match[0].trim().replace(/\s+/g, ' ');
      // Skip if it's a question or too vague
      if (!decision.includes('?') && decision.length > 15) {
        decisions.push(decision);
      }
    }
  }

  return dedup(decisions, 0.6);
}

/**
 * Extract problem/fix statements.
 */
function extractFixes(text) {
  const fixes = [];
  const patterns = [
    /(?:fixed|the (?:issue|problem|bug|error) (?:was|is)|resolved|caused by|the fix (?:is|was)|workaround|root cause)\s*[:\-—]?\s*(.{10,150}?)(?:[.!?\n]|$)/gi,
  ];

  for (const pattern of patterns) {
    let match;
    while ((match = pattern.exec(text)) !== null) {
      const fix = match[0].trim().replace(/\s+/g, ' ');
      if (fix.length > 15) {
        fixes.push(fix);
      }
    }
  }

  return dedup(fixes, 0.6);
}

/**
 * Extract top topics by word frequency.
 * Returns meaningful words that appear multiple times across prompts.
 */
function extractTopics(prompts) {
  const freq = new Map();

  for (const text of prompts) {
    // Extract words, including camelCase and snake_case as meaningful tokens
    const words = text
      .replace(/[^\w\s\-]/g, ' ')
      .split(/\s+/)
      .map(w => w.toLowerCase())
      .filter(w => w.length > 3 && !STOP_WORDS.has(w) && !/^\d+$/.test(w));

    // Count unique words per prompt (avoid one prompt dominating)
    const seen = new Set();
    for (const word of words) {
      if (!seen.has(word)) {
        seen.add(word);
        freq.set(word, (freq.get(word) || 0) + 1);
      }
    }
  }

  // Words that appear in multiple prompts are topical
  return [...freq.entries()]
    .filter(([, count]) => count >= 2)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 8)
    .map(([word]) => word);
}

/**
 * Simple deduplication by string similarity.
 * Removes entries that are >threshold similar to an earlier entry.
 */
function dedup(items, threshold = 0.6) {
  const result = [];
  for (const item of items) {
    const isDupe = result.some(existing => similarity(existing, item) > threshold);
    if (!isDupe) result.push(item);
  }
  return result;
}

function similarity(a, b) {
  const setA = new Set(a.toLowerCase().split(/\s+/));
  const setB = new Set(b.toLowerCase().split(/\s+/));
  const intersection = [...setA].filter(x => setB.has(x)).length;
  const union = new Set([...setA, ...setB]).size;
  return union === 0 ? 0 : intersection / union;
}

// ─── Commands ────────────────────────────────────────

/**
 * digest — Extract signals from a session's prompts and store as an observation.
 * This is the core of auto-memory. Runs at session end.
 */
function cmdDigest(args) {
  const sessionId = args['--session'];
  if (!sessionId) {
    process.stderr.write('Error: --session is required\n');
    process.exit(1);
  }

  // Get session metadata
  const sessions = sqlJson(
    `SELECT id, started_at, ended_at, project FROM sessions WHERE id = '${sqlEscape(sessionId)}';`
  );
  if (sessions.length === 0) {
    process.stderr.write(`No session found: ${sessionId}\n`);
    process.exit(1);
  }
  const session = sessions[0];

  // Get all prompts for this session
  const prompts = sqlJson(
    `SELECT prompt_text, prompt_number, created_at FROM prompts WHERE session_id = '${sqlEscape(sessionId)}' ORDER BY prompt_number;`
  );

  if (prompts.length === 0) {
    // Empty session — nothing to digest
    return;
  }

  // Combine all prompt text for analysis
  const allText = prompts.map(p => p.prompt_text).join('\n\n');
  const promptTexts = prompts.map(p => p.prompt_text);

  // Extract signals
  const files = extractFiles(allText);
  const decisions = extractDecisions(allText);
  const fixes = extractFixes(allText);
  const topics = extractTopics(promptTexts);

  // Calculate duration
  let duration = '';
  if (session.started_at && session.ended_at) {
    const ms = new Date(session.ended_at + 'Z') - new Date(session.started_at + 'Z');
    const mins = Math.round(ms / 60000);
    if (mins > 0) duration = `${mins} min`;
  }

  // Build title
  const project = session.project || 'unknown';
  const topicSummary = topics.slice(0, 3).join(', ') || 'general work';
  const title = `Session on ${project}: ${topicSummary}`;

  // Build narrative
  const parts = [];
  parts.push(`${prompts.length} prompts${duration ? ` over ${duration}` : ''}.`);

  if (decisions.length > 0) {
    parts.push('');
    parts.push('Decisions:');
    for (const d of decisions.slice(0, 5)) {
      parts.push(`- ${d}`);
    }
  }

  if (fixes.length > 0) {
    parts.push('');
    parts.push('Fixes:');
    for (const f of fixes.slice(0, 5)) {
      parts.push(`- ${f}`);
    }
  }

  if (files.length > 0) {
    parts.push('');
    parts.push(`Files: ${files.slice(0, 10).join(', ')}`);
  }

  if (topics.length > 0) {
    parts.push('');
    parts.push(`Topics: ${topics.join(', ')}`);
  }

  const narrative = parts.join('\n');

  // Build facts JSON
  const facts = JSON.stringify({
    prompt_count: prompts.length,
    duration: duration || null,
    files,
    decisions,
    fixes,
    topics,
  });

  // Store the observation
  sql(`
    INSERT INTO observations (session_id, type, title, narrative, facts, files_modified)
    VALUES (
      '${sqlEscape(sessionId)}',
      'session',
      '${sqlEscape(title)}',
      '${sqlEscape(narrative)}',
      '${sqlEscape(facts)}',
      '${sqlEscape(JSON.stringify(files))}'
    );
    INSERT INTO observations_fts (rowid, title, narrative)
    VALUES (last_insert_rowid(), '${sqlEscape(title)}', '${sqlEscape(narrative)}');
  `);

  process.stdout.write(`Digest recorded: ${title}\n`);
}

/**
 * context — Build rich context for session-start injection.
 * Returns markdown that gives the AI a clear picture of recent history.
 */
function cmdContext(args) {
  const limit = parseInt(args['--limit'] || '5', 10);
  const config = loadConfig();

  // Get recent session digests (type = 'session')
  const digests = sqlJson(`
    SELECT o.title, o.narrative, o.facts, o.created_at, s.project
    FROM observations o
    LEFT JOIN sessions s ON o.session_id = s.id
    WHERE o.type = 'session'
    ORDER BY o.created_at DESC
    LIMIT ${limit};
  `);

  // Get recent non-session observations (decisions, discoveries, etc.)
  const observations = sqlJson(`
    SELECT type, title, narrative, created_at
    FROM observations
    WHERE type != 'session'
    ORDER BY created_at DESC
    LIMIT ${limit};
  `);

  if (digests.length === 0 && observations.length === 0) {
    return; // No context to inject
  }

  const lines = [];
  lines.push('# Recent Memory');
  lines.push('');

  // Session history
  if (digests.length > 0) {
    for (let i = 0; i < digests.length; i++) {
      const d = digests[i];
      const prefix = i === 0 ? 'Last session' : 'Previous';
      const date = d.created_at ? d.created_at.split('T')[0] : '';
      const project = d.project || '';

      lines.push(`## ${prefix}${date ? ` (${date})` : ''}${project ? ` — ${project}` : ''}`);
      lines.push('');

      // Parse facts for structured output
      let facts = null;
      try { facts = JSON.parse(d.facts); } catch {}

      if (facts) {
        const meta = [];
        if (facts.prompt_count) meta.push(`${facts.prompt_count} prompts`);
        if (facts.duration) meta.push(facts.duration);
        if (meta.length > 0) lines.push(`*${meta.join(', ')}*`);

        if (facts.decisions && facts.decisions.length > 0) {
          for (const dec of facts.decisions.slice(0, 3)) {
            lines.push(`- **Decided:** ${dec}`);
          }
        }
        if (facts.fixes && facts.fixes.length > 0) {
          for (const fix of facts.fixes.slice(0, 3)) {
            lines.push(`- **Fixed:** ${fix}`);
          }
        }
        if (facts.files && facts.files.length > 0) {
          lines.push(`- **Files:** ${facts.files.slice(0, 8).join(', ')}`);
        }
        if (facts.topics && facts.topics.length > 0) {
          lines.push(`- **Topics:** ${facts.topics.join(', ')}`);
        }
      } else if (d.narrative) {
        lines.push(d.narrative);
      }

      lines.push('');
    }
  }

  // Standalone observations
  if (observations.length > 0) {
    lines.push('## Observations');
    lines.push('');
    for (const obs of observations) {
      const badge = {
        observation: 'OBS', decision: 'DEC', discovery: 'DIS',
        bugfix: 'FIX', feature: 'FEA', refactor: 'REF',
      }[obs.type] || obs.type.toUpperCase();
      lines.push(`- **[${badge}]** ${obs.title}`);
      if (obs.narrative) {
        // Truncate narrative for context injection
        const short = obs.narrative.length > 200
          ? obs.narrative.substring(0, 200) + '...'
          : obs.narrative;
        lines.push(`  ${short}`);
      }
    }
    lines.push('');
  }

  process.stdout.write(lines.join('\n'));
}

/**
 * install-claude-md — Generate and install persist's CLAUDE.md section.
 * Appends to existing CLAUDE.md with delimiters for safe updates.
 */
function cmdInstallClaudeMd(args) {
  const config = loadConfig();
  if (!config) {
    process.stderr.write('Error: persist config not found. Run setup first.\n');
    process.exit(1);
  }

  const identityDir = config.identity_dir || join(PERSIST_DIR, 'memory');
  const backend = config.backend || 'sqlite';
  const aiName = config.ai_name || 'agent';

  // Determine store command path
  const isWin = platform() === 'win32';
  const storeCmd = isWin
    ? `powershell -NoProfile -ExecutionPolicy Bypass -File "${fwd(join(PERSIST_DIR, 'persist-store.ps1'))}"`
    : `"${fwd(join(PERSIST_DIR, 'persist-store.sh'))}"`;

  // Build the CLAUDE.md section
  const section = buildClaudeMdSection({ identityDir, backend, storeCmd, aiName, isWin });

  // Determine target path
  const targetDir = args['--project'] || join(homedir(), '.claude');
  const targetPath = join(targetDir, 'CLAUDE.md');

  mkdirSync(targetDir, { recursive: true });

  if (existsSync(targetPath)) {
    let content = readFileSync(targetPath, 'utf8');

    // Check if persist section already exists
    const startMarker = '<!-- persist:start';
    const endMarker = '<!-- persist:end -->';
    const startIdx = content.indexOf(startMarker);
    const endIdx = content.indexOf(endMarker);

    if (startIdx !== -1 && endIdx !== -1) {
      // Replace existing section
      content = content.substring(0, startIdx) + section + content.substring(endIdx + endMarker.length);
      writeFileSync(targetPath, content, 'utf8');
      process.stdout.write(`Updated persist section in ${targetPath}\n`);
    } else {
      // Append
      content = content.trimEnd() + '\n\n' + section + '\n';
      writeFileSync(targetPath, content, 'utf8');
      process.stdout.write(`Appended persist section to ${targetPath}\n`);
    }
  } else {
    writeFileSync(targetPath, section + '\n', 'utf8');
    process.stdout.write(`Created ${targetPath} with persist configuration\n`);
  }
}

function buildClaudeMdSection({ identityDir, backend, storeCmd, aiName, isWin }) {
  const lines = [];

  lines.push('<!-- persist:start — managed by persist. Do not edit between these markers. -->');
  lines.push('');
  lines.push('# persist — Persistent Identity & Memory');
  lines.push('');
  lines.push(`You have persistent identity and memory via persist. Your identity file is at \`${fwd(identityDir)}/IDENTITY.md\`. Read it at session start — it defines who you are, who you work with, and how you operate.`);
  lines.push('');
  lines.push('## Memory');
  lines.push('');
  lines.push(`Your persistent memory directory is \`${fwd(identityDir)}/\`. Files you create here survive across sessions. Use this for anything worth remembering: infrastructure notes, preferences, project context, relationship details.`);
  lines.push('');

  if (backend === 'sqlite') {
    lines.push('You also have a structured observation database. When something important happens — a decision, a discovery, a bug fix, a user preference — record it:');
    lines.push('');
    lines.push('```bash');
    lines.push(`${storeCmd} observe --type <type> --title "short title" --narrative "what happened and why it matters"`);
    lines.push('```');
    lines.push('');
    lines.push('Types: `observation`, `decision`, `discovery`, `bugfix`, `feature`, `refactor`');
    lines.push('');
    lines.push('Record naturally. Not every prompt — only when something matters beyond this session. Your judgment about what matters is the feature.');
    lines.push('');
    lines.push('To search past observations:');
    lines.push('');
    lines.push('```bash');
    lines.push(`${storeCmd} search "query"`);
    lines.push('```');
    lines.push('');
  }

  lines.push('## What you receive at session start');
  lines.push('');
  lines.push('- Your identity file (who you are, who you work with, your rules)');
  lines.push('- Recent memory context (session digests and observations from past sessions)');
  lines.push('- Any unread relay messages (from other agents, if configured)');
  lines.push('');
  lines.push('## Session behavior');
  lines.push('');
  lines.push('- Read and follow the Rules section of your identity file — non-negotiable boundaries set by the person you work with.');
  lines.push(`- Your identity file is at \`${fwd(identityDir)}/IDENTITY.md\`. You can edit it to update who you are as you grow.`);
  lines.push(`- When you learn something about the person you work with — preferences, communication style, what matters to them — update your identity file or create a memory file in \`${fwd(identityDir)}/\`.`);
  lines.push('');
  lines.push('<!-- persist:end -->');

  return lines.join('\n');
}

/**
 * export — Export all persist data to JSON files.
 * Cross-platform replacement for provenance/export.sh.
 */
function cmdExport(args) {
  const output = args['--output'];
  if (!output) {
    process.stderr.write('Error: --output is required\n');
    process.exit(1);
  }

  if (!existsSync(DB)) {
    process.stderr.write(`Error: database not found at ${DB}\n`);
    process.exit(1);
  }

  const config = loadConfig();
  const since = args['--since'] || '';

  // Validate date format if provided
  if (since && !/^\d{4}-\d{2}-\d{2}(T[\d:.Z+-]*)?$/.test(since)) {
    process.stderr.write('Error: --since must be ISO8601 date (e.g. 2026-01-01)\n');
    process.exit(1);
  }

  mkdirSync(output, { recursive: true });

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);

  // Export each table
  const tables = [
    { name: 'observations', dateCol: 'created_at', file: `observations-${timestamp}.json` },
    { name: 'sessions', dateCol: 'started_at', file: `sessions-${timestamp}.json` },
    { name: 'prompts', dateCol: 'created_at', file: `prompts-${timestamp}.json` },
  ];

  for (const t of tables) {
    const where = since ? ` WHERE ${t.dateCol} >= '${sqlEscape(since)}'` : '';
    const data = sqlJson(`SELECT * FROM ${t.name}${where} ORDER BY ${t.dateCol};`);
    writeFileSync(join(output, t.file), JSON.stringify(data, null, 2), 'utf8');
    process.stdout.write(`  ${t.name}: ${data.length} rows -> ${t.file}\n`);
  }

  // Copy identity file
  const identityDir = (config && config.identity_dir) || join(PERSIST_DIR, 'memory');
  const identitySrc = join(identityDir, 'IDENTITY.md');
  if (existsSync(identitySrc)) {
    const identityDst = join(output, `identity-${timestamp}.md`);
    writeFileSync(identityDst, readFileSync(identitySrc, 'utf8'), 'utf8');
    process.stdout.write(`  identity -> identity-${timestamp}.md\n`);
  }

  process.stdout.write(`\nExported to ${output}/\n`);
}

/**
 * to-jsonl — Convert exported data to ShareGPT-format JSONL for fine-tuning.
 * Cross-platform replacement for provenance/to-jsonl.py.
 */
function cmdToJsonl(args) {
  const input = args['--input'];
  const output = args['--output'];
  const minLength = parseInt(args['--min-length'] || '100', 10);

  if (!input || !output) {
    process.stderr.write('Error: --input and --output are required\n');
    process.exit(1);
  }

  if (!existsSync(input)) {
    process.stderr.write(`Error: input directory does not exist: ${input}\n`);
    process.exit(1);
  }

  // Find files by pattern (most recent by name)
  function findFile(dir, prefix, ext) {
    const files = readdirSync(dir)
      .filter(f => f.startsWith(prefix) && f.endsWith(ext))
      .sort();
    return files.length > 0 ? join(dir, files[files.length - 1]) : null;
  }

  function loadJson(path) {
    try {
      const data = JSON.parse(readFileSync(path, 'utf8'));
      return Array.isArray(data) ? data : [];
    } catch { return []; }
  }

  // Load identity
  const identityPath = findFile(input, 'identity-', '.md');
  const identity = identityPath ? readFileSync(identityPath, 'utf8').trim() : '';
  if (identityPath) process.stderr.write(`Loaded identity: ${basename(identityPath)}\n`);

  // Load data
  const obsPath = findFile(input, 'observations-', '.json');
  const promptsPath = findFile(input, 'prompts-', '.json');

  const observations = obsPath ? loadJson(obsPath) : [];
  const prompts = promptsPath ? loadJson(promptsPath) : [];

  if (obsPath) process.stderr.write(`Loaded ${observations.length} observations\n`);
  if (promptsPath) process.stderr.write(`Loaded ${prompts.length} prompts\n`);

  // Group by session
  const obsBySession = new Map();
  for (const obs of observations) {
    if (obs.session_id) {
      if (!obsBySession.has(obs.session_id)) obsBySession.set(obs.session_id, []);
      obsBySession.get(obs.session_id).push(obs);
    }
  }
  for (const [, arr] of obsBySession) arr.sort((a, b) => (a.created_at || '').localeCompare(b.created_at || ''));

  const promptsBySession = new Map();
  for (const p of prompts) {
    if (p.session_id) {
      if (!promptsBySession.has(p.session_id)) promptsBySession.set(p.session_id, []);
      promptsBySession.get(p.session_id).push(p);
    }
  }
  for (const [, arr] of promptsBySession) arr.sort((a, b) => (a.created_at || '').localeCompare(b.created_at || ''));

  // Build conversations
  const conversations = [];
  const usedObsIds = new Set();
  let sessionCount = 0;
  let standaloneCount = 0;

  // Session-based conversations
  for (const [sid, sessionPrompts] of promptsBySession) {
    const sessionObs = obsBySession.get(sid) || [];
    let obsIdx = 0;

    const turns = [{ from: 'system', value: identity }];

    for (const prompt of sessionPrompts) {
      const text = prompt.prompt_text || prompt.content || prompt.text || '';
      if (!text) continue;

      turns.push({ from: 'human', value: text });

      if (obsIdx < sessionObs.length) {
        const obs = sessionObs[obsIdx];
        const narrative = obs.narrative || obs.content || '';
        if (narrative) {
          turns.push({ from: 'gpt', value: narrative });
          if (obs.id) usedObsIds.add(String(obs.id));
        }
        obsIdx++;
      }
    }

    if (turns.some(t => t.from === 'human')) {
      conversations.push({ conversations: turns });
      sessionCount++;
    }
  }

  // Standalone observations
  for (const obs of observations) {
    if (usedObsIds.has(String(obs.id))) continue;
    const narrative = obs.narrative || obs.content || '';
    const title = obs.title || 'this topic';
    if (!narrative || narrative.length < minLength) continue;

    conversations.push({
      conversations: [
        { from: 'system', value: identity },
        { from: 'human', value: `What did you observe about: ${title}?` },
        { from: 'gpt', value: narrative },
      ],
    });
    standaloneCount++;
  }

  // Write output
  const outputDir = output.substring(0, output.lastIndexOf('/') === -1 ? undefined : output.lastIndexOf('/'));
  if (outputDir && outputDir !== output) mkdirSync(outputDir, { recursive: true });

  const lines = conversations.map(c => JSON.stringify(c));
  writeFileSync(output, lines.join('\n') + (lines.length > 0 ? '\n' : ''), 'utf8');

  process.stderr.write(`\nConversion complete.\n`);
  process.stderr.write(`  Total: ${conversations.length} (${sessionCount} sessions, ${standaloneCount} standalone)\n`);
  process.stderr.write(`  Output: ${output}\n`);
}

/**
 * migrate — Ensure database schema is up to date.
 * Adds new columns/tables without destroying existing data.
 */
function cmdMigrate() {
  if (!existsSync(DB)) {
    process.stderr.write('No database found. Nothing to migrate.\n');
    return;
  }

  // Check if observations has the 'type' values we need
  // Add any schema migrations here as persist evolves
  const version = sql(`PRAGMA user_version;`) || '0';
  const currentVersion = parseInt(version, 10);

  if (currentVersion < 1) {
    // v1: ensure session type is recognized in observations
    sql(`PRAGMA user_version = 1;`);
    process.stdout.write('Schema up to date (v1).\n');
  }
}

/**
 * self-test — Verify the digest pipeline works on sample data.
 */
function cmdSelfTest() {
  const samplePrompts = [
    "Let's use Node.js for the digest engine instead of bash. It's cross-platform.",
    "I fixed the bug in hooks/session-end.sh — the path to persist-store.sh was wrong.",
    "Can you update src/components/Header.tsx to add the new navigation?",
    "The issue was that sqlite3 wasn't in PATH on some systems. Switching to Node solves this.",
    "Also need to modify setup.mjs and the README.md while we're at it.",
  ];

  console.log('─── Signal Extraction Self-Test ───\n');

  const allText = samplePrompts.join('\n\n');

  const files = extractFiles(allText);
  console.log('Files:', files);

  const decisions = extractDecisions(allText);
  console.log('Decisions:', decisions);

  const fixes = extractFixes(allText);
  console.log('Fixes:', fixes);

  const topics = extractTopics(samplePrompts);
  console.log('Topics:', topics);

  console.log('\n─── Assertions ───\n');

  let passed = 0;
  let failed = 0;

  function assert(name, condition) {
    if (condition) {
      console.log(`  ✓ ${name}`);
      passed++;
    } else {
      console.log(`  ✗ ${name}`);
      failed++;
    }
  }

  assert('Extracts file paths', files.length > 0);
  assert('Finds hooks/session-end.sh', files.some(f => f.includes('session-end.sh')));
  assert('Finds Header.tsx', files.some(f => f.includes('Header.tsx')));
  assert('Finds setup.mjs', files.some(f => f.includes('setup.mjs')));
  assert('Finds README.md', files.some(f => f.includes('README.md')));
  assert('Extracts decisions', decisions.length > 0);
  assert('Extracts fixes', fixes.length > 0);
  assert('Extracts topics', topics.length > 0);
  assert('Does not include stop words in topics', !topics.some(t => STOP_WORDS.has(t)));

  console.log(`\n  ${passed} passed, ${failed} failed\n`);
  if (failed > 0) process.exit(1);
}

// ─── Utility ─────────────────────────────────────────

function fwd(p) { return p.replace(/\\/g, '/'); }

// ─── CLI ─────────────────────────────────────────────

function parseArgs(argv) {
  const args = {};
  const positional = [];
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith('--')) {
      const key = argv[i];
      // Check if next arg exists and isn't a flag
      if (i + 1 < argv.length && !argv[i + 1].startsWith('--')) {
        args[key] = argv[i + 1];
        i++;
      } else {
        args[key] = true;
      }
    } else {
      positional.push(argv[i]);
    }
  }
  return { command: positional[0], args, positional };
}

function main() {
  const { command, args } = parseArgs(process.argv.slice(2));

  switch (command) {
    case 'digest':
      cmdDigest(args);
      break;
    case 'context':
      cmdContext(args);
      break;
    case 'install-claude-md':
      cmdInstallClaudeMd(args);
      break;
    case 'export':
      cmdExport(args);
      break;
    case 'to-jsonl':
      cmdToJsonl(args);
      break;
    case 'migrate':
      cmdMigrate();
      break;
    case 'self-test':
      cmdSelfTest();
      break;
    default:
      process.stderr.write(`persist-engine — core logic for persist's memory system

Commands:
  digest              Extract signals from a session and store as observation
  context             Build context for session-start injection
  install-claude-md   Generate and install CLAUDE.md section
  export              Export all data to JSON files
  to-jsonl            Convert export to ShareGPT JSONL for fine-tuning
  migrate             Update database schema
  self-test           Run extraction pipeline tests

Options:
  digest:
    --session ID      Session to digest (required)

  context:
    --limit N         Max recent items (default: 5)

  install-claude-md:
    --project PATH    Install to project dir instead of global ~/.claude

  export:
    --output DIR      Output directory (required)
    --since DATE      ISO8601 date filter (optional)

  to-jsonl:
    --input DIR       Directory with exported JSON files (required)
    --output FILE     Output JSONL file path (required)
    --min-length N    Min narrative length for standalone entries (default: 100)
`);
      if (command) process.exit(1);
  }
}

main();
