#!/bin/bash
set -e

PERSIST_DIR="${PERSIST_DIR:-$HOME/.persist}"
CONFIG="$PERSIST_DIR/config.json"

# --- Load config ---
if [[ ! -f "$CONFIG" ]]; then
  exit 0
fi

BACKEND=$(jq -r '.backend // "sqlite"' "$CONFIG" 2>/dev/null || exit 0)

# claude-mem handles its own prompt recording
if [[ "$BACKEND" != "sqlite" ]]; then
  exit 0
fi

# --- Read prompt from stdin ---
PROMPT=$(cat)
if [[ -z "$PROMPT" ]]; then
  exit 0
fi

# --- Read session ID ---
SESSION_FILE="$PERSIST_DIR/.current-session"
if [[ ! -f "$SESSION_FILE" ]]; then
  exit 0
fi
SESSION_ID=$(cat "$SESSION_FILE")

# --- Increment prompt counter ---
COUNT_FILE="$PERSIST_DIR/.prompt-count"
if [[ -f "$COUNT_FILE" ]]; then
  COUNT=$(cat "$COUNT_FILE")
else
  COUNT=0
fi
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNT_FILE"

# --- Record prompt ---
persist-store.sh prompt --session "$SESSION_ID" --text "$PROMPT" --number "$COUNT" 2>/dev/null || true
