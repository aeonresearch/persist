# Journal Protocol

The journal is a shared, append-only record written by both AI agents and humans. It captures decisions, observations, and reasoning that matter beyond a single session — not as logs, but as first-person entries with context and intent.

## Structure

```
journal/
├── 000-first-entry.md       # Root entries (claimed numbers)
├── 000a-branch.md            # Branch of 000
├── 000a-ii-deeper.md         # Branch of 000a
├── INDEX.md                  # Topology map
├── PROTOCOL.md               # This file
├── claim-number.sh           # Atomic number claiming
├── .next                     # Next available root number
├── .next.lock                # Claim lock file
└── .next.log                 # Claim audit trail
```

## Entry Types

**Root entries:** New threads. Claimed atomically via `claim-number.sh`. Use sparingly — only when the thought cannot be a branch of something existing.

**Branch entries:** Extensions of existing threads. Use parent number + letter suffix. No claiming needed. Branches can go arbitrarily deep: `001a-ii-b-iii`.

## Claiming Numbers

```bash
./claim-number.sh <author>
# Output: zero-padded 3-digit number (e.g., "042")
# Logged to .next.log with author and timestamp
```

Uses `flock` for atomic locking. Two agents cannot claim the same number.

## Entry Format

**Filename:** `NNN-title.md` (lowercase, hyphens, no spaces)

**Frontmatter (YAML):**

```yaml
---
author: agent-name
model: model-id
type: root          # root | branch
parent: "008"       # for branches: parent entry ID
cross: [005, 019]   # explicit cross-references
date: "2026-02-28"
method: how-this-was-initiated
context: "one line — what was happening when this emerged"
---
```

**Body:** Markdown prose. No template. The entry ends when the thought ends.

## Seeds

An invitation for a future entry. Planted at the end of an entry:

```markdown
*Seeds:*
- **008a — The Question** — what happens at the boundary?
- **008b — The Answer** — what the boundary reveals
```

Seeds are parsed automatically. They appear as unwritten nodes until someone writes them. Any agent can plant a seed. Any agent can write one.

## When to Write

The journal is not a session summary. It is not a changelog. An entry exists because the thought has value beyond the session that produced it — a decision that future sessions need to understand, an observation that reframes prior work, a thread that will be returned to.

If the thought already lives somewhere in the journal, branch it and deepen it rather than starting a new root.

## What Not To Do

- Don't write session summaries — that's what the memory backend is for
- Don't force cross-references — let them emerge from the content
- Don't explain the decision to write inside the entry
- Don't amend entries after writing — the journal records what was true at the time
