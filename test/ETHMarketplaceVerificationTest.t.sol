// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MarketTestBase.t.sol";
import {
    IdeationMarket__WrongPaymentCurrency,
    IdeationMarket__PriceNotMet,
    IdeationMarket__CollectionNotWhitelisted,
    IdeationMarket__AlreadyListed,
    IdeationMarketFacet
} from "../src/facets/IdeationMarketFacet.sol";

/**
 * @title ETHMarketplaceVerificationTest
 * @notice Unit tests for ETH payment-path correctness and ETH/ERC20 interaction boundaries.
 * @dev Coverage groups:
 * - Exact ETH payment enforcement (overpayment must revert with PriceNotMet).
 * - Currency-path isolation for mixed ETH/ERC20 listings in the same marketplace.
 * - Cross-path sequencing safety (ERC20 purchase followed by ETH purchase).
 * - Wrong-currency protection when sending ETH to ERC20 listings.
 */
contract ETHMarketplaceVerificationTest is MarketTestBase {
    MockERC20 internal tokenA;

    function setUp() public override {
        super.setUp();

        // Deploy and setup tokenA for mixed currency tests
        tokenA = new MockERC20("TokenA", "TKA");
        tokenA.mint(buyer, 10000e18);

        // Add tokenA to currency allowlist
        vm.prank(owner);
        currencies.addAllowedCurrency(address(tokenA));
    }

    // ============================================
    // FOCUSED TESTS
    // ============================================

    function testCreateListingERC721() public {
        _whitelistCollectionAndApproveERC721();
        vm.startPrank(seller);

        uint128 expectedId = getter.getNextListingId();
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCreated(
            expectedId,
            address(erc721),
            1,
            0,
            1 ether,
            address(0), // currency (ETH)
            getter.getInnovationFee(),
            seller,
            false,
            false,
            address(0),
            0,
            0
        );

        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        uint128 id = getter.getNextListingId() - 1;
        Listing memory l = getter.getListingByListingId(id);
        assertEq(l.listingId, id);
        assertEq(l.tokenAddress, address(erc721));
        assertEq(l.tokenId, 1);
        assertEq(l.price, 1 ether);
        assertEq(l.seller, seller);
        assertEq(l.erc1155Quantity, 0);
        assertFalse(l.buyerWhitelistEnabled);
        assertFalse(l.partialBuyEnabled);

        uint128 activeId = getter.getActiveListingIdByERC721(address(erc721), 1);
        assertEq(activeId, id);
    }

    function testCreateListingERC721Reverts() public {
        vm.startPrank(seller);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__CollectionNotWhitelisted.selector, address(erc721)));
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        _whitelistCollectionAndApproveERC721();
        vm.startPrank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.expectRevert(IdeationMarket__AlreadyListed.selector);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();
    }

    function testPurchaseListingERC721() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.deal(buyer, 10 ether);

        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__PriceNotMet.selector, id, 1 ether, 0.5 ether));
        market.purchaseListing{value: 0.5 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        vm.startPrank(buyer);

        uint32 feeSnap = getter.getListingByListingId(id).feeRate;
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingPurchased(
            id, address(erc721), 1, 0, false, 1 ether, address(0), feeSnap, seller, buyer, address(0), 0, 0
        );

        uint256 sellerBalanceBefore = seller.balance;
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
        assertEq(erc721.ownerOf(1), buyer);

        uint256 sellerBalanceAfter = seller.balance;
        assertEq(sellerBalanceAfter - sellerBalanceBefore, 0.99 ether);
    }

    /**
     * @notice Test overpayment is rejected (NEW behavior - exact payment required)
     * @dev UNIQUE: Tests that marketplace requires msg.value == purchasePrice
     * @dev This is new/changed behavior that could have regressed during ERC20 implementation
     */
    function testETHPurchaseOverpaymentReverts() public {
        // Setup
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc721));
        vm.stopPrank();

        vm.startPrank(seller);
        erc721.approve(address(diamond), 1);
        market.createListing(
            address(erc721),
            1,
            seller,
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

        // Buyer attempts to send 1.5 ETH for 1 ETH listing (overpayment)
        vm.deal(buyer, 1.5 ether);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__PriceNotMet.selector, listingId, 1 ether, 1.5 ether));
        market.purchaseListing{value: 1.5 ether}(listingId, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        // Assert: Transaction reverted, no state changes
        assertEq(erc721.ownerOf(1), seller, "Seller should still own NFT");
        assertEq(buyer.balance, 1.5 ether, "Buyer should retain all ETH");
    }

    /**
     * @notice Test multiple listings with different currencies
     * @dev UNIQUE: Proves ETH and ERC20 can coexist without interference
     * @dev Tests currency isolation - critical for mixed-currency marketplace
     */
    function testMixedCurrencyListingsInSameContract() public {
        // Setup: Whitelist collection
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc721));
        vm.stopPrank();

        // Seller creates 3 listings with mixed currencies
        vm.startPrank(seller);
        erc721.mint(seller, 2);
        erc721.mint(seller, 3);

        // Listing A: ETH
        erc721.approve(address(diamond), 1);
        market.createListing(
            address(erc721),
            1,
            seller,
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
        uint128 listingA = getter.getNextListingId() - 1;

        // Listing B: ERC20 (tokenA)
        erc721.approve(address(diamond), 2);
        market.createListing(
            address(erc721),
            2,
            seller,
            500e18,
            address(tokenA), // ERC20
            address(0),
            0,
            0,
            0,
            false,
            false,
            new address[](0)
        );
        uint128 listingB = getter.getNextListingId() - 1;

        // Listing C: ETH
        erc721.approve(address(diamond), 3);
        market.createListing(
            address(erc721),
            3,
            seller,
            2 ether,
            address(0), // ETH
            address(0),
            0,
            0,
            0,
            false,
            false,
            new address[](0)
        );
        uint128 listingC = getter.getNextListingId() - 1;
        vm.stopPrank();

        // Buyer purchases all 3 in sequence
        vm.startPrank(buyer);

        // Purchase A (ETH)
        vm.deal(buyer, 3 ether);
        market.purchaseListing{value: 1 ether}(listingA, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        // Purchase B (ERC20)
        tokenA.approve(address(diamond), 500e18);
        market.purchaseListing{value: 0}(listingB, 500e18, address(tokenA), 0, address(0), 0, 0, 0, address(0));

        // Purchase C (ETH)
        market.purchaseListing{value: 2 ether}(listingC, 2 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Assert: All purchases succeeded
        assertEq(erc721.ownerOf(1), buyer, "Buyer should own NFT #1");
        assertEq(erc721.ownerOf(2), buyer, "Buyer should own NFT #2");
        assertEq(erc721.ownerOf(3), buyer, "Buyer should own NFT #3");

        // Verify diamond balances = 0 for both currencies
        assertEq(address(diamond).balance, 0, "Diamond ETH balance must be 0");
        assertEq(tokenA.balanceOf(address(diamond)), 0, "Diamond tokenA balance must be 0");
    }

    /**
     * @notice Test ETH purchase after ERC20 purchase
     * @dev UNIQUE: Proves ERC20 state doesn't pollute ETH payment path
     * @dev Tests state isolation between payment mechanisms
     */
    function testETHPurchaseAfterERC20Purchase() public {
        // Setup
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc721));
        vm.stopPrank();

        vm.startPrank(seller);
        erc721.mint(seller, 2);

        // Create ERC20 listing
        erc721.approve(address(diamond), 1);
        market.createListing(
            address(erc721), 1, seller, 1000e18, address(tokenA), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 erc20Listing = getter.getNextListingId() - 1;

        // Create ETH listing
        erc721.approve(address(diamond), 2);
        market.createListing(
            address(erc721),
            2,
            seller,
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
        uint128 ethListing = getter.getNextListingId() - 1;
        vm.stopPrank();

        // Purchase ERC20 listing first
        vm.startPrank(buyer);
        tokenA.approve(address(diamond), 1000e18);
        market.purchaseListing{value: 0}(erc20Listing, 1000e18, address(tokenA), 0, address(0), 0, 0, 0, address(0));

        // Purchase ETH listing second
        vm.deal(buyer, 1 ether);
        market.purchaseListing{value: 1 ether}(ethListing, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Assert: Both purchases succeeded independently
        assertEq(erc721.ownerOf(1), buyer, "Buyer should own NFT #1 (ERC20)");
        assertEq(erc721.ownerOf(2), buyer, "Buyer should own NFT #2 (ETH)");
        assertEq(address(diamond).balance, 0, "Diamond ETH balance must be 0");
        assertEq(tokenA.balanceOf(address(diamond)), 0, "Diamond tokenA balance must be 0");
    }

    /**
     * @notice Test sending ETH to ERC20 listing fails with correct error
     * @dev UNIQUE: Critical validation - sending msg.value to ERC20 listing could cause fund loss
     * @dev This is a cross-currency validation edge case specific to mixed ETH/ERC20 marketplace
     */
    function testCannotSendETHToERC20Listing() public {
        // Setup
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc721));
        vm.stopPrank();

        // Create ERC20 listing
        vm.startPrank(seller);
        erc721.approve(address(diamond), 1);
        market.createListing(
            address(erc721),
            1,
            seller,
            1000e18,
            address(tokenA), // ERC20 only
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

        // Buyer attempts to pay with ETH (wrong currency)
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__WrongPaymentCurrency.selector);
        market.purchaseListing{value: 1 ether}(listingId, 1000e18, address(tokenA), 0, address(0), 0, 0, 0, address(0));

        // Assert: Buyer retains ETH, listing still active
        assertEq(buyer.balance, 1 ether, "Buyer should retain ETH");
        assertEq(erc721.ownerOf(1), seller, "Seller still owns NFT");
    }
}
