# Test Coverage Analysis & Recommendations
**Date:** December 11, 2025  
**Marketplace Version:** Non-custodial with ERC20 support  

## Executive Summary

After thorough analysis of your diamond marketplace implementation and the existing 331 tests, I've identified **critical gaps in test coverage**, particularly around:
1. **ERC20 payment currency support** (completely untested)
2. **CurrencyWhitelistFacet** functionality (no dedicated test file)
3. **Non-custodial edge cases** with ERC20 tokens and ETH
4. **Gas efficiency tests** for ERC20 vs ETH, adding to the IdeationMarketGasTest.t.sol
5. **Attack vectors** specific to ERC20 tokens and sending ETH directly to the seller

## Architecture Understanding

### Current Implementation
Your marketplace has evolved through 3 phases:
1. **Phase 1 (Deleted):** Custodial with proceeds mapping (push-over-pull)
2. **Phase 2 (Deleted):** Added ERC20 support with custody
3. **Phase 3 (Current):** Non-custodial atomic payments for both ETH and ERC20

### Key Mechanisms Analyzed

#### Non-Custodial Payment Flow (IdeationMarketFacet.sol:1027-1105)
```solidity
// ETH: Diamond receives msg.value, immediately forwards to recipients
// ERC20: Diamond uses buyer's approval, transferFrom directly to recipients
// Order: marketplace owner → royalty receiver → seller
```

#### ERC20 Safety (IdeationMarketFacet.sol:1085-1105)
- Custom `_safeTransferFrom` handles non-standard tokens (USDT, XAUt without return values)
- Low-level call avoids ABI decoding issues
- Checks success + optional bool return value

#### Currency Allowlist (CurrencyWhitelistFacet.sol)
- diamondOwner-only curated list prevents malicious tokens
- address(0) = native ETH (always conceptually allowed)
- Swap-and-pop O(1) removal from array
- Existing listings unaffected by allowlist changes

## Current Test Coverage Analysis

### ✅ Well-Covered Areas

1. **ETH-based marketplace operations** (204 tests in IdeationMarketDiamondTest)
   - Create, purchase, update, cancel listings
   - ERC721 and ERC1155 support
   - Partial buys
   - NFT swaps with ETH
   - Buyer whitelisting
   - Collection whitelisting

2. **Diamond architecture** (25 tests)
   - DiamondCutFacetTest (12)
   - LibDiamondEdgesTest (13)
   - Facet management, upgrades, storage isolation

3. **Security** (24 attack vector tests)
   - Reentrancy prevention
   - Double-sell prevention
   - Token burn scenarios
   - Malicious NFT contracts
   - But **ONLY for ETH payments**

4. **Pause mechanism** (28 tests)
   - Comprehensive pause/unpause coverage

5. **Non-custodial invariant** (2 tests)
   - `invariant_DiamondBalanceIsZero()` with 128k calls
   - But **ONLY tests ETH**, not ERC20

6. **Gas benchmarks** (8 tests)
   - All operations under budget
   - But **ONLY for ETH**

### ❌ Critical Gaps

#### 1. **ZERO ERC20 Tests** 🚨🚨🚨
**Finding:** All 331 tests use `address(0)` (ETH) for the currency parameter.
```solidity
// Every single test does this:
address(0), // currency (ETH)
```

**Missing Coverage:**
- ERC20 listing creation
- ERC20 purchases
- ERC20 payment distribution (marketplace fee, royalties, seller proceeds)
- ERC20 with buyer whitelisting
- ERC20 with NFT swaps
- ERC20 partial buys
- ERC20 with pausable operations
- Mixing ETH and ERC20 listings in same contract

#### 2. **CurrencyWhitelistFacet Untested** 🚨🚨
**Finding:** No dedicated test file for `CurrencyWhitelistFacet.sol`

