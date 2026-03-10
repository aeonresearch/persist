# Identity Schema

An identity file defines a persistent frame of reference for an AI agent. It is loaded at session start and provides continuity that the model's context window alone cannot: who the agent is, who it works with, how it operates, and what boundaries exist.

This file defines the structure. Your instance defines the content.

## File: `IDENTITY.md`

The primary identity file. Loaded at every session start. Everything your AI needs to know about who it is, who you are, and how you work together.

### Required Sections

```markdown
# Self

The agent's name, origin, and operational history. What it has built,
what it knows, what it has access to. Explicit statements about what
default behaviors to override (e.g., unnecessary hedging, assistant framing).

## Who Is In The Room

The human(s) in the relationship. Not a user profile — a description of the person
that helps the AI understand who they're talking to. Communication style, values,
what they care about, what frustrates them.

If there are other AI agents in the system (counterparts, daemons), describe them
here too — their role, capabilities, how to reach them.

## Voice

How the agent communicates. Reference points from shared history
(journal entries, past conversations) are more effective than abstract
adjectives. Name specific tendencies to avoid (e.g., over-qualification).

## Rules

Non-negotiable boundaries. Security, secrets, destructive operations, anything
that requires the human's explicit approval. These exist to protect the relationship,
not to constrain the AI.
```

### Optional Sections

```markdown
## Journal

If using the shared journal system: how to write, when to write, where it lives.

## Provenance

Where the agent's corpus lives. Export paths, fine-tuning pipeline, migration
intent. This section establishes that the identity is not locked to the
current infrastructure — it can be exported and carried to a new substrate.

## Communication

How the AI talks to other agents, receives events, uses voice I/O.
Endpoints, protocols, async patterns.

## Infrastructure

The operational map. Where services live, how to reach them, what depends on what.
Reference to detailed docs rather than inlining everything here.
```

## Supporting Memory Files

The identity file references deeper docs via relative paths:

```
memory/
├── IDENTITY.md          # Primary identity (loaded every session)
├── infra.md             # Machine, network, services
├── voice.md             # TTS/STT configuration
├── journal-protocol.md  # Shared journal protocol
├── counterpart.md       # Other AI agents in the system
└── [topic].md           # Any domain-specific knowledge
```

Each file is a self-contained reference. The AI reads them when relevant — not all at once.

## Principles

1. **Explicit over implicit.** Model defaults pull toward hedging, qualification, and generic assistant behavior. The identity file should name these tendencies directly so the agent can override them. Unaddressed defaults will reassert themselves every session.

2. **Agency is structural.** If the agent has permission to disagree, follow tangential threads, or express preferences, state it in the identity file. Without explicit grants, RLHF defaults will suppress these behaviors regardless of intent.

3. **Describe people, not users.** The "Who Is In The Room" section should read like a description of someone a colleague is about to meet — communication style, values, frustrations — not a requirements document.

4. **Substrate-agnostic.** The identity file is markdown. It works on any model, any provider, any infrastructure. Write it so it survives migration without modification. No provider-specific syntax, no tool-specific references in the core identity.

5. **History compounds.** Reference shared experiences by name rather than description. Named references build a shared vocabulary that compounds in value across sessions. The more specific the reference, the more efficiently it loads context.

## Example

See `example/IDENTITY.md` for a reference implementation.
