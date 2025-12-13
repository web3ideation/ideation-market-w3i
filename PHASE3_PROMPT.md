# Phase 3: Advanced ERC20 Scenarios - Comprehensive Prompt

## Context & Requirements

You are implementing an advanced ERC20 test suite to validate complex marketplace interactions with ERC20 currencies. This is **Phase 3 of 4** for ERC20 testing, building on Phase 1 (CurrencyWhitelistFacet) and Phase 2 (ERC20 Core Flows).

### Critical Background Knowledge

1. **ERC2981 Royalty Integration**
   - NFT collections can implement `IERC2981.royaltyInfo(tokenId, salePrice)`.
   - Returns `(receiver, amount)` — royalty is deducted from seller's proceeds.
   - If `receiver == address(0)` or `amount == 0`, royalty is skipped.
   - Royalty is paid BEFORE seller (payment order: owner fee → royalty → seller).
   - **Critical invariant**: `royaltyAmount <= remainingProceeds` (checked during purchase).

2. **Partial Buy for ERC1155**
   - ERC1155 listings can enable `partialBuyEnabled = true`.
   - Buyer specifies `erc1155PurchaseQuantity <= erc1155Quantity`.
   - Price is pro-rata: `unitPrice = price / quantity; purchasePrice = unitPrice * buyQuantity`.
   - After partial buy, listing remains with reduced quantity and price.
   - All payments (fee, royalty, seller proceeds) scale with `purchasePrice` (not full `price`).

3. **NFT Swaps with ERC20 Payment**
   - Buyer can provide a desired NFT (ERC721 or ERC1155) as part of purchase.
   - `desiredTokenAddress`, `desiredTokenId`, `desiredErc1155Quantity` define the swap target.
   - Marketplace transfers: seller's NFT → buyer, buyer's desired NFT → seller.
   - Payment still flows: buyer → owner fee, royalty, seller proceeds (in ERC20).
   - Swap NFTs are transferred AFTER listed NFT is moved (CEI pattern).

4. **Multi-Currency Payment Mixing (Advanced)**
   - A seller can list multiple items in different currencies simultaneously.
   - Buyer can purchase different listings (different currencies) in sequence.
   - Each purchase uses its own currency; diamond balance per currency must stay 0.
   - Fee and royalty deductions are currency-specific (not mixed).

5. **Payment Math with Royalty & Partial Buy**
   ```
   purchasePrice = erc1155PurchaseQuantity > 0 ? (price / quantity) * buyQuantity : price
   innovationFee = (purchasePrice * feeRate) / 100000
   remainingProceeds = purchasePrice - innovationFee
   
   if (hasRoyalty && receiver != address(0)) {
       if (royaltyAmount > remainingProceeds) revert RoyaltyExceedsProceeds
       remainingProceeds -= royaltyAmount
   }
   
   sellerProceeds = remainingProceeds
   ```

### Test File Structure

**File:** `test/ERC20AdvancedTest.t.sol` (new file)

**Must:**
- Extend `MarketTestBase` for standard setup.
- Create or import `MockERC721Royalty` and `MockERC1155Royalty` contracts:
  - Implement ERC2981 interface: `royaltyInfo(uint256 tokenId, uint256 salePrice) returns (address receiver, uint256 amount)`
  - Allow setting royalty rate and receiver via test helper functions.
  - Support standard ERC721/ERC1155 operations (mint, approve, transferFrom).
- Reuse `MockERC20` from Phase 1 & 2 or define inline.
- Deploy royalty-enabled NFT collections in `setUp()`.
- Use existing facet references from `MarketTestBase`: `market`, `collections`, `getter`, `currencies`.

### Required Tests (12-15 total)

#### **Group 1: Royalty Payment with ERC20 (3-4 tests)**

1. **testERC20RoyaltyPaymentERC721**
   - Create ERC721 listing with royalty (10% to royalty receiver) in ERC20.
   - Purchase; assert:
     - Owner receives fee = `price * feeRate / 100000`
     - Royalty receiver receives 10% of purchase price
     - Seller receives remainder = `price - fee - royalty`
     - Diamond balance = 0
     - Listing removed

