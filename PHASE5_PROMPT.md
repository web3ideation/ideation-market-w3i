# Phase 5: ETH Marketplace Verification & Mixed Scenarios - Comprehensive Prompt

## Context & Requirements

You are implementing **Phase 5 of 5** for comprehensive marketplace testing. This phase verifies that **native ETH functionality remains intact** after adding ERC20 support, and tests **mixed ETH/ERC20 scenarios** that could expose edge cases.

### Critical Background Knowledge

1. **Architecture Evolution:**
   - Original marketplace: ETH-only payments (well-tested, 331 tests)
   - Current marketplace: Support for both ETH and ERC20
   - Risk: Changes for ERC20 support could have broken ETH functionality
   - **Phase 5 Goal:** Prove ETH still works perfectly, test mixed scenarios

2. **ETH Payment Flow (IdeationMarketFacet.sol:1040-1058):**
   ```solidity
   // ETH Path (currency == address(0)):
   // 1. Diamond receives ETH via msg.value
   // 2. Immediately forwards to recipients (marketplace owner, royalty receiver, seller)
   // 3. Diamond balance must be 0 after distribution
   // 4. Any excess msg.value is refunded to buyer
   
   // Critical checks:
   // - msg.value >= purchasePrice (or == purchasePrice if strict)
   // - All .call{value: X}("") must succeed or revert entire tx
   // - Refund = msg.value - purchasePrice sent back to buyer
   ```

3. **ERC20 vs ETH Differences:**
   - **ETH:** Uses `msg.value`, direct transfers via `.call{value: X}("")`
   - **ERC20:** Uses `msg.value == 0`, approval + `transferFrom()` via `_safeTransferFrom()`
   - **Both:** Non-custodial (diamond balance = 0), atomic payments, same order (owner → royalty → seller)

4. **Front-Running Protection:**
   - `expectedCurrency` parameter guards against listing updates between tx submission and execution
   - ETH listings: `expectedCurrency == address(0)`
   - ERC20 listings: `expectedCurrency == token address`
   - **Critical:** Currency switch (ETH→ERC20 or vice versa) must be caught

5. **Mixed Scenario Risks:**
   - User sends ETH to ERC20 listing → should revert with `IdeationMarket__WrongPaymentCurrency`
   - User sends ERC20 approval but no `msg.value` to ETH listing → should fail
   - Multiple listings in different currencies in same block → isolation critical
   - Diamond receives ETH from ETH purchase, should not affect ERC20 purchase in same tx/block

### Test File Structure

**File:** `test/ETHMarketplaceVerificationTest.t.sol`

**Must:**
- Extend `MarketTestBase` for standard setup
- Use existing diamond facet references
- Reuse existing `MockERC20` from Phase 1-4 tests
- Focus on **ETH-specific edge cases** and **mixed ETH/ERC20 scenarios**
- Verify that 331 existing ETH tests still pass (regression prevention)

### Required Tests (14-16 total)

---

## Group 1: ETH Purchase Path Verification (5 tests)

**Goal:** Prove ETH purchases still work exactly as before ERC20 addition

### 1. testETHPurchaseBasicFlow
**Purpose:** Verify core ETH purchase functionality unchanged
- Whitelist collection
- Create ERC721 listing with `currency = address(0)`, price = 1 ether
- Buyer purchases with `msg.value = 1 ether`
- **Assert:**
  - Buyer owns NFT
  - Seller received proceeds (≈ 0.99 ether after fee)
  - Owner received fee (≈ 0.01 ether)
  - Diamond balance = 0
  - Buyer's ETH balance decreased by 1 ether
- **Why critical:** Core ETH path could be broken by ERC20 changes

### 2. testETHPurchaseWithExactMsgValue
**Purpose:** Verify exact payment works (no overpayment)
- Create listing with price = 2 ether
- Buyer sends exactly `msg.value = 2 ether`
- **Assert:**
  - Purchase succeeds
  - No refund needed (buyer paid exact amount)
  - Diamond balance = 0
