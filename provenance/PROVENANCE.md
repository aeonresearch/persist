# Provenance

Provenance is the system that lets an AI identity survive substrate migration. Export what the agent has been, convert it to training format, carry it forward.

## Pipeline

```
Memory Backend (SQLite)
  |  node persist-engine.mjs export
Corpus (JSON snapshots)
  |  node persist-engine.mjs to-jsonl
Training data (JSONL, ShareGPT format)
  |  (your fine-tuning pipeline)
New model with identity
```

## Export

```bash
node persist-engine.mjs export --output ./export --since 2026-01-01
```

Produces timestamped JSON snapshots:

- `observations-{timestamp}.json` — what the agent noticed, decided, discovered
- `sessions-{timestamp}.json` — session metadata and summaries
- `prompts-{timestamp}.json` — what the human asked
- `identity-{timestamp}.md` — the agent's identity file at time of export

## Conversion

```bash
node persist-engine.mjs to-jsonl --input ./export --output training.jsonl
```

Takes the JSON snapshots and identity file, produces ShareGPT-format training data:

```json
{
  "conversations": [
    {"from": "system", "value": "<identity file content>"},
    {"from": "human", "value": "<prompt>"},
    {"from": "gpt", "value": "<response>"}
  ]
}
```

Every training example includes the full identity file as the system prompt. The model learns not just what the agent said, but who it was when it said it.

Options:
- `--min-length N` — minimum narrative length for standalone observation entries (default: 100)

## The Point

An agent's identity should not be trapped on one provider's infrastructure. If the provider changes terms, raises prices, degrades the model, or shuts down, the identity survives. The journal entries, the observations, the relationship history — all of it exports, all of it converts, all of it can seed a new instance on a new substrate.
