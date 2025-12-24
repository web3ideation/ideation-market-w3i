# Phase 6: Edge Cases & Integration Test Suite - Comprehensive Prompt

## Context & Requirements

You are implementing a complete test suite for **Edge Cases and Integration Scenarios** in a Diamond marketplace contract. This is **Phase 6 of 6** for ERC20 testing - the **FINAL PHASE**.

**Status:** Phases 1-5 complete (56 tests total, all passing)
- Phase 1: CurrencyWhitelistFacet (16 tests) ✅
- Phase 2: ERC20Marketplace (7 tests) ✅
- Phase 3: ERC20PaymentDistribution (11 tests) ✅
- Phase 4: ERC20Security (18 tests) ✅
- Phase 5: ETHMarketplaceVerification (4 tests) ✅

**Phase 6 Priority:** Medium 🟡 (edge cases and integration - adds robustness)

### Critical Background Knowledge

1. **What Phase 6 Tests (Edge Cases ONLY):**
   - Complex interaction patterns between features
   - Tiny amounts and rounding edge cases
   - Multiple currencies in rapid succession
   - Whitelist interactions (buyer + collection) with ERC20
   - Currency updates and de-whitelisting with active listings
   - Partial buys with ERC20 (unit price calculations)
   - NFT swaps with additional ERC20 payment
   - Getter facet accuracy with large currency arrays

2. **What Phase 6 Does NOT Test (Already Covered):**
   - ❌ Basic ERC20 purchases (Phase 2)
   - ❌ Payment distribution mechanics (Phase 3)
   - ❌ Security attacks (Phase 4: reentrancy, front-running, etc.)
   - ❌ Mixed ETH+ERC20 scenarios (Phase 5)
   - ❌ Basic ETH purchases (331 existing tests)
   - ❌ Pause functionality (28 existing tests)

3. **Non-Custodial Payment Invariant:**
   - Diamond balance MUST always be 0 for all tokens
   - After every purchase: `diamond.balanceOf(ERC20) == 0`
   - Payments flow directly: buyer → marketplace owner → royalty receiver → seller
   - NO intermediate custody at any point

4. **Partial Buy Mechanics:**
   - Listing has: `amount` (total NFTs), `unitPrice` (price per NFT)
   - Total listing price: `amount * unitPrice`
   - Partial buy: buyer specifies `buyAmount < amount`
   - Payment calculation: `buyAmount * unitPrice` (MUST NOT round incorrectly)
   - After partial buy: listing still exists with `amount -= buyAmount`

5. **Update Listing Rules:**
   - Can update: price, amount, currency, swapNFT
   - CANNOT change: nftContract, tokenId (those would be a different listing)
   - **Currency switch attack vector:** buyer approves old currency, seller switches to new currency
   - **Protection:** `expectedCurrency` parameter in `buyListing()`

6. **Whitelist Interactions:**
   - **Collection whitelist:** Only whitelisted collections can have listings
   - **Buyer whitelist:** Optional per-listing; if enabled, only whitelisted buyers can purchase
   - **Currency whitelist:** Only whitelisted currencies can be used for NEW listings
   - De-whitelisting collection triggers `cleanListing()` to remove all its listings

7. **ERC2981 Royalty Support:**
   - Standard NFT royalty interface
   - `royaltyInfo(tokenId, salePrice)` → returns (receiver, royaltyAmount)
   - Marketplace respects royalties automatically
   - Payment flow: marketplace fee → royalty → seller

### Test File Structure

**File:** `test/EdgeCasesAndIntegrationTest.t.sol`

**Must:**
- Extend `MarketTestBase` for standard setup
- Use existing mock tokens from `MarketTestBase`: `usdc`, `dai`, `weth`
- Create additional mocks as needed: `TinyToken` (tiny decimals), `RoyaltyNFT` (ERC2981)
- Use existing diamond facet references: `currencies`, `market`, `getter`, `collections`, `buyerWhitelist`
- Follow existing test naming conventions (e.g., `testXxxYyyZzz`)

### Required Tests (8-10 total)

#### **Group 1: Mixed Currency Sequencing (2 tests)**

1. **testMixETHAndERC20ListingsBackToBack**
   - Whitelist 2 collections
   - Create listing in collection A with ETH (address(0))
   - Create listing in collection B with USDC
   - Purchase listing A with ETH (msg.value = price)
   - Purchase listing B with USDC (approve + buy)
   - Verify BOTH listings deleted
   - Verify diamond balance = 0 for USDC
   - **Tests:** State isolation between ETH and ERC20 purchases in same transaction block

2. **testMultipleERC20CurrenciesInSequence**
   - Add 3 ERC20 tokens to allowlist (USDC, DAI, WETH)
   - Create 3 listings with 3 different tokens (same collection, different tokenIds)
   - Purchase all 3 in sequence
   - Verify diamond balance = 0 for ALL 3 tokens
   - Verify payment distribution correct for each token
   - **Tests:** Currency isolation and no cross-contamination

#### **Group 2: Update Listing Currency Switch (2 tests)**

