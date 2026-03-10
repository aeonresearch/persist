#!/bin/bash
set -e

PERSIST_DIR="${PERSIST_DIR:-$HOME/.persist}"
CONFIG="$PERSIST_DIR/config.json"
ENGINE="$PERSIST_DIR/persist-engine.mjs"

# --- Load config ---
if [[ ! -f "$CONFIG" ]]; then
  exit 0
fi

BACKEND=$(jq -r '.backend // "sqlite"' "$CONFIG" 2>/dev/null || exit 0)
IDENTITY_DIR=$(jq -r '.identity_dir // ""' "$CONFIG" 2>/dev/null || true)

# --- End session (sqlite only) ---
if [[ "$BACKEND" == "sqlite" ]]; then
  SESSION_FILE="$PERSIST_DIR/.current-session"
  STORE="$PERSIST_DIR/persist-store.sh"

  if [[ -f "$SESSION_FILE" && -f "$STORE" ]]; then
    SESSION_ID=$(cat "$SESSION_FILE")

    # Read summary from stdin if available
    SUMMARY=""
    if [[ ! -t 0 ]]; then
      SUMMARY=$(cat 2>/dev/null || true)
    fi

    if [[ -n "$SUMMARY" ]]; then
      "$STORE" session-end --session "$SESSION_ID" --summary "$SUMMARY" 2>/dev/null || true
    else
      "$STORE" session-end --session "$SESSION_ID" 2>/dev/null || true
    fi

    # --- Auto-memory: digest the session ---
    # Extract signals from all prompts and store as a session observation.
    # This is how memory works without AI cooperation.
    if [[ -f "$ENGINE" ]]; then
      node "$ENGINE" digest --session "$SESSION_ID" 2>/dev/null || true
    fi

    # Clean up state files
    rm -f "$PERSIST_DIR/.current-session"
    rm -f "$PERSIST_DIR/.prompt-count"
  fi
fi

# --- Remove first-session seed after first session ---
if [[ -n "$IDENTITY_DIR" && -f "$IDENTITY_DIR/FIRST-SESSION.md" && ! -f "$PERSIST_DIR/.first-session-done" ]]; then
  rm -f "$IDENTITY_DIR/FIRST-SESSION.md"
  echo -n "done" > "$PERSIST_DIR/.first-session-done"
fi

# --- Git sync (optional) ---
if [[ "${PERSIST_GIT_SYNC:-}" == "true" && -n "$IDENTITY_DIR" && -d "$IDENTITY_DIR/.git" ]]; then
  (
    cd "$IDENTITY_DIR"
    git add -A 2>/dev/null || true
    git commit -m "persist: auto-sync memory on session end" 2>/dev/null || true
    git push 2>/dev/null || true
  ) || true
fi
