#!/usr/bin/env bash
set -euo pipefail

# Purpose: Run Slither static analysis and write a markdown report.

log() {
	if [[ "${VERBOSE:-0}" == "1" ]]; then
		echo "$@" >&2
	fi
}

usage() {
	cat <<'EOF'
Usage:
	bash script/run-slither.sh
	bash script/run-slither.sh [slither args...]

Notes:
	- Default writes/overwrites: security-tools/slither/slither_report.md
	- The default run may exit non-zero if Slither finds issues; the wrapper still produces the report.
	- Outputs: security-tools/slither/slither_report.md

Examples:
	bash script/run-slither.sh
	bash script/run-slither.sh --print human-summary
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

log "Outputs: $ROOT/security-tools/slither/slither_report.md"

if [[ $# -eq 0 ]]; then
	yarn --cwd "$ROOT/security-tools/slither" slither:report || true
	exit 0
fi

exec yarn --cwd "$ROOT/security-tools/slither" slither -- "$@"
