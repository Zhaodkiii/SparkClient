#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FORBIDDEN_FILE="$ROOT_DIR/scripts/chat-refactor/forbidden.txt"

while IFS= read -r pattern; do
  [[ -z "$pattern" ]] && continue
  if rg -n --fixed-strings "$pattern" \
    "$ROOT_DIR/SparkClient/Projects/Features/Chat" \
    "$ROOT_DIR/SparkClient/Projects/App" \
    --glob '*.swift' \
    --glob '!Infrastructure/ChatSyncEngine.swift' \
    --glob '!Infrastructure/ChatSyncSupervisor.swift'; then
    echo "Forbidden chat refactor symbol found: $pattern" >&2
    exit 1
  fi
done < "$FORBIDDEN_FILE"