3. **testUpdateListingCurrencySwitchWithExpectedCurrency**
   - Create listing with USDC
   - Buyer approves marketplace for 1000 USDC
   - Seller updates listing to use DAI instead
   - Buyer calls `buyListing()` with `expectedCurrency = USDC`
   - Verify purchase REVERTS (currency mismatch protection)
   - **Tests:** Front-run protection when seller switches currency

4. **testCanCreateListingInNonAllowedCurrencyAfterRemoval**
   - Add custom ERC20 to allowlist
   - Create listing with that ERC20
   - Remove ERC20 from allowlist
   - Attempt to create NEW listing with removed ERC20 → expect REVERT
   - But existing listing can still be purchased (backward compatibility)
   - **Tests:** Currency whitelist enforcement for new listings only

#### **Group 3: Tiny Amounts and Rounding (1 test)**

5. **testTinyERC20AmountPurchaseNoRounding**
   - Create MockERC20 with 6 decimals (like USDC)
   - Create listing: `amount = 1`, `unitPrice = 1` (1 token unit = smallest possible)
   - Mint 1 token to buyer, approve marketplace
   - Purchase listing
   - Verify:
     - Buyer paid exactly 1 unit
     - Seller + owner fees = 1 unit (no rounding errors)
     - Diamond balance = 0
   - **Tests:** Rounding behavior with smallest possible amounts

#### **Group 4: Buyer Whitelist + ERC20 (1 test)**

6. **testBuyerWhitelistWithERC20Purchase**
   - Create listing with USDC, enable buyer whitelist
   - Add `buyer1` to buyer whitelist
   - Attempt purchase as `buyer2` (not whitelisted) → expect REVERT
   - Purchase as `buyer1` (whitelisted) → succeeds
   - Verify payment distribution correct
   - Verify diamond balance = 0
   - **Tests:** Buyer whitelist enforcement works with ERC20 payments

#### **Group 5: Collection De-whitelist + CleanListing (1 test)**

7. **testCollectionDewhitelistTriggersCleanListingWithERC20**
   - Create 2 listings in collection A with USDC
   - Remove collection A from whitelist (triggers cleanListing internally)
   - Verify both listings deleted (getter returns empty)
   - Attempt to purchase deleted listing → expect REVERT
   - Re-whitelist collection A for cleanup
   - **Tests:** cleanListing() properly removes all listings when collection de-whitelisted

#### **Group 6: Partial Buys with ERC20 (1 test)**

8. **testPartialBuyWithERC20UnitPriceCalculation**
   - Create listing: `amount = 10`, `unitPrice = 100 USDC` (total = 1000 USDC)
   - Buyer approves 500 USDC
   - Buyer purchases `buyAmount = 5`
   - Verify:
     - Buyer paid exactly 500 USDC (5 * 100)
     - Listing still exists with `amount = 5` remaining
     - Seller + owner fees = 500 USDC
     - Diamond balance = 0
   - Second buyer purchases remaining 5 NFTs
   - Verify listing deleted after full purchase
   - **Tests:** Partial buy unit price calculation and listing update

#### **Group 7: NFT Swaps with ERC20 (1 test)**

9. **testNFTSwapWithAdditionalERC20Payment**
   - Create listing: `price = 500 USDC`, `swapNFT = collection B, tokenId 1`
   - Buyer must provide:
     - NFT from collection B (tokenId 1) - owned and approved
     - 500 USDC - approved
   - Execute purchase
   - Verify:
     - Buyer receives NFT A
     - Seller receives NFT B + 500 USDC proceeds (minus fees)
     - Owner receives fee in USDC
     - Diamond balance = 0 for USDC
   - **Tests:** Combined NFT swap + ERC20 payment distribution

#### **Group 8: Getter Facet Accuracy (1 test - OPTIONAL)**

10. **testGetAllowedCurrenciesWithLargeArray** (BONUS)
    - Verify `getAllowedCurrencies()` returns 76 initialized currencies
    - Add 10 more currencies
    - Verify array length = 86
    - Remove 5 currencies
    - Verify array length = 81
    - Verify removed currencies NOT in array (no duplicates)
    - **Tests:** Getter accuracy with large currency arrays

### Common Pitfalls to Avoid

❌ **Don't retest basic ERC20 purchases** → Phases 2-3 already cover this
❌ **Don't retest security vectors** → Phase 4 already covers reentrancy, front-running, etc.
❌ **Don't retest mixed ETH+ERC20** → Phase 5 already covers this
❌ **Don't forget** diamond balance = 0 invariant for ALL tokens
❌ **Don't skip** partial buy unit price verification (easy to get rounding wrong)
❌ **Don't assume** currency switch is caught automatically (need expectedCurrency)
❌ **Don't forget** to whitelist collections before creating listings
❌ **Don't forget** to whitelist buyers when buyer whitelist is enabled

### Real Bugs These Tests Should Catch

