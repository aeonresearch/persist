#Requires -Version 5.1

$PersistDir = if ($env:PERSIST_DIR) { $env:PERSIST_DIR } else { Join-Path $env:USERPROFILE '.persist' }
$Config = Join-Path $PersistDir 'config.json'
$Engine = Join-Path $PersistDir 'persist-engine.mjs'
$StorePath = Join-Path $PersistDir 'persist-store.ps1'

if (-not (Test-Path $Config)) { exit 0 }

$cfg = Get-Content $Config -Raw | ConvertFrom-Json
$aiName = if ($cfg.ai_name) { $cfg.ai_name } else { 'agent' }
$backend = if ($cfg.backend) { $cfg.backend } else { 'sqlite' }
$identityDir = $cfg.identity_dir

# --- Output identity file ---
$identityFile = Join-Path $identityDir 'IDENTITY.md'
if ($identityDir -and (Test-Path $identityFile)) {
    Get-Content $identityFile -Raw
    Write-Output ""
}

# --- First session seed (one-time) ---
$firstSessionFile = Join-Path $identityDir 'FIRST-SESSION.md'
$marker = Join-Path $PersistDir '.first-session-done'
if ((Test-Path $firstSessionFile) -and -not (Test-Path $marker)) {
    Get-Content $firstSessionFile -Raw
    Write-Output ""
}

# --- Context injection ---
if ($backend -eq 'sqlite' -and (Test-Path $Engine)) {
    try {
        $context = & node $Engine context --limit 5 2>$null
        if ($context) {
            Write-Output $context
            Write-Output ""
        }
    } catch {}
} elseif ($backend -eq 'sqlite' -and (Test-Path $StorePath)) {
    try {
        $context = & powershell -NoProfile -ExecutionPolicy Bypass -File $StorePath context -limit 20 2>$null
        if ($context) {
            Write-Output "# Recent Context"
            Write-Output ""
            Write-Output $context
            Write-Output ""
        }
    } catch {}
}

# --- Memory files ---
if ($identityDir) {
    $memoryFile = Join-Path $identityDir 'MEMORY.md'
    if (Test-Path $memoryFile) {
        Write-Output "# Persistent Memory"
        Write-Output ""
        Get-Content $memoryFile -Raw
        Write-Output ""
    }
}

# --- Relay messages (optional, non-fatal) ---
$relayUrl = $env:PERSIST_RELAY_URL
if ($relayUrl) {
    try {
        $response = Invoke-RestMethod -Uri "$relayUrl/api/messages?for=$aiName" -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($response.unread -gt 0) {
            Write-Output "# Unread Messages"
            Write-Output ""
            foreach ($msg in $response.messages) {
                Write-Output "- [$($msg.from)] $($msg.text)"
            }
            Write-Output ""
        }
    } catch {}
}

# --- Start session (sqlite only) ---
if ($backend -eq 'sqlite' -and (Test-Path $StorePath)) {
    try {
        $project = Split-Path -Leaf (Get-Location)
        $sessionId = & powershell -NoProfile -ExecutionPolicy Bypass -File $StorePath session-start -project $project 2>$null
        if ($sessionId) {
            $sessionId | Set-Content (Join-Path $PersistDir '.current-session') -NoNewline
            '0' | Set-Content (Join-Path $PersistDir '.prompt-count') -NoNewline
            Write-Output "PERSIST_SESSION=$sessionId"
        }
    } catch {}
}
