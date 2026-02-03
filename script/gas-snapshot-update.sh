#!/usr/bin/env bash
set -euo pipefail

# Purpose: Update/regenerate the pinned Foundry gas snapshot for CI regression checks.

log() {
	if [[ "${VERBOSE:-0}" == "1" ]]; then
		echo "$@" >&2
	fi
}

usage() {
	cat <<'EOF'
Usage:
	bash script/gas-snapshot-update.sh
	bash script/gas-snapshot-update.sh [forge snapshot args...]

Notes:
	- Default snapshots only IdeationMarketGasTest into the pinned snapshot.
	- Snapshot file lives at security-tools/gas/.gas-snapshot.
	- Outputs: security-tools/gas/.gas-snapshot (write)

Examples:
	bash script/gas-snapshot-update.sh
	bash script/gas-snapshot-update.sh --match-contract IdeationMarketGasTest
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
	usage
	exit 0
fi

if ! command -v forge >/dev/null 2>&1; then
	echo "error: forge not found in PATH" >&2
	exit 127
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAPSHOT_FILE="$ROOT/security-tools/gas/.gas-snapshot"

log "Outputs: $SNAPSHOT_FILE"

if [[ $# -eq 0 ]]; then
	exec forge snapshot --match-contract IdeationMarketGasTest --snap "$SNAPSHOT_FILE"
fi

exec forge snapshot --snap "$SNAPSHOT_FILE" "$@"
