#!/usr/bin/env bash
set -euo pipefail

# ──────────────────── 1) Rebuild all contracts ─────────────────────────────
forge build --force --silent

# ──────────────────── 2) Extract & find duplicates ────────────────────────
dupes=$(
python3 << 'PY'
import glob, json

seen = set()
dups = set()

def facet_source(path, art):
    # Foundry ≥0.2.0
    if "sourcePath" in art:
        return art["sourcePath"]
    # Foundry ≤0.1.x
    comp = art.get("metadata", {}) \
              .get("settings", {}) \
              .get("compilationTarget", {})
    if isinstance(comp, dict) and comp:
        return next(iter(comp))
    return None

for fn in glob.glob("out/**/*.json", recursive=True):
    art = json.load(open(fn))
    src = facet_source(fn, art)
    if not src or "/facets/" not in src.replace("\\","/"):
        continue

    # pick up selectors from either top-level or evm.methodIdentifiers
    methods = art.get("methodIdentifiers") \
           or art.get("evm", {}).get("methodIdentifiers", {})
    for sel in methods.values():
        if sel in seen:
            dups.add(sel)
        else:
            seen.add(sel)

for sel in sorted(dups):
    print(sel)
PY
)

# ──────────────────── 3) Report & exit ────────────────────────────────────
if [[ -z "$dupes" ]]; then
  echo "✅  No selector clashes among facets."
  exit 0
else
  echo "❌  Selector clash(es) among facets:"
  echo "$dupes"
  exit 1
fi


# Make it executable: chmod +x script/check-selectors.sh
# How to run: script/check-selectors.sh | Exits 0 (success) if no duplicates. Exits 1 and prints the offending selectors if duplicates exist – perfect for CI pipelines.