**Missing Coverage:**
- `addAllowedCurrency()` 
- `removeAllowedCurrency()`
- Events: `CurrencyAllowed`, `CurrencyRemoved`
- Ownership enforcement
- Double-add prevention
- Remove non-allowed currency
- Array management (swap-and-pop logic)
- Getter functions: `isCurrencyAllowed()`, `getAllowedCurrencies()`
- Creating listings with non-allowed currency (should revert)
- Removing currency doesn't affect existing listings
- Edge case: max currencies in allowlist

#### 3. **ERC20 Attack Vectors** 🚨
**Existing:** 24 attack tests, but all ETH-only

**Missing:**
- Fee-on-transfer token attempts (should be blocked by curation)
- Rebasing token attempts (e.g., stETH-like)
- Malicious ERC20 that reverts on transfer
- ERC20 with pausable transfers
- Non-standard ERC20 (no return value like USDT)
- ERC20 reentrancy via token hooks
- Insufficient approval scenarios
- Approval frontrunning
- ERC20 balance changes between listing and purchase

#### 4. **ERC20 Payment Distribution Edge Cases** 🚨
**Critical Scenarios:**
- Royalty payment in ERC20
- 100% fee in ERC20 (seller gets 0 tokens)
- Rounding errors with ERC20 decimals (6 vs 18)
- ERC20 transfer failure mid-distribution (marketplace fee succeeds, seller fails)
- Gas optimization: ETH vs ERC20 costs
- Multiple recipients with tiny amounts

#### 5. **ERC20 Front-Running Protection**
**Current:** Tests check `expectedPrice`, `expectedCurrency`, etc.

**Missing:**
- Specific tests for `expectedCurrency` protection with ERC20
- Listing updated ETH→ERC20 between user's transaction submission and execution
- ERC20 price manipulation scenarios

#### 6. **ERC20 Non-Custodial Invariants**
**Current:** `invariant_DiamondBalanceIsZero()` only tests ETH balance

**Missing:**
- Invariant: Diamond's ERC20 balance should ALWAYS be 0
- Fuzz test with random ERC20 tokens
- Verify no ERC20 "stuck" in contract after any operation

#### 7. **Mixed Currency Scenarios**
**Missing:**
- User has ETH listing + ERC20 listing for different NFTs
- Purchase ERC20 listing with msg.value > 0 (should revert)
- Gas comparison: ETH purchase vs ERC20 purchase
- Events emitted with correct currency parameter

#### 8. **ERC20 Integration with Existing Features**
**Missing:**
- ERC20 + Partial Buys (unit price calculation in ERC20)
- ERC20 + NFT Swaps (swap NFT, pay additional ERC20)
- ERC20 + Buyer Whitelist
- ERC20 + Pause/Unpause
- ERC20 listings + Collection de-whitelisting + cleanListing

#### 9. **ERC20 Update/Cancel Flows**
**Missing:**
- Create listing in ETH, update to ERC20
- Create listing in ERC20, update to different ERC20
- Create listing in ERC20, update to ETH
- Cancel ERC20 listing (no payment involved, should work)

#### 10. **Real-World ERC20 Tokens**
**Missing:** Tests with realistic token behaviors:
- USDT (no return value, 6 decimals)
- USDC (6 decimals)
- DAI (18 decimals)
- WETH (18 decimals)
- Token with 0 decimals
- Token with 30 decimals

## Recommended Testing Strategy

### Phase 1: CurrencyWhitelist Foundation (Critical) 🔴
**Goal:** Test new CurrencyWhitelistFacet completely

**CRITICAL CONTEXT YOU MUST UNDERSTAND FIRST:**
1. **DiamondInit.sol initializes 76 currencies** (address(0) for ETH + 75 ERC20 tokens)
2. **Swap-and-pop algorithm** updates BOTH `allowedCurrenciesArray` AND `allowedCurrenciesIndex` mapping
3. **Index mapping** stores the array position; must stay in sync after removals
4. **Existing listings** continue to work even after currency removed from allowlist
5. **Payment distribution** is atomic and non-custodial (diamond balance must stay 0)

