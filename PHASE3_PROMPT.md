# Phase 3: ERC20 Payment Distribution - Comprehensive Prompt

## Context & Requirements

You are implementing a comprehensive test suite for **ERC20 payment distribution** to verify the atomic non-custodial push payment system with fees and royalties. This is **Phase 3 of 4** for ERC20 testing, building on Phase 1 (CurrencyWhitelistFacet) and Phase 2 (ERC20 Core Flows).

### Critical Background Knowledge

1. **Payment Distribution Architecture (_distributePayments, IdeationMarketFacet.sol:1027-1105)**
   ```solidity
   // Payment Order (both ETH and ERC20):
   // 1. Marketplace owner receives innovation fee (FIRST - most trusted)
   // 2. Royalty receiver receives royalty (SECOND - if ERC2981 and amount > 0)
   // 3. Seller receives proceeds (LAST - least trusted)
   
   // For ERC20:
   _safeTransferFrom(currency, buyer, marketplaceOwner, innovationFee);
   if (royaltyAmount > 0 && royaltyReceiver != address(0)) {
       _safeTransferFrom(currency, buyer, royaltyReceiver, royaltyAmount);
   }
   _safeTransferFrom(currency, buyer, seller, sellerProceeds);
   ```

2. **Fee Calculation**
   - Fee denominator: **100,000** (e.g., 1,000 = 1%)
   - Fee snapshots per listing: `listing.feeRate` captured at creation/update
   - Innovation fee: `(purchasePrice * feeRate) / 100000`
   - Remaining proceeds: `purchasePrice - innovationFee`
   - Seller proceeds: `remainingProceeds - royaltyAmount` (if ERC2981 applicable)

3. **Royalty Handling (ERC2981)**
   - Contract checks: `supportsInterface(IERC2981.interfaceId)`
   - Royalty info: `royaltyInfo(tokenId, salePrice)` returns `(receiver, amount)`
   - Royalty deducted from **seller proceeds**, not buyer payment
   - Edge cases:
     - `receiver == address(0)` → skip royalty payment (set amount = 0)
     - `royaltyAmount > remainingProceeds` → revert with `IdeationMarket__RoyaltyFeeExceedsProceeds`
     - `royaltyAmount == 0` → skip payment, no revert

4. **Non-Custodial Invariant**
   - Diamond **NEVER** holds ERC20 tokens
   - All transfers: `transferFrom(buyer, recipient, amount)` directly
   - After every purchase: `diamond.balanceOf(token) == 0`

5. **_safeTransferFrom (line 1079-1105)**
   - Handles non-standard ERC20 tokens:
     - USDT/XAUt (no return value)
     - Tokens that return false instead of reverting
   - Low-level call to avoid ABI decoding issues
   - Checks: `success && (returndata.length == 0 || abi.decode(returndata, (bool)))`
   - Reverts with: `IdeationMarket__ERC20TransferFailed(token, to)`

### Test File Structure

**File:** `test/ERC20PaymentDistributionTest.t.sol`

**Must:**
- Extend `MarketTestBase` (reuse diamond, facets, mock NFTs)
- Create enhanced `MockERC20` with configurable behavior:
  - Standard compliant (returns bool)
  - Non-standard (no return value like USDT)
  - Failing token (returns false)
  - Various decimals (6, 18, 30)
- Create `MockERC721Royalty` extending `MockERC721` with ERC2981 support
- Use facet handles: `market`, `collections`, `currencies`, `getter`, `ownership`

### Required Tests (8-10 total)

#### Group 1: Basic Payment Distribution (3 tests)

1. **testMarketplaceFeeDistributionWithERC20**
   - Create ERC721 listing in ERC20 with price 100 tokens
   - Buyer approves marketplace and purchases
   - Capture owner balance before/after
   - Calculate expected fee: `(100 * INNOVATION_FEE) / 100000`
   - Assert: `ownerBalanceAfter - ownerBalanceBefore == expectedFee`
   - Assert: Diamond ERC20 balance = 0

