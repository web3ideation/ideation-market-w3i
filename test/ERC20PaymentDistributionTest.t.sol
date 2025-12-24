// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import {IdeationMarket__RoyaltyFeeExceedsProceeds} from "../src/facets/IdeationMarketFacet.sol";
import {IERC2981} from "../src/interfaces/IERC2981.sol";

contract ERC20PaymentDistributionTest is MarketTestBase {
    MockERC20Ext internal tokenA;
    MockERC20Ext internal tokenB;
    MockERC20Ext internal tokenC;
    MockERC721Royalty internal royaltyNFT;
    MockERC20NoReturn internal usdtLike;

    address internal royaltyReceiver;

    function setUp() public virtual override {
        super.setUp();

        // Deploy standard ERC20 tokens
        tokenA = new MockERC20Ext("TokenA", "TKA", 18);
        tokenB = new MockERC20Ext("TokenB", "TKB", 6);
        tokenC = new MockERC20Ext("TokenC", "TKC", 30);
        // Deploy non-standard ERC20 (USDT-like)
        usdtLike = new MockERC20NoReturn("USDT-Like", "USDT", 6);

        // Deploy royalty NFT
        royaltyNFT = new MockERC721Royalty();

        // Setup royalty receiver
        royaltyReceiver = makeAddr("royaltyReceiver");

        // Add tokens to allowlist
        vm.startPrank(owner);
        currencies.addAllowedCurrency(address(tokenA));
        currencies.addAllowedCurrency(address(tokenB));
        currencies.addAllowedCurrency(address(tokenC));
        currencies.addAllowedCurrency(address(usdtLike));
        vm.stopPrank();
    }

    // ----------------------------------------------------------
    // Group 1: Basic Payment Distribution
    // ----------------------------------------------------------

    function testMarketplaceFeeDistributionWithERC20() public {
        uint128 listingId = _createERC721Listing(address(tokenA), 100 ether);

        tokenA.mint(buyer, 100 ether);
        vm.prank(buyer);
        tokenA.approve(address(diamond), 100 ether);

        uint256 ownerStart = tokenA.balanceOf(owner);

        vm.prank(buyer);
        market.purchaseListing(listingId, 100 ether, address(tokenA), 0, address(0), 0, 0, 0, address(0));

        uint256 ownerEnd = tokenA.balanceOf(owner);
        uint256 expectedFee = (100 ether * uint256(INNOVATION_FEE)) / 100000;

        assertEq(ownerEnd - ownerStart, expectedFee, "Owner fee incorrect");
        assertEq(tokenA.balanceOf(address(diamond)), 0, "Diamond holds ERC20");
    }

    function testSellerProceedsWithERC20() public {
        uint128 listingId = _createERC721Listing(address(tokenA), 500 ether);

        tokenA.mint(buyer, 500 ether);
        vm.prank(buyer);
        tokenA.approve(address(diamond), 500 ether);

        uint256 sellerStart = tokenA.balanceOf(seller);

        vm.prank(buyer);
        market.purchaseListing(listingId, 500 ether, address(tokenA), 0, address(0), 0, 0, 0, address(0));

        uint256 sellerEnd = tokenA.balanceOf(seller);
        uint256 fee = (500 ether * uint256(INNOVATION_FEE)) / 100000;
        uint256 expectedProceeds = 500 ether - fee;

        assertEq(sellerEnd - sellerStart, expectedProceeds, "Seller proceeds incorrect");
        assertEq(tokenA.balanceOf(address(diamond)), 0, "Diamond holds ERC20");
    }

    function testCompletePaymentFlowWithERC20() public {
        uint128 listingId = _createERC721Listing(address(tokenA), 1000 ether);

        tokenA.mint(buyer, 1000 ether);
        vm.prank(buyer);
        tokenA.approve(address(diamond), 1000 ether);

        uint256 buyerStart = tokenA.balanceOf(buyer);
        uint256 sellerStart = tokenA.balanceOf(seller);
        uint256 ownerStart = tokenA.balanceOf(owner);

        vm.prank(buyer);
        market.purchaseListing(listingId, 1000 ether, address(tokenA), 0, address(0), 0, 0, 0, address(0));

        uint256 buyerEnd = tokenA.balanceOf(buyer);
        uint256 sellerEnd = tokenA.balanceOf(seller);
        uint256 ownerEnd = tokenA.balanceOf(owner);

        uint256 fee = (1000 ether * uint256(INNOVATION_FEE)) / 100000;
        uint256 sellerProceeds = 1000 ether - fee;

        assertEq(buyerStart - buyerEnd, 1000 ether, "Buyer spent wrong amount");
        assertEq(ownerEnd - ownerStart, fee, "Owner fee incorrect");
        assertEq(sellerEnd - sellerStart, sellerProceeds, "Seller proceeds incorrect");
        assertEq((ownerEnd - ownerStart) + (sellerEnd - sellerStart), 1000 ether, "Distribution has dust");
        assertEq(tokenA.balanceOf(address(diamond)), 0, "Diamond holds ERC20");

        // Verify listing deleted
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingId));
        getter.getListingByListingId(listingId);
    }

    // ----------------------------------------------------------
    // Group 2: Royalty Distribution
    // ----------------------------------------------------------

    function testRoyaltyPaymentWithERC20() public {
        // Setup: 10% royalty (10,000 basis points)
        uint128 listingId = _createRoyaltyListing(royaltyNFT, address(tokenA), 1000 ether, royaltyReceiver, 10000);

        tokenA.mint(buyer, 1000 ether);
        vm.prank(buyer);
        tokenA.approve(address(diamond), 1000 ether);

        uint256 ownerStart = tokenA.balanceOf(owner);
        uint256 royaltyStart = tokenA.balanceOf(royaltyReceiver);
        uint256 sellerStart = tokenA.balanceOf(seller);

        vm.prank(buyer);
        market.purchaseListing(listingId, 1000 ether, address(tokenA), 0, address(0), 0, 0, 0, address(0));

        uint256 ownerEnd = tokenA.balanceOf(owner);
        uint256 royaltyEnd = tokenA.balanceOf(royaltyReceiver);
        uint256 sellerEnd = tokenA.balanceOf(seller);

        // Calculate expected distribution
        uint256 innovationFee = (1000 ether * uint256(INNOVATION_FEE)) / 100000;
        uint256 remaining = 1000 ether - innovationFee;
        uint256 royaltyAmount = (1000 ether * 10000) / 100000; // 10% of sale price
        uint256 sellerProceeds = remaining - royaltyAmount;

        assertEq(ownerEnd - ownerStart, innovationFee, "Owner fee incorrect");
        assertEq(royaltyEnd - royaltyStart, royaltyAmount, "Royalty amount incorrect");
        assertEq(sellerEnd - sellerStart, sellerProceeds, "Seller proceeds incorrect");
        assertEq(
            (ownerEnd - ownerStart) + (royaltyEnd - royaltyStart) + (sellerEnd - sellerStart),
            1000 ether,
            "Total distribution incorrect"
        );
        assertEq(tokenA.balanceOf(address(diamond)), 0, "Diamond holds ERC20");
    }

    function testZeroRoyaltyDoesNotRevert() public {
        // Setup: 0% royalty
        uint128 listingId = _createRoyaltyListing(royaltyNFT, address(tokenA), 500 ether, royaltyReceiver, 0);

        tokenA.mint(buyer, 500 ether);
        vm.prank(buyer);
        tokenA.approve(address(diamond), 500 ether);

        uint256 ownerStart = tokenA.balanceOf(owner);
        uint256 royaltyStart = tokenA.balanceOf(royaltyReceiver);
        uint256 sellerStart = tokenA.balanceOf(seller);

        vm.prank(buyer);
        market.purchaseListing(listingId, 500 ether, address(tokenA), 0, address(0), 0, 0, 0, address(0));

        uint256 ownerEnd = tokenA.balanceOf(owner);
        uint256 royaltyEnd = tokenA.balanceOf(royaltyReceiver);
        uint256 sellerEnd = tokenA.balanceOf(seller);

        uint256 fee = (500 ether * uint256(INNOVATION_FEE)) / 100000;

        assertEq(ownerEnd - ownerStart, fee, "Owner fee incorrect");
        assertEq(royaltyEnd - royaltyStart, 0, "Royalty should be 0");
        assertEq(sellerEnd - sellerStart, 500 ether - fee, "Seller proceeds incorrect");
        assertEq(tokenA.balanceOf(address(diamond)), 0, "Diamond holds ERC20");
    }

    function testRoyaltyExceedsProceedsReverts() public {
        // Create listing with very high royalty (99.5%) that will exceed proceeds after 1% fee
        // With 1% fee: remaining = 1000 ether - 10 ether = 990 ether
        // With 99.5% royalty: royalty = 995 ether > 990 ether remaining → should revert
        uint128 listingId = _createRoyaltyListing(royaltyNFT, address(tokenA), 1000 ether, royaltyReceiver, 99500);

        tokenA.mint(buyer, 1000 ether);
        vm.prank(buyer);
        tokenA.approve(address(diamond), 1000 ether);

        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__RoyaltyFeeExceedsProceeds.selector);
        market.purchaseListing(listingId, 1000 ether, address(tokenA), 0, address(0), 0, 0, 0, address(0));
    }

    // ----------------------------------------------------------
    // Group 3: Edge Cases & Precision
    // ----------------------------------------------------------

    function testTinyAmountsDistributionExact() public {
        uint128 listingId = _createERC721Listing(address(tokenA), 100);

        tokenA.mint(buyer, 100);
        vm.prank(buyer);
        tokenA.approve(address(diamond), 100);

        uint256 ownerStart = tokenA.balanceOf(owner);
        uint256 sellerStart = tokenA.balanceOf(seller);

        vm.prank(buyer);
        market.purchaseListing(listingId, 100, address(tokenA), 0, address(0), 0, 0, 0, address(0));

        uint256 ownerEnd = tokenA.balanceOf(owner);
        uint256 sellerEnd = tokenA.balanceOf(seller);

        uint256 fee = (100 * uint256(INNOVATION_FEE)) / 100000;
        uint256 sellerProceeds = 100 - fee;

        assertEq(ownerEnd - ownerStart, fee, "Owner fee incorrect for tiny amount");
        assertEq(sellerEnd - sellerStart, sellerProceeds, "Seller proceeds incorrect for tiny amount");
        assertEq((ownerEnd - ownerStart) + (sellerEnd - sellerStart), 100, "Distribution has dust");
        assertEq(tokenA.balanceOf(address(diamond)), 0, "Diamond holds ERC20");
    }

    function testMicroPaymentFeeTruncatesToZero() public {
        // With 1% fee (INNOVATION_FEE = 1000), amounts < 100 result in zero fee due to truncation
        // This tests that the system handles this edge case without reverting
        uint128 listingId = _createERC721Listing(address(tokenA), 50);

        tokenA.mint(buyer, 50);
        vm.prank(buyer);
        tokenA.approve(address(diamond), 50);

        uint256 ownerStart = tokenA.balanceOf(owner);
        uint256 sellerStart = tokenA.balanceOf(seller);

        vm.prank(buyer);
        market.purchaseListing(listingId, 50, address(tokenA), 0, address(0), 0, 0, 0, address(0));

        uint256 ownerEnd = tokenA.balanceOf(owner);
        uint256 sellerEnd = tokenA.balanceOf(seller);

        // Fee calculation: (50 * 1000) / 100000 = 50000 / 100000 = 0 (truncated)
        uint256 fee = (50 * uint256(INNOVATION_FEE)) / 100000;
        assertEq(fee, 0, "Fee should truncate to 0 for micro-payment");
        assertEq(ownerEnd - ownerStart, 0, "Owner gets no fee due to truncation");
        assertEq(sellerEnd - sellerStart, 50, "Seller gets full amount when fee truncates to 0");
        assertEq(tokenA.balanceOf(address(diamond)), 0, "Diamond holds ERC20");
    }

    function testHundredPercentFeeEdgeCase() public {
        // Create listing with normal 1% fee FIRST
        uint128 listingId = _createERC721Listing(address(tokenA), 500 ether);

        // NOW change fee to 100% (should NOT affect existing listing due to snapshot)
        vm.prank(owner);
        market.setInnovationFee(100000);

        tokenA.mint(buyer, 500 ether);
        vm.prank(buyer);
        tokenA.approve(address(diamond), 500 ether);

        uint256 ownerStart = tokenA.balanceOf(owner);
        uint256 sellerStart = tokenA.balanceOf(seller);

        vm.prank(buyer);
        market.purchaseListing(listingId, 500 ether, address(tokenA), 0, address(0), 0, 0, 0, address(0));

        uint256 ownerEnd = tokenA.balanceOf(owner);
        uint256 sellerEnd = tokenA.balanceOf(seller);

        // Listing should use 1% snapshot fee, NOT the 100% current fee
        uint256 expectedFee = (500 ether * uint256(INNOVATION_FEE)) / 100000;
        uint256 expectedProceeds = 500 ether - expectedFee;

        assertEq(ownerEnd - ownerStart, expectedFee, "Owner should get 1% (snapshot), not 100%");
        assertEq(sellerEnd - sellerStart, expectedProceeds, "Seller should get 99% (snapshot protects them)");
        assertEq(tokenA.balanceOf(address(diamond)), 0, "Diamond holds ERC20");

        // Restore original fee
        vm.prank(owner);
        market.setInnovationFee(INNOVATION_FEE);
    }

    function testMultipleDecimalsTokensDistribution() public {
        // TokenA: 18 decimals
        uint128 listingA = _createERC721Listing(address(tokenA), 1000 ether);

        // TokenB: 6 decimals
        uint128 listingB = _createERC721ListingWithToken(address(tokenB), 1000 * 1e6, 2);

        // TokenC: 30 decimals
        uint128 listingC = _createERC721ListingWithToken(address(tokenC), 1000 * 1e30, 3);

        // Mint and approve for all
        tokenA.mint(buyer, 1000 ether);
        tokenB.mint(buyer, 1000 * 1e6);
        tokenC.mint(buyer, 1000 * 1e30);

        vm.startPrank(buyer);
        tokenA.approve(address(diamond), 1000 ether);
        tokenB.approve(address(diamond), 1000 * 1e6);
        tokenC.approve(address(diamond), 1000 * 1e30);
        vm.stopPrank();

        // Track balances before purchases
        uint256 ownerBalanceA = tokenA.balanceOf(owner);
        uint256 ownerBalanceB = tokenB.balanceOf(owner);
        uint256 ownerBalanceC = tokenC.balanceOf(owner);
        uint256 sellerBalanceA = tokenA.balanceOf(seller);
        uint256 sellerBalanceB = tokenB.balanceOf(seller);
        uint256 sellerBalanceC = tokenC.balanceOf(seller);

        // Purchase all three
        vm.startPrank(buyer);
        market.purchaseListing(listingA, 1000 ether, address(tokenA), 0, address(0), 0, 0, 0, address(0));
        market.purchaseListing(listingB, 1000 * 1e6, address(tokenB), 0, address(0), 0, 0, 0, address(0));
        market.purchaseListing(listingC, 1000 * 1e30, address(tokenC), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Verify distribution for 18 decimals (TokenA)
        uint256 feeA = (1000 ether * uint256(INNOVATION_FEE)) / 100000;
        assertEq(tokenA.balanceOf(owner) - ownerBalanceA, feeA, "Owner fee wrong for 18 decimals");
        assertEq(tokenA.balanceOf(seller) - sellerBalanceA, 1000 ether - feeA, "Seller proceeds wrong for 18 decimals");
        assertEq(tokenA.balanceOf(address(diamond)), 0, "Diamond holds tokenA");

        // Verify distribution for 6 decimals (TokenB) - critical for rounding bugs
        uint256 feeB = (1000 * 1e6 * uint256(INNOVATION_FEE)) / 100000;
        assertEq(tokenB.balanceOf(owner) - ownerBalanceB, feeB, "Owner fee wrong for 6 decimals");
        assertEq(tokenB.balanceOf(seller) - sellerBalanceB, 1000 * 1e6 - feeB, "Seller proceeds wrong for 6 decimals");
        assertEq(tokenB.balanceOf(address(diamond)), 0, "Diamond holds tokenB");

        // Verify distribution for 30 decimals (TokenC) - critical for overflow
        uint256 feeC = (1000 * 1e30 * uint256(INNOVATION_FEE)) / 100000;
        assertEq(tokenC.balanceOf(owner) - ownerBalanceC, feeC, "Owner fee wrong for 30 decimals");
        assertEq(tokenC.balanceOf(seller) - sellerBalanceC, 1000 * 1e30 - feeC, "Seller proceeds wrong for 30 decimals");
        assertEq(tokenC.balanceOf(address(diamond)), 0, "Diamond holds tokenC");
    }

    // ----------------------------------------------------------
    // Group 4: Payment Failure Handling
    // ----------------------------------------------------------

    function testNonStandardERC20PaymentDistribution() public {
        // USDT-like token (no return value)
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc721));
        vm.stopPrank();

        vm.startPrank(seller);
        erc721.approve(address(diamond), 1);
        market.createListing(
            address(erc721),
            1,
            address(0),
            1000 * 1e6,
            address(usdtLike),
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

        usdtLike.mint(buyer, 1000 * 1e6);
        vm.prank(buyer);
        usdtLike.approve(address(diamond), 1000 * 1e6);

        uint256 ownerStart = usdtLike.balanceOf(owner);
        uint256 sellerStart = usdtLike.balanceOf(seller);
        uint256 buyerStart = usdtLike.balanceOf(buyer);

        vm.prank(buyer);
        market.purchaseListing(listingId, 1000 * 1e6, address(usdtLike), 0, address(0), 0, 0, 0, address(0));

        uint256 ownerEnd = usdtLike.balanceOf(owner);
        uint256 sellerEnd = usdtLike.balanceOf(seller);
        uint256 buyerEnd = usdtLike.balanceOf(buyer);

        uint256 fee = (1000 * 1e6 * uint256(INNOVATION_FEE)) / 100000;
        uint256 sellerProceeds = 1000 * 1e6 - fee;

        assertEq(buyerStart - buyerEnd, 1000 * 1e6, "Buyer spent wrong amount");
        assertEq(ownerEnd - ownerStart, fee, "Owner fee incorrect");
        assertEq(sellerEnd - sellerStart, sellerProceeds, "Seller proceeds incorrect");
        assertEq(usdtLike.balanceOf(address(diamond)), 0, "Diamond holds non-standard ERC20");
    }
}
