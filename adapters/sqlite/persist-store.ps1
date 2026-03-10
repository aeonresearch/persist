#Requires -Version 5.1
# persist-store.ps1 — SQLite adapter CLI for persist (Windows)
# Requires sqlite3.exe in PATH (install via: winget install SQLite.SQLite or scoop install sqlite)

$ErrorActionPreference = 'Stop'

$PersistDir = if ($env:PERSIST_DIR) { $env:PERSIST_DIR } else { Join-Path $env:USERPROFILE '.persist' }
$DB = Join-Path $PersistDir 'persist.db'

function Show-Usage {
    @"
persist-store.ps1 — SQLite adapter CLI for persist

Usage:
  persist-store.ps1 <command> [options]

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
  -type TYPE                    observation|decision|discovery|bugfix|feature|refactor
  -title TITLE                  Observation title
  -narrative TEXT               Narrative text
  -session SESSION              Session ID (auto-generated if omitted)
  -facts JSON                   JSON array of facts
  -filesRead JSON               JSON array of files read
  -filesModified JSON           JSON array of files modified

Options for 'search':
  -limit N                      Max results (default: 10)

Options for 'context':
  -limit N                      Max results (default: 20)

Options for 'session-start':
  -project NAME                 Project name

Options for 'session-end':
  -session ID                   Session ID (required)
  -summary TEXT                 Session summary

Options for 'prompt':
  -session ID                   Session ID (required)
  -text TEXT                    Prompt text (required)
  -number N                    Prompt number (required)

Options for 'export':
  -output DIR                   Output directory (required)
"@
    exit 0
}

function Test-Sqlite {
    try {
        $null = & sqlite3 --version 2>&1
        return $true
    } catch {
        return $false
    }
}

function Invoke-Sql {
    param([string]$Query)
    if (-not (Test-Path $DB)) {
        Write-Error "Database not found at $DB. Run 'persist-store.ps1 init' first."
        exit 1
    }
    $Query | & sqlite3 $DB
}

function ConvertTo-SqlSafe {
    param([string]$Value)
    $Value -replace "'", "''"
}

function Invoke-Init {
    if (-not (Test-Sqlite)) {
        Write-Error "sqlite3 not found in PATH. Install via: winget install SQLite.SQLite"
        exit 1
    }
    New-Item -ItemType Directory -Path $PersistDir -Force | Out-Null
    $sql = @"
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
"@
    $sql | & sqlite3 $DB
    Write-Output "Database initialized at $DB"
}

function Invoke-Observe {
    param([string[]]$Arguments)
    $type = 'observation'; $title = ''; $narrative = ''; $session = ''
    $facts = '[]'; $filesRead = '[]'; $filesModified = '[]'

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        switch ($Arguments[$i]) {
            '-type'          { $type = $Arguments[++$i] }
            '-title'         { $title = $Arguments[++$i] }
            '-narrative'     { $narrative = $Arguments[++$i] }
            '-session'       { $session = $Arguments[++$i] }
            '-facts'         { $facts = $Arguments[++$i] }
            '-filesRead'     { $filesRead = $Arguments[++$i] }
            '-filesModified' { $filesModified = $Arguments[++$i] }
            default          { Write-Error "Unknown option: $($Arguments[$i])"; exit 1 }
        }
    }

    if (-not $title) { Write-Error "-title is required"; exit 1 }
    if (-not $session) { $session = "S$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())" }

    $sql = @"
INSERT INTO observations (session_id, type, title, narrative, facts, files_read, files_modified)
VALUES ('$(ConvertTo-SqlSafe $session)', '$(ConvertTo-SqlSafe $type)', '$(ConvertTo-SqlSafe $title)', '$(ConvertTo-SqlSafe $narrative)', '$(ConvertTo-SqlSafe $facts)', '$(ConvertTo-SqlSafe $filesRead)', '$(ConvertTo-SqlSafe $filesModified)');
INSERT INTO observations_fts (rowid, title, narrative)
VALUES (last_insert_rowid(), '$(ConvertTo-SqlSafe $title)', '$(ConvertTo-SqlSafe $narrative)');
"@
    Invoke-Sql $sql
    Write-Output "Observation recorded."
}

function Invoke-Search {
    param([string[]]$Arguments)
    $query = ''; $limit = 10

    if ($Arguments.Count -gt 0 -and $Arguments[0] -notlike '-*') {
        $query = $Arguments[0]
        if ($Arguments.Count -gt 1) {
            $Arguments = $Arguments[1..($Arguments.Count - 1)]
        } else {
            $Arguments = @()
        }
    }

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        switch ($Arguments[$i]) {
            '-limit' { $limit = [int]$Arguments[++$i] }
            default  { Write-Error "Unknown option: $($Arguments[$i])"; exit 1 }
        }
    }

    if (-not $query) { Write-Error "search query required"; exit 1 }

    $sql = @"
.separator |
SELECT o.title, o.type, o.created_at, substr(o.narrative, 1, 200)
FROM observations_fts f
JOIN observations o ON o.id = f.rowid
WHERE observations_fts MATCH '$(ConvertTo-SqlSafe $query)'
ORDER BY rank
LIMIT $limit;
"@
    $results = $sql | & sqlite3 $DB
    foreach ($line in $results) {
        if (-not $line) { continue }
        $parts = $line -split '\|', 4
        Write-Output "### $($parts[0])"
        Write-Output "[$($parts[1])] $($parts[2])"
        Write-Output ""
        Write-Output $parts[3]
        Write-Output ""
        Write-Output "---"
        Write-Output ""
    }
}

