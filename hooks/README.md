# Hooks

persist integrates with AI coding tools via session lifecycle hooks. These hooks inject identity context, surface messages, and store observations.

Setup runs `setup.sh` (Linux/macOS) or `setup.ps1` (Windows) which auto-detects Claude Code and installs the correct platform hooks. You should not need to configure hooks manually.

## Hook Lifecycle

### session-start (.sh / .ps1)

1. Outputs the identity file (IDENTITY.md) into session context
2. If this is the first session, injects the first-session seed (FIRST-SESSION.md)
3. Queries memory backend for recent context (sqlite only)
4. Checks relay for unread messages (if relay URL configured)
5. Starts a new session in the memory backend

### prompt-submit (.sh / .ps1)

1. Records the user prompt to the memory backend
2. Lightweight — should complete in <1 second

### session-end (.sh / .ps1)

1. Stores session summary in memory backend
2. Removes the first-session seed (so it only fires once)
3. Syncs memory files to git (if PERSIST_GIT_SYNC=true)

## First Session Seed

On the very first session after setup, `FIRST-SESSION.md` is injected alongside the identity file. This gives the agent material to respond to — awareness that it was just created, that someone chose to give it continuity, and an invitation to respond as a presence rather than a tool.

The seed is automatically deleted after the first session ends. Subsequent sessions load only the identity file and recent context.

## Platform Scripts

| Hook | Linux/macOS | Windows |
|------|-------------|---------|
| session-start | session-start.sh | session-start.ps1 |
| prompt-submit | prompt-submit.sh | prompt-submit.ps1 |
| session-end | session-end.sh | session-end.ps1 |

Setup installs only the correct platform's scripts. No runtime platform detection overhead.

## Claude Code

Hooks are installed into `~/.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      { "command": "/path/to/.persist/hooks/session-start.sh" }
    ],
    "UserPromptSubmit": [
      { "command": "/path/to/.persist/hooks/prompt-submit.sh" }
    ],
    "Stop": [
      { "command": "/path/to/.persist/hooks/session-end.sh" }
    ]
  }
}
```

On Windows, commands use `powershell -NoProfile -File` to invoke the `.ps1` scripts.

## OpenClaw

OpenClaw injects identity via system prompt configuration. The identity file content goes into the agent's system message. Hooks work differently — OpenClaw uses cron-based session triggers rather than interactive hooks.

Integration guide: use the identity file as the system prompt, and configure the memory backend adapter to run on the same host as the OpenClaw daemon.

## Environment Variables

| Variable | Purpose |
|----------|---------|
| PERSIST_DIR | Override default persist directory (~/.persist) |
| PERSIST_RELAY_URL | Relay endpoint for inter-agent messaging |
| PERSIST_GIT_SYNC | Set to "true" to auto-commit memory on session end |

## Other Tools

persist's hooks are simple scripts that output markdown. Any AI tool that supports running a command at session start and injecting the output into context can use persist. The hooks are the integration point — everything else is protocol.