- **Why critical:** Tests exact payment path without overpayment logic

### 3. testETHPurchaseWithOverpayment
**Purpose:** Verify overpayment refund mechanism
- Create listing with price = 1 ether
- Buyer sends `msg.value = 1.5 ether` (50% overpayment)
- Capture buyer balance before
- Execute purchase
- **Assert:**
  - Purchase succeeds
  - Buyer received refund of 0.5 ether
  - Seller + Owner received exactly 1 ether total
  - Diamond balance = 0
  - Buyer's net cost = 1 ether
- **Why critical:** Overpayment logic could be broken by ERC20 changes

### 4. testETHPurchaseWithInsufficientMsgValue
**Purpose:** Verify underpayment protection
- Create listing with price = 2 ether
- Buyer sends `msg.value = 1 ether` (insufficient)
- **Assert:**
  - Transaction reverts
  - No state changes (listing still active)
- **Why critical:** Protects against paying less than listing price

### 5. testETHPurchaseWithRoyalties
**Purpose:** Verify ETH royalty payment flow
- Deploy MockERC721Royalty with 10% royalty
- Create listing for 1 ether
- Buyer purchases with `msg.value = 1 ether`
- **Assert:**
  - Royalty receiver gets 0.1 ether (10%)
  - Marketplace owner gets fee from remainder
  - Seller gets proceeds after fee and royalty
  - `royaltyAmount + fee + sellerProceeds == 1 ether` (no dust)
  - Diamond balance = 0
- **Why critical:** Royalty path must work with ETH

---

## Group 2: ETH Front-Running Protection (3 tests)

**Goal:** Verify `expectedCurrency` protection works for ETH

### 6. testETHExpectedCurrencyMismatchReverts
**Purpose:** Buyer expects ETH but seller updates to ERC20
- Create listing in ETH (address(0))
- Seller updates listing to ERC20 token
- Buyer attempts purchase with `expectedCurrency = address(0)` and `msg.value = 1 ether`
- **Assert:**
  - Transaction reverts with `IdeationMarket__ListingTermsChanged`
  - Buyer retains ETH
  - Listing still exists with ERC20 currency
- **Why critical:** Prevents front-running currency switches

### 7. testETHToERC20UpdateFrontRun
**Purpose:** Detailed front-running scenario
- Create listing in ETH, price = 1 ether
- Buyer prepares tx with `expectedCurrency = address(0)`, `msg.value = 1 ether`
- Before buyer's tx executes, seller updates currency to tokenA
- Buyer's tx executes
- **Assert:**
  - Reverts with `IdeationMarket__ListingTermsChanged`
  - No payment transferred
  - Buyer still has full ETH balance
- **Why critical:** Real-world front-running protection test

### 8. testETHExpectedCurrencyMatchSucceeds
**Purpose:** Verify correct expectedCurrency allows purchase
- Create listing in ETH
- Buyer purchases with correct `expectedCurrency = address(0)`
- **Assert:**
  - Purchase succeeds
  - All payments distributed correctly
- **Why critical:** Proves guard doesn't block legitimate purchases

---

## Group 3: Mixed ETH/ERC20 Scenarios (4 tests)

**Goal:** Prove ETH and ERC20 listings can coexist without interference

### 9. testMixedCurrencyListingsInSameContract
**Purpose:** Multiple listings with different currencies
- Create 3 listings:
  - Listing A: ERC721 #1, price 1 ether, currency = address(0) (ETH)
  - Listing B: ERC721 #2, price 500 tokens, currency = tokenA (ERC20)
  - Listing C: ERC721 #3, price 2 ether, currency = address(0) (ETH)
- Execute purchases in order: A → B → C
- **Assert:**
  - All 3 purchases succeed
  - Buyer paid 1 ETH + 500 tokens + 2 ETH
  - Diamond balance = 0 for ETH AND tokenA
  - All NFTs transferred correctly
