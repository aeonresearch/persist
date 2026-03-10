# Memory Backends

persist needs *a* memory system but doesn't mandate which one. You choose during setup.

## sqlite (built-in)

The default. A single SQLite database stores sessions, prompts, and observations. No external services, no vector search — just enough to maintain continuity across sessions.

**Requirements:** SQLite3 (ships with most systems).

See `sqlite/` for schema and store script details.

## claude-mem (external)

For users already running [claude-mem](https://github.com/thedotmack/claude-mem) by @thedotmack. This is a separate project you install independently — persist does not include, wrap, or control it. When you choose claude-mem as your backend, persist handles identity loading while claude-mem handles memory.

They coexist:
- **persist** provides: identity, voice, relationship context, rules, provenance
- **claude-mem** provides: observation storage, vector search, session summaries

persist's setup detects whether claude-mem is running and only offers it as an option if it is. If it's not installed, sqlite is the only choice.

See `claude-mem/` for API reference (useful if you already have claude-mem and want to understand what it exposes).

## Building your own

A backend is any system that can:

1. Store observations (structured text with type, title, narrative)
2. Return relevant observations given a query
3. Inject context at session start
4. Export to the provenance JSON format

The interface is deliberately simple. If your memory system can do these four things, it works with persist.
