#!/usr/bin/env bash
# iOS 16 回部署兼容扫描：找出 SwiftUI View / Representable / ObservableObject 上
# 仍存储 async closure 的可疑字段，便于 code review 与 CI 门禁。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECTS="$ROOT/SparkClient/Projects"

PATTERN='(let|var)[[:space:]]+[^=]*async[[:space:]]*(throws[[:space:]]*)?->'

echo "== iOS 16 compat: scanning stored async closure properties =="
echo "Root: $PROJECTS"
echo

scan_file() {
  local label="$1"
  local glob="$2"
  echo "--- $label ---"
  if rg -n --glob "$glob" "$PATTERN" "$PROJECTS" 2>/dev/null; then
    echo
  else
    echo "(none)"
    echo
  fi
}

scan_file "SwiftUI View (*View*.swift)" "*View*.swift"
scan_file "UIViewControllerRepresentable" "*Representable*.swift"
scan_file "ObservableObject ViewModels (*ViewModel*.swift)" "*ViewModel*.swift"

echo "Done. 若命中项为 View / Representable / ObservableObject 存储属性，请改用："
echo "  - MainActorThrowingAction / MainActorAsyncAction 包装类"
echo "  - 协议 + class 引用"
echo "  - 同步 closure + 调用方 Task { }"
