# Phase 2: ERC20 Core Marketplace Flows - Comprehensive Prompt

## Context & Requirements

You are implementing a focused ERC20 core-flow test suite to prove the marketplace works end-to-end with ERC20 currencies. This is **Phase 2 of 4** for ERC20 testing, building on Phase 1 (CurrencyWhitelistFacet).

### Critical Background Knowledge

1. **Non-Custodial Payments**
   - ERC20 purchases: buyer approves diamond; diamond calls `transferFrom(buyer, recipient, amount)`.
   - Payment order: marketplace owner (fee) → royalty receiver (if any) → seller.
   - Diamond should hold **zero** ERC20 balance before/after.

2. **Guards & Preconditions**
   - Collection must be whitelisted before listing creation.
   - Currency must be allowed (use `getter.isCurrencyAllowed`).
   - `expectedCurrency` and other expected fields protect against front-running.
   - ERC20 purchases require `msg.value == 0`; ETH listings require exact `msg.value`.
   - Buyer must have sufficient balance **and** allowance for full purchase amount.

3. **Listings & Updates**
   - `createListing` checks currency allowlist and collection whitelist.
   - Updates can change currency: ETH → ERC20, ERC20 → ETH, ERC20A → ERC20B.
   - Listing `feeRate` snapshots at creation and updates.

4. **Token Standards**
   - ERC721 vs ERC1155 is driven by `erc1155Quantity` (0 for ERC721, >0 for ERC1155).
   - Partial buys only for ERC1155 with `partialBuyEnabled` and divisible price.

### Test File Structure

**File:** `test/ERC20MarketplaceTest.t.sol`

**Must:**
- Extend `MarketTestBase` (reuse deployed diamond, facets, mock NFTs).
- Reuse or define a simple `MockERC20` (standard return true; 18 decimals) for core flows.
- Deploy 2+ mock tokens for multi-currency checks.
- Use facet handles from `MarketTestBase`: `market`, `collections`, `currencies`, `getter`.
- Whitelist collections before listings; add currencies via `currencies` (owner-only).

### Required Tests (10-12 total)

#### Group 1: Listing Creation (3 tests)
1. **testCreateERC721ListingInERC20Succeeds**
   - Add token to allowlist; whitelist collection; approve NFT.
   - Create ERC721 listing with ERC20 currency.
   - Assert listing stored with correct `currency` and `feeRate` snapshot.

2. **testCreateERC1155ListingInERC20Succeeds**
   - Whitelist ERC1155 collection; setApprovalForAll.
   - Create ERC1155 listing in ERC20; ensure `erc1155Quantity` set.

3. **testCreateListingWithNonAllowedCurrencyReverts**
   - Skip allowlisting currency; expect `IdeationMarket__CurrencyNotAllowed`.

#### Group 2: Purchases & Payment Flow (3 tests)
4. **testPurchaseERC721WithERC20TransfersFunds**
   - Buyer mints tokens, approves diamond.
   - Purchase listing; assert fee to owner, proceeds to seller, buyer spends price, diamond balance = 0.

5. **testPurchaseERC1155WithERC20FullQuantity**
   - Similar to #4 but ERC1155 listing; assert balances and listing removal.

6. **testPurchaseWithMsgValueRevertsForERC20**
   - Call purchase with `msg.value > 0`; expect `IdeationMarket__WrongPaymentCurrency`.

#### Group 3: Approval & Balance Guards (2 tests)
7. **testPurchaseWithInsufficientAllowanceReverts**
   - Allowance < price; expect revert (transferFrom fails).

8. **testPurchaseWithInsufficientBalanceReverts**
   - Balance < price (even if allowance is enough); expect revert.

#### Group 4: Updates & Front-Run Protection (2-3 tests)
9. **testUpdateListingCurrencyEthToErc20AndBack**
   - Create ETH listing, update to ERC20; verify `currency` stored.
   - Update back to ETH; ensure expectedCurrency guard works (use stale expectedCurrency to revert once, then succeed with fresh expected values).

10. **testUpdateBetweenTwoERC20CurrenciesPersistsNewCurrency**
    - ERC20A listing → update to ERC20B; assert stored currency and purchase requires `expectedCurrency` = ERC20B.

11. **testExpectedCurrencyMismatchReverts**
    - After updating currency, purchase using stale `expectedCurrency`; expect `IdeationMarket__ListingTermsChanged`.

#### Group 5: Cancel & Events (1-2 tests)
12. **testCancelERC20ListingSucceedsAndZeroBalance**
    - Create ERC20 listing; cancel; assert listing removed and diamond ERC20 balance remains 0.

13. **(Optional) testEventsEmitCurrencyAddress**
    - Check `ListingCreated` and `ListingPurchased` carry correct `currency` field (indexed param).

### Common Pitfalls to Avoid

- Do **not** send `msg.value` on ERC20 purchases.
- Always whitelist both collection and currency before listing.
- Use `getter.isCurrencyAllowed`, not `currencies.isCurrencyAllowed` for assertions.
- Approve the correct buyer address and amount before purchase.
- For updates, pass fresh `expected*` parameters to avoid term-mismatch revert.
- Ensure diamond ERC20 balance is asserted to 0 after purchases and cancels.

### Success Criteria

- 10-12 passing tests covering ERC721 and ERC1155 flows with ERC20.
- Non-custodial invariant holds: diamond ERC20 balance stays 0 in all tests.
- Front-running guard (`expectedCurrency`) verified.
- Approval and balance guards verified.
- Update paths between ETH and ERC20 validated.

### Final Checklist Before Submitting

- [ ] Extends `MarketTestBase`
- [ ] MockERC20 deployed (2+ instances)
- [ ] Collections whitelisted before listings
- [ ] Currencies allowlisted before ERC20 listings
- [ ] ERC721 and ERC1155 listings covered
- [ ] Purchases assert fee/seller/buyer balances and diamond balance = 0
- [ ] msg.value > 0 on ERC20 purchase reverts
- [ ] Insufficient balance/allowance reverts
- [ ] Update currency ETH ↔ ERC20, ERC20A ↔ ERC20B covered
- [ ] expectedCurrency mismatch tested
- [ ] Cancel ERC20 listing tested
- [ ] Events checked for currency (if optional test included)
- [ ] `forge test --match-contract ERC20MarketplaceTest -vv` passes
