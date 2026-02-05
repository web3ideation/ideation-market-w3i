#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Compares on-chain runtime bytecode for two deployments (often across networks).

Requirements:
  - foundry (cast)

Usage:
  script/compare-contract-code.sh \
    --rpc-a <RPC_URL_A> --addr-a <ADDRESS_A> \
    --rpc-b <RPC_URL_B> --addr-b <ADDRESS_B>

Notes:
  - Prints keccak256 hashes of the deployed (runtime) bytecode.
  - Also prints hashes with Solidity CBOR metadata stripped (best-effort).
  - Attempts to detect common proxies:
      * EIP-1967 implementation slot
      * Gnosis Safe-style proxy singleton at storage slot 0
    If detected, it will also compare the implementation/singleton runtime code.
EOF
}

RPC_A=""
ADDR_A=""
RPC_B=""
ADDR_B=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rpc-a) RPC_A="$2"; shift 2;;
    --addr-a) ADDR_A="$2"; shift 2;;
    --rpc-b) RPC_B="$2"; shift 2;;
    --addr-b) ADDR_B="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

if [[ -z "$RPC_A" || -z "$ADDR_A" || -z "$RPC_B" || -z "$ADDR_B" ]]; then
  usage
  exit 2
fi

if ! command -v cast >/dev/null 2>&1; then
  echo "Missing dependency: cast (foundry)." >&2
  exit 1
fi

addr_norm() {
  # Keep it simple; cast can handle checksum/0x already.
  echo "$1"
}

keccak_hex() {
  local hex="$1"
  # cast keccak accepts hex strings; ensure no newline.
  printf "%s" "$hex" | cast keccak
}

hex_len_bytes() {
  local hex="$1"
  hex="${hex#0x}"
  echo $(( ${#hex} / 2 ))
}

strip_solc_metadata() {
  # Best-effort stripping of Solidity CBOR metadata.
  # Solidity appends: <cbor-metadata><uint16 big-endian metadata_length>
  # We strip metadata_length + 2 bytes.
  python3 - <<'PY' "$1"
import sys

hexstr = sys.argv[1].strip()
if hexstr.startswith('0x'):
    hexstr = hexstr[2:]

try:
    b = bytes.fromhex(hexstr)
except ValueError:
    print('0x' + hexstr)
    sys.exit(0)

if len(b) < 4:
    print('0x' + b.hex())
    sys.exit(0)

meta_len = int.from_bytes(b[-2:], 'big')
if meta_len == 0:
    print('0x' + b.hex())
    sys.exit(0)

total = meta_len + 2
if total >= len(b):
    # Not plausible; leave unchanged
    print('0x' + b.hex())
    sys.exit(0)

meta = b[-total:-2]
if not meta:
    print('0x' + b.hex())
    sys.exit(0)

# CBOR maps often start 0xa1..0xa5 for small maps
if meta[0] < 0xA0 or meta[0] > 0xBF:
    # Doesn't look like CBOR; leave unchanged
    print('0x' + b.hex())
    sys.exit(0)

stripped = b[:-total]
print('0x' + stripped.hex())
PY
}

get_code() {
  local rpc="$1"
  local addr
  addr="$(addr_norm "$2")"
  cast code --rpc-url "$rpc" "$addr"
}

get_storage() {
  local rpc="$1"
  local addr="$2"
  local slot="$3"
  cast storage --rpc-url "$rpc" "$addr" "$slot"
}

extract_addr_from_word() {
  # Input: 0x + 32-byte word. Output: 0x + last 20 bytes (address) or 0x000..0.
  python3 - <<'PY' "$1"
import sys
w = sys.argv[1].strip().lower()
if w.startswith('0x'):
    w = w[2:]
w = w.zfill(64)
addr = w[-40:]
print('0x' + addr)
PY
}

is_zero_addr() {
  [[ "${1,,}" == "0x0000000000000000000000000000000000000000" ]]
}

compare_pair() {
  local label="$1"
  local rpc1="$2"
  local addr1="$3"
  local rpc2="$4"
  local addr2="$5"

  local code1 code2
  code1="$(get_code "$rpc1" "$addr1")"
  code2="$(get_code "$rpc2" "$addr2")"

  local h1 h2 l1 l2
  h1="$(keccak_hex "$code1")"
  h2="$(keccak_hex "$code2")"
  l1="$(hex_len_bytes "$code1")"
  l2="$(hex_len_bytes "$code2")"

  local s1 s2 sh1 sh2
  s1="$(strip_solc_metadata "$code1")"
  s2="$(strip_solc_metadata "$code2")"
  sh1="$(keccak_hex "$s1")"
  sh2="$(keccak_hex "$s2")"

  echo "== $label =="
  echo "A: $addr1"
  echo "  runtime_bytes: $l1"
  echo "  runtime_keccak: $h1"
  echo "  stripped_keccak: $sh1"
  echo "B: $addr2"
  echo "  runtime_bytes: $l2"
  echo "  runtime_keccak: $h2"
  echo "  stripped_keccak: $sh2"

  if [[ "${h1,,}" == "${h2,,}" ]]; then
    echo "RESULT: ✅ runtime bytecode is IDENTICAL"
  elif [[ "${sh1,,}" == "${sh2,,}" ]]; then
    echo "RESULT: ⚠️ differs only in (likely) Solidity metadata/embedded values"
  else
    echo "RESULT: ❌ runtime bytecode differs"
  fi
  echo
}

maybe_compare_proxy_targets() {
  local rpc1="$1"; local addr1="$2"
  local rpc2="$3"; local addr2="$4"

  # EIP-1967 implementation slot:
  # bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1)
  local slot_eip1967_impl
  slot_eip1967_impl="0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"

  local w1 w2 impl1 impl2
  w1="$(get_storage "$rpc1" "$addr1" "$slot_eip1967_impl")"
  w2="$(get_storage "$rpc2" "$addr2" "$slot_eip1967_impl")"
  impl1="$(extract_addr_from_word "$w1")"
  impl2="$(extract_addr_from_word "$w2")"

  if ! is_zero_addr "$impl1" || ! is_zero_addr "$impl2"; then
    echo "Detected EIP-1967 impl slot (non-zero on at least one side):"
    echo "  impl A: $impl1"
    echo "  impl B: $impl2"
    echo
    compare_pair "EIP-1967 implementation (runtime)" "$rpc1" "$impl1" "$rpc2" "$impl2"
  fi

  # Gnosis Safe Proxy pattern: master copy (singleton) is stored at slot 0.
  # This is not standardized, but common for Safe-style multisig proxies.
  local ws1 ws2 sing1 sing2
  ws1="$(get_storage "$rpc1" "$addr1" 0x0)"
  ws2="$(get_storage "$rpc2" "$addr2" 0x0)"
  sing1="$(extract_addr_from_word "$ws1")"
  sing2="$(extract_addr_from_word "$ws2")"

  # Heuristic: ignore if zero.
  if ! is_zero_addr "$sing1" || ! is_zero_addr "$sing2"; then
    echo "Slot-0 singleton/mastercopy (common for Safe-style proxies):"
    echo "  singleton A: $sing1"
    echo "  singleton B: $sing2"
    echo
    compare_pair "Slot-0 singleton/mastercopy (runtime)" "$rpc1" "$sing1" "$rpc2" "$sing2"
  fi
}

echo "Comparing on-chain code via RPC..."
echo

compare_pair "Target contract (runtime)" "$RPC_A" "$ADDR_A" "$RPC_B" "$ADDR_B"
maybe_compare_proxy_targets "$RPC_A" "$ADDR_A" "$RPC_B" "$ADDR_B"
