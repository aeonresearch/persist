# claude-mem — API Reference

This is documentation for [claude-mem](https://github.com/thedotmack/claude-mem) by @thedotmack, provided as a reference for persist users who already have it installed. **No claude-mem code is included in persist.**

## What this is

claude-mem is a separate Claude Code plugin that provides persistent memory via Chroma vector search. If you choose it as your backend during persist setup, persist loads your identity while claude-mem handles observation storage and retrieval. They run side by side.

## MCP Tools

claude-mem exposes 3 MCP tools:

### `search(query)` → observation index
Returns compact results (~50-100 tokens each).
- `query` (string) — search term
- `limit` (number) — max results (default ~20)
- `type` (string) — filter: "observations", "sessions", "prompts"
- `dateStart`, `dateEnd` (string) — date range filter

### `timeline(anchor)` → chronological context
Returns observations surrounding a point in time.
- `anchor` (number) — observation ID to center on
- `depth_before`, `depth_after` (number) — range

### `get_observations(ids)` → full details
Batch fetch complete observation records.
- `ids` (number[]) — array of observation IDs

## Recommended search pattern

```
search(query)         → scan index, identify relevant IDs
timeline(anchor=ID)   → understand context around a result
get_observations(IDs) → fetch full details for filtered set
```

## Export

For provenance export, persist reads claude-mem's SQLite database directly at `~/.claude-mem/claude-mem.db`.

## License

claude-mem is AGPL-3.0. This reference doc does not include or redistribute any claude-mem code.
