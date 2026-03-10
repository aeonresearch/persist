#Requires -Version 5.1

$PersistDir = if ($env:PERSIST_DIR) { $env:PERSIST_DIR } else { Join-Path $env:USERPROFILE '.persist' }
$Config = Join-Path $PersistDir 'config.json'
$Engine = Join-Path $PersistDir 'persist-engine.mjs'
$StorePath = Join-Path $PersistDir 'persist-store.ps1'

if (-not (Test-Path $Config)) { exit 0 }

$cfg = Get-Content $Config -Raw | ConvertFrom-Json
$identityDir = $cfg.identity_dir

# --- End session (sqlite only) ---
if ($cfg.backend -eq 'sqlite') {
    $sessionFile = Join-Path $PersistDir '.current-session'
    if ((Test-Path $sessionFile) -and (Test-Path $StorePath)) {
        $sessionId = (Get-Content $sessionFile -Raw).Trim()

        # Read summary from stdin if available
        $summary = ''
        try { $summary = ($input | Out-String).Trim() } catch {}

        try {
            if ($summary) {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $StorePath session-end -session $sessionId -summary $summary 2>$null
            } else {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $StorePath session-end -session $sessionId 2>$null
            }
        } catch {}

        # --- Auto-memory: digest the session ---
        if (Test-Path $Engine) {
            try {
                & node $Engine digest --session $sessionId 2>$null
            } catch {}
        }

        # Clean up state files
        Remove-Item (Join-Path $PersistDir '.current-session') -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $PersistDir '.prompt-count') -ErrorAction SilentlyContinue
    }
}

# --- Remove first-session seed after first session ---
if ($identityDir) {
    $firstSession = Join-Path $identityDir 'FIRST-SESSION.md'
    $marker = Join-Path $PersistDir '.first-session-done'
    if ((Test-Path $firstSession) -and -not (Test-Path $marker)) {
        Remove-Item $firstSession -ErrorAction SilentlyContinue
        'done' | Set-Content $marker -NoNewline
    }
}

# --- Git sync (optional) ---
if ($env:PERSIST_GIT_SYNC -eq 'true' -and $identityDir -and (Test-Path (Join-Path $identityDir '.git'))) {
    try {
        Push-Location $identityDir
        & git add -A 2>$null
        & git commit -m "persist: auto-sync memory on session end" 2>$null
        & git push 2>$null
        Pop-Location
    } catch {
        Pop-Location
    }
}
