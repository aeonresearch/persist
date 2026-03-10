# SQLite Adapter (Built-in)

Zero-dependency persistence for users who don't want to install claude-mem or any other memory system. A single SQLite file stores everything persist needs.

## What it provides

- Observation storage (what the AI noticed, decided, discovered)
- Session tracking (when sessions start/end, what happened)
- Context injection (recent observations surfaced at session start)
- Full-text search (SQLite FTS5)
- Export to provenance JSON format

## What it doesn't provide

- Vector/semantic search (use claude-mem adapter for this)
- AI-powered observation tagging (observations stored as-is)
- Chroma integration

## Database

**Location:** `~/.persist/persist.db`

**Schema:**

```sql
CREATE TABLE observations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT,
  type TEXT DEFAULT 'observation',  -- observation, decision, discovery
  title TEXT,
  narrative TEXT,
  facts TEXT,           -- JSON array
  files_read TEXT,      -- JSON array
  files_modified TEXT,  -- JSON array
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE sessions (
  id TEXT PRIMARY KEY,
  started_at TEXT DEFAULT (datetime('now')),
  ended_at TEXT,
  project TEXT,
  summary TEXT
);

CREATE TABLE prompts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT,
  prompt_text TEXT,
  prompt_number INTEGER,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE VIRTUAL TABLE observations_fts USING fts5(
  title, narrative, content=observations, content_rowid=id
);
```

## Usage

The adapter ships as a single script (`persist-store.sh`) that handles:

```bash
# Store an observation
persist-store.sh observe --type decision --title "Chose X over Y" --narrative "..."

# Search observations
persist-store.sh search "query text"

# Get recent context (for session start hook)
persist-store.sh context --limit 20

# Export for provenance
persist-store.sh export --output ~/persist-export/
```

## Hook Integration

At session start, the hook calls `persist-store.sh context` and injects the output as a system reminder. This gives the AI awareness of recent observations without needing a full memory service running.

## For Windows Users

The SQLite adapter includes a PowerShell equivalent (`persist-store.ps1`) for Windows environments where bash is not available. The database format is identical — cross-platform by design.
