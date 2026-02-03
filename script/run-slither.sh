#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ $# -eq 0 ]]; then
	yarn --cwd "$ROOT/security-tools/slither" slither:report || true
	exit 0
fi

exec yarn --cwd "$ROOT/security-tools/slither" slither -- "$@"
