# Phase 1: CurrencyWhitelistFacet Test Suite - Comprehensive Prompt

## Context & Requirements

You are implementing a complete test suite for the `CurrencyWhitelistFacet` in a Diamond marketplace contract. This is **Phase 1 of 4** for ERC20 testing.

### Critical Background Knowledge

1. **Initialization State:**
   - `DiamondInit.sol` pre-initializes **76 currencies** in the `init()` function
   - Index 0: `address(0)` = native ETH
   - Indices 1-75: Various ERC20 tokens (WETH, USDC, USDT, DAI, etc.)
   - ALL 76 currencies are pre-loaded into:
     - `s.allowedCurrencies[currency] = true` (mapping)
     - `s.allowedCurrenciesIndex[currency] = i` (index mapping)
     - `s.allowedCurrenciesArray.push(currency)` (array)

2. **Swap-and-Pop Algorithm:**
   ```solidity
   // When removing currency at index X:
   uint256 index = s.allowedCurrenciesIndex[currency];
   uint256 lastIndex = s.allowedCurrenciesArray.length - 1;
   
   if (index != lastIndex) {
       address lastCurrency = s.allowedCurrenciesArray[lastIndex];
       s.allowedCurrenciesArray[index] = lastCurrency;  // Move last to removed position
       s.allowedCurrenciesIndex[lastCurrency] = index;  // Update moved currency's index
   }
   
   s.allowedCurrenciesArray.pop();  // Remove last element
   delete s.allowedCurrenciesIndex[currency];  // Clean up removed currency
   ```

3. **Non-Custodial Payment Flow:**
   - For ERC20 listings: buyer approves marketplace, then `transferFrom(buyer, recipient, amount)`
   - Payment order: marketplace owner → royalty receiver → seller
   - **Diamond NEVER holds tokens** (balance must always be 0)

4. **Currency Lifecycle:**
   - Currency can be added/removed from allowlist at any time
   - Removing currency from allowlist does NOT affect existing listings
   - New listings in removed currency will revert
   - Purchases of existing listings in removed currency still work

### Test File Structure

**File:** `test/CurrencyWhitelistFacetTest.t.sol`

**Must:**
- Extend `MarketTestBase` for standard setup
- Create a simple `MockERC20` contract with:
  - Standard ERC20 functions: `mint()`, `approve()`, `transfer()`, `transferFrom()`
  - Public `balanceOf` and `allowance` mappings
  - 18 decimals by default
- Deploy 2+ mock tokens in `setUp()` for testing
- Use existing diamond facet references from `MarketTestBase`: `currencies`, `market`, `getter`, `collections`
- Follow existing test naming conventions (e.g., `testXxxYyyZzz`)

### Required Tests (16-18 total)

#### **Group 1: Basic Functionality (5 tests)**

1. **testOwnerCanAddAndRemoveCurrency**
   - Owner adds a new ERC20 token
   - Verify `isCurrencyAllowed()` returns true
   - Owner removes the token
   - Verify `isCurrencyAllowed()` returns false

2. **testNonOwnerCannotAddOrRemove**
   - Attempt add as non-owner → expect revert
   - Attempt remove as non-owner → expect revert

3. **testEventsEmittedOnAddAndRemove**
   - Add currency → expect `CurrencyAllowed(address)` event
   - Remove currency → expect `CurrencyRemoved(address)` event

4. **testDoubleAddReverts**
   - Add currency once (succeeds)
   - Add same currency again → expect revert with `CurrencyWhitelist__AlreadyAllowed`

5. **testRemoveNonAllowedReverts**
   - Attempt to remove currency that was never added → expect revert with `CurrencyWhitelist__NotAllowed`

#### **Group 2: Getter Functions (1 test)**

6. **testGettersReflectAllowedCurrencies**
   - Add 2-3 currencies
   - Call `isCurrencyAllowed()` for each → all return true
   - Call `getAllowedCurrencies()` → verify array contains all added currencies
   - **Note:** Array will have 76+ elements due to pre-initialization

#### **Group 3: Initialization State (2 tests - CRITICAL)**

7. **testETHIsInitializedInAllowlist**
   - Verify `isCurrencyAllowed(address(0))` returns true WITHOUT any manual adds
   - This tests DiamondInit pre-initialization

8. **testCanRemoveETHFromAllowlist**
   - Remove `address(0)` from allowlist
   - Verify `isCurrencyAllowed(address(0))` returns false
   - Attempt to create ETH listing → expect revert
   - Re-add `address(0)` for cleanup

#### **Group 4: Swap-and-Pop Array Integrity (4 tests - CRITICAL)**

