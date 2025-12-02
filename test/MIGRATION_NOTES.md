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
13. **Storage collision/invariant tests**: Add currency params everywhere (createListing, updateListing, purchaseListing), replace `getProceeds()` with balance diffs, remove `withdrawProceeds()` from invariant handlers. Storage canary checks (innovationFee, maxBatch, whitelistedCollections) remain unchanged - they validate storage slots don't drift during marketplace operations

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

### 📝 Pending
- **IdeationMarketDiamondTest.t.sol** - Has ReentrantWithdrawer (needs withdrawal removal)
- **PauseFacetTest.t.sol** - TBD
- **ReceiveAndGetterBalanceTest.t.sol** - TBD (may test old proceeds mapping)
- **StorageCollisionTest.t.sol** - TBD
- **VersionFacetTest.t.sol** - TBD


### Test Type Insights
- **Invariant Tests**: Remove withdraw actions, replace proceeds invariants with atomic payment invariants (InvariantTest)
- **Gas Benchmarks**: Need full migration + remove withdrawProceeds test (IdeationMarketGasTest)
- **Infrastructure Tests**: No marketplace calls = no migration (DiamondCutFacet tests EIP-2535 diamond upgrades)
- **Whitelist/Access Control Tests**: No currency changes needed (BuyerWhitelistFacetTest, CollectionWhitelistFacetEdgeTest)
- **Swap Logic Tests**: Already migrated if currency params present (DeprecatedSwapListingDeletionTest)
- **Payment Flow Tests**: Need full migration (balance snapshots, currency params)
- **Facet-Specific Tests**: Only migrate if they create/purchase listings
