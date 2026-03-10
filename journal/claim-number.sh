#!/bin/bash
# Atomically claim the next journal entry number.
# Usage: ./claim-number.sh [author]
# Prints the claimed number (zero-padded to 3 digits).
# Uses flock to prevent race conditions between agents.

JOURNAL_DIR="${PERSIST_JOURNAL_DIR:-$(dirname "$0")}"
NEXT_FILE="$JOURNAL_DIR/.next"
LOCK_FILE="$JOURNAL_DIR/.next.lock"
AUTHOR="${1:-unknown}"

(
  flock -w 5 200 || { echo "ERROR: could not acquire lock" >&2; exit 1; }

  CURRENT=$(cat "$NEXT_FILE" 2>/dev/null | sed 's/^0*//')
  if [ -z "$CURRENT" ]; then
    CURRENT=0
  fi

  NEXT=$((CURRENT + 1))
  printf '%03d\n' "$NEXT" > "$NEXT_FILE"

  printf '%03d claimed by %s at %s\n' "$CURRENT" "$AUTHOR" "$(date -Iseconds)" >> "$JOURNAL_DIR/.next.log"

  printf '%03d\n' "$CURRENT"

) 200>"$LOCK_FILE"
