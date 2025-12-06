# Test Migration Notes: Multi-Currency + Non-Custodial

## Quick Reference

### Key Changes
1. **Currency parameter** added after `price` in all functions
2. **No proceeds mapping** - check balances directly (before/after snapshots)
3. **No withdrawal function** - payments are atomic
4. **CurrencyWhitelistFacet** added - must deploy and whitelist ETH

### Function Signatures
```solidity
// createListing: add currency after price
market.createListing(tokenAddr, tokenId, erc1155Holder, price, address(0), ...);

// purchaseListing: add expectedCurrency after expectedPrice  
market.purchaseListing{value: price}(listingId, price, address(0), ...);

// updateListing: add newCurrency after newPrice
market.updateListing(listingId, newPrice, address(0), ...);
```

---

## Critical Gotchas

### ⚠️ ERC-1155 Price is TOTAL, Not Per-Unit
```solidity
// ❌ WRONG: quantity * 1 ether (makes each unit cost 1 ether)
// ✅ RIGHT: 1 ether (total for ALL units)
market.createListing(..., 1 ether, ..., quantity, ...);
```

### ⚠️ Balance Checks, Not Proceeds
```solidity
// ❌ OLD: uint256 proceeds = market.getProceeds(seller);
// ✅ NEW:
uint256 balBefore = seller.balance;
// ... purchase ...
assertEq(seller.balance - balBefore, expectedProceeds);
```

### ⚠️ Remove Withdrawal Code
- Delete `market.withdraw()` calls
- Delete `getProceeds()` checks  
- Delete `ReentrantWithdrawer` mock contracts

---

## Lessons Learned

### Batch 4 - ERC1155 Tests
- **Non-custodial payment model**: Replaced `getProceeds()` and `withdrawProceeds()` with balance snapshots (before/after)
- **Event signature updates**: `ListingPurchased` has `currency` parameter between `price` and `feeRate`
- **testExcessPaymentCreditAndWithdraw renamed**: Now `testExactPaymentRequired` - atomic payments, no overpay mechanism
- **Balance assertions pattern**: `assertEq(seller.balance - sellerBalBefore, expectedAmount)` instead of proceeds checks

### Batch 5 - Edge Cases & Validation
- **RoyaltyPaid event**: Takes 4 params (listingId, receiver, tokenAddress, amount) - removed tokenId parameter
- **ListingCreated event**: Added `currency` parameter between `price` and `feeRate`
- **testWithdrawHappyPathWithRoyaltyAndOwner renamed**: Now `testRoyaltyPaymentWithOwnerFee` - uses balance snapshots, no withdrawals
- **Multi-purchase tests**: Track balance changes per purchase separately (no cumulative proceeds mapping)
- **testNoOpUpdateKeepsValues**: Use `beforeL.currency` in updateListing call
- **Diamond balance**: Assert `address(diamond).balance == 0` after purchases (non-custodial = no accumulation)