2. **testERC20RoyaltyPaymentERC1155FullQuantity**
   - Create ERC1155 listing (qty=5, price=10 ether) with 5% royalty in ERC20.
   - Purchase full quantity; assert royalty deducted from seller proceeds.
   - **Verify**: `sellerProceeds = 10 ether - fee - royalty`

3. **testERC20RoyaltyHighRate**
   - Create listing with high royalty (50% of sale price).
   - Purchase; assert royalty paid correctly and seller gets remainder.
   - **Edge case**: Ensure royalty doesn't exceed proceeds (should still work if < proceeds).

4. **(Optional) testERC20RoyaltyExceedsProceeds**
   - Create listing with very high royalty (99% of sale price).
   - Purchase should revert with `IdeationMarket__RoyaltyFeeExceedsProceeds`.
   - **Note**: May be difficult to construct; skip if royalty is capped in contract.

#### **Group 2: Partial Buy ERC1155 with ERC20 (3 tests)**

5. **testERC20PartialBuyERC1155ScaledPayments**
   - Create ERC1155 listing: qty=10, price=100 ether, `partialBuyEnabled=true` in ERC20.
   - Partial purchase: buyQuantity=5 (50%).
   - Assert purchasePrice = 50 ether.
   - Assert fee, royalty, seller proceeds all calculated on 50 ether (not 100 ether).
   - Assert listing remains with qty=5, price=50 ether.

6. **testERC20PartialBuyThenFullBuyERC1155**
   - Create ERC1155 listing: qty=10, price=100 ether, partial enabled in ERC20.
   - First buyer purchases 4 units → listing now qty=6, price=60 ether.
   - Second buyer purchases remaining 6 units.
   - Assert both purchases have correct scaled fees and seller proceeds.
   - Assert diamond balance = 0 throughout.

7. **testERC20PartialBuyRoyaltyScaled**
   - Create ERC1155 with royalty (10%) and partial buy enabled in ERC20.
   - Partial purchase (50% of qty) with scaled fee and royalty.
   - Assert both fee and royalty are calculated on pro-rata purchasePrice.

#### **Group 3: NFT Swaps with ERC20 Payment (2-3 tests)**

8. **testERC20SwapERC721ToERC721**
   - Seller lists NFT A, wants NFT B in return, price in ERC20.
   - Buyer holds NFT B and approves it.
   - Purchase: NFT A → buyer, NFT B → seller, ERC20 → owner/royalty/seller.
   - Assert:
     - Owner receives fee in ERC20
     - Seller receives proceeds in ERC20 AND NFT B
     - Buyer receives NFT A (no ERC20 sent from buyer to seller; only to owner/royalty)
     - Diamond ERC20 balance = 0

9. **testERC20SwapERC1155ToERC721**
   - Seller lists ERC1155 (qty=5), wants specific ERC721 as swap.
   - Buyer purchases partial (qty=2) with swap.
   - Assert:
     - Buyer receives 2 units of ERC1155
     - Seller receives desired ERC721
     - Payment: fee and proceeds to owner/royalty/seller in ERC20
     - Listing reduces to qty=3, price adjusted

10. **(Optional) testERC20SwapWithRoyalty**
    - NFT A has 5% royalty and is being swapped for NFT B.
    - Purchase with swap in ERC20; assert royalty still deducted from seller proceeds.

#### **Group 4: Multi-Currency Payment Sequences (2-3 tests)**

11. **testMultipleERC20ListingsDifferentCurrencies**
    - Seller creates 2 listings:
      - Listing 1: NFT A, price 10 tokenA
      - Listing 2: NFT B, price 20 tokenB
    - Buyer purchases both in sequence (separate txs).
    - Assert:
      - Owner receives fee in tokenA and tokenB (independent)
      - Seller receives proceeds in tokenA and tokenB
      - Buyer spends 10 tokenA + 20 tokenB
      - `diamond.balanceOf(tokenA) == 0` AND `diamond.balanceOf(tokenB) == 0`

12. **testMultipleBuyersMultipleCurrencies**
    - Two sellers create listings in different currencies.
    - Two buyers purchase from different sellers simultaneously (in same block or sequential).
    - Assert currency independence: fees/proceeds per currency are correct.
    - Assert non-custodial invariant for both currencies.

