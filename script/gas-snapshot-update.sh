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
TMP_SNAPSHOT="$(mktemp)"

cleanup() {
	rm -f "$TMP_SNAPSHOT"
}
trap cleanup EXIT

log "Outputs: $SNAPSHOT_FILE"

if [[ $# -eq 0 ]]; then
	forge snapshot --match-contract IdeationMarketGasTest --snap "$TMP_SNAPSHOT"
else
	forge snapshot --snap "$TMP_SNAPSHOT" "$@"
fi

if grep -Eq '1844674407[0-9]{10,}' "$TMP_SNAPSHOT"; then
	echo "error: generated gas snapshot appears corrupted (wrapped uint64-like values detected)" >&2
	echo "hint: run snapshot update under the same Foundry toolchain used in CI" >&2
	exit 1
fi

mv "$TMP_SNAPSHOT" "$SNAPSHOT_FILE"
echo "Updated gas snapshot: $SNAPSHOT_FILE"
