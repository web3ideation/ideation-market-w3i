// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import {
    IdeationMarket__ERC20TransferFailed,
    IdeationMarket__ListingTermsChanged,
    IdeationMarket__WrongPaymentCurrency
} from "../src/facets/IdeationMarketFacet.sol";

contract ERC20SecurityTest is MarketTestBase {
    MaliciousERC20Reverting internal revertingToken;
    MaliciousERC20ReturnsFalse internal falseToken;
    FeeOnTransferERC20 internal feeToken;
    ReentrantERC20 internal reentrantToken;
    HighGasERC20 internal gasToken;
    MockERC20WithDecimals internal token0Dec;
    MockERC20WithDecimals internal token6Dec;
    MockERC20WithDecimals internal token18Dec;
    MockERC20WithDecimals internal token30Dec;
    MockERC20WithDecimals internal tokenA;
    MockERC20WithDecimals internal tokenB;

    function setUp() public virtual override {
        super.setUp();

        // Deploy malicious tokens
        revertingToken = new MaliciousERC20Reverting();
        falseToken = new MaliciousERC20ReturnsFalse();
        feeToken = new FeeOnTransferERC20();
        reentrantToken = new ReentrantERC20(address(diamond));
        gasToken = new HighGasERC20();

        // Deploy tokens with various decimals
        token0Dec = new MockERC20WithDecimals("Token0", "TK0", 0);
        token6Dec = new MockERC20WithDecimals("Token6", "TK6", 6);
        token18Dec = new MockERC20WithDecimals("Token18", "TK18", 18);
        token30Dec = new MockERC20WithDecimals("Token30", "TK30", 30);

        // Deploy standard tokens for front-running tests
        tokenA = new MockERC20WithDecimals("TokenA", "TKA", 18);
        tokenB = new MockERC20WithDecimals("TokenB", "TKB", 18);
    }

    // ----------------------------------------------------------
    // Group 1: Malicious Token Behaviors
    // ----------------------------------------------------------

    function testMaliciousERC20RevertsOnTransfer() public {
        uint128 listingId = _createMaliciousTokenListing(address(revertingToken), 1000 ether, 1);

        revertingToken.mint(buyer, 1000 ether);

        uint256 ownerBefore = revertingToken.balanceOf(owner);
        uint256 sellerBefore = revertingToken.balanceOf(seller);
        uint256 buyerBefore = revertingToken.balanceOf(buyer);

        vm.startPrank(buyer);
        revertingToken.approve(address(diamond), 1000 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IdeationMarket__ERC20TransferFailed.selector, address(revertingToken), owner)
        );
        market.purchaseListing(listingId, 1000 ether, address(revertingToken), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Verify no partial payments
        assertEq(revertingToken.balanceOf(owner), ownerBefore, "Owner balance changed");
        assertEq(revertingToken.balanceOf(seller), sellerBefore, "Seller balance changed");
        assertEq(revertingToken.balanceOf(buyer), buyerBefore, "Buyer balance changed");
    }

    function testMaliciousERC20ReturnsFalse() public {
        uint128 listingId = _createMaliciousTokenListing(address(falseToken), 1000 ether, 1);

        falseToken.mint(buyer, 1000 ether);

        uint256 ownerBefore = falseToken.balanceOf(owner);
        uint256 sellerBefore = falseToken.balanceOf(seller);
        uint256 buyerBefore = falseToken.balanceOf(buyer);

        vm.startPrank(buyer);
        falseToken.approve(address(diamond), 1000 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IdeationMarket__ERC20TransferFailed.selector, address(falseToken), owner)
        );
        market.purchaseListing(listingId, 1000 ether, address(falseToken), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Verify _safeTransferFrom caught the false return
        assertEq(falseToken.balanceOf(owner), ownerBefore, "Owner received tokens despite false return");
        assertEq(falseToken.balanceOf(seller), sellerBefore, "Seller received tokens despite false return");
        assertEq(falseToken.balanceOf(buyer), buyerBefore, "Buyer tokens transferred despite false return");
    }

    function testMaliciousERC20PartialTransfer() public {
        // Fee-on-transfer token: demonstrates critical vulnerability if such tokens are allowlisted
        // The marketplace cannot detect that less than expected arrives
        uint128 listingId = _createMaliciousTokenListing(address(feeToken), 1000 ether, 1);

        feeToken.mint(buyer, 1000 ether);

        vm.startPrank(buyer);
        feeToken.approve(address(diamond), 1000 ether);
        market.purchaseListing(listingId, 1000 ether, address(feeToken), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Calculate what recipients SHOULD receive vs what they ACTUALLY receive
        uint256 expectedFee = (1000 ether * uint256(INNOVATION_FEE)) / 100000;
        uint256 expectedSellerProceeds = 1000 ether - expectedFee;

        uint256 actualOwnerFee = feeToken.balanceOf(owner);
        uint256 actualSellerProceeds = feeToken.balanceOf(seller);

        // CRITICAL BUG DEMONSTRATION: Seller loses 50% of their money
        // This test documents the vulnerability that MUST be prevented via allowlist curation
        assertEq(actualOwnerFee, expectedFee / 2, "Owner receives 50% of fee (token steals 50%)");
        assertEq(actualSellerProceeds, expectedSellerProceeds / 2, "Seller receives 50% of proceeds (LOSES 50%!)");

        // Verify buyer paid full amount but seller didn't receive it (stolen by token)
        assertEq(feeToken.balanceOf(buyer), 0, "Buyer paid full 1000 ether");
        assertEq(actualOwnerFee + actualSellerProceeds, 500 ether, "Total received is only 50% (500 ether stolen)");
    }

    function testReentrancyAttemptViaERC20Blocked() public {
        // Create two listings
        uint128 listingId1 = _createMaliciousTokenListing(address(reentrantToken), 1000 ether, 1);
        erc721.mint(seller, 2);
        vm.startPrank(seller);
        erc721.approve(address(diamond), 2);
        market.createListing(
            address(erc721),
            2,
            address(0),
            1000 ether,
            address(reentrantToken),
            address(0),
            0,
            0,
            0,
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();
        uint128 listingId2 = getter.getNextListingId() - 1;

        // Setup: token will try to reenter and purchase listing 2
        reentrantToken.setTarget(listingId2);
        reentrantToken.mint(buyer, 2000 ether);

        vm.startPrank(buyer);
        reentrantToken.approve(address(diamond), 2000 ether);

        // Purchase listing 1 - token will attempt reentrancy during transfer
        // nonReentrant modifier should block it, causing the entire transaction to revert
        vm.expectRevert();
        market.purchaseListing(listingId1, 1000 ether, address(reentrantToken), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Since the transaction reverted, we can't check hasReentered (state rolled back)
        // Instead verify both listings still exist (no purchase succeeded)
        Listing memory listing1 = getter.getListingByListingId(listingId1);
        assertEq(listing1.seller, seller, "Listing 1 should still exist");
        assertEq(erc721.ownerOf(1), seller, "Seller should still own NFT 1");

        Listing memory listing2 = getter.getListingByListingId(listingId2);
        assertEq(listing2.seller, seller, "Listing 2 should still exist");
        assertEq(erc721.ownerOf(2), seller, "Seller should still own NFT 2");
    }

    function testMaliciousERC20ExcessiveGasConsumption() public {
        uint128 listingId = _createMaliciousTokenListing(address(gasToken), 1000 ether, 1);

        gasToken.mint(buyer, 1000 ether);

        vm.startPrank(buyer);
        gasToken.approve(address(diamond), 1000 ether);

        // Measure gas consumption with malicious token
        uint256 gasBefore = gasleft();
        market.purchaseListing(listingId, 1000 ether, address(gasToken), 0, address(0), 0, 0, 0, address(0));
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        // LIMITATION DOCUMENTATION: High-gas tokens will make transactions expensive
        // This test shows the purchase completes but at high cost (1.2M gas vs normal ~400k)
        // Defense: allowlist curation MUST exclude such tokens
        assertGt(gasUsed, 1_000_000, "Gas usage elevated with malicious token (shows vulnerability)");
        assertLt(gasUsed, 2_000_000, "Still completes (below block limit), but at 3x normal cost");

        // Verify purchase succeeded despite high gas cost (vulnerability: users pay more)
        assertEq(erc721.ownerOf(1), buyer, "Buyer owns NFT but paid high gas fees");
        assertEq(gasToken.balanceOf(address(diamond)), 0, "Diamond should not hold tokens");
    }

    // ----------------------------------------------------------
    // Group 2: Approval & Balance Edge Cases
    // ----------------------------------------------------------

    function testInsufficientBuyerBalanceReverts() public {
        uint128 listingId = _createMaliciousTokenListing(address(token18Dec), 1000 ether, 1);

        token18Dec.mint(buyer, 500 ether); // Only mint 500

        uint256 ownerBefore = token18Dec.balanceOf(owner);
        uint256 sellerBefore = token18Dec.balanceOf(seller);
        uint256 buyerBefore = token18Dec.balanceOf(buyer);

        vm.startPrank(buyer);
        token18Dec.approve(address(diamond), 1000 ether); // Approve 1000 but only have 500

        // Will fail when trying to pay seller (after fee is paid)
        vm.expectRevert(
            abi.encodeWithSelector(IdeationMarket__ERC20TransferFailed.selector, address(token18Dec), seller)
        );
        market.purchaseListing(listingId, 1000 ether, address(token18Dec), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Verify no balance changes
        assertEq(token18Dec.balanceOf(owner), ownerBefore, "Owner balance changed");
        assertEq(token18Dec.balanceOf(seller), sellerBefore, "Seller balance changed");
        assertEq(token18Dec.balanceOf(buyer), buyerBefore, "Buyer balance unchanged");
    }

    function testZeroAmountPurchasePrevented() public {
        // Marketplace doesn't support free listings (price 0)
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc721));
        currencies.addAllowedCurrency(address(token18Dec));
        vm.stopPrank();

        vm.startPrank(seller);
        erc721.approve(address(diamond), 1);

        // Creating a listing with price 0 should revert
        vm.expectRevert(IdeationMarket__FreeListingsNotSupported.selector);
        market.createListing(
            address(erc721), 1, address(0), 0, address(token18Dec), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();
    }

    // ----------------------------------------------------------
    // Group 3: Front-Running Protection
    // ----------------------------------------------------------

    function testExpectedCurrencyMismatchReverts() public {
        vm.startPrank(owner);
        currencies.addAllowedCurrency(address(tokenA));
        currencies.addAllowedCurrency(address(tokenB));
        collections.addWhitelistedCollection(address(erc721));
        vm.stopPrank();

        // Create listing in tokenA
        vm.startPrank(seller);
        erc721.approve(address(diamond), 1);
        market.createListing(
            address(erc721),
            1,
            address(0),
            1000 ether,
            address(tokenA),
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

        // Seller updates to tokenB
        vm.prank(seller);
        market.updateListing(
            listingId, 1000 ether, address(tokenB), address(0), 0, 0, 0, false, false, new address[](0)
        );

        // Buyer attempts purchase with stale expectedCurrency = tokenA
        tokenB.mint(buyer, 1000 ether);

        vm.startPrank(buyer);
        tokenB.approve(address(diamond), 1000 ether);

        vm.expectRevert(IdeationMarket__ListingTermsChanged.selector);
        market.purchaseListing(listingId, 1000 ether, address(tokenA), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Verify buyer not charged
        assertEq(tokenB.balanceOf(buyer), 1000 ether, "Buyer should retain tokens");
    }

    function testExpectedCurrencyETHToERC20Switch() public {
        vm.startPrank(owner);
        currencies.addAllowedCurrency(address(tokenA));
        collections.addWhitelistedCollection(address(erc721));
        vm.stopPrank();

        // Create listing in ETH
        vm.startPrank(seller);
        erc721.approve(address(diamond), 1);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        uint128 listingId = getter.getNextListingId() - 1;

        // Seller updates to ERC20
        vm.prank(seller);
        market.updateListing(
            listingId, 1000 ether, address(tokenA), address(0), 0, 0, 0, false, false, new address[](0)
        );

        // Buyer sends ETH with expectedCurrency = address(0)
        vm.deal(buyer, 1 ether);

        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__ListingTermsChanged.selector);
        market.purchaseListing{value: 1 ether}(listingId, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Verify buyer's ETH intact (reverted)
        assertEq(buyer.balance, 1 ether, "Buyer should retain ETH");
    }

    function testExpectedCurrencyERC20ToETHSwitch() public {
        vm.startPrank(owner);
        currencies.addAllowedCurrency(address(tokenA));
        collections.addWhitelistedCollection(address(erc721));
        vm.stopPrank();

        // Create listing in ERC20
        vm.startPrank(seller);
        erc721.approve(address(diamond), 1);
        market.createListing(
            address(erc721),
            1,
            address(0),
            1000 ether,
            address(tokenA),
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

        // Seller updates to ETH
        vm.prank(seller);
        market.updateListing(listingId, 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));

        // Buyer approves ERC20 and attempts purchase with expectedCurrency = tokenA
        tokenA.mint(buyer, 1000 ether);

        vm.startPrank(buyer);
        tokenA.approve(address(diamond), 1000 ether);

        vm.expectRevert(IdeationMarket__ListingTermsChanged.selector);
        market.purchaseListing(listingId, 1000 ether, address(tokenA), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Verify buyer's ERC20 approval unused
        assertEq(tokenA.balanceOf(buyer), 1000 ether, "Buyer should retain tokens");
    }

    // ----------------------------------------------------------
    // Group 4: Payment Distribution Failures (Atomicity)
    // ----------------------------------------------------------

    function testPaymentDistributionAtomicityOwnerFails() public {
        // Create token that fails on first transfer (to owner)
        ConditionalFailureERC20 failToken = new ConditionalFailureERC20();
        failToken.setFailOnTransferTo(owner); // Fail when transferring to owner

        uint128 listingId = _createMaliciousTokenListing(address(failToken), 1000 ether, 1);

        failToken.mint(buyer, 1000 ether);

        uint256 sellerBefore = failToken.balanceOf(seller);
        uint256 buyerBefore = failToken.balanceOf(buyer);

        vm.startPrank(buyer);
        failToken.approve(address(diamond), 1000 ether);

        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__ERC20TransferFailed.selector, address(failToken), owner));
        market.purchaseListing(listingId, 1000 ether, address(failToken), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Verify atomicity: seller got nothing
        assertEq(failToken.balanceOf(seller), sellerBefore, "Seller should not receive tokens");
        assertEq(failToken.balanceOf(buyer), buyerBefore, "Buyer should retain tokens");
    }

    function testPaymentDistributionAtomicitySellerFails() public {
        // Create token that fails on third transfer (to seller)
        ConditionalFailureERC20 failToken = new ConditionalFailureERC20();
        failToken.setFailOnTransferTo(seller); // Fail when transferring to seller

        uint128 listingId = _createMaliciousTokenListing(address(failToken), 1000 ether, 1);

        failToken.mint(buyer, 1000 ether);

        uint256 ownerBefore = failToken.balanceOf(owner);
        uint256 buyerBefore = failToken.balanceOf(buyer);

        vm.startPrank(buyer);
        failToken.approve(address(diamond), 1000 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IdeationMarket__ERC20TransferFailed.selector, address(failToken), seller)
        );
        market.purchaseListing(listingId, 1000 ether, address(failToken), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Verify atomicity: owner got nothing (entire tx reverted)
        assertEq(failToken.balanceOf(owner), ownerBefore, "Owner should not receive tokens");
        assertEq(failToken.balanceOf(buyer), buyerBefore, "Buyer should retain tokens");
    }

    // ----------------------------------------------------------
    // Group 5: Decimal Precision & Overflow
    // ----------------------------------------------------------

    function testVariousDecimalTokensCalculationCorrectness() public {
        vm.startPrank(owner);
        currencies.addAllowedCurrency(address(token0Dec));
        currencies.addAllowedCurrency(address(token6Dec));
        currencies.addAllowedCurrency(address(token18Dec));
        currencies.addAllowedCurrency(address(token30Dec));
        collections.addWhitelistedCollection(address(erc721));
        vm.stopPrank();

        // 0 decimals: price = 1000
        _testDecimalToken(token0Dec, 1000, 2);

        // 6 decimals (USDC-like): price = 1000 * 10^6
        _testDecimalToken(token6Dec, 1000 * 1e6, 3);

        // 18 decimals (standard): price = 1000 * 10^18
        _testDecimalToken(token18Dec, 1000 ether, 4);

        // 30 decimals: price = 1000 * 10^30
        _testDecimalToken(token30Dec, 1000 * 1e30, 5);
    }

    function testExtremelySmallAmountsRounding() public {
        vm.startPrank(owner);
        currencies.addAllowedCurrency(address(token18Dec));
        collections.addWhitelistedCollection(address(erc721));
        vm.stopPrank();

        // Price = 1 wei
        vm.startPrank(seller);
        erc721.approve(address(diamond), 1);
        market.createListing(
            address(erc721), 1, address(0), 1, address(token18Dec), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        uint128 listingId = getter.getNextListingId() - 1;

        token18Dec.mint(buyer, 1);

        uint256 ownerBefore = token18Dec.balanceOf(owner);
        uint256 sellerBefore = token18Dec.balanceOf(seller);

        vm.startPrank(buyer);
        token18Dec.approve(address(diamond), 1);
        market.purchaseListing(listingId, 1, address(token18Dec), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Fee calculation: (1 * 1000) / 100000 = 0 (truncated)
        uint256 expectedFee = (1 * uint256(INNOVATION_FEE)) / 100000;
        assertEq(expectedFee, 0, "Fee should truncate to 0");

        // Owner gets 0, seller gets full 1 wei
        assertEq(token18Dec.balanceOf(owner) - ownerBefore, 0, "Owner should get 0 due to truncation");
        assertEq(token18Dec.balanceOf(seller) - sellerBefore, 1, "Seller should get full amount");
    }

    function testExtremelyLargeAmountsNearUint256Max() public {
        vm.startPrank(owner);
        currencies.addAllowedCurrency(address(token18Dec));
        collections.addWhitelistedCollection(address(erc721));
        vm.stopPrank();

        // Use type(uint96).max as a very large but safe amount
        uint256 largeAmount = uint256(type(uint96).max);

        vm.startPrank(seller);
        erc721.approve(address(diamond), 1);
        market.createListing(
            address(erc721),
            1,
            address(0),
            largeAmount,
            address(token18Dec),
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

        token18Dec.mint(buyer, largeAmount);

        vm.startPrank(buyer);
        token18Dec.approve(address(diamond), largeAmount);
        market.purchaseListing(listingId, largeAmount, address(token18Dec), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Verify no overflow in fee calculation
        uint256 expectedFee = (largeAmount * uint256(INNOVATION_FEE)) / 100000;
        assertEq(token18Dec.balanceOf(owner), expectedFee, "Owner fee calculation should not overflow");
        assertEq(token18Dec.balanceOf(address(diamond)), 0, "Diamond should not hold tokens");
    }

    // ----------------------------------------------------------
    // Group 6: Mixed Scenarios & Integration
    // ----------------------------------------------------------

    function testPurchaseWithMsgValueForERC20ListingReverts() public {
        uint128 listingId = _createMaliciousTokenListing(address(token18Dec), 1000 ether, 1);

        token18Dec.mint(buyer, 1000 ether);

        vm.deal(buyer, 1 ether);

        vm.startPrank(buyer);
        token18Dec.approve(address(diamond), 1000 ether);

        vm.expectRevert(IdeationMarket__WrongPaymentCurrency.selector);
        market.purchaseListing{value: 1 wei}(
            listingId, 1000 ether, address(token18Dec), 0, address(0), 0, 0, 0, address(0)
        );
        vm.stopPrank();

        // Verify buyer's ETH intact
        assertEq(buyer.balance, 1 ether, "Buyer should retain ETH");
    }

    function testERC20PurchaseWhilePausedReverts() public {
        uint128 listingId = _createMaliciousTokenListing(address(token18Dec), 1000 ether, 1);

        token18Dec.mint(buyer, 1000 ether);

        // Pause marketplace
        vm.prank(owner);
        pauseFacet.pause();

        vm.startPrank(buyer);
        token18Dec.approve(address(diamond), 1000 ether);

        vm.expectRevert();
        market.purchaseListing(listingId, 1000 ether, address(token18Dec), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Unpause and retry
        vm.prank(owner);
        pauseFacet.unpause();

        vm.prank(buyer);
        market.purchaseListing(listingId, 1000 ether, address(token18Dec), 0, address(0), 0, 0, 0, address(0));

        // Verify purchase succeeded after unpause
        assertEq(erc721.ownerOf(1), buyer, "Buyer should own NFT");
    }

    function testMultipleERC20TokensInSameContract() public {
        MockERC20WithDecimals token1 = new MockERC20WithDecimals("Token1", "TK1", 18);
        MockERC20WithDecimals token2 = new MockERC20WithDecimals("Token2", "TK2", 18);
        MockERC20WithDecimals token3 = new MockERC20WithDecimals("Token3", "TK3", 18);

        vm.startPrank(owner);
        currencies.addAllowedCurrency(address(token1));
        currencies.addAllowedCurrency(address(token2));
        currencies.addAllowedCurrency(address(token3));
        collections.addWhitelistedCollection(address(erc721));
        vm.stopPrank();

        // Create 3 listings
        erc721.mint(seller, 2);
        erc721.mint(seller, 3);

        vm.startPrank(seller);
        erc721.approve(address(diamond), 1);
        erc721.approve(address(diamond), 2);
        erc721.approve(address(diamond), 3);
        market.createListing(
            address(erc721),
            1,
            address(0),
            1000 ether,
            address(token1),
            address(0),
            0,
            0,
            0,
            false,
            false,
            new address[](0)
        );
        market.createListing(
            address(erc721),
            2,
            address(0),
            1000 ether,
            address(token2),
            address(0),
            0,
            0,
            0,
            false,
            false,
            new address[](0)
        );
        market.createListing(
            address(erc721),
            3,
            address(0),
            1000 ether,
            address(token3),
            address(0),
            0,
            0,
            0,
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();

        uint128 listingId1 = getter.getNextListingId() - 3;
        uint128 listingId2 = getter.getNextListingId() - 2;
        uint128 listingId3 = getter.getNextListingId() - 1;

        // Mint and approve all tokens
        token1.mint(buyer, 1000 ether);
        token2.mint(buyer, 1000 ether);
        token3.mint(buyer, 1000 ether);

        vm.startPrank(buyer);
        token1.approve(address(diamond), 1000 ether);
        token2.approve(address(diamond), 1000 ether);
        token3.approve(address(diamond), 1000 ether);

        // Purchase all 3
        market.purchaseListing(listingId1, 1000 ether, address(token1), 0, address(0), 0, 0, 0, address(0));
        market.purchaseListing(listingId2, 1000 ether, address(token2), 0, address(0), 0, 0, 0, address(0));
        market.purchaseListing(listingId3, 1000 ether, address(token3), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Verify all payments distributed correctly and diamond holds nothing
        assertEq(token1.balanceOf(address(diamond)), 0, "Diamond should not hold token1");
        assertEq(token2.balanceOf(address(diamond)), 0, "Diamond should not hold token2");
        assertEq(token3.balanceOf(address(diamond)), 0, "Diamond should not hold token3");

        // Verify all NFTs transferred
        assertEq(erc721.ownerOf(1), buyer, "Buyer should own NFT 1");
        assertEq(erc721.ownerOf(2), buyer, "Buyer should own NFT 2");
        assertEq(erc721.ownerOf(3), buyer, "Buyer should own NFT 3");
    }
}
