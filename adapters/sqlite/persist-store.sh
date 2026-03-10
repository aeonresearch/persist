#!/bin/bash
set -e

PERSIST_DIR="${PERSIST_DIR:-$HOME/.persist}"
DB="${PERSIST_DIR}/persist.db"

usage() {
  cat <<'EOF'
persist-store.sh — SQLite adapter CLI for persist

Usage:
  persist-store.sh <command> [options]

Commands:
  init                          Create database and tables (idempotent)
  observe                       Insert an observation
  search <query>                Full-text search observations
  context                       Recent observations as markdown
  session-start                 Start a new session
  session-end                   End a session
  prompt                        Record a user prompt
  export                        Export all data as JSON

Options for 'observe':
  --type TYPE                   observation|decision|discovery|bugfix|feature|refactor
  --title TITLE                 Observation title
  --narrative TEXT              Narrative text
  --session SESSION             Session ID (auto-generated if omitted)
  --facts JSON                  JSON array of facts
  --files-read JSON             JSON array of files read
  --files-modified JSON         JSON array of files modified

Options for 'search':
  --limit N                     Max results (default: 10)

Options for 'context':
  --limit N                     Max results (default: 20)

Options for 'session-start':
  --project NAME                Project name

Options for 'session-end':
  --session ID                  Session ID (required)
  --summary TEXT                Session summary

Options for 'prompt':
  --session ID                  Session ID (required)
  --text TEXT                   Prompt text (required)
  --number N                    Prompt number (required)

Options for 'export':
  --output DIR                  Output directory (required)
EOF
  exit 0
}

sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

ensure_db() {
  if [ ! -f "$DB" ]; then
    echo "Database not found at $DB. Run 'persist-store.sh init' first." >&2
    exit 1
  fi
}

cmd_init() {
  mkdir -p "$PERSIST_DIR"
  sqlite3 "$DB" <<'SQL'
CREATE TABLE IF NOT EXISTS observations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT,
  type TEXT DEFAULT 'observation',
  title TEXT,
  narrative TEXT,
  facts TEXT,
  files_read TEXT,
  files_modified TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  started_at TEXT DEFAULT (datetime('now')),
  ended_at TEXT,
  project TEXT,
  summary TEXT
);

CREATE TABLE IF NOT EXISTS prompts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT,
  prompt_text TEXT,
  prompt_number INTEGER,
  created_at TEXT DEFAULT (datetime('now'))
);

CREATE VIRTUAL TABLE IF NOT EXISTS observations_fts USING fts5(
  title, narrative, content=observations, content_rowid=id
);
SQL
  echo "Database initialized at $DB"
}

cmd_observe() {
  ensure_db
  local type="observation" title="" narrative="" session="" facts="[]" files_read="[]" files_modified="[]"

  while [ $# -gt 0 ]; do
    case "$1" in
      --type) type="$2"; shift 2 ;;
      --title) title="$2"; shift 2 ;;
      --narrative) narrative="$2"; shift 2 ;;
      --session) session="$2"; shift 2 ;;
      --facts) facts="$2"; shift 2 ;;
      --files-read) files_read="$2"; shift 2 ;;
      --files-modified) files_modified="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [ -z "$title" ]; then
    echo "Error: --title is required" >&2
    exit 1
  fi

  if [ -z "$session" ]; then
    session="S$(date +%s)"
  fi

  local e_session e_type e_title e_narrative e_facts e_files_read e_files_modified
  e_session="$(sql_escape "$session")"
  e_type="$(sql_escape "$type")"
  e_title="$(sql_escape "$title")"
  e_narrative="$(sql_escape "$narrative")"
  e_facts="$(sql_escape "$facts")"
  e_files_read="$(sql_escape "$files_read")"
  e_files_modified="$(sql_escape "$files_modified")"

  sqlite3 "$DB" <<SQL
INSERT INTO observations (session_id, type, title, narrative, facts, files_read, files_modified)
VALUES ('${e_session}', '${e_type}', '${e_title}', '${e_narrative}', '${e_facts}', '${e_files_read}', '${e_files_modified}');

INSERT INTO observations_fts (rowid, title, narrative)
VALUES (last_insert_rowid(), '${e_title}', '${e_narrative}');
SQL
  echo "Observation recorded."
}