### Process
1. **Check if already migrated**: Some tests have `address(0)` currency params already
2. **Compile specific file**: Use `get_errors([filePath])` - don't compile all tests
3. **Ignore blocking errors**: IdeationMarketDiamondTest.t.sol has errors - work on other files
4. **MarketTestBase done**: Foundation is complete with CurrencyWhitelistFacet
5. **Infrastructure tests skip migration**: Tests for diamond mechanics (cut/loupe), ownership, pausing don't touch marketplace functions
6. **Fork tests are orthogonal**: Health checks on deployed contracts test ERC165/ERC173 compliance and loupe views, not marketplace logic
7. **Gas tests need withdraw removal**: Delete withdrawProceeds test + WITHDRAW_BUDGET constant entirely (non-custodial = no withdrawal)
8. **Naming convention**: Use `Listing memory listing` instead of `L` for readability
9. **Invariant tests fundamentally different**: Remove `withdraw()` handler action, remove proceeds-sum invariant, add `invariant_DiamondBalanceIsZero()` (non-custodial = no balance accumulation)
10. **Mock facet naming**: Use `DummyUpgradeFacetV1/V2` from MarketTestBase, not `VersionFacetV1/V2` (which don't exist)
11. **Fork tests with minimal interfaces**: Import `Listing` struct from `LibAppStorage.sol` - GetterFacet actually returns `Listing memory` not destructured values. Add `isCurrencyAllowed(address)` to IGetterFacet interface. Add ETH whitelisting in setUp using low-level call to CurrencyWhitelistFacet's `addAllowedCurrency(address(0))`
12. **Balance/proceeds tests fundamentally different**: Remove overpay logic (exact ETH required), remove `getProceeds()` calls, replace with balance snapshots before/after purchase. Test that diamond balance is UNCHANGED after purchase (non-custodial = no accumulation), verify seller/owner receive atomic payments directly
12. **Storage collision/invariant tests**: Add currency params everywhere (createListing, updateListing, purchaseListing), replace `getProceeds()` with balance diffs, remove `withdrawProceeds()` from invariant handlers. Storage canary checks (innovationFee, maxBatch, whitelistedCollections) remain unchanged - they validate storage slots don't drift during marketplace operations
13. **updateListing signature change**: Added `newErc1155Quantity` parameter between `newDesiredErc1155Quantity` and `newBuyerWhitelistEnabled`. For ERC721 updates, pass 0. Event `ListingUpdated` has `currency` between `price` and `feeRate`
14. **createListing parameter order**: After `currency`, must pass `address(0)` for `desiredTokenAddress` (not `0`). Common error: passing integer 0 instead of address(0) causes "11 arguments given but 12 expected"

### New Errors to Handle
```solidity
error IdeationMarket__CurrencyNotAllowed();
error IdeationMarket__WrongPaymentCurrency();
error IdeationMarket__EthTransferFailed(address receiver);
error IdeationMarket__ERC20TransferFailed(address token, address receiver);
error IdeationMarket__ContractPaused();
```

### Event Parameter Order Changed
All listing events now have `currency` between `price` and `feeRate`:
```solidity
// OLD: emit ListingCreated(..., price, feeRate, ...)
// NEW: emit ListingCreated(..., price, currency, feeRate, ...)
```

### ERC-20 Testing Pattern (When Needed)
```solidity
// 1. Deploy and whitelist token
MockERC20 token = new MockERC20();
vm.prank(owner);
currencies.addAllowedCurrency(address(token));

// 2. Mint and approve
token.mint(buyer, 10 ether);
vm.prank(buyer);
token.approve(address(diamond), 10 ether);

// 3. Create listing with ERC-20
market.createListing(..., price, address(token), ...);

// 4. Capture balances before purchase
uint256 buyerBal = token.balanceOf(buyer);
uint256 sellerBal = token.balanceOf(seller);

// 5. Purchase (NO msg.value for ERC-20)
vm.prank(buyer);
market.purchaseListing(listingId, price, address(token), ...);

// 6. Verify atomic transfers
assertEq(token.balanceOf(buyer), buyerBal - totalPrice);
assertEq(token.balanceOf(seller), sellerBal + sellerProceeds);
```

### Test-Specific Patterns

#### BuyerWhitelistFacetTest (✅ DONE)
- Already has currency parameters
- Helper function `listERC1155WithOperatorAndWhitelistEnabled` correct
- No payment assertions needed (tests access control only)
- Facet tests focus on their domain, not payment flows

#### Custom Helper Functions
Test files with their own helpers must match IdeationMarketFacet signature:
```solidity
function helperCreateListing(...) internal {
    market.createListing(
        tokenAddress,
        tokenId,
        seller,        // erc1155Holder for ERC1155, address(0) for ERC721
        1 ether,       // TOTAL price
        address(0),    // ← currency
        address(0),    // desiredTokenAddress
        0, 0,          // desired token params
        quantity,      // erc1155Quantity (0 for ERC721)
        true,          // buyerWhitelistEnabled
        false,         // partialBuyEnabled
        new address[](0)
    );
}
```

---

## Quick Checklist Per Test File

- [ ] Check if already migrated (look for `address(0)` after price)
- [ ] Add currency to all `createListing` calls
- [ ] Add expectedCurrency to all `purchaseListing` calls
- [ ] Add newCurrency to all `updateListing` calls
- [ ] Replace `getProceeds()` with balance snapshots
- [ ] Remove `withdraw()` calls
- [ ] Remove `ReentrantWithdrawer` mocks
- [ ] Update event expectations (currency between price and feeRate)
- [ ] Verify price is total for ERC1155, not per-unit
- [ ] Check compilation with `get_errors([filePath])`

---

---

## Migration Status

### ✅ Completed
- **MarketTestBase.t.sol** - Foundation with CurrencyWhitelistFacet setup
- **BuyerWhitelistFacetTest.t.sol** - Already migrated, no changes needed
- **CollectionWhitelistFacetEdgeTest.t.sol** - No changes needed
- **DeprecatedSwapListingDeletionTest.t.sol** - Already migrated, no changes needed
- **DiamondCutFacetTest.t.sol** - No changes needed
- **DiamondHealth.t.sol** - No changes needed
- **IdeationMarketGasTest.t.sol** - Migrated: added currency params, removed withdrawProceeds test
- **InvariantTest.t.sol** - Migrated: added currency params, removed withdraw function, replaced proceeds invariant with zero-balance invariant
- **LibDiamondEdgesTest.t.sol** - Fixed: replaced VersionFacetV1/V2 with DummyUpgradeFacetV1/V2
- **MarketSmoke.t.sol** - Migrated: imported Listing struct, updated minimal interfaces, added currency params to all calls (5 createListing + 6 purchaseListing), added ETH whitelisting in setUp
- **MarketSmokeBroadcast.s.sol** - Migrated: imported Listing struct, updated minimal interfaces, added currency params to all calls (2 createListing + 1 purchaseListing), added ETH whitelisting in run()
- **MarketSmokeBroadcastFull.s.sol** - Migrated: imported Listing struct, updated minimal interfaces, added currency params to all calls (4 createListing + 4 purchaseListing including ERC1155 partial), added ETH whitelisting in run()
- **ReceiveAndGetterBalanceTest.t.sol** - Migrated: added currency param to createListing/purchaseListing, replaced overpay test with atomic payment test verifying zero diamond balance after purchase
- **StorageCollisionTest.t.sol** - Migrated: added currency params to all createListing/updateListing/purchaseListing calls, replaced getProceeds with balance snapshots, removed withdrawProceeds from handlers, all storage collision canary tests intact

### 🔄 In Progress
- None

### ✅ Completed (Continued)
- **PauseFacetTest.t.sol** - Migrated: Extended MarketTestBase, added currency params, fixed error imports, added selector routing verification (29 tests)
- **VersionFacetTest.t.sol** - Migrated: Extended MarketTestBase, added currency params, fixed selector references, added selector routing verification, fixed unused variable warnings (11 tests)

### 📝 Pending
- **IdeationMarketDiamondTest.t.sol** - 6185 lines, ~200 tests - NEEDS BATCHED MIGRATION (see plan below)

---

## IdeationMarketDiamondTest.t.sol Migration Plan

**Status**: 🟢 Batch 1-2 COMPLETE (13/200 tests)  
**File Size**: 6185 lines, ~200 test functions  
**Strategy**: Batched migration in 9 sequential batches  
**Estimated Prompts**: 9-10 agent runs

**important notes**: do not try to compile IdeationMarketDiamondTest.t.sol since until all these batches are dealt with we WILL have compilation issues anyway.

### Batch 1-3 Completion Summary
- ✅ Updated diamond facet count: 7 → 9
- ✅ Commented out 10 obsolete withdrawal/reentrancy tests  
- ✅ Infrastructure & whitelist tests verified (no changes needed)
- ✅ Basic listing & purchase tests migrated (7 tests)

### Batch Breakdown:

**Batch 1: Diamond Infrastructure (lines 1-110, ~8 tests)** ✅ COMPLETE
- Diamond initialization, loupe, interfaces, ownership
- **Changes**: Updated facet count from 7 to 9 (added PauseFacet & VersionFacet)
- **Result**: All infrastructure tests work without marketplace changes

**Batch 2: Whitelist Tests (lines 111-230, ~5 tests)** ✅ COMPLETE
- Collection whitelist, buyer whitelist (uses _createListingERC721 helper)
- **Changes**: None - helper already has currency param
- **Result**: All whitelist tests work without marketplace changes

**Batch 3: Basic Listing & Purchase (lines 231-430, 7 tests)** ✅ COMPLETE
- Create, purchase, update, cancel ERC721
- **Changes**: Fixed updateListing signature (added newErc1155Quantity param), fixed ListingUpdated event (added currency), fixed createListing in testCleanListing_WhileStillApproved_ERC721_Reverts (missing desiredTokenAddress param)
- **Result**: All 7 tests compile successfully

**Batch 4: ERC1155 Tests (lines 431-850, ~15 tests)** ⚠️ COMPLEX
- ERC1155 quantity rules, partial buys, fee math
- **Changes**: Currency params + balance checking changes
- **Estimate**: 1-2 prompts

**Batch 5: Edge Cases & Validation (lines 851-1500, ~25 tests)** ⚠️ COMPLEX
- Whitelist edge cases, zero values, authorization
- **Changes**: Currency params + proceeds removal
- **Estimate**: 2 prompts

**Batch 6: Advanced Features (lines 1501-2500, ~35 tests)** 🔥 VERY COMPLEX
- Swaps, royalties, operators, ERC1155 advanced
- **Changes**: Currency params + proceeds + balance snapshots
- **Estimate**: 2-3 prompts

**Batch 7: Events & Integration (lines 2501-3900, ~30 tests)** ⚠️ COMPLEX
- Event emissions, reverse index, payment flows
- **Changes**: Event parameter updates (currency field)
- **Estimate**: 2 prompts

**Batch 8: Attack Vectors & Security (lines 3901-5000, ~30 tests)** 🔥 VERY COMPLEX
- Reentrancy, malicious tokens, burns, cleanups
- **Changes**: Complete rewrite of withdrawal reentrancy tests
- **Estimate**: 2-3 prompts

**Batch 9: Receiver Hooks & Final Tests (lines 5001-6185, ~25 tests)** ⚠️ COMPLEX
- Receiver contracts, final swaps, scale tests
- **Changes**: Verify non-custodial behavior
- **Estimate**: 1-2 prompts

### Total Estimate: **9-15 prompts** depending on complexity

### Workflow:
After each batch completion:
1. ✅ Compile batch to verify no errors
2. ✅ Run tests to verify functionality
3. ✅ Update this file with batch completion status
4. ⏸️ **PAUSE and ask user**: "Batch X complete (Y/200 tests migrated). Continue with Batch X+1?"
5. 🔄 User confirms → proceed to next batch

### Progress Tracking:
- [x] Batch 1-2: Infrastructure & Whitelists (13 tests) - Lines 1-230
- [x] Batch 3: Basic Listing & Purchase (7 tests) - Lines 231-430
- [x] Batch 4: ERC1155 Tests (15 tests) - Lines 431-850
- [x] Batch 5: Edge Cases (25 tests) - Lines 851-1500
- [ ] Batch 6: Advanced Features (35 tests) - Lines 1501-2500
- [ ] Batch 7: Events & Integration (30 tests) - Lines 2501-3900
- [ ] Batch 8: Attack Vectors (30 tests) - Lines 3901-5000
- [ ] Batch 9: Receiver Hooks (25 tests) - Lines 5001-6185

**Current Batch**: Batch 5 complete
**Tests Migrated**: 60/~200
**Lines Migrated**: 1500/5728


### Test Type Insights
- **Invariant Tests**: Remove withdraw actions, replace proceeds invariants with atomic payment invariants (InvariantTest)
- **Gas Benchmarks**: Need full migration + remove withdrawProceeds test (IdeationMarketGasTest)
- **Infrastructure Tests**: No marketplace calls = no migration (DiamondCutFacet tests EIP-2535 diamond upgrades)
- **Whitelist/Access Control Tests**: No currency changes needed (BuyerWhitelistFacetTest, CollectionWhitelistFacetEdgeTest)
- **Swap Logic Tests**: Already migrated if currency params present (DeprecatedSwapListingDeletionTest)
- **Payment Flow Tests**: Need full migration (balance snapshots, currency params)
- **Facet-Specific Tests**: Only migrate if they create/purchase listings
