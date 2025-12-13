# Phase 4: ERC20 Security & Attack Vectors - Comprehensive Prompt

## Context & Requirements

You are implementing a comprehensive security test suite for **ERC20 attack vectors and edge cases** to ensure the marketplace is hardened against malicious tokens and exploits. This is **Phase 4 of 4** for ERC20 testing, building on Phase 1 (CurrencyWhitelistFacet), Phase 2 (ERC20 Core Flows), and Phase 3 (ERC20 Payment Distribution).

### Critical Background Knowledge

1. **Security Architecture**
   ```solidity
   // Defense Layers:
   // 1. Currency Allowlist: diamondOwner curates trusted tokens (blocks fee-on-transfer, rebasing)
   // 2. nonReentrant Modifier: prevents reentrancy attacks
   // 3. _safeTransferFrom: handles non-standard tokens and failures
   // 4. Front-run Protection: expectedCurrency guard
   // 5. CEI Pattern: payment distribution after NFT transfer
   ```

2. **_safeTransferFrom Implementation (IdeationMarketFacet.sol:1079-1105)**
   ```solidity
   function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
       bytes memory data = abi.encodeWithSelector(0x23b872dd, from, to, amount);
       (bool success, bytes memory returndata) = token.call(data);
       
       // Handles 3 cases:
       // 1. Call succeeds + returns true → success
       // 2. Call succeeds + no return data (USDT) → success
       // 3. Call fails OR returns false → revert
       if (!success || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
           revert IdeationMarket__ERC20TransferFailed(token, to);
       }
   }
   ```

3. **Reentrancy Protection**
   - `nonReentrant` modifier on `purchaseListing()` (line 326)
   - No callbacks/hooks during ERC20 transfers (unlike ERC777)
   - Even if malicious token tries callback, modifier blocks it

4. **Front-Running Guards**
   - Purchase requires `expectedCurrency` parameter
   - Reverts with `IdeationMarket__ListingTermsChanged` if currency changed
   - Protects buyer from listing updates between tx submission and execution

5. **Approval Flow**
   - Buyer must approve marketplace: `token.approve(diamond, amount)`
   - Diamond checks allowance via `transferFrom(buyer, recipient, amount)`
   - Insufficient allowance → ERC20 transfer fails → tx reverts

### Test File Structure

**File:** `test/ERC20SecurityTest.t.sol`

**Must:**
- Extend `MarketTestBase` for standard setup
- Create malicious token mocks for attack scenarios
- Create edge case token mocks (various decimals, behaviors)
- Test both ERC721 and ERC1155 flows where applicable
- Use facet handles: `market`, `collections`, `currencies`, `getter`

### Required Tests (14-18 total)

#### Group 1: Malicious Token Behaviors (5 tests)

1. **testMaliciousERC20RevertsOnTransfer**
   - Create `MaliciousERC20Reverting` that reverts on `transferFrom()`
   - Add to allowlist, create listing
   - Buyer approves and attempts purchase
   - Assert: Purchase reverts with `IdeationMarket__ERC20TransferFailed`
   - Verify: No partial payments (all recipients have same balance before/after)

2. **testMaliciousERC20ReturnsFalse**
   - Create `MaliciousERC20ReturnsFalse` that returns `false` instead of reverting
   - Add to allowlist, create listing
   - Buyer attempts purchase
   - Assert: `_safeTransferFrom` catches false return and reverts
   - Assert: Transaction reverts with `IdeationMarket__ERC20TransferFailed`

3. **testMaliciousERC20PartialTransfer**
   - Create token that transfers only 50% of requested amount (fee-on-transfer simulation)
   - Even if added to allowlist (policy mistake), verify behavior
   - Create listing, buyer approves full amount
   - Purchase: verify all recipients receive amounts
   - **NOTE:** System can't detect this - responsibility of allowlist curation
   - Document expected behavior: recipients get less than expected, but tx succeeds

4. **testReentrancyAttemptViaERC20Blocked**
   - Create `ReentrantERC20` that tries to call `purchaseListing()` again during transfer
   - Add to allowlist, create 2 listings
   - Purchase first listing → during transfer, token attempts to purchase second listing
   - Assert: `nonReentrant` modifier blocks the callback
   - Assert: First purchase completes, second attempt reverts