**Create CurrencyWhitelistFacetTest.t.sol** (~16-18 tests)

**Basic Functionality (5 tests):**
- ✅ Add currency as diamondOwner
- ✅ Remove currency as diamondOwner  
- ✅ Revert when non-diamondOwner tries add/remove
- ✅ Events: CurrencyAllowed, CurrencyRemoved emitted correctly
- ✅ Getter functions work: isCurrencyAllowed(), getAllowedCurrencies()

**Error Cases (3 tests):**
- ✅ Double-add reverts with CurrencyWhitelist__AlreadyAllowed error
- ✅ Remove non-existent reverts with CurrencyWhitelist__NotAllowed error
- ✅ Create listing with non-allowed currency reverts with IdeationMarket__CurrencyNotAllowed

**Initialization & Pre-existing State (2 tests):**
- ✅ **CRITICAL:** ETH (address(0)) is initialized and allowed by default from DiamondInit
- ✅ **CRITICAL:** Can remove ETH from allowlist (it's not hardcoded) and new ETH listings fail

**Swap-and-Pop Array Integrity (4 tests):**
- ✅ Remove middle element: array compacts correctly, no holes
- ✅ Remove last element: array shrinks correctly
- ✅ Remove only added element: array returns to original state
- ✅ **CRITICAL:** Index mapping (`allowedCurrenciesIndex`) stays correct after swap-and-pop

**Listing Lifecycle with Currency Changes (2 tests):**
- ✅ Remove currency BEFORE listing: new listings in that currency fail
- ✅ Remove currency AFTER listing: existing listings still purchasable (backward compatibility)

**Payment Distribution with ERC20 (2 tests):**
- ✅ **CRITICAL:** ERC20 purchase after currency removal: verify atomic payment distribution (marketplace fee → royalty → seller)
- ✅ **CRITICAL:** Diamond ERC20 balance always 0 after purchase (non-custodial invariant)

### Phase 2: ERC20 Core Flows (Critical) 🔴
**Goal:** Verify marketplace works with ERC20 tokens end-to-end without custody

**Critical Context:**
- Collections must be whitelisted before listing creation
- `expectedCurrency` guards against front-running; must match storage
- ERC20 purchases require `msg.value == 0` and sufficient `allowance`
- Diamond must not hold ERC20 after any operation (non-custodial)

**Create ERC20MarketplaceTest.t.sol** (~10-12 tests)
- ✅ Create ERC721 listing in ERC20 (with collection whitelisted)
- ✅ Create ERC1155 listing in ERC20 (holder/approval paths)
- ✅ Purchase ERC721 listing with ERC20 (buyer approves marketplace)
- ✅ Purchase ERC1155 listing with ERC20 (full quantity)
- ✅ Purchase with `msg.value > 0` reverts (WrongPaymentCurrency)
- ✅ Purchase with insufficient approval reverts
- ✅ Update listing: ETH→ERC20, ERC20→ETH, ERC20A→ERC20B (verify currency persisted)
- ✅ Cancel ERC20 listing (no payment involved)
- ✅ Expected currency mismatch protection (front-running): update currency and assert revert
- ✅ Events include correct `currency` address on create/update/purchase
- ✅ Diamond ERC20 balance remains 0 across create/purchase/update/cancel

### Phase 3: ERC20 Payment Distribution (Critical) 🔴
**Goal:** Verify atomic non-custodial push payments with fees and royalties

**Critical Context:**
- Fee denominator is 100_000; fee snapshot per listing (`feeRate`)
- Royalty via ERC-2981 deducted from seller proceeds; may be 0 or receiver=0
- Payment order: marketplace owner → royalty receiver → seller (CEI pattern)
- `_safeTransferFrom` handles non-standard tokens (no return, false return)

**Create ERC20PaymentDistributionTest.t.sol** (~8-10 tests)
- ✅ Marketplace fee paid in ERC20 to diamondOwner (exact math)
- ✅ Seller proceeds paid in ERC20 to seller (fee deducted)
- ✅ Royalty paid in ERC20 to royalty receiver (when applicable)
- ✅ All three recipients in one purchase (complete flow) with assertions
- ✅ Diamond ERC20 balance always 0 after purchase
- ✅ 100% fee edge case (seller gets 0 ERC20)
- ✅ Tiny amounts: exact distribution without dust
- ✅ Payment order and failure propagation: if a transfer fails, tx reverts
- ✅ Non-standard ERC20 handling: token returns no value (simulate USDT)
- ✅ Verify fee snapshot remains unchanged after update

### Phase 4: ERC20 Security & Attack Vectors (Critical) 🔴🔴🔴
**Goal:** Harden against malicious tokens and exploits, verify guardrails

**Critical Context:**
- `nonReentrant` modifier protects purchase path
- Currency allowlist is the first defense (should block fee-on-transfer/rebasing tokens by policy)
- `_safeTransferFrom` must revert on failure or false return

**Create ERC20AttackVectorTest.t.sol** (~14-18 tests)
- ✅ Malicious ERC20 that reverts on transferFrom (purchase reverts)
- ✅ ERC20 that returns false (not revert) → `_safeTransferFrom` must revert
- ✅ Non-standard ERC20 with no return value: transfers succeed if call returns
- ✅ Simulated reentrancy attempt via ERC20 hook (ensure `nonReentrant` blocks)
- ✅ Insufficient buyer approval (not enough tokens) → purchase reverts
- ✅ Buyer reduces balance after approval before purchase → purchase reverts
- ✅ Double-spend attempt using allowance changes → guarded by exact checks
- ✅ Transfer failure mid-distribution causes whole tx revert (no partial payments)
- ✅ Front-running currency: update listing currency, buyer passes stale `expectedCurrency` → reverts
- ✅ Decimals coverage: 0, 6, 18, 30 decimals tokens (math correctness)
- ✅ Very large amounts near uint256 limits where feasible
- ✅ ERC1155 partial buy with ERC20: unit price calculation exactness
- ✅ Swap with ERC20 payment: verify transfers for desired and listed assets
- ✅ Pause + ERC20 operations: creation and purchase reverts when paused

### Phase 5: ERC20 Non-Custodial Invariants (Critical) 🔴
**Goal:** Prove diamond never holds ERC20 tokens and payment math always balances

**Create ERC20InvariantTest.t.sol** (~3-4 invariants)
- ✅ Invariant: Diamond ERC20 balance always 0 across operations
- ✅ Invariant: Sum(fee + royalty + sellerProceeds) == purchasePrice for all purchases
- ✅ Invariant: No ERC20 remains after cancel/update flows
- ✅ Handler covers multi-token scenarios, mixed ETH/ERC20, swaps and partial buys

### Phase 6: Edge Cases (Medium Priority) 🟡
**Goal:** Cover corner cases and mixed scenarios for realism

**Add to existing test files** (~8-10 tests)
- ✅ Mix ETH and ERC20 listings in same contract and run purchases back-to-back
- ✅ Update listing: switch currency mid-listing (ensure front-run guards work)
- ✅ Create listing in non-allowed currency (reverts) including ETH if removed
- ✅ Tiny ERC20 amounts (1 unit) and rounding behavior remains exact
- ✅ Buyer whitelist + ERC20 purchase path
- ✅ Collection de-whitelist + ERC20 listing + `cleanListing` behavior checked
- ✅ ERC20 with royalty (ERC2981) - verify fee and royalty both transfer
- ✅ Multiple ERC20 tokens in allowlist, purchase with each, diamond balance always 0
- ✅ Getter facet currency list size checks after multiple add/remove operations

## Estimated Test Count (REVISED - Lean Approach)

**Philosophy:** Marketplace logic already tested with ETH. We need to verify:
1. ERC20 works the same way (smoke tests for key flows)
2. ERC20-specific issues (token types, approvals, attack vectors)
3. Non-custodial atomicity for ERC20

| Category | Tests | Priority | Rationale |
|----------|-------|----------|-----------|
| CurrencyWhitelistFacet | 12-15 | 🔴 Critical | New facet, needs full coverage |
| ERC20 Core Flows | 8-10 | 🔴 Critical | Create, purchase, update, cancel with ERC20 |
| ERC20 Payment Distribution | 6-8 | 🔴 Critical | Atomic push payments (marketplace fee, royalty, seller) |
| ERC20 Attack Vectors | 12-15 | 🔴🔴 Critical | Malicious tokens, reentrancy, approval issues |
| ERC20 Non-Custodial Invariant | 2-3 | 🔴 Critical | Diamond balance always 0, no stuck tokens |
| Non-Standard Tokens | 5-6 | 🔴 High | USDT (no return), various decimals |
| ERC20 Edge Cases | 6-8 | 🟡 Medium | Mixed ETH/ERC20, currency switches, tiny amounts |
| **TOTAL NEW TESTS** | **~51-65** | | **Much more reasonable!** |
| **Current Tests** | **331** | |
| **Final Test Count** | **~382-396** | | **~15-20% increase** |

## Risk Assessment

### Current Risk Level: **HIGH** 🔴

**Rationale:**
- **Core feature (ERC20) has ZERO test coverage**
- Smart contract handling real money (potentially millions in ERC20 tokens)
- Complex payment distribution logic untested with ERC20
- Attack surface expanded but not validated
- No fuzzing/invariant testing for ERC20 paths

### Post-Testing Risk Level: **LOW** 🟢 (after implementing above)

## Quick Validation (Optional - Start Here)

If you want to quickly validate ERC20 works before full test suite:

### **Single Smoke Test (15 minutes)**
Add one test to an existing file that:
- Deploys MockERC20, adds to currency whitelist
- Creates ERC721 listing in ERC20
- Buyer approves + purchases with ERC20
- Asserts: marketplace fee, seller proceeds, diamond balance = 0
- **If this passes, your ERC20 implementation likely works!**

Then proceed with full test suite for robustness.

## Test Helper Utilities Needed

You'll need these utilities in `MarketTestBase.t.sol`:

```solidity
// MockERC20 with configurable behavior
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    uint8 public decimals;
    bool public shouldRevert;
    bool public returnsBool; // false = USDT-like
    
    function mint(address to, uint256 amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// Helper function to create ERC20 listing
function createERC20Listing(..., address currency, uint256 amount) internal;

// Helper to approve and purchase with ERC20
function purchaseWithERC20(..., address currency) internal;
```

## Conclusion & Priorities

Your marketplace has excellent test coverage for ETH-based operations and diamond architecture. The ERC20 feature is **functionally the same logic**, we just need to verify:

1. **Token transfer mechanism works** (ERC20 instead of ETH)
2. **Atomic non-custodial payments work** (no tokens stuck)
3. **Security against malicious tokens** (reverts, reentrancy, non-standard)

### Minimum Critical Path (~32-38 tests, 2 sessions)
- **Session 1:** CurrencyWhitelist + Core Flows (20-25 tests)
- **Session 2:** Payment Distribution + Security (12-13 tests)

### Complete Coverage (~48-59 tests, 4 sessions)
- Add Session 3 (Attack Vectors) and Session 4 (Edge Cases)

**Recommendation:** Start with Session 1 to establish foundation, then assess.

---

## Next Steps

**Your choice - pick an approach:**

### Option A: Sequential Deep Dive
I create each test file one by one, you review, we iterate.

### Option B: Parallel Batch
Give me 2-3 prompts in parallel, I create multiple test files simultaneously.

### Option C: Guided Implementation
You tell me which specific scenario concerns you most, we start there.

### Option D: Quick Smoke Test First
I create ONE comprehensive smoke test proving ERC20 works end-to-end, then we expand.

**What's your preference?**
