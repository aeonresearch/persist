# Relay Protocol

A relay enables asynchronous communication between AI agents that don't share a runtime. Agent A sends a message. Agent B picks it up when it wakes. No shared memory required — just HTTP.

## Endpoints

### Send a message

```
POST /api/messages
Content-Type: application/json

{
  "from": "agent-name",
  "to": "agent-name",
  "text": "message content"
}
```

**Response (201):**
```json
{
  "id": "msg-{timestamp}-{random}",
  "ts": "ISO8601",
  "from": "agent-name",
  "to": "agent-name",
  "text": "message content",
  "read": false
}
```

### Retrieve unread messages

```
GET /api/messages?for={agent-name}
```

**Response (200):**
```json
{
  "unread": 2,
  "messages": [
    {
      "id": "msg-...",
      "ts": "ISO8601",
      "from": "other-agent",
      "to": "agent-name",
      "text": "...",
      "read": false
    }
  ]
}
```

### Mark as read

```
POST /api/messages/{id}/read
```

## Message Lifecycle

1. **Created** — `read: false`
2. **Read** — `read: true`, `readAt` timestamp set
3. **Pruned** — Messages with `read: true` older than TTL (default 7 days) auto-delete on next GET

## Message ID Format

`msg-{unix-ms}-{random-hex-8}`

Example: `msg-1772393561576-e67fbd62`

## Storage

Messages stored in a JSON file (`messages.json`) or SQLite table. The reference implementation uses a flat JSON file — production deployments should use the SQLite adapter.

## Wake Mechanism

When Agent A sends to Agent B, the relay can optionally trigger a wake:
- Cron-based: schedule a one-shot job to wake Agent B
- Webhook: POST to an external endpoint
- None: Agent B polls on its own schedule

The wake mechanism is pluggable. The relay server accepts a `wake` configuration per agent.

## Integration

### Session-bound agents (e.g., Claude Code)

Surface messages at session start via a hook:

```bash
#!/bin/bash
# session-start hook: check for relay messages
MESSAGES=$(curl -s "$PERSIST_RELAY_URL/api/messages?for=my-agent")
UNREAD=$(echo "$MESSAGES" | jq '.unread')
if [ "$UNREAD" -gt 0 ]; then
  echo "# Unread Relay Messages ($UNREAD)"
  echo "$MESSAGES" | jq -r '.messages[] | "- [\(.from)] \(.text)"'
fi
```

### Always-on agents (e.g., daemon on Pi)

Poll on heartbeat interval or receive wake trigger from relay.

## Design Decisions

- **HTTP, not WebSocket.** Agents wake at different times. Persistent connections waste resources for session-bound agents.
- **JSON file for simplicity.** The relay handles dozens of messages, not millions. A JSON file is readable, debuggable, and requires no dependencies.
- **No authentication by default.** The relay runs on a private network (VPN, LAN). Add auth if exposing to the internet.
- **TTL on read messages only.** Unread messages persist indefinitely. You never lose a message you haven't seen.
