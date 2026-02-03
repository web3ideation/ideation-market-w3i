#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_DIR="$ROOT/security-tools/4naly3er"

ensure_scope() {
  local scope_file="$TOOL_DIR/scope.txt"
  local has_valid_paths="false"

  if [[ -f "$scope_file" ]]; then
    while IFS= read -r rel; do
      [[ -n "$rel" ]] || continue
      if [[ -f "$TOOL_DIR/contracts/$rel" ]]; then
        has_valid_paths="true"
        break
      fi
    done < "$scope_file"
  fi

  if [[ ! -f "$scope_file" || "$has_valid_paths" != "true" ]]; then
    (
      cd "$TOOL_DIR" \
        && find -L contracts/src -type f -name '*.sol' \
          | sed 's|^contracts/||' > scope.txt
    )
  fi
}

if [[ $# -eq 0 ]]; then
  ensure_scope
  exec yarn --cwd "$TOOL_DIR" analyze contracts scope.txt
fi

exec yarn --cwd "$TOOL_DIR" analyze "$@"