- **Why critical:** Proves currency isolation works

### 10. testETHPurchaseAfterERC20Purchase
**Purpose:** ERC20 state doesn't affect ETH path
- Create ETH listing
- Create ERC20 listing
- Purchase ERC20 listing first (buyer approves tokens)
- Purchase ETH listing second (buyer sends msg.value)
- **Assert:**
  - Both purchases succeed independently
  - Diamond balance = 0 for both currencies
  - No cross-currency interference
- **Why critical:** Proves stateless payment distribution

### 11. testCannotSendETHToERC20Listing
**Purpose:** Verify wrong currency rejection
- Create listing in ERC20 (tokenA), price = 1000 tokens
- Buyer attempts purchase with `msg.value = 1 ether` (wrong currency)
- **Assert:**
  - Transaction reverts with `IdeationMarket__WrongPaymentCurrency`
  - Buyer retains ETH
  - Listing still active
- **Why critical:** Prevents accidental wrong-currency payments

### 12. testCannotUseERC20ForETHListing
**Purpose:** Reverse scenario of test 11
- Create listing in ETH, price = 1 ether
- Buyer approves 1000 tokenA to marketplace
- Buyer attempts purchase with `msg.value = 0` (trying to use ERC20)
- **Assert:**
  - Transaction reverts (insufficient msg.value)
  - Buyer retains ETH and tokens
- **Why critical:** Proves ETH listings require actual ETH

---

## Group 4: ETH Edge Cases & Regression Tests (3-4 tests)

**Goal:** Cover ETH-specific edge cases that could regress

### 13. testETHListingWithZeroMsgValue
**Purpose:** Ensure msg.value validation works
- Create ETH listing, price = 1 ether
- Buyer calls purchaseListing with `msg.value = 0`
- **Assert:**
  - Transaction reverts (insufficient payment)
- **Why critical:** Guards against free purchases

### 14. testETHRefundFailureScenario
**Purpose:** Verify refund failure handling (if applicable)
- Create listing with price = 1 ether
- Deploy a contract buyer that rejects ETH refunds
- Contract buyer sends `msg.value = 2 ether`
- **Assert:**
  - Transaction completes (refund sent to buyer)
  - If refund fails, verify behavior (depends on implementation)
- **Why critical:** Tests refund edge case with contract buyers

### 15. testETHPurchaseWhilePaused
**Purpose:** Verify pause affects ETH purchases
- Create ETH listing
- Owner pauses marketplace
- Buyer attempts ETH purchase
- **Assert:**
  - Transaction reverts (paused)
- Owner unpauses
- Buyer purchases successfully
- **Why critical:** Proves pause works for ETH path

### 16. testMultipleETHPurchasesInSequence (BONUS)
**Purpose:** Stress test ETH payment distribution
- Create 5 ETH listings (different NFTs)
- Purchase all 5 in sequence
- **Assert:**
  - All succeed
  - Diamond balance = 0 after each purchase
  - Cumulative fees + proceeds balance correctly
- **Why critical:** Proves no state leakage between purchases

---

## Critical Validation Points

### ✅ Must Verify for Every ETH Test:
1. **Diamond balance = 0** after purchase
2. **msg.value** handled correctly (exact, overpayment, underpayment)
3. **Payment order** correct: owner → royalty → seller
4. **Refund mechanism** works (if overpayment)
5. **Events emitted** with `currency = address(0)`

### ❌ Anti-Patterns (Things That Would Hide Bugs):

**DON'T:**
- Assume ETH works without explicit verification
- Skip checking diamond balance after ETH purchases
- Use imprecise balance assertions (always use exact math)
- Forget to test overpayment scenarios
- Skip front-running protection tests
- Ignore mixed ETH/ERC20 scenarios

