#Requires -Version 5.1

$PersistDir = if ($env:PERSIST_DIR) { $env:PERSIST_DIR } else { Join-Path $env:USERPROFILE '.persist' }
$Config = Join-Path $PersistDir 'config.json'
$StorePath = Join-Path $PersistDir 'persist-store.ps1'

if (-not (Test-Path $Config)) { exit 0 }

$cfg = Get-Content $Config -Raw | ConvertFrom-Json
if ($cfg.backend -ne 'sqlite') { exit 0 }

# --- Read prompt from stdin ---
$prompt = $input | Out-String
if (-not $prompt.Trim()) { exit 0 }

# --- Read session ID ---
$sessionFile = Join-Path $PersistDir '.current-session'
if (-not (Test-Path $sessionFile)) { exit 0 }
$sessionId = (Get-Content $sessionFile -Raw).Trim()

# --- Increment prompt counter ---
$countFile = Join-Path $PersistDir '.prompt-count'
$count = 0
if (Test-Path $countFile) {
    $count = [int](Get-Content $countFile -Raw).Trim()
}
$count++
"$count" | Set-Content $countFile -NoNewline

# --- Record prompt ---
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $StorePath prompt -session $sessionId -text $prompt -number $count 2>$null
} catch {}