function Invoke-Context {
    param([string[]]$Arguments)
    $limit = 20

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        switch ($Arguments[$i]) {
            '-limit' { $limit = [int]$Arguments[++$i] }
            default  { Write-Error "Unknown option: $($Arguments[$i])"; exit 1 }
        }
    }

    $sql = @"
.separator |
SELECT id, type, title, created_at, substr(narrative, 1, 300), facts, files_modified
FROM observations
ORDER BY created_at DESC
LIMIT $limit;
"@
    $results = $sql | & sqlite3 $DB
    foreach ($line in $results) {
        if (-not $line) { continue }
        $parts = $line -split '\|', 7
        $badge = switch ($parts[1]) {
            'observation' { 'OBS' }
            'decision'    { 'DEC' }
            'discovery'   { 'DIS' }
            'bugfix'      { 'FIX' }
            'feature'     { 'FEA' }
            'refactor'    { 'REF' }
            default       { $parts[1] }
        }
        Write-Output "- **[$badge]** $($parts[2]) ($($parts[3]))"
        if ($parts[4]) { Write-Output "  $($parts[4])" }
        if ($parts[6] -and $parts[6] -ne '[]') { Write-Output "  files: $($parts[6])" }
    }
}

function Invoke-SessionStart {
    param([string[]]$Arguments)
    $project = ''

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        switch ($Arguments[$i]) {
            '-project' { $project = $Arguments[++$i] }
            default    { Write-Error "Unknown option: $($Arguments[$i])"; exit 1 }
        }
    }

    $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $rand = -join ((1..8) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
    $sessionId = "S$ts-$PID-$rand"

    $sql = "INSERT INTO sessions (id, project) VALUES ('$sessionId', '$(ConvertTo-SqlSafe $project)');"
    Invoke-Sql $sql
    Write-Output $sessionId
}

function Invoke-SessionEnd {
    param([string[]]$Arguments)
    $session = ''; $summary = ''

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        switch ($Arguments[$i]) {
            '-session' { $session = $Arguments[++$i] }
            '-summary' { $summary = $Arguments[++$i] }
            default    { Write-Error "Unknown option: $($Arguments[$i])"; exit 1 }
        }
    }

    if (-not $session) { Write-Error "-session is required"; exit 1 }

    $sql = "UPDATE sessions SET ended_at = datetime('now'), summary = '$(ConvertTo-SqlSafe $summary)' WHERE id = '$(ConvertTo-SqlSafe $session)';"
    Invoke-Sql $sql
    Write-Output "Session $session ended."
}

function Invoke-Prompt {
    param([string[]]$Arguments)
    $session = ''; $text = ''; $number = ''

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        switch ($Arguments[$i]) {
            '-session' { $session = $Arguments[++$i] }
            '-text'    { $text = $Arguments[++$i] }
            '-number'  { $number = $Arguments[++$i] }
            default    { Write-Error "Unknown option: $($Arguments[$i])"; exit 1 }
        }
    }

    if (-not $session -or -not $text -or -not $number) {
        Write-Error "-session, -text, and -number are all required"
        exit 1
    }

    $sql = "INSERT INTO prompts (session_id, prompt_text, prompt_number) VALUES ('$(ConvertTo-SqlSafe $session)', '$(ConvertTo-SqlSafe $text)', $number);"
    Invoke-Sql $sql
    Write-Output "Prompt recorded."
}

function Invoke-Export {
    param([string[]]$Arguments)
    $output = ''

    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        switch ($Arguments[$i]) {
            '-output' { $output = $Arguments[++$i] }
            default   { Write-Error "Unknown option: $($Arguments[$i])"; exit 1 }
        }
    }

    if (-not $output) { Write-Error "-output is required"; exit 1 }

    New-Item -ItemType Directory -Path $output -Force | Out-Null

    foreach ($table in @('observations', 'sessions', 'prompts')) {
        $result = ".mode json`nSELECT * FROM $table;" | & sqlite3 $DB
        $outFile = Join-Path $output "$table.json"
        if ($result) {
            # Use WriteAllText to avoid UTF-8 BOM (PS 5.1 Set-Content -Encoding UTF8 adds BOM)
            [System.IO.File]::WriteAllText($outFile, ($result -join "`n"), [System.Text.UTF8Encoding]::new($false))
        } else {
            [System.IO.File]::WriteAllText($outFile, '[]', [System.Text.UTF8Encoding]::new($false))
        }
    }
    Write-Output "Exported to $output/"
}

# --- Main dispatch ---
if ($args.Count -eq 0 -or $args[0] -eq '--help' -or $args[0] -eq '-h') {
    Show-Usage
}

$command = $args[0]
$remaining = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }

switch ($command) {
    'init'          { Invoke-Init }
    'observe'       { Invoke-Observe $remaining }
    'search'        { Invoke-Search $remaining }
    'context'       { Invoke-Context $remaining }
    'session-start' { Invoke-SessionStart $remaining }
    'session-end'   { Invoke-SessionEnd $remaining }
    'prompt'        { Invoke-Prompt $remaining }
    'export'        { Invoke-Export $remaining }
    default {
        Write-Error "Unknown command: $command"
        Write-Error "Run 'persist-store.ps1 --help' for usage."
        exit 1
    }
}
