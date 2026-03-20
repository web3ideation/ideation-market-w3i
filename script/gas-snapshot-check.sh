#!/usr/bin/env bash
set -euo pipefail

# Purpose: Check the pinned Foundry gas snapshot (regression detector).

log() {
	if [[ "${VERBOSE:-0}" == "1" ]]; then
		echo "$@" >&2
	fi
}

usage() {
	cat <<'EOF'
Usage:
	bash script/gas-snapshot-check.sh
	bash script/gas-snapshot-check.sh --refresh-and-check
	bash script/gas-snapshot-check.sh [forge snapshot args...]

Notes:
	- Default checks only IdeationMarketGasTest against the pinned snapshot.
	- Enforces a 5% tolerance window against the pinned snapshot baseline.
	- `--refresh-and-check` first regenerates snapshot via gas-snapshot-update.sh,
	  then runs the regression check (useful for local workflows).
	- Snapshot file lives at security-tools/gas/.gas-snapshot.
	- Outputs: security-tools/gas/.gas-snapshot (read)

Examples:
	bash script/gas-snapshot-check.sh
	bash script/gas-snapshot-check.sh --match-contract IdeationMarketGasTest
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
	usage
	exit 0
fi

REFRESH_FIRST=0
FORGE_ARGS=()
for arg in "$@"; do
	if [[ "$arg" == "--refresh-and-check" ]]; then
		REFRESH_FIRST=1
		continue
	fi
	FORGE_ARGS+=("$arg")
done

if ! command -v forge >/dev/null 2>&1; then
	echo "error: forge not found in PATH" >&2
	exit 127
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAPSHOT_FILE="$ROOT/security-tools/gas/.gas-snapshot"
GAS_TOLERANCE="${GAS_TOLERANCE:-5}"

log "Outputs: $SNAPSHOT_FILE"

if grep -Eq '1844674407[0-9]{10,}' "$SNAPSHOT_FILE"; then
	echo "error: gas snapshot appears corrupted (wrapped uint64-like values detected)" >&2
	echo "hint: restore security-tools/gas/.gas-snapshot from a known-good CI baseline" >&2
	exit 1
fi

if [[ "$REFRESH_FIRST" == "1" ]]; then
	bash "$ROOT/script/gas-snapshot-update.sh" "${FORGE_ARGS[@]}"
fi

if [[ ${#FORGE_ARGS[@]} -eq 0 ]]; then
	exec forge snapshot --match-contract IdeationMarketGasTest --tolerance "$GAS_TOLERANCE" --check "$SNAPSHOT_FILE"
fi

exec forge snapshot --tolerance "$GAS_TOLERANCE" --check "$SNAPSHOT_FILE" "${FORGE_ARGS[@]}"
