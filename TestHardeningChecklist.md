# Test Hardening Checklist (P0/P1/P2)

Status (2026-03-11): P0 items 1, 2, 3, and 4 are completed. P1 items 5, 6, and 7 are completed. P2 items 8 and 9 are completed.

This checklist covers only the targeted fuzz/invariant suites:

- `test/InvariantTest.t.sol`
- `test/StorageCollisionTest.t.sol`
- `test/PauseFacetTest.t.sol` (`testFuzz_*` only)
- `security-tools/echidna/Harness.sol` (`echidna_*` only)

## P0 (Must Do Before Production)

### 1) Remove vacuity from `StorageCollisionInvariant`

Files:

- `test/MarketTestBase.t.sol`
- `test/StorageCollisionTest.t.sol`

Changes:

- Add success/progress counters to `SellerHandler` and `BuyerHandler` for real state-changing operations:
  - successful creates
  - successful updates
  - successful whitelist add/remove
  - successful purchases
- Expose a small read API from handlers to read those counters.
- In `StorageCollisionInvariant.invariant_NoDriftOnForeignState()`, keep existing canary assertions and add a progress assertion requiring at least one successful operation in campaign.

Acceptance:

- Invariant fails if campaign is all reverts/no-ops.
- Invariant still passes with normal handler activity.

---

### 2) Replace Echidna placeholder property

File:

- `security-tools/echidna/Harness.sol`

Changes:

- Replace `echidna_collections_still_whitelisted()` (currently always `true`) with a meaningful property.
- Recommended replacement: assert whitelist enforcement behavior rather than static whitelist membership.
- Add/keep explicit bypass flags to indicate invalid success paths.

Acceptance:

- No `echidna_*` property is a permanent `return true` placeholder.

---

### 3) Set production-viable baseline run budgets

Files:

- `foundry.toml`
- `security-tools/echidna/echidna.yaml`

Changes:

- Add Foundry fuzz and invariant sections:

```toml
[fuzz]
runs = 10000

[invariant]
runs = 2000
depth = 120
```

- Raise Echidna campaign baseline:

```yaml
testLimit: 2000000
seqLen: 120
shrinkLimit: 2000
```

Acceptance:

- Local baseline gives materially higher confidence than default 256 runs.

---

### 4) Add seed reproducibility policy

Files:

- `README.md`
- optionally `script/run-echidna.sh` usage text

Changes:

- Document exact commands for fixed-seed reruns for:
  - Foundry fuzz
  - Foundry invariant
  - Echidna
- Document where failing reproducers are stored and how to replay.

Acceptance:

- Every randomized failure can be replayed deterministically.

## P1 (Strongly Recommended)

### 5) Strengthen `PauseFacetTest` fuzz suite

File:

- `test/PauseFacetTest.t.sol`

Changes:

- Keep current two fuzz tests.
- Add at least two richer `testFuzz_*` tests with randomized sequences and role permutations:
  - role/action sequence fuzz: pause/unpause/create/purchase/update/cancel
  - listing mode fuzz: ETH vs ERC20, ERC721 vs ERC1155 partial, whitelist on/off
- Include explicit invariants in each test for expected pause behavior and no unauthorized transitions.

Acceptance:

- Fuzz suite validates more than a single-address or single-bool input path.

---

### 6) Expand Foundry invariant coverage for listing consistency

Files:

- `test/InvariantTest.t.sol`
- `test/MarketTestBase.t.sol` (if helper data needed)

Changes:

- Add at least one invariant for active listing mapping consistency (especially ERC721 active listing pointer validity).
- Add at least one invariant for authorization-sensitive state drift under handler calls.
- Include non-vacuity guard(s), similar to `successfulERC20Purchases > 0`.

Acceptance:

- Invariants cover custody/accounting plus core listing-state correctness.

---

### 7) Improve Echidna activity observability

File:

- `security-tools/echidna/Harness.sol`

Changes:

- Add lightweight counters for attempted and successful key actions:
  - create
  - update
  - purchase
  - pause/unpause
- Gate selected properties on minimum activity thresholds to reduce passive passes.

Acceptance:

- Passing campaign demonstrates exercised behavior, not just absence of crashes.

## P2 (Operational Hardening)

### 8) Add staged test profiles

Files:

- `foundry.toml`
- `security-tools/echidna/echidna.yaml`
- optionally add `security-tools/echidna/echidna.nightly.yaml`

Changes:

- Define PR/nightly/release profiles and document how to run each.

Suggested profile targets:

- PR:
  - Foundry fuzz runs: 3000
  - Foundry invariant runs/depth: 500/60
  - Echidna testLimit/seqLen: 300000/50
- Nightly:
  - Foundry fuzz runs: 20000
  - Foundry invariant runs/depth: 3000/150
  - Echidna testLimit/seqLen: 3000000/150
- Release:
  - Foundry fuzz runs: 50000
  - Foundry invariant runs/depth: 8000/250
  - Echidna testLimit/seqLen: 10000000/250

---

### 9) Multi-seed campaign matrix

Files:

- CI workflow files (if/when added)
- `README.md`

Changes:

- Run multiple seeds in nightly/release lanes:
  - minimum 10 seeds nightly
  - minimum 20 seeds pre-release
- Save and retain failing seeds/reproducers.

Acceptance:

- Confidence is not dependent on a single lucky random stream.

## Command Checklist (Validation)

Foundry targeted checks:

```bash
forge test --match-contract IdeationMarketInvariantTest -vv
forge test --match-contract StorageCollisionInvariant -vv
forge test --match-test "testFuzz_OnlyOwnerCanPause|testFuzz_PauseStateConsistent" -vv
```

Echidna targeted check:

```bash
bash script/run-echidna.sh --test-limit 2000000 --seq-len 120 --format text
```

## Definition Of Done

- No vacuous placeholder properties in target suites.
- Foundry invariants include progress guards where needed.
- Fuzz/invariant budgets are explicitly configured (not defaults).
- Echidna and Foundry randomized runs are reproducible via documented seeds.
- All P0 items completed and passing before production release.