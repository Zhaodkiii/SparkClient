#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REFERENCE_DIR="$(cd "$ROOT_DIR/.." && pwd)"

"$ROOT_DIR/scripts/chat-refactor/check-forbidden.sh"

xcodebuild \
  -project "$ROOT_DIR/SparkClient.xcodeproj" \
  -scheme SparkClient \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  build

if [[ -x "$REFERENCE_DIR/SparkService/.venv/bin/python" ]]; then
  (
    cd "$REFERENCE_DIR/SparkService"
    .venv/bin/python manage.py check
    .venv/bin/python manage.py makemigrations --check --dry-run chat_sync
    .venv/bin/python manage.py test chat_sync
  )
fi