**DO:**
- Capture balances BEFORE and AFTER each operation
- Verify exact payment distribution: `fee + royalty + proceeds == price`
- Test currency switches in both directions (ETH→ERC20, ERC20→ETH)
- Verify diamond balance = 0 for BOTH ETH and any ERC20s involved
- Test with royalty receiver AND without (0 royalty cases)

---

## Common Pitfalls to Avoid

❌ **Don't assume** ETH path is unchanged just because tests pass
❌ **Don't skip** testing msg.value overpayment/underpayment
❌ **Don't forget** to verify refund mechanism
❌ **Don't ignore** front-running protection for ETH
❌ **Don't skip** mixed currency scenarios
❌ **Don't test** in isolation; verify ETH works alongside ERC20

---

## Success Criteria

✅ All 14-16 tests pass
✅ ETH purchase flow verified as working correctly
✅ Front-running protection works for ETH
✅ Mixed ETH/ERC20 scenarios work without interference
✅ Diamond balance = 0 verified for all ETH operations
✅ Overpayment refund mechanism tested
✅ No regression in existing 331 ETH tests
✅ All assertions use exact math, no approximations

---

## Test Structure Example

```solidity
function testETHPurchaseBasicFlow() public {
    // Setup
    vm.startPrank(owner);
    collections.addWhitelistedCollection(address(erc721));
    vm.stopPrank();
    
    vm.startPrank(seller);
    erc721.approve(address(diamond), 1);
    market.createListing(
        address(erc721),
        1,
        address(0),
        1 ether,
        address(0), // ETH
        address(0),
        0,
        0,
        0,
        false,
        false,
        new address[](0)
    );
    vm.stopPrank();
    
    uint128 listingId = getter.getNextListingId() - 1;
    
    // Capture balances
    uint256 buyerBefore = buyer.balance;
    uint256 sellerBefore = seller.balance;
    uint256 ownerBefore = owner.balance;
    
    // Action
    vm.deal(buyer, 1 ether);
    vm.prank(buyer);
    market.purchaseListing{value: 1 ether}(
        listingId,
        1 ether,
        address(0), // expectedCurrency
        0,
        address(0),
        0,
        0,
        0,
        address(0)
    );
    
    // Assert
    assertEq(erc721.ownerOf(1), buyer, "Buyer should own NFT");
    
    uint256 expectedFee = (1 ether * INNOVATION_FEE) / 100000;
    assertEq(owner.balance - ownerBefore, expectedFee, "Owner fee incorrect");
    assertEq(seller.balance - sellerBefore, 1 ether - expectedFee, "Seller proceeds incorrect");
    assertEq(buyer.balance - buyerBefore, 0, "Buyer should have spent 1 ETH");
    assertEq(address(diamond).balance, 0, "Diamond should not hold ETH");
}
```

---

## Final Checklist Before Submitting

- [ ] Extends `MarketTestBase`
- [ ] All 14-16 tests implemented
- [ ] Tests ETH purchase flow thoroughly
- [ ] Tests msg.value handling (exact, over, under)
- [ ] Tests overpayment refund mechanism
- [ ] Tests front-running protection for ETH
- [ ] Tests mixed ETH/ERC20 scenarios
- [ ] Tests wrong currency rejection (ETH to ERC20, ERC20 to ETH)
- [ ] Verifies diamond balance = 0 for all operations
- [ ] Uses exact math in all assertions
- [ ] All tests pass with `forge test --match-contract ETHMarketplaceVerificationTest -vv`

---

## Your Task

Create `test/ETHMarketplaceVerificationTest.t.sol` implementing all 14-16 tests above. 

**Key Focus:**
1. Prove ETH still works perfectly after ERC20 addition
2. Test currency isolation (ETH and ERC20 don't interfere)
3. Verify front-running protection for ETH
4. Test msg.value handling edge cases
5. Verify non-custodial invariant (diamond balance = 0)

**Think critically:** Each test should be able to catch a REAL bug, not just pass to make coverage numbers look good. If a test would still pass even if the code is broken, that's a bad test.
