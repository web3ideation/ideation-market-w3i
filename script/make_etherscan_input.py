#!/usr/bin/env python3

# Usage:
#   python3 script/make_etherscan_input.py src/facets/VersionFacet.sol:VersionFacet ./etherscan/VersionFacet.standard-input.json
# for manual etherscan verification input generation.
# If no 2nd arg is given, defaults to /tmp/etherscan-input.json

# To generate for all facets + diamond dispatcher:
#   python3 script/make_etherscan_input.py --all ./etherscan

import json, subprocess, sys, os, re

def _usage() -> str:
    return (
        "Usage:\n"
        "  python3 script/make_etherscan_input.py <file.sol:ContractName> [out.json]\n"
        "  python3 script/make_etherscan_input.py --all [out_dir]\n\n"
        "Examples:\n"
        "  python3 script/make_etherscan_input.py src/facets/VersionFacet.sol:VersionFacet ./etherscan/VersionFacet.standard-input.json\n"
        "  python3 script/make_etherscan_input.py --all ./etherscan\n"
    )


def _run_forge_inspect(fq: str, field: str) -> str:
    return subprocess.check_output(["forge", "inspect", fq, field]).decode().strip()


def _parse_metadata(raw: str) -> dict:
    # Normalize to dict (some Foundry versions return a quoted JSON string)
    if raw.startswith("{"):
        return json.loads(raw)
    return json.loads(json.loads(raw))


def _extract_solc_version(meta: dict) -> str:
    # solc version is typically stored in the standard solc metadata under compiler.version
    compiler = meta.get("compiler") or {}
    version = compiler.get("version")
    if isinstance(version, str) and version:
        return version
    # Some toolchains may nest differently; keep this resilient.
    for key in ("solcVersion", "solc", "version"):
        v = meta.get(key)
        if isinstance(v, str) and v:
            return v
    return "<unknown>"


def _build_standard_input(meta: dict) -> dict:
    # Standard-JSON "settings": keep only allowed keys, add sane defaults
    raw_settings = meta.get("settings", {})
    allow = {"optimizer", "evmVersion", "metadata", "libraries", "viaIR", "remappings", "outputSelection"}
    settings = {k: v for k, v in raw_settings.items() if k in allow}

    # Ensure outputSelection so solc returns bytecode/abi predictably
    settings.setdefault("outputSelection", {"*": {"*": ["abi", "evm.bytecode", "evm.deployedBytecode"]}})

    language = meta.get("language", "Solidity")

    # Inline source contents for every file listed in metadata.sources
    sources = {}
    repo_root = os.getcwd()
    for path in meta.get("sources", {}).keys():
        fs_path = os.path.normpath(os.path.join(repo_root, path))
        if not os.path.isfile(fs_path):
            fs_path = os.path.normpath(path)
        with open(fs_path, "r", encoding="utf-8") as f:
            sources[path] = {"content": f.read()}

    return {"language": language, "settings": settings, "sources": sources}


def _write_json(path: str, obj: dict) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2)


def _print_verification_hints(fq: str, meta: dict) -> None:
    solc_version = _extract_solc_version(meta)
    settings = meta.get("settings", {}) or {}
    optimizer = settings.get("optimizer", {}) or {}
    optimizer_enabled = optimizer.get("enabled")
    optimizer_runs = optimizer.get("runs")
    evm_version = settings.get("evmVersion")
    via_ir = settings.get("viaIR")
    bytecode_hash = (settings.get("metadata") or {}).get("bytecodeHash")

    print("\n=== Etherscan verification hints ===")
    print(f"Contract: {fq}")
    print(f"solc: {solc_version}")
    if evm_version is not None:
        print(f"evmVersion: {evm_version}")
    if via_ir is not None:
        print(f"viaIR: {via_ir}")
    if optimizer_enabled is not None:
        print(f"optimizer.enabled: {optimizer_enabled}")
    if optimizer_runs is not None:
        print(f"optimizer.runs: {optimizer_runs}")
    if bytecode_hash is not None:
        print(f"metadata.bytecodeHash: {bytecode_hash}")
    print("===================================\n")


def _parse_contract_names_from_file(sol_path: str) -> list[str]:
    # Very small parser: grab `contract X` declarations.
    # (Facets are expected to be contracts; we intentionally skip interfaces/libraries.)
    with open(sol_path, "r", encoding="utf-8") as f:
        src = f.read()
    # Strip block comments to avoid accidental matches.
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.DOTALL)
    names = []
    for line in src.splitlines():
        # remove line comments
        line = line.split("//", 1)[0]
        m = re.match(r"^\s*contract\s+([A-Za-z_]\w*)\b", line)
        if m:
            names.append(m.group(1))
    return names


def _generate_one(fq: str, out_path: str) -> None:
    raw = _run_forge_inspect(fq, "metadata")
    meta = _parse_metadata(raw)
    std_input = _build_standard_input(meta)

    _write_json(out_path, std_input)
    _print_verification_hints(fq, meta)

    # Also write a small sidecar with the exact compiler version/settings for easy copy-paste.
    info_path = out_path.replace(".standard-input.json", ".verification-info.json")
    solc_version = _extract_solc_version(meta)
    info = {
        "contract": fq,
        "solc": solc_version,
        "settings": meta.get("settings", {}),
    }
    _write_json(info_path, info)

    print(out_path)


def _generate_all(out_dir: str) -> None:
    repo_root = os.getcwd()
    facets_dir = os.path.join(repo_root, "src", "facets")
    diamond_file = os.path.join(repo_root, "src", "IdeationMarketDiamond.sol")

    targets: list[tuple[str, str]] = []

    # Diamond dispatcher
    if os.path.isfile(diamond_file):
        for name in _parse_contract_names_from_file(diamond_file):
            rel = os.path.relpath(diamond_file, repo_root)
            fq = f"{rel}:{name}"
            out_path = os.path.join(out_dir, f"{name}.standard-input.json")
            targets.append((fq, out_path))

    # Facets
    if os.path.isdir(facets_dir):
        for root, _, files in os.walk(facets_dir):
            for fn in files:
                if not fn.endswith(".sol"):
                    continue
                sol_path = os.path.join(root, fn)
                rel = os.path.relpath(sol_path, repo_root)
                for name in _parse_contract_names_from_file(sol_path):
                    fq = f"{rel}:{name}"
                    out_path = os.path.join(out_dir, f"{name}.standard-input.json")
                    targets.append((fq, out_path))

    if not targets:
        raise SystemExit("No contracts found to generate inputs for.")

    # Generate deterministically (stable order)
    targets.sort(key=lambda t: t[0])
    for fq, out_path in targets:
        _generate_one(fq, out_path)


def main() -> None:
    if len(sys.argv) == 1:
        print(_usage())
        raise SystemExit(2)

    if sys.argv[1] in {"-h", "--help"}:
        print(_usage())
        return

    if sys.argv[1] == "--all":
        out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.getcwd(), "etherscan")
        _generate_all(out_dir)
        return

    fq = sys.argv[1]
    out_path = sys.argv[2] if len(sys.argv) > 2 else "/tmp/etherscan-input.json"
    _generate_one(fq, out_path)


if __name__ == "__main__":
    main()