5. **testMaliciousERC20ExcessiveGasConsumption**
   - Create token with expensive transferFrom (e.g., lots of storage writes)
   - Verify purchase completes without hitting gas limits
   - If gas limit concerns exist, document acceptable gas ranges
   - **NOTE:** This tests system doesn't break under high-gas tokens

#### Group 2: Approval & Balance Edge Cases (4 tests)

6. **testInsufficientApprovalReverts**
   - Create listing with price 1000 tokens
   - Buyer approves only 500 tokens
   - Purchase attempt
   - Assert: Reverts with `IdeationMarket__ERC20TransferFailed`
   - Verify: No tokens transferred to any recipient

7. **testInsufficientBuyerBalanceReverts**
   - Create listing with price 1000 tokens
   - Buyer approves 1000 but only has 500 balance
   - Purchase attempt
   - Assert: Reverts (ERC20 transfer fails)
   - Verify: No balance changes for any party

8. **testBuyerReducesBalanceBetweenApprovalAndPurchase**
   - Buyer approves 1000 tokens
   - Buyer transfers 500 away (balance now 500)
   - Purchase attempt for 1000
   - Assert: Reverts due to insufficient balance
   - This tests the approval-spend pattern security

9. **testZeroAmountPurchasePrevented**
   - Attempt to create listing with price = 0 in ERC20
   - If allowed, attempt purchase
   - Verify system behavior (likely succeeds with 0 transfers)
   - Assert: No unexpected reverts, diamond balance = 0

#### Group 3: Front-Running Protection (3 tests)

10. **testExpectedCurrencyMismatchReverts**
    - Create listing in tokenA
    - Seller updates listing to tokenB
    - Buyer attempts purchase with `expectedCurrency = tokenA` (stale)
    - Assert: Reverts with `IdeationMarket__ListingTermsChanged`
    - Buyer NOT charged incorrectly

11. **testExpectedCurrencyETHToERC20Switch**
    - Create listing in ETH (address(0))
    - Seller updates to ERC20
    - Buyer sends ETH with `expectedCurrency = address(0)`
    - Assert: Reverts (currency changed)
    - Protects buyer from unexpected token requirements

12. **testExpectedCurrencyERC20ToETHSwitch**
    - Create listing in ERC20
    - Seller updates to ETH
    - Buyer approves ERC20 and purchases with `expectedCurrency = tokenA`
    - Assert: Reverts (currency changed)
    - Buyer's ERC20 approval unused, no tokens taken

#### Group 4: Payment Distribution Failures (2 tests)

13. **testPaymentDistributionAtomicityOwnerFails**
    - Create token that fails on 1st transfer (marketplace owner)
    - Create listing, buyer approves and purchases
    - Assert: Entire transaction reverts
    - Verify: Seller and royalty receiver got nothing (atomic)

14. **testPaymentDistributionAtomicitySellerFails**
    - Create token that fails on 3rd transfer (seller)
    - Create listing with royalty
    - Buyer approves and purchases
    - Assert: Entire transaction reverts
    - Verify: Owner and royalty receiver got nothing (atomic)
    - This proves CEI pattern + atomicity

#### Group 5: Decimal Precision & Overflow (3 tests)

15. **testVariousDecimalTokensCalculationCorrectness**
    - Deploy tokens: 0 decimals, 6 decimals, 18 decimals, 30 decimals
    - Create listing in each with equivalent "1000 unit" value
    - Calculate fee and proceeds for each
    - Purchase and verify:
      - 0 decimals: fee = 0 might occur (document)
      - 6 decimals (USDC): typical case, exact math
      - 18 decimals (standard): baseline case
      - 30 decimals: no overflow, exact math
    - Diamond balance = 0 for all

16. **testExtremelySmallAmountsRounding**
    - Token with 18 decimals, price = 1 wei
    - Calculate: `fee = (1 * 1000) / 100000 = 0` (truncated)
    - Purchase: seller gets full 1 wei, owner gets 0
    - Document: Minimum viable price depends on fee rate
    - Assert: No unexpected reverts

17. **testExtremelyLargeAmountsNearUint256Max**
    - Create token with huge supply
    - Listing price = `type(uint96).max` or similar large value
    - Purchase with large amounts
    - Verify: No overflow in fee calculation
    - Assert: `(price * feeRate) / 100000` doesn't overflow
    - **NOTE:** Fee rate max is 100,000, so calculation should be safe

#### Group 6: Mixed Scenarios & Integration (3-4 tests)