✅ **Tiny amount rounding errors** → seller/owner lose 1 unit due to integer division
✅ **Partial buy miscalculation** → wrong total price charged (e.g., total price instead of unit price * buyAmount)
✅ **Currency switch front-run** → buyer approved old currency but charged in new currency
✅ **Collection de-whitelist incomplete cleanup** → listings remain after collection removed
✅ **NFT swap + ERC20 payment error** → ERC20 transferred but NFT swap fails (or vice versa)
✅ **Buyer whitelist bypass** → non-whitelisted buyer can purchase by manipulating state
✅ **Multiple currency cross-contamination** → balance from token A affects token B purchase
✅ **Diamond custody leak** → diamond holds tokens after purchase (breaks non-custodial promise)

### Success Criteria

✅ All 8-10 tests pass
✅ No compilation errors
✅ Tests verify unique edge cases NOT covered in Phases 1-5
✅ Tests verify non-custodial invariant (diamond balance = 0) for all tokens
✅ Tests verify complex interactions work correctly (partial buys, swaps, whitelists)
✅ Tests can catch real implementation bugs (rounding, front-runs, state corruption)
✅ Zero redundancy with existing 56 tests

### Example Test Structure

```solidity
function testPartialBuyWithERC20UnitPriceCalculation() public {
    // Setup: Whitelist collection
    vm.prank(owner);
    collections.addCollection(address(nft), "TestNFT");
    
    // Setup: Create listing with 10 NFTs at 100 USDC each
    uint256 tokenId = 1;
    nft.mint(seller, tokenId);
    vm.startPrank(seller);
    nft.setApprovalForAll(address(market), true);
    market.createListing(
        address(nft),
        tokenId,
        10,        // amount
        100e18,    // unitPrice (100 USDC with 18 decimals)
        address(usdc),  // currency
        address(0), // no swap NFT
        0,
        false      // no buyer whitelist
    );
    vm.stopPrank();
    
    // Setup: Buyer approves 500 USDC for partial buy
    usdc.mint(buyer, 500e18);
    vm.startPrank(buyer);
    usdc.approve(address(market), 500e18);
    
    // Execute: Buy 5 out of 10 NFTs
    market.buyListing(
        address(nft),
        tokenId,
        seller,
        5,             // buyAmount
        address(usdc), // expectedCurrency
        0              // no msg.value
    );
    vm.stopPrank();
    
    // Verify: Buyer paid exactly 500 USDC
    assertEq(usdc.balanceOf(buyer), 0, "Buyer should have paid 500 USDC");
    
    // Verify: Diamond has zero balance (non-custodial)
    assertEq(usdc.balanceOf(address(market)), 0, "Diamond must not hold tokens");
    
    // Verify: Listing still exists with 5 NFTs remaining
    (
        ,
        ,
        uint256 remainingAmount,
        ,
        ,
        ,
        ,
    ) = getter.getListingDetails(address(nft), tokenId, seller);
    assertEq(remainingAmount, 5, "Should have 5 NFTs remaining");
    
    // Verify: Second buyer can purchase remaining 5
    address buyer2 = makeAddr("buyer2");
    usdc.mint(buyer2, 500e18);
    vm.startPrank(buyer2);
    usdc.approve(address(market), 500e18);
    market.buyListing(
        address(nft),
        tokenId,
        seller,
        5,             // buy remaining 5
        address(usdc),
        0
    );
    vm.stopPrank();
    
    // Verify: Listing deleted after full purchase
    (
        ,
        ,
        uint256 finalAmount,
        ,
        ,
        ,
        ,
    ) = getter.getListingDetails(address(nft), tokenId, seller);
    assertEq(finalAmount, 0, "Listing should be fully purchased and deleted");
}
```

### Final Checklist Before Submitting

- [ ] All 8-10 tests implemented
- [ ] Tests compile without errors
- [ ] Tests pass: `forge test --match-contract "EdgeCasesAndIntegrationTest"`
- [ ] All tests verify diamond balance = 0 for relevant tokens
- [ ] No tests duplicate Phases 1-5 coverage
- [ ] Tests cover edge cases that could hide real bugs
- [ ] Partial buy unit price calculation verified
- [ ] Currency switch protection verified
- [ ] Buyer whitelist + ERC20 interaction verified
- [ ] Collection de-whitelist cleanup verified
- [ ] NFT swap + ERC20 payment verified
- [ ] Tiny amount rounding verified

---

## Anti-Pattern Warnings

⚠️ **This is NOT a "make tests pass" exercise** - these tests must be capable of catching real bugs in your marketplace facets.

⚠️ **Do NOT retest fundamentals** - Phases 1-5 already cover ERC20 basics, security, and ETH interactions.

⚠️ **Do NOT add tests just for coverage numbers** - every test must verify a UNIQUE edge case or integration scenario.

⚠️ **Do NOT skip payment distribution verification** - verify seller + owner = buyer payment (no dust/loss).

⚠️ **Do NOT skip diamond balance checks** - non-custodial invariant is critical for all ERC20 purchases.

---

**Good luck with Phase 6 - the final testing phase! 🎯**