9. **testArrayIntegritySwapAndPopRemoval**
   - Add 3 new currencies (A, B, C)
   - Remove middle currency B
   - Verify array no longer contains B
   - Remove last currency C
   - Verify array no longer contains C

10. **testIndexMappingCorrectAfterSwapAndPop**
    - Add 3 currencies
    - Get array length before
    - Remove middle currency
    - Verify array length decreased by 1
    - Verify ALL remaining currencies still return true for `isCurrencyAllowed()`
    - **This tests index mapping stays in sync**

11. **testRemoveOnlyElementInArray**
    - Add single new currency
    - Count occurrences in `getAllowedCurrencies()` (should be 1)
    - Remove it
    - Count occurrences again (should be 0)
    - Tests edge case of removing when it's the last element

12. **testMultipleCurrenciesInAllowlistAndEdges**
    - Add 4 currencies (A, B, C, D)
    - Remove middle two (B, C)
    - Verify remaining currencies (A, D) still in array
    - Cleanup by removing A and D

#### **Group 5: Listing Creation with Currency Validation (2 tests)**

13. **testCreateListingWithNonAllowedCurrencyReverts**
    - Ensure a test token is NOT in allowlist
    - Whitelist an NFT collection
    - Attempt to create listing with non-allowed token → expect revert

14. **testCannotCreateListingAfterCurrencyRemoved**
    - Add token to allowlist
    - Remove token from allowlist
    - Attempt to create listing with removed token → expect revert

#### **Group 6: Existing Listings After Currency Removal (1 test)**

15. **testRemoveCurrencyDoesNotAffectExistingListings**
    - Add token to allowlist
    - Create listing with that token
    - Remove token from allowlist
    - Mint tokens to buyer and approve marketplace
    - Purchase listing → should succeed (backward compatibility)
    - Verify listing deleted after purchase

#### **Group 7: ERC20 Payment Distribution (2 tests - CRITICAL)**

16. **testPaymentDistributionWithERC20AfterRemoval**
    - Add token, create listing, remove token from allowlist
    - Mint tokens to buyer, buyer approves marketplace
    - Capture seller, owner, buyer balances BEFORE purchase
    - Execute purchase
    - Verify:
      - Buyer paid exact listing price
      - Seller received proceeds (> 0)
      - Owner received fee (> 0)
      - `seller + owner = listing price` (no dust)
      - **Diamond balance = 0** (non-custodial invariant)

17. **testMultipleERC20TokensPaymentDistribution** (BONUS if time)
    - Create listings in 2 different ERC20 tokens
    - Purchase both
    - Verify both work correctly
    - Verify diamond balance = 0 for BOTH tokens

### Common Pitfalls to Avoid

❌ **Don't test `currencies.isCurrencyAllowed()`** → use `getter.isCurrencyAllowed()`
❌ **Don't forget** that 76 currencies are pre-initialized
❌ **Don't assume** ETH can't be removed (it can)
❌ **Don't skip** verifying index mapping after swap-and-pop
❌ **Don't forget** to verify diamond balance = 0 after ERC20 purchases
❌ **Don't create** listings without whitelisting the collection first

### Success Criteria

✅ All 16-18 tests pass
✅ MockERC20 works with marketplace
✅ No compilation errors
✅ Tests verify BOTH array and mapping integrity
✅ Tests verify non-custodial invariant (diamond balance = 0)
✅ Tests cover initialization state from DiamondInit
✅ Tests verify backward compatibility (old listings work after currency removal)

### Example Test Structure

```solidity
function testExampleTest() public {
    // Setup
    vm.startPrank(owner);
    currencies.addAllowedCurrency(address(tokenA));
    vm.stopPrank();
    
    // Action
    bool allowed = getter.isCurrencyAllowed(address(tokenA));
    
    // Assert
    assertTrue(allowed, "Token should be allowed");
}
```

### Final Checklist Before Submitting

- [ ] Extends `MarketTestBase`
- [ ] Creates `MockERC20` contract
- [ ] All 16+ tests implemented
- [ ] Tests ETH initialization
- [ ] Tests swap-and-pop index mapping
- [ ] Tests payment distribution atomicity
- [ ] Tests diamond balance = 0
- [ ] Uses `getter.isCurrencyAllowed()` not `currencies.isCurrencyAllowed()`
- [ ] All tests pass with `forge test --match-contract CurrencyWhitelistFacetTest -vv`

---

## Your Task

Create `test/CurrencyWhitelistFacetTest.t.sol` implementing all 16-18 tests above. Think through the swap-and-pop algorithm carefully. Verify non-custodial invariants. Don't skip the critical tests marked above.
