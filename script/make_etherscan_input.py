#!/usr/bin/env python3
import json, subprocess, sys, os

# Usage:
#   python3 scripts/make_etherscan_input.py src/facets/VersionFacet.sol:VersionFacet ./etherscan/VersionFacet.standard-input.json
# for manual etherscan verification input generation.
# If no 2nd arg is given, defaults to /tmp/etherscan-input.json

fq = sys.argv[1] if len(sys.argv) > 1 else "src/facets/VersionFacet.sol:VersionFacet"
out_path = sys.argv[2] if len(sys.argv) > 2 else "/tmp/etherscan-input.json"

# 1) Ask Foundry for compiler metadata (works on older Foundry)
raw = subprocess.check_output(["forge", "inspect", fq, "metadata"]).decode().strip()

# Normalize to dict (some Foundry versions return a quoted JSON string)
if raw.startswith("{"):
    meta = json.loads(raw)
else:
    meta = json.loads(json.loads(raw))

# 2) Standard-JSON "settings": keep only allowed keys, add sane defaults
raw_settings = meta.get("settings", {})
allow = {"optimizer", "evmVersion", "metadata", "libraries", "viaIR", "remappings", "outputSelection"}
settings = {k: v for k, v in raw_settings.items() if k in allow}

# Ensure outputSelection so solc returns bytecode/abi predictably
settings.setdefault("outputSelection", {"*": {"*": ["abi", "evm.bytecode", "evm.deployedBytecode"]}})

# Ensure metadata uses literal content (robust verification)
md = settings.setdefault("metadata", {})
# this line caused a tiny offset in bytecode for the ipfs bit, so I commented it out: md["useLiteralContent"] = True

language = meta.get("language", "Solidity")

# 3) Inline source contents for every file listed in metadata.sources
sources = {}
repo_root = os.getcwd()
for path in meta.get("sources", {}).keys():
    fs_path = os.path.normpath(os.path.join(repo_root, path))
    if not os.path.isfile(fs_path):
        fs_path = os.path.normpath(path)
    with open(fs_path, "r", encoding="utf-8") as f:
        sources[path] = {"content": f.read()}

# 4) Emit Standard-JSON "input"
std_input = {"language": language, "settings": settings, "sources": sources}

os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(std_input, f, indent=2)

print(out_path)