13. **(Optional) testPartialBuyMultipleCurrencies**
    - Seller lists ERC1155 in tokenA with partial buy enabled.
    - Multiple buyers each do partial buys in tokenA.
    - Assert all partial buy scaling works correctly and currency balance stays 0.

#### **Group 5: Edge Cases & State Consistency (2 tests)**

14. **testERC20RoyaltyZeroAmountEdgeCase**
    - Listing with `royaltyInfo()` returning `(receiver, 0)`.
    - Purchase should skip royalty payment (even if receiver is non-zero).
    - Seller receives full proceeds (minus fee).

15. **testERC20PartialBuyRemainingQuantityInvalidation**
    - Create ERC1155 with partial buy enabled in ERC20.
    - Buyer1 purchases leaving insufficient quantity for a swap requirement.
    - Buyer2 attempts purchase with swap that would fail due to insufficient qty.
    - Assert appropriate revert behavior.

### Common Pitfalls to Avoid

- **Royalty Math**: Royalty is deducted from `remainingProceeds` (after fee), not from `purchasePrice`.
- **Partial Buy Scaling**: `purchasePrice = (price / quantity) * buyQuantity`. Ensure division happens before multiplication to avoid rounding.
- **Swap Order**: NFT swaps happen AFTER listed NFT is transferred (CEI pattern). Validate in contract flow.
- **Currency Independence**: Different ERC20 currencies should NOT interfere with each other's balances or fee calculations.
- **Royalty + Partial Buy**: Both apply independently; both scale with `purchasePrice`.
- **Diamond Balance**: Must be 0 for EVERY currency at the end of EVERY test involving that currency.
- **Royalty Receiver Validation**: If `royaltyInfo()` returns `address(0)`, skip payment (contract handles this).

### Success Criteria

- 12-15 passing tests covering:
  - Royalty deduction with ERC20 (3-4 tests)
  - Partial buy with ERC20 and scaled payments (3 tests)
  - NFT swaps with ERC20 payment (2-3 tests)
  - Multi-currency independence (2-3 tests)
  - Edge cases (2 tests)
- All assertions validate actual balance changes, not just reverts.
- Non-custodial invariant (`diamond.balanceOf(currency) == 0`) verified in every test.
- Royalty, fee, and seller proceeds math explicitly checked with expected values.
- Partial buy quantity and price scaling validated.

### Final Checklist Before Submitting

- [ ] Extends `MarketTestBase`
- [ ] MockERC721Royalty and MockERC1155Royalty deployed and configured
- [ ] MockERC20 instances deployed (2-3 for multi-currency tests)
- [ ] Collections whitelisted before listings
- [ ] Currencies allowlisted before ERC20 listings
- [ ] Royalty tests assert owner fee, royalty receiver, seller proceeds separately
- [ ] Royalty deduction verified (seller proceeds = price - fee - royalty)
- [ ] Partial buy tests verify pro-rata pricing: `(price / qty) * buyQty`
- [ ] Partial buy tests check fee/royalty scaled correctly
- [ ] Swap tests verify NFT transfers AND ERC20 payment flow
- [ ] Multi-currency tests assert independent fee/proceeds per currency
- [ ] Diamond balance = 0 for all currencies in all tests
- [ ] Edge case: royalty = 0 handled correctly
- [ ] Edge case: royalty > remaining proceeds reverted or handled
- [ ] All balance assertions use explicit expected values (no magic numbers)
- [ ] `forge test --match-contract ERC20AdvancedTest -vv` passes

### Test Execution Expectations

- **Gas**: Royalty-enabled listings and swaps will use 10-20% more gas than basic purchases.
- **Setup**: Expect longer test setup due to MockERC721Royalty/ERC1155Royalty initialization.
- **Time**: Full suite should execute in <100ms.
- **Confidence**: Phase 3 tests should achieve 95%+ detection rate for royalty/partial-buy/swap bugs.

### Notes

- Phase 3 is **optional but recommended** for production-grade ERC20 support.
- If royalty tests prove complex, start with simpler cases (10% fixed royalty) before edge cases.
- Partial buy tests leverage existing ERC1155 infrastructure; focus on ERC20 + quantity math.
- Swap tests are heavyweight but critical for marketplace integrity; validate both token transfers AND payment flow.
- Multi-currency tests ensure ERC20 is truly modular (not hardcoded to single currency).

