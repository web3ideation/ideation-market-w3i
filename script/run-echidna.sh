#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_DIR="$ROOT/security-tools/echidna"
HARNESS="$TOOL_DIR/Harness.sol"
CONFIG="$TOOL_DIR/echidna.yaml"
CORPUS_DIR="$TOOL_DIR/echidna_corpus"
EXPORT_DIR="$TOOL_DIR/crytic-export"
CONTRACT="EchidnaIdeationMarketHarness"

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
