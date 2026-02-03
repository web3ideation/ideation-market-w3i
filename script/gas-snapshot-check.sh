#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAPSHOT_FILE="$ROOT/security-tools/gas/.gas-snapshot"

if [[ $# -eq 0 ]]; then
	exec forge snapshot --match-contract IdeationMarketGasTest --check "$SNAPSHOT_FILE"
fi

exec forge snapshot --check "$SNAPSHOT_FILE" "$@"
