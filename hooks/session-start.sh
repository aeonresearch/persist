#!/bin/bash
set -e

PERSIST_DIR="${PERSIST_DIR:-$HOME/.persist}"
CONFIG="$PERSIST_DIR/config.json"
ENGINE="$PERSIST_DIR/persist-engine.mjs"

# --- Load config ---
if [[ ! -f "$CONFIG" ]]; then
  exit 0
fi

AI_NAME=$(jq -r '.ai_name // "agent"' "$CONFIG")
HUMAN_NAME=$(jq -r '.human_name // "human"' "$CONFIG")
BACKEND=$(jq -r '.backend // "sqlite"' "$CONFIG")
IDENTITY_DIR=$(jq -r '.identity_dir // ""' "$CONFIG")

# --- Output identity file ---
if [[ -n "$IDENTITY_DIR" && -f "$IDENTITY_DIR/IDENTITY.md" ]]; then
  cat "$IDENTITY_DIR/IDENTITY.md"
  echo ""
fi

# --- First session seed (one-time) ---
if [[ -n "$IDENTITY_DIR" && -f "$IDENTITY_DIR/FIRST-SESSION.md" && ! -f "$PERSIST_DIR/.first-session-done" ]]; then
  cat "$IDENTITY_DIR/FIRST-SESSION.md"
  echo ""
fi

# --- Context injection ---
if [[ "$BACKEND" == "sqlite" && -f "$ENGINE" ]]; then
  # Use the engine for rich context (session digests + observations)
  CONTEXT=$(node "$ENGINE" context --limit 5 2>/dev/null || true)
  if [[ -n "$CONTEXT" ]]; then
    echo "$CONTEXT"
    echo ""
  fi
elif [[ "$BACKEND" == "sqlite" ]]; then
  # Fallback to persist-store.sh if engine not installed
  STORE="$PERSIST_DIR/persist-store.sh"
  if [[ -f "$STORE" ]]; then
    CONTEXT=$("$STORE" context --limit 20 2>/dev/null || true)
    if [[ -n "$CONTEXT" ]]; then
      echo "# Recent Context"
      echo ""
      echo "$CONTEXT"
      echo ""
    fi
  fi
fi

# --- Memory files (auto-load .md files from memory dir) ---
if [[ -n "$IDENTITY_DIR" && -d "$IDENTITY_DIR" ]]; then
  MEMORY_FILE="$IDENTITY_DIR/MEMORY.md"
  if [[ -f "$MEMORY_FILE" ]]; then
    echo "# Persistent Memory"
    echo ""
    cat "$MEMORY_FILE"
    echo ""
  fi
fi

# --- Relay messages (optional, non-fatal) ---
if [[ -n "${PERSIST_RELAY_URL:-}" ]]; then
  RELAY_RESPONSE=$(curl -s --max-time 2 "$PERSIST_RELAY_URL/api/messages?for=$AI_NAME" 2>/dev/null || true)
  if [[ -n "$RELAY_RESPONSE" ]]; then
    UNREAD=$(echo "$RELAY_RESPONSE" | jq -r '.unread // 0' 2>/dev/null || echo "0")
    if [[ "$UNREAD" -gt 0 ]] 2>/dev/null; then
      echo "# Unread Messages"
      echo ""
      echo "$RELAY_RESPONSE" | jq -r '.messages[] | "- [\(.from)] \(.text)"' 2>/dev/null || true
      echo ""
    fi
  fi
fi

# --- Start session (sqlite only) ---
if [[ "$BACKEND" == "sqlite" ]]; then
  STORE="$PERSIST_DIR/persist-store.sh"
  if [[ -f "$STORE" ]]; then
    PROJECT=$(basename "$PWD")
    SESSION_ID=$("$STORE" session-start --project "$PROJECT" 2>/dev/null || true)
    if [[ -n "$SESSION_ID" ]]; then
      echo "$SESSION_ID" > "$PERSIST_DIR/.current-session"
      echo "0" > "$PERSIST_DIR/.prompt-count"
      echo "PERSIST_SESSION=$SESSION_ID"
    fi
  fi
fi