2. **testSellerProceedsWithERC20**
   - Create listing with price 500 tokens
   - Calculate expected proceeds: `500 - (500 * INNOVATION_FEE) / 100000`
   - Purchase and verify seller receives exact proceeds
   - Assert: `sellerBalanceAfter - sellerBalanceBefore == expectedProceeds`
   - Assert: Diamond ERC20 balance = 0

3. **testCompletePaymentFlowWithERC20**
   - Create listing with price 1000 tokens
   - Capture balances: buyer, seller, owner BEFORE
   - Purchase listing
   - Verify:
     - Buyer spent exactly 1000 tokens
     - Owner received fee
     - Seller received proceeds (1000 - fee)
     - `ownerFee + sellerProceeds == 1000` (no dust)
     - Diamond balance = 0
   - Assert listing deleted after purchase

#### Group 2: Royalty Distribution (3 tests)

4. **testRoyaltyPaymentWithERC20**
   - Deploy `MockERC721Royalty` with 10% royalty (10,000 basis points)
   - Mint token to seller, set royalty receiver
   - Create listing with price 1000 tokens
   - Calculate:
     - Innovation fee: `(1000 * INNOVATION_FEE) / 100000`
     - Remaining: `1000 - innovationFee`
     - Royalty: `1000 * 10000 / 100000 = 100`
     - Seller proceeds: `remaining - royalty`
   - Purchase and verify all three recipients receive correct amounts
   - Assert: `ownerFee + royalty + sellerProceeds == 1000`

5. **testZeroRoyaltyDoesNotRevert**
   - Deploy ERC721 with ERC2981 support but `royaltyAmount = 0`
   - Verify purchase succeeds
   - Verify only owner and seller receive payments (royalty receiver gets 0)
   - Diamond balance = 0

6. **testRoyaltyExceedsProceedsReverts**
   - Set marketplace fee very high (e.g., 95%)
   - Set royalty to 10%
   - Create listing: innovation fee leaves < 10% for seller
   - Purchase should revert with `IdeationMarket__RoyaltyFeeExceedsProceeds`

#### Group 3: Edge Cases & Precision (2-3 tests)

7. **testTinyAmountsDistributionExact**
   - Create listing with price = 100 tokens (smallest practical amount)
   - Calculate fee with rounding: `(100 * INNOVATION_FEE) / 100000`
   - Verify distribution is exact (no dust lost/gained)
   - Assert: `ownerFee + sellerProceeds == 100`

8. **testHundredPercentFeeEdgeCase**
   - Temporarily set marketplace fee to 100,000 (100%)
   - Create listing
   - Purchase: owner gets 100%, seller gets 0
   - Assert: `sellerProceeds == 0`, `ownerFee == price`
   - Restore original fee for cleanup

9. **(Optional) testMultipleDecimalsTokensDistribution**
   - Deploy 3 tokens: 6, 18, 30 decimals
   - Create listings in each
   - Purchase all three
   - Verify payment math is exact for all decimal counts
   - Diamond balance = 0 for all tokens

#### Group 4: Payment Failure Handling (2 tests)

10. **testPaymentDistributionAtomicity**
    - Create mock token that fails on 3rd transfer (seller payment)
    - Purchase should revert completely (no partial payments)
    - Verify: owner and royalty receiver did NOT receive tokens (tx reverted)
    - This tests CEI pattern and atomicity

11. **testNonStandardERC20PaymentDistribution**
    - Deploy `MockERC20NoReturn` (USDT-like, no return value)
    - Add to allowlist, create listing
    - Purchase successfully
    - Verify `_safeTransferFrom` handles no-return-value tokens
    - All recipients receive correct amounts

### Helper Functions & Mocks

#### MockERC721Royalty
```solidity
contract MockERC721Royalty is MockERC721 {
    address public royaltyReceiver;
    uint96 public royaltyBasisPoints; // out of 100,000
    
    function supportsInterface(bytes4 interfaceId) 
        public pure override returns (bool) {
        return interfaceId == type(IERC2981).interfaceId 
            || super.supportsInterface(interfaceId);
    }
    
    function royaltyInfo(uint256, uint256 salePrice) 
        external view returns (address, uint256) {
        uint256 royaltyAmount = (salePrice * royaltyBasisPoints) / 100000;
        return (royaltyReceiver, royaltyAmount);
    }
    
    function setRoyalty(address receiver, uint96 bps) external {
        royaltyReceiver = receiver;
        royaltyBasisPoints = bps;
    }
}
```

