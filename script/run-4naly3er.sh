#!/usr/bin/env bash
set -euo pipefail

# Purpose: Run 4naly3er review tool and write a markdown report.

log() {
  if [[ "${VERBOSE:-0}" == "1" ]]; then
    echo "$@" >&2
  fi
}

usage() {
  cat <<'EOF'
Usage:
  bash script/run-4naly3er.sh
  bash script/run-4naly3er.sh [4naly3er args...]

Notes:
  - Default writes/overwrites: security-tools/4naly3er/report.md
  - Default run uses security-tools/4naly3er/scope.txt (auto-generated if missing/stale).
  - Outputs: security-tools/4naly3er/report.md

Examples:
  bash script/run-4naly3er.sh
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v yarn >/dev/null 2>&1; then
  echo "error: yarn not found in PATH" >&2
  exit 127
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_DIR="$ROOT/security-tools/4naly3er"

log "Outputs: $TOOL_DIR/report.md"

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