18. **testPurchaseWithMsgValueForERC20ListingReverts**
    - Create ERC20 listing
    - Buyer sends msg.value > 0 during purchase
    - Assert: Reverts with `IdeationMarket__WrongPaymentCurrency`
    - Buyer's ETH refunded via revert

19. **testERC20PurchaseWhilePausedReverts**
    - Create ERC20 listing
    - Owner pauses marketplace
    - Buyer attempts purchase
    - Assert: Reverts with pause error
    - Unpause and retry → succeeds

20. **testMultipleERC20TokensInSameContract**
    - Add 3 different ERC20 tokens to allowlist
    - Create 3 listings (1 per token)
    - Purchase all 3 in sequence
    - Verify: All payments distributed correctly
    - Assert: Diamond balance = 0 for all 3 tokens

21. **(Optional) testERC20SwapListingWithPayment**
    - Create swap listing: NFT A for NFT B + 100 ERC20 tokens
    - Buyer owns NFT B, approves ERC20
    - Purchase swap listing
    - Verify:
      - NFT A → buyer
      - NFT B → seller
      - 100 ERC20 → distributed (fee, seller)
    - Diamond balances = 0 (ERC20 and NFTs)

### Mock Contracts Required

#### MaliciousERC20Reverting
```solidity
contract MaliciousERC20Reverting {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function transferFrom(address, address, uint256) external pure returns (bool) {
        revert("MaliciousERC20: transfer failed");
    }
}
```

#### MaliciousERC20ReturnsFalse
```solidity
contract MaliciousERC20ReturnsFalse {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) 
        external returns (bool) {
        // Deduct allowance and balance but return false
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        require(balanceOf[from] >= amount, "insufficient balance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return false; // ⚠️ Returns false despite successful transfer
    }
}
```

#### ReentrantERC20
```solidity
contract ReentrantERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    address public marketplace;
    uint128 public targetListingId;
    bool public hasReentered;
    
    constructor(address _marketplace) {
        marketplace = _marketplace;
    }
    
    function setTarget(uint128 listingId) external {
        targetListingId = listingId;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) 
        external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        require(balanceOf[from] >= amount, "insufficient balance");
        
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        
        // Attempt reentrancy on first transfer
        if (!hasReentered && targetListingId != 0) {
            hasReentered = true;
            // Try to call purchaseListing again
            IIdeationMarketFacet(marketplace).purchaseListing(
                targetListingId, 1 ether, address(this), 0, 
                address(0), 0, 0, 0, address(0)
            );
        }
        
        return true;
    }
}
```

#### FeeOnTransferERC20
```solidity
contract FeeOnTransferERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public transferFeePercent = 50; // 50% fee
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) 
        external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        require(balanceOf[from] >= amount, "insufficient balance");
        
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        
        // Only transfer 50% of amount (fee-on-transfer)
        uint256 actualAmount = (amount * transferFeePercent) / 100;
        balanceOf[to] += actualAmount;
        
        return true;
    }
}
```

#### MockERC20WithDecimals
```solidity
contract MockERC20WithDecimals {
    string public name;
    string public symbol;
    uint8 public decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) 
        external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        require(balanceOf[from] >= amount, "insufficient balance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}
```

### Helper Functions

```solidity
// Helper to create listing with malicious token
function _createMaliciousTokenListing(
    address token,
    uint256 price,
    uint256 tokenId
) internal returns (uint128 listingId) {
    vm.startPrank(owner);
    currencies.addAllowedCurrency(token);
    collections.addWhitelistedCollection(address(erc721));
    vm.stopPrank();
    
    vm.startPrank(seller);
    erc721.approve(address(diamond), tokenId);
    market.createListing(
        address(erc721), tokenId, address(0), price, token,
        address(0), 0, 0, 0, false, false, new address[](0)
    );
    vm.stopPrank();
    
    listingId = getter.getNextListingId() - 1;
}

// Helper to attempt purchase with malicious token
function _attemptPurchaseWithMaliciousToken(
    address token,
    uint128 listingId,
    uint256 price
) internal {
    MockERC20(token).mint(buyer, price);
    
    vm.startPrank(buyer);
    MockERC20(token).approve(address(diamond), price);
    market.purchaseListing(
        listingId, price, token, 0, 
        address(0), 0, 0, 0, address(0)
    );
    vm.stopPrank();
}
```

### Test Patterns