#### MockERC20NoReturn
```solidity
contract MockERC20NoReturn {
    // Same as MockERC20 but transferFrom doesn't return bool (USDT-like)
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    function transferFrom(address from, address to, uint256 amount) external {
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        require(balanceOf[from] >= amount, "insufficient balance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        // NO RETURN VALUE
    }
}
```

#### Helper Functions
```solidity
function _createRoyaltyListing(
    MockERC721Royalty nft,
    uint256 tokenId,
    address currency,
    uint256 price,
    address royaltyReceiver,
    uint96 royaltyBps
) internal returns (uint128 listingId) {
    // Setup: whitelist, set royalty, approve, create listing
}

function _calculateExpectedDistribution(uint256 price, uint96 royaltyBps) 
    internal view returns (uint256 fee, uint256 royalty, uint256 sellerProceeds) {
    // Helper to calculate expected distribution
}
```

### Common Pitfalls to Avoid

❌ **Don't forget** to whitelist collection AND allowlist currency before listing
❌ **Don't use** integer division without considering rounding (test with exact values)
❌ **Don't assume** royalty receiver is always valid (could be address(0))
❌ **Don't skip** asserting diamond balance = 0 after EVERY purchase
❌ **Don't forget** buyer needs to approve marketplace for full purchase amount
❌ **Don't test** only happy paths (test royalty edge cases: 0, 100%, exceeds proceeds)
❌ **Don't ignore** non-standard ERC20 behavior (no return value)

### Calculation Reference

For a purchase of **1000 tokens** with:
- Innovation fee: 1% (1,000 basis points)
- Royalty: 10% (10,000 basis points)

```
purchasePrice = 1000
innovationFee = (1000 * 1000) / 100000 = 10
remainingProceeds = 1000 - 10 = 990
royaltyAmount = (1000 * 10000) / 100000 = 100
sellerProceeds = 990 - 100 = 890

Verify: 10 + 100 + 890 = 1000 ✅
```

### Success Criteria

✅ All 8-10 tests pass
✅ Marketplace fee distribution verified with exact math
✅ Seller proceeds calculation correct (after fee AND royalty deduction)
✅ Royalty payment verified (when applicable)
✅ Edge cases covered: 0 royalty, 100% fee, royalty > proceeds
✅ Non-custodial invariant maintained: diamond balance = 0
✅ Non-standard ERC20 handling tested
✅ Payment atomicity verified (all or nothing)
✅ Multiple decimal precisions tested (optional)

### Final Checklist Before Submitting

- [ ] Extends `MarketTestBase`
- [ ] `MockERC721Royalty` with ERC2981 support implemented
- [ ] `MockERC20NoReturn` for non-standard token testing
- [ ] All 8+ tests implemented
- [ ] Fee calculation verified with explicit math
- [ ] Royalty deduction verified from seller proceeds
- [ ] Edge cases tested: 0 royalty, 100% fee, exceeds proceeds
- [ ] Diamond balance = 0 asserted in all purchase tests
- [ ] Payment order validated: owner → royalty → seller
- [ ] Atomicity tested (failure reverts all payments)
- [ ] Non-standard token (no return value) tested
- [ ] `forge test --match-contract ERC20PaymentDistributionTest -vv` passes

---

## Your Task

Create `test/ERC20PaymentDistributionTest.t.sol` implementing all 8-10 tests above. Focus on **exact balance assertions** with explicit fee/royalty math. Verify the non-custodial invariant (diamond balance = 0) in every purchase test. Test edge cases thoroughly: zero royalty, 100% fee, royalty exceeding proceeds. Don't skip the atomicity and non-standard ERC20 tests.

**Key Principle:** Every test should capture balances BEFORE purchase, calculate expected distribution based on fee/royalty math, execute purchase, and assert AFTER balances match expected values. The sum of all payments must equal the purchase price (no dust).