cmd_search() {
  ensure_db
  local query="" limit=10

  if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
    query="$1"
    shift
  fi

  while [ $# -gt 0 ]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [ -z "$query" ]; then
    echo "Error: search query required" >&2
    exit 1
  fi

  local e_query
  e_query="$(sql_escape "$query")"

  sqlite3 -separator '|' "$DB" <<SQL | while IFS='|' read -r title type created_at narrative; do
SELECT o.title, o.type, o.created_at, substr(o.narrative, 1, 200)
FROM observations_fts f
JOIN observations o ON o.id = f.rowid
WHERE observations_fts MATCH '${e_query}'
ORDER BY rank
LIMIT ${limit};
SQL
    echo "### ${title}"
    echo "[${type}] ${created_at}"
    echo ""
    echo "${narrative}"
    echo ""
    echo "---"
    echo ""
  done
}

cmd_context() {
  ensure_db
  local limit=20

  while [ $# -gt 0 ]; do
    case "$1" in
      --limit) limit="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  sqlite3 -separator '|' "$DB" <<SQL | while IFS='|' read -r id type title created_at narrative facts files_modified; do
SELECT id, type, title, created_at, substr(narrative, 1, 300), facts, files_modified
FROM observations
ORDER BY created_at DESC
LIMIT ${limit};
SQL
    local badge
    case "$type" in
      observation) badge="OBS" ;;
      decision)    badge="DEC" ;;
      discovery)   badge="DIS" ;;
      bugfix)      badge="FIX" ;;
      feature)     badge="FEA" ;;
      refactor)    badge="REF" ;;
      *)           badge="$type" ;;
    esac
    echo "- **[${badge}]** ${title} (${created_at})"
    if [ -n "$narrative" ]; then
      echo "  ${narrative}"
    fi
    if [ "$files_modified" != "[]" ] && [ -n "$files_modified" ]; then
      echo "  files: ${files_modified}"
    fi
  done
}

cmd_session_start() {
  ensure_db
  local project=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --project) project="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  local session_id="S$(date +%s)-$$-$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' ')"
  local e_project
  e_project="$(sql_escape "$project")"

  sqlite3 "$DB" <<SQL
INSERT INTO sessions (id, project) VALUES ('${session_id}', '${e_project}');
SQL
  echo "$session_id"
}

cmd_session_end() {
  ensure_db
  local session="" summary=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --session) session="$2"; shift 2 ;;
      --summary) summary="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [ -z "$session" ]; then
    echo "Error: --session is required" >&2
    exit 1
  fi

  local e_session e_summary
  e_session="$(sql_escape "$session")"
  e_summary="$(sql_escape "$summary")"

  sqlite3 "$DB" <<SQL
UPDATE sessions SET ended_at = datetime('now'), summary = '${e_summary}' WHERE id = '${e_session}';
SQL
  echo "Session ${session} ended."
}

cmd_prompt() {
  ensure_db
  local session="" text="" number=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --session) session="$2"; shift 2 ;;
      --text) text="$2"; shift 2 ;;
      --number) number="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [ -z "$session" ] || [ -z "$text" ] || [ -z "$number" ]; then
    echo "Error: --session, --text, and --number are all required" >&2
    exit 1
  fi

  local e_session e_text
  e_session="$(sql_escape "$session")"
  e_text="$(sql_escape "$text")"

  sqlite3 "$DB" <<SQL
INSERT INTO prompts (session_id, prompt_text, prompt_number) VALUES ('${e_session}', '${e_text}', ${number});
SQL
  echo "Prompt recorded."
}

cmd_export() {
  ensure_db
  local output=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --output) output="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [ -z "$output" ]; then
    echo "Error: --output is required" >&2
    exit 1
  fi

  mkdir -p "$output"

  sqlite3 "$DB" <<'SQL' > "${output}/observations.json"
.mode json
SELECT * FROM observations;
SQL

  sqlite3 "$DB" <<'SQL' > "${output}/sessions.json"
.mode json
SELECT * FROM sessions;
SQL

  sqlite3 "$DB" <<'SQL' > "${output}/prompts.json"
.mode json
SELECT * FROM prompts;
SQL

  # Ensure empty tables produce valid JSON arrays
  for f in "${output}/observations.json" "${output}/sessions.json" "${output}/prompts.json"; do
    if [ ! -s "$f" ]; then
      echo '[]' > "$f"
    fi
  done

  echo "Exported to ${output}/"
}

# Main dispatch
if [ $# -eq 0 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  usage
fi

command="$1"
shift

case "$command" in
  init)          cmd_init "$@" ;;
  observe)       cmd_observe "$@" ;;
  search)        cmd_search "$@" ;;
  context)       cmd_context "$@" ;;
  session-start) cmd_session_start "$@" ;;
  session-end)   cmd_session_end "$@" ;;
  prompt)        cmd_prompt "$@" ;;
  export)        cmd_export "$@" ;;
  *)
    echo "Unknown command: $command" >&2
    echo "Run 'persist-store.sh --help' for usage." >&2
    exit 1
    ;;
esac
