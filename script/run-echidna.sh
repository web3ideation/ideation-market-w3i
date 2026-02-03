#!/usr/bin/env bash
set -euo pipefail

# Purpose: Run Echidna fuzzing against the canonical harness in a self-contained way.
#          Mirrors repo src/ into security-tools/echidna/src/ before running.

log() {
  if [[ "${VERBOSE:-0}" == "1" ]]; then
    echo "$@" >&2
  fi
}

usage() {
  cat <<'EOF'
Usage:
  bash script/run-echidna.sh
  bash script/run-echidna.sh [echidna args...]

Notes:
  - Runs the canonical harness at security-tools/echidna/Harness.sol.
  - Mirrors repo src/ into security-tools/echidna/src/ for self-contained compilation.
  - Writes corpus/coverage/reproducers under security-tools/echidna/echidna_corpus/.
  - Outputs: security-tools/echidna/echidna_corpus/, security-tools/echidna/crytic-export/

Examples:
  bash script/run-echidna.sh --format text
  bash script/run-echidna.sh --seq-len 120 --test-limit 300000 --format text
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v echidna >/dev/null 2>&1; then
  echo "error: echidna not found in PATH" >&2
  echo "hint: install echidna (Trail of Bits) and ensure it's on PATH" >&2
  exit 127
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "error: solc not found in PATH (echidna needs a Solidity compiler)" >&2
  exit 127
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_DIR="$ROOT/security-tools/echidna"
HARNESS="$TOOL_DIR/Harness.sol"
CONFIG="$TOOL_DIR/echidna.yaml"
CORPUS_DIR="$TOOL_DIR/echidna_corpus"
EXPORT_DIR="$TOOL_DIR/crytic-export"
CONTRACT="EchidnaIdeationMarketHarness"

log "Outputs: $CORPUS_DIR (corpus/coverage/reproducers), $EXPORT_DIR (crytic export)"

mkdir -p "$CORPUS_DIR" "$EXPORT_DIR"

# Keep Echidna compilation self-contained: copy the repo's src/ into TOOL_DIR/src.
# This avoids solc allow-path issues when `src/` is outside the allowed directories.
SRC_MIRROR="$TOOL_DIR/src"
rm -rf "$SRC_MIRROR"
mkdir -p "$SRC_MIRROR"

if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete "$ROOT/src/" "$SRC_MIRROR/"
else
  cp -a "$ROOT/src/." "$SRC_MIRROR/"
fi

cd "$TOOL_DIR"
exec echidna "$HARNESS" \
  --contract "$CONTRACT" \
  --config "$CONFIG" \
  --corpus-dir "$CORPUS_DIR" \
  --disable-slither \
  --solc-args "--via-ir --optimize --optimize-runs 5000" \
  --crytic-args "--export-dir $EXPORT_DIR" \
  "$@"