#### Pattern 1: Balance Snapshot Testing
```solidity
uint256 ownerBefore = token.balanceOf(owner);
uint256 sellerBefore = token.balanceOf(seller);
uint256 buyerBefore = token.balanceOf(buyer);

// Execute operation

uint256 ownerAfter = token.balanceOf(owner);
uint256 sellerAfter = token.balanceOf(seller);
uint256 buyerAfter = token.balanceOf(buyer);

// Assert no changes if reverted
assertEq(ownerAfter, ownerBefore, "Owner balance changed");
assertEq(sellerAfter, sellerBefore, "Seller balance changed");
assertEq(buyerAfter, buyerBefore, "Buyer balance changed");
```

#### Pattern 2: Atomicity Testing
```solidity
// Setup malicious token that fails on specific transfer
// Purchase attempt → entire tx reverts
// Verify ALL recipients have unchanged balances (atomicity)
```

#### Pattern 3: Reentrancy Detection
```solidity
// Create token with reentrancy attempt
// Track reentrancy attempts
// Assert nonReentrant blocked the callback
assertEq(reentrantToken.reentrancyAttempts(), 0, "Reentrancy not blocked");
```

### Success Criteria

1. **All malicious token attacks blocked** ✅
   - Reverting tokens caught
   - False-returning tokens caught
   - Reentrancy attempts blocked

2. **Approval edge cases handled** ✅
   - Insufficient approval → revert
   - Insufficient balance → revert
   - Zero amount purchases behave correctly

3. **Front-running protection verified** ✅
   - Currency changes detected
   - Buyer protected from unexpected switches

4. **Payment atomicity proven** ✅
   - Any transfer failure → complete revert
   - No partial payments possible

5. **Decimal precision tested** ✅
   - 0, 6, 18, 30 decimals work correctly
   - Rounding behavior documented
   - No overflows

6. **Non-custodial invariant maintained** ✅
   - Diamond ERC20 balance always 0
   - Even after failed purchases

### Anti-Patterns to Avoid

❌ **Don't test implementation details**
- Focus on observable behavior, not internal state

❌ **Don't duplicate ETH tests**
- ETH security already tested; focus on ERC20-specific issues

❌ **Don't test impossible scenarios**
- E.g., "token decimals change mid-purchase" (not possible)

❌ **Don't skip cleanup**
- Reset fees, unpause, etc. after each test

### Estimated Test Count

- **Malicious Tokens:** 5 tests
- **Approval & Balance:** 4 tests
- **Front-Running:** 3 tests
- **Payment Atomicity:** 2 tests
- **Decimal Precision:** 3 tests
- **Mixed Scenarios:** 3-4 tests
- **Total:** 20-21 tests

Combined with Phases 1-3: **55-56 tests total** for complete ERC20 coverage.

### Integration with Existing Tests

This phase complements:
- **Phase 1:** Currency allowlist (foundation)
- **Phase 2:** Core ERC20 flows (happy path)
- **Phase 3:** Payment distribution (fee/royalty math)
- **Phase 4:** Security hardening (THIS PHASE)

Together, they provide comprehensive ERC20 testing without redundancy.

---

## Implementation Notes

1. **Priority Order:**
   - Malicious tokens (highest risk)
   - Approval edge cases (common user errors)
   - Front-running protection (MEV security)
   - Payment atomicity (correctness)
   - Decimal precision (correctness)
   - Mixed scenarios (integration)

2. **Test Independence:**
   - Each test should be self-contained
   - Use setUp() for common initialization
   - Clean up state changes (fees, pause, etc.)

3. **Gas Considerations:**
   - Some malicious tokens may consume excessive gas
   - Document expected gas ranges
   - Skip gas-intensive tests if needed

4. **Documentation:**
   - Comment expected behavior for edge cases
   - Document policy decisions (e.g., fee-on-transfer allowed via curation)
   - Note limitations (e.g., can't detect silent balance changes)

---

## Expected Outcomes

After implementing this phase:

✅ **Marketplace is hardened against malicious ERC20 tokens**
✅ **Approval and balance edge cases handled gracefully**
✅ **Front-running attacks prevented**
✅ **Payment atomicity proven under all conditions**
✅ **Decimal precision tested across token types**
✅ **Complete ERC20 security coverage achieved**

Combined with Phases 1-3: **Production-ready ERC20 marketplace with comprehensive test coverage**.
