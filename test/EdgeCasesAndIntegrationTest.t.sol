// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import {Listing} from "../src/libraries/LibAppStorage.sol";
import {Getter__ListingNotFound} from "../src/facets/GetterFacet.sol";
import {
    IdeationMarket__ListingTermsChanged,
    IdeationMarket__CurrencyNotAllowed,
    IdeationMarket__BuyerNotWhitelisted,
    IdeationMarket__CollectionNotWhitelisted,
    IdeationMarket__NotListed,
    IdeationMarket__NotAuthorizedOperator,
    IdeationMarketFacet
} from "../src/facets/IdeationMarketFacet.sol";

/**
 * @title EdgeCasesAndIntegrationTest
 * @notice Integration-focused tests for cross-feature marketplace behavior under realistic edge scenarios.
 * @dev Coverage groups:
 * - Mixed ETH/ERC20 settlement sequencing and multi-currency isolation.
 * - Listing update/front-run expectation checks and currency allowlist transitions.
 * - Tiny-amount rounding, buyer-whitelist enforcement, and collection de-whitelist cleanup flows.
 * - ERC1155 partial-buy accounting, NFT swap + ERC20 payment, and ERC2981 royalty distribution.
 * - Getter accuracy for large allowlist arrays after add/remove operations.
 */
contract EdgeCasesAndIntegrationTest is MarketTestBase {
    MockERC20 internal usdc;
    MockERC20 internal dai;
    MockERC20 internal weth;
    MockERC20 internal tinyToken;
    MockERC721Royalty internal royaltyNFT;

    function setUp() public override {
        super.setUp();

        // Deploy ERC20 mocks
        usdc = new MockERC20("USD Coin", "USDC");
        dai = new MockERC20("Dai Stablecoin", "DAI");
        weth = new MockERC20("Wrapped Ether", "WETH");
        tinyToken = new MockERC20("Tiny Token", "TINY");

        // Deploy royalty NFT
        royaltyNFT = new MockERC721Royalty();

        // Add ERC20 tokens to currency allowlist
        vm.startPrank(owner);
        currencies.addAllowedCurrency(address(usdc));
        currencies.addAllowedCurrency(address(dai));
        currencies.addAllowedCurrency(address(weth));
        currencies.addAllowedCurrency(address(tinyToken));
        vm.stopPrank();

        // Whitelist royalty NFT collection
        vm.prank(owner);
        collections.addWhitelistedCollection(address(royaltyNFT));
    }

    // =========================================================================
    // Group 1: Mixed Currency Sequencing (2 tests)
    // =========================================================================

    /**
     * @notice Test mixing ETH and ERC20 listings back-to-back
     * @dev Verifies state isolation between ETH and ERC20 purchases
     */
    function testMixETHAndERC20ListingsBackToBack() public {
        // Setup: Whitelist collections
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        // Mint NFTs to seller
        erc721.mint(seller, 10);
        erc721.mint(seller, 11);

        // Create listing in ETH (address(0))
        vm.startPrank(seller);
        erc721.setApprovalForAll(address(market), true);
        market.createListing(
            address(erc721), 10, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );

        // Create listing in USDC
        market.createListing(
            address(erc721), 11, address(0), 1000e18, address(usdc), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        uint128 listingId1 = getter.getNextListingId() - 2;
        uint128 listingId2 = getter.getNextListingId() - 1;

        // Purchase listing with ETH
        uint256 sellerEthBefore = seller.balance;
        uint256 ownerEthBefore = owner.balance;

        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(listingId1, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        // Verify ETH payment distribution
        uint256 sellerEthReceived = seller.balance - sellerEthBefore;
        uint256 ownerEthReceived = owner.balance - ownerEthBefore;
        assertEq(sellerEthReceived + ownerEthReceived, 1 ether, "Total ETH distribution must equal price");
        assertGt(ownerEthReceived, 0, "Owner must receive ETH fee");
        assertGt(sellerEthReceived, 0, "Seller must receive ETH proceeds");

        // Purchase listing with USDC
        uint256 sellerUsdcBefore = usdc.balanceOf(seller);
        uint256 ownerUsdcBefore = usdc.balanceOf(owner);

        usdc.mint(buyer, 1000e18);
        vm.startPrank(buyer);
        usdc.approve(address(market), 1000e18);
        market.purchaseListing(listingId2, 1000e18, address(usdc), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Verify USDC payment distribution
        uint256 sellerUsdcReceived = usdc.balanceOf(seller) - sellerUsdcBefore;
        uint256 ownerUsdcReceived = usdc.balanceOf(owner) - ownerUsdcBefore;
        assertEq(sellerUsdcReceived + ownerUsdcReceived, 1000e18, "Total USDC distribution must equal price");
        assertGt(ownerUsdcReceived, 0, "Owner must receive USDC fee");
        assertGt(sellerUsdcReceived, 0, "Seller must receive USDC proceeds");

        // Verify both listings deleted (getter reverts for non-existent listings)
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingId1));
        getter.getListingByListingId(listingId1);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingId2));
        getter.getListingByListingId(listingId2);

        // Verify diamond balance = 0 for USDC
        assertEq(usdc.balanceOf(address(market)), 0, "Diamond must not hold USDC");

        // Verify buyer owns both NFTs
        assertEq(erc721.ownerOf(10), buyer, "Buyer should own NFT 10");
        assertEq(erc721.ownerOf(11), buyer, "Buyer should own NFT 11");
    }

    /**
     * @notice Test multiple ERC20 currencies in sequence
     * @dev Verifies no cross-contamination between different tokens
     */
    function testMultipleERC20CurrenciesInSequence() public {
        // Setup: Whitelist collection
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        // Mint 3 NFTs to seller
        erc721.mint(seller, 20);
        erc721.mint(seller, 21);
        erc721.mint(seller, 22);

        // Create 3 listings with different tokens
        vm.startPrank(seller);
        erc721.setApprovalForAll(address(market), true);

        market.createListing(
            address(erc721), 20, address(0), 100e18, address(usdc), address(0), 0, 0, 0, false, false, new address[](0)
        );
        market.createListing(
            address(erc721), 21, address(0), 200e18, address(dai), address(0), 0, 0, 0, false, false, new address[](0)
        );
        market.createListing(
            address(erc721), 22, address(0), 300e18, address(weth), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        uint128 listingId1 = getter.getNextListingId() - 3;
        uint128 listingId2 = getter.getNextListingId() - 2;
        uint128 listingId3 = getter.getNextListingId() - 1;

        // Purchase all 3 in sequence
        usdc.mint(buyer, 100e18);
        dai.mint(buyer, 200e18);
        weth.mint(buyer, 300e18);

        vm.startPrank(buyer);
        // Purchase 1: USDC
        uint256 sellerUsdcBefore = usdc.balanceOf(seller);
        uint256 ownerUsdcBefore = usdc.balanceOf(owner);
        usdc.approve(address(market), 100e18);
        market.purchaseListing(listingId1, 100e18, address(usdc), 0, address(0), 0, 0, 0, address(0));
        uint256 sellerUsdcReceived = usdc.balanceOf(seller) - sellerUsdcBefore;
        uint256 ownerUsdcReceived = usdc.balanceOf(owner) - ownerUsdcBefore;
        assertEq(sellerUsdcReceived + ownerUsdcReceived, 100e18, "Total USDC must equal price");
        assertGt(ownerUsdcReceived, 0, "Owner must receive USDC fee");
        assertGt(sellerUsdcReceived, 0, "Seller must receive USDC proceeds");

        // Purchase 2: DAI
        uint256 sellerDaiBefore = dai.balanceOf(seller);
        uint256 ownerDaiBefore = dai.balanceOf(owner);
        dai.approve(address(market), 200e18);
        market.purchaseListing(listingId2, 200e18, address(dai), 0, address(0), 0, 0, 0, address(0));
        uint256 sellerDaiReceived = dai.balanceOf(seller) - sellerDaiBefore;
        uint256 ownerDaiReceived = dai.balanceOf(owner) - ownerDaiBefore;
        assertEq(sellerDaiReceived + ownerDaiReceived, 200e18, "Total DAI must equal price");
        assertGt(ownerDaiReceived, 0, "Owner must receive DAI fee");
        assertGt(sellerDaiReceived, 0, "Seller must receive DAI proceeds");

        // Purchase 3: WETH
        uint256 sellerWethBefore = weth.balanceOf(seller);
        uint256 ownerWethBefore = weth.balanceOf(owner);
        weth.approve(address(market), 300e18);
        market.purchaseListing(listingId3, 300e18, address(weth), 0, address(0), 0, 0, 0, address(0));
        uint256 sellerWethReceived = weth.balanceOf(seller) - sellerWethBefore;
        uint256 ownerWethReceived = weth.balanceOf(owner) - ownerWethBefore;
        assertEq(sellerWethReceived + ownerWethReceived, 300e18, "Total WETH must equal price");
        assertGt(ownerWethReceived, 0, "Owner must receive WETH fee");
        assertGt(sellerWethReceived, 0, "Seller must receive WETH proceeds");
        vm.stopPrank();

        // Verify diamond balance = 0 for ALL 3 tokens
        assertEq(usdc.balanceOf(address(market)), 0, "Diamond must not hold USDC");
        assertEq(dai.balanceOf(address(market)), 0, "Diamond must not hold DAI");
        assertEq(weth.balanceOf(address(market)), 0, "Diamond must not hold WETH");

        // Verify buyer received all NFTs
        assertEq(erc721.ownerOf(20), buyer, "Buyer should own NFT 20");
        assertEq(erc721.ownerOf(21), buyer, "Buyer should own NFT 21");
        assertEq(erc721.ownerOf(22), buyer, "Buyer should own NFT 22");
    }

    // =========================================================================
    // Group 2: Update Listing Currency Switch (2 tests)
    // =========================================================================

    /**
     * @notice Test expectedCurrency protection against currency switch
     * @dev Seller switches from USDC to DAI, buyer's expectedCurrency prevents purchase
     */
    function testUpdateListingCurrencySwitchWithExpectedCurrency() public {
        // Setup
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        erc721.mint(seller, 30);

        // Create listing with USDC
        vm.startPrank(seller);
        erc721.setApprovalForAll(address(market), true);
        market.createListing(
            address(erc721), 30, address(0), 1000e18, address(usdc), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        uint128 listingId = getter.getNextListingId() - 1;

        // Buyer approves USDC
        usdc.mint(buyer, 1000e18);
        vm.prank(buyer);
        usdc.approve(address(market), 1000e18);

        // Seller switches listing to DAI
        vm.prank(seller);
        market.updateListing(
            listingId,
            1000e18, // same price
            address(dai), // switched to DAI!
            address(0),
            0,
            0,
            0,
            false,
            false,
            new address[](0)
        );

        // Buyer attempts purchase with expectedCurrency = USDC
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__ListingTermsChanged.selector); // Should revert due to currency mismatch
        market.purchaseListing(listingId, 1000e18, address(usdc), 0, address(0), 0, 0, 0, address(0));

        // Verify listing still exists
        Listing memory listing = getter.getListingByListingId(listingId);
        assertEq(listing.erc1155Quantity, 0, "Listing should still exist (ERC721)");
        assertEq(listing.currency, address(dai), "Listing currency should be DAI");
    }

    function testUpdateListing() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__NotAuthorizedOperator.selector);
        market.updateListing(id, 2 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));
        vm.stopPrank();

        vm.startPrank(seller);
        uint32 feeNow = getter.getInnovationFee();
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingUpdated(
            id, address(erc721), 1, 0, 2 ether, address(0), feeNow, seller, false, false, address(0), 0, 0
        );
        market.updateListing(id, 2 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));
        vm.stopPrank();

        Listing memory updated = getter.getListingByListingId(id);
        assertEq(updated.price, 2 ether);

        address[] memory newBuyers = new address[](1);
        newBuyers[0] = buyer;
        vm.startPrank(seller);
        market.updateListing(id, 2 ether, address(0), address(0), 0, 0, 0, true, false, newBuyers);
        vm.stopPrank();

        assertTrue(getter.isBuyerWhitelisted(id, buyer));
    }

    /**
     * @notice Test creating listing in non-allowed currency after removal
     * @dev New listings in removed currency revert, but existing listings still work
     */
    function testCanCreateListingInNonAllowedCurrencyAfterRemoval() public {
        // Setup: Add custom token
        MockERC20 customToken = new MockERC20("Custom", "CSTM");
        vm.prank(owner);
        currencies.addAllowedCurrency(address(customToken));

        // Whitelist collection
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        erc721.mint(seller, 40);
        erc721.mint(seller, 41);

        // Create listing with custom token
        vm.startPrank(seller);
        erc721.setApprovalForAll(address(market), true);
        market.createListing(
            address(erc721),
            40,
            address(0),
            100e18,
            address(customToken),
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

        // Remove custom token from allowlist
        vm.prank(owner);
        currencies.removeAllowedCurrency(address(customToken));

        // Attempt to create NEW listing with removed token → should REVERT
        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__CurrencyNotAllowed.selector);
        market.createListing(
            address(erc721),
            41,
            address(0),
            100e18,
            address(customToken),
            address(0),
            0,
            0,
            0,
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();

        // But existing listing can still be purchased (backward compatibility)
        customToken.mint(buyer, 100e18);
        vm.startPrank(buyer);
        customToken.approve(address(market), 100e18);
        market.purchaseListing(listingId, 100e18, address(customToken), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Verify purchase succeeded
        assertEq(erc721.ownerOf(40), buyer, "Buyer should own NFT 40");
        assertEq(customToken.balanceOf(address(market)), 0, "Diamond must not hold custom token");
    }

    // =========================================================================
    // Group 3: Tiny Amounts and Rounding (1 test)
    // =========================================================================

    /**
     * @notice Test tiny ERC20 amounts (1 unit) for rounding errors
     * @dev Verifies no rounding loss with smallest possible amounts
     */
    function testTinyERC20AmountPurchaseNoRounding() public {
        // Setup
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        erc721.mint(seller, 50);

        // Create listing: 1 unit price (smallest possible)
        vm.startPrank(seller);
        erc721.setApprovalForAll(address(market), true);
        market.createListing(
            address(erc721), 50, address(0), 1, address(tinyToken), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        uint128 listingId = getter.getNextListingId() - 1;

        // Get balances before purchase
        uint256 sellerBefore = tinyToken.balanceOf(seller);
        uint256 ownerBefore = tinyToken.balanceOf(owner);

        // Buyer purchases
        tinyToken.mint(buyer, 1);
        vm.startPrank(buyer);
        tinyToken.approve(address(market), 1);
        market.purchaseListing(listingId, 1, address(tinyToken), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Verify buyer paid exactly 1 unit
        assertEq(tinyToken.balanceOf(buyer), 0, "Buyer should have paid 1 unit");

        // Verify seller + owner = 1 unit (no rounding loss)
        uint256 sellerAfter = tinyToken.balanceOf(seller);
        uint256 ownerAfter = tinyToken.balanceOf(owner);
        uint256 totalReceived = (sellerAfter - sellerBefore) + (ownerAfter - ownerBefore);
        assertEq(totalReceived, 1, "Seller + owner should equal 1 unit");

        // Verify diamond balance = 0
        assertEq(tinyToken.balanceOf(address(market)), 0, "Diamond must not hold tokens");

        // Verify NFT transferred
        assertEq(erc721.ownerOf(50), buyer, "Buyer should own NFT");
    }

    // =========================================================================
    // Group 4: Buyer Whitelist + ERC20 (1 test)
    // =========================================================================

    /**
     * @notice Test buyer whitelist enforcement with ERC20 payment
     * @dev Non-whitelisted buyer cannot purchase, whitelisted buyer can
     */
    function testBuyerWhitelistWithERC20Purchase() public {
        // Setup
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        erc721.mint(seller, 60);

        // Create listing with buyer whitelist enabled
        address buyer1 = makeAddr("buyer1");
        address buyer2 = makeAddr("buyer2");
        address[] memory allowedBuyers = new address[](1);
        allowedBuyers[0] = buyer1;

        vm.startPrank(seller);
        erc721.setApprovalForAll(address(market), true);
        market.createListing(
            address(erc721),
            60,
            address(0),
            500e18,
            address(usdc),
            address(0),
            0,
            0,
            0,
            true, // buyer whitelist enabled
            false,
            allowedBuyers
        );
        vm.stopPrank();

        uint128 listingId = getter.getNextListingId() - 1;

        // Attempt purchase as buyer2 (not whitelisted) → should REVERT
        usdc.mint(buyer2, 500e18);
        vm.startPrank(buyer2);
        usdc.approve(address(market), 500e18);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__BuyerNotWhitelisted.selector, listingId, buyer2));
        market.purchaseListing(listingId, 500e18, address(usdc), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Purchase as buyer1 (whitelisted) → should SUCCEED
        uint256 sellerBefore = usdc.balanceOf(seller);
        uint256 ownerBefore = usdc.balanceOf(owner);

        usdc.mint(buyer1, 500e18);
        vm.startPrank(buyer1);
        usdc.approve(address(market), 500e18);
        market.purchaseListing(listingId, 500e18, address(usdc), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Verify payment distribution
        uint256 sellerReceived = usdc.balanceOf(seller) - sellerBefore;
        uint256 ownerReceived = usdc.balanceOf(owner) - ownerBefore;
        assertEq(sellerReceived + ownerReceived, 500e18, "Total distribution must equal price");
        assertGt(ownerReceived, 0, "Owner must receive fee");
        assertGt(sellerReceived, 0, "Seller must receive proceeds");
        assertEq(usdc.balanceOf(address(market)), 0, "Diamond must not hold USDC");

        // Verify NFT transferred to buyer1
        assertEq(erc721.ownerOf(60), buyer1, "Buyer1 should own NFT");
    }

    // =========================================================================
    // Group 5: Collection De-whitelist + CleanListing (1 test)
    // =========================================================================

    /**
     * @notice Test collection de-whitelist triggers cleanListing
     * @dev All listings should be removed when collection is de-whitelisted
     */
    function testCollectionDewhitelistTriggersCleanListingWithERC20() public {
        // Setup: Whitelist collection
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        // Mint NFTs and create 2 listings
        erc721.mint(seller, 70);
        erc721.mint(seller, 71);

        vm.startPrank(seller);
        erc721.setApprovalForAll(address(market), true);
        market.createListing(
            address(erc721), 70, address(0), 100e18, address(usdc), address(0), 0, 0, 0, false, false, new address[](0)
        );
        market.createListing(
            address(erc721), 71, address(0), 200e18, address(usdc), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        uint128 listingId1 = getter.getNextListingId() - 2;
        uint128 listingId2 = getter.getNextListingId() - 1;

        // Verify listings exist
        Listing memory listing1 = getter.getListingByListingId(listingId1);
        Listing memory listing2 = getter.getListingByListingId(listingId2);
        assertEq(listing1.tokenAddress, address(erc721), "Listing 1 should exist");
        assertEq(listing2.tokenAddress, address(erc721), "Listing 2 should exist");

        // Remove collection from whitelist
        vm.prank(owner);
        collections.removeWhitelistedCollection(address(erc721));

        // Verify purchases FAIL for de-whitelisted collection (before cleanListing)
        usdc.mint(buyer, 100e18);
        vm.startPrank(buyer);
        usdc.approve(address(market), 100e18);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__CollectionNotWhitelisted.selector, address(erc721)));
        market.purchaseListing(listingId1, 100e18, address(usdc), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Listings still exist but are invalid - manually call cleanListing
        vm.prank(owner);
        market.cleanListing(listingId1);
        vm.prank(owner);
        market.cleanListing(listingId2);

        // Verify both listings deleted (reverts when accessing)
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingId1));
        getter.getListingByListingId(listingId1);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingId2));
        getter.getListingByListingId(listingId2);

        // Attempt to purchase deleted listing → should REVERT
        usdc.mint(buyer, 100e18);
        vm.startPrank(buyer);
        usdc.approve(address(market), 100e18);
        vm.expectRevert(IdeationMarket__NotListed.selector);
        market.purchaseListing(listingId1, 100e18, address(usdc), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Re-whitelist collection for cleanup
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));
    }

    // =========================================================================
    // Group 6: Partial Buys with ERC20 (1 test)
    // =========================================================================

    /**
     * @notice Test partial buy with ERC20 unit price calculation
     * @dev Verifies correct payment for partial amounts and listing update
     */
    function testPartialBuyWithERC20UnitPriceCalculation() public {
        // Setup: Whitelist collection
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Mint ERC1155 tokens to seller (use tokenId 99 to avoid conflict with base setup)
        erc1155.mint(seller, 99, 10);

        // Create listing: 10 NFTs at 100 USDC each (total = 1000 USDC)
        vm.startPrank(seller);
        erc1155.setApprovalForAll(address(market), true);
        market.createListing(
            address(erc1155), 99, seller, 1000e18, address(usdc), address(0), 0, 0, 10, false, true, new address[](0)
        );
        vm.stopPrank();

        uint128 listingId = getter.getNextListingId() - 1;

        // Buyer purchases 5 out of 10 NFTs (should pay 500 USDC)
        uint256 sellerBefore = usdc.balanceOf(seller);
        uint256 ownerBefore = usdc.balanceOf(owner);

        usdc.mint(buyer, 500e18);
        vm.startPrank(buyer);
        usdc.approve(address(market), 500e18);
        market.purchaseListing(listingId, 1000e18, address(usdc), 10, address(0), 0, 0, 5, address(0));
        vm.stopPrank();

        // Verify buyer paid exactly 500 USDC (5/10 * 1000)
        assertEq(usdc.balanceOf(buyer), 0, "Buyer should have paid 500 USDC");

        // Verify payment distribution
        uint256 sellerReceived = usdc.balanceOf(seller) - sellerBefore;
        uint256 ownerReceived = usdc.balanceOf(owner) - ownerBefore;
        assertEq(sellerReceived + ownerReceived, 500e18, "Total distribution must equal partial price");

        // Verify buyer received exactly 5 ERC1155 tokens
        assertEq(erc1155.balanceOf(buyer, 99), 5, "Buyer should have 5 ERC1155 tokens");

        // Verify diamond has zero balance
        assertEq(usdc.balanceOf(address(market)), 0, "Diamond must not hold tokens");

        // Verify listing still exists with 5 NFTs remaining
        Listing memory listing = getter.getListingByListingId(listingId);
        assertEq(listing.erc1155Quantity, 5, "Should have 5 NFTs remaining");

        // Second buyer purchases remaining 5 (listing now has 5 NFTs at 500 USDC)
        address buyer2 = makeAddr("buyer2");
        usdc.mint(buyer2, 500e18);
        vm.startPrank(buyer2);
        usdc.approve(address(market), 500e18);
        market.purchaseListing(listingId, 500e18, address(usdc), 5, address(0), 0, 0, 5, address(0));
        vm.stopPrank();

        // Verify buyer2 received exactly 5 ERC1155 tokens
        assertEq(erc1155.balanceOf(buyer2, 99), 5, "Buyer2 should have 5 ERC1155 tokens");

        // Verify seller has 0 remaining of tokenId 99
        assertEq(erc1155.balanceOf(seller, 99), 0, "Seller should have 0 ERC1155 tokens left");

        // Verify listing deleted after full purchase
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingId));
        getter.getListingByListingId(listingId);

        // Verify diamond balance still 0
        assertEq(usdc.balanceOf(address(market)), 0, "Diamond must not hold tokens");
    }

    // =========================================================================
    // Group 7: NFT Swaps with ERC20 (1 test)
    // =========================================================================

    /**
     * @notice Test NFT swap with additional ERC20 payment
     * @dev Buyer provides swap NFT + ERC20 payment
     */
    function testNFTSwapWithAdditionalERC20Payment() public {
        // Setup: Whitelist both collections
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        MockERC721 swapNFT = new MockERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(swapNFT));

        // Mint NFTs
        erc721.mint(seller, 80);
        swapNFT.mint(buyer, 100);

        // Create listing: seller wants swapNFT tokenId 100 + 500 USDC
        vm.startPrank(seller);
        erc721.setApprovalForAll(address(market), true);
        market.createListing(
            address(erc721),
            80,
            address(0),
            500e18,
            address(usdc),
            address(swapNFT),
            100,
            0,
            0,
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();

        uint128 listingId = getter.getNextListingId() - 1;

        // Buyer approves swap NFT and USDC
        uint256 sellerBefore = usdc.balanceOf(seller);
        uint256 ownerBefore = usdc.balanceOf(owner);

        usdc.mint(buyer, 500e18);
        vm.startPrank(buyer);
        swapNFT.approve(address(market), 100);
        usdc.approve(address(market), 500e18);

        // Execute purchase
        market.purchaseListing(listingId, 500e18, address(usdc), 0, address(swapNFT), 100, 0, 0, address(0));
        vm.stopPrank();

        // Verify ERC20 payment distribution
        uint256 sellerReceived = usdc.balanceOf(seller) - sellerBefore;
        uint256 ownerReceived = usdc.balanceOf(owner) - ownerBefore;
        assertEq(sellerReceived + ownerReceived, 500e18, "Total distribution must equal price");
        assertGt(ownerReceived, 0, "Owner must receive fee");
        assertGt(sellerReceived, 0, "Seller must receive proceeds");

        // Verify NFT swap
        assertEq(erc721.ownerOf(80), buyer, "Buyer should own NFT 80");
        assertEq(swapNFT.ownerOf(100), seller, "Seller should own swap NFT 100");

        // Verify ERC20 payment
        assertEq(usdc.balanceOf(address(market)), 0, "Diamond must not hold USDC");

        // Verify buyer paid 500 USDC
        assertEq(usdc.balanceOf(buyer), 0, "Buyer should have paid 500 USDC");
    }

    // =========================================================================
    // Group 8: ERC2981 Royalty with ERC20 (1 test)
    // =========================================================================

    /**
     * @notice Test ERC2981 royalty distribution with ERC20 payment
     * @dev Verifies royalty receiver gets correct amount from ERC20 sale
     */
    function testERC2981RoyaltyWithERC20Payment() public {
        // Setup royalty: 5% royalty (5000 out of 100_000)
        address royaltyReceiver = makeAddr("royaltyReceiver");
        royaltyNFT.setRoyalty(royaltyReceiver, 5000); // 5%

        // Mint NFT to seller
        royaltyNFT.mint(seller, 90);

        // Create listing for 1000 USDC
        vm.startPrank(seller);
        royaltyNFT.setApprovalForAll(address(market), true);
        market.createListing(
            address(royaltyNFT),
            90,
            address(0),
            1000e18,
            address(usdc),
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

        // Get balances before purchase
        uint256 royaltyReceiverBefore = usdc.balanceOf(royaltyReceiver);
        uint256 sellerBefore = usdc.balanceOf(seller);
        uint256 ownerBefore = usdc.balanceOf(owner);

        // Buyer purchases
        usdc.mint(buyer, 1000e18);
        vm.startPrank(buyer);
        usdc.approve(address(market), 1000e18);
        market.purchaseListing(listingId, 1000e18, address(usdc), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Verify royalty payment (5% of 1000 = 50 USDC)
        uint256 royaltyReceiverAfter = usdc.balanceOf(royaltyReceiver);
        uint256 royaltyPaid = royaltyReceiverAfter - royaltyReceiverBefore;
        assertEq(royaltyPaid, 50e18, "Royalty receiver should get 50 USDC (5%)");

        // Verify diamond balance = 0
        assertEq(usdc.balanceOf(address(market)), 0, "Diamond must not hold USDC");

        // Verify total distribution (owner fee + royalty + seller = 1000)
        uint256 sellerAfter = usdc.balanceOf(seller);
        uint256 ownerAfter = usdc.balanceOf(owner);
        uint256 totalDistributed =
            (ownerAfter - ownerBefore) + (royaltyReceiverAfter - royaltyReceiverBefore) + (sellerAfter - sellerBefore);
        assertEq(totalDistributed, 1000e18, "Total distribution should equal listing price");

        // Verify NFT transferred
        assertEq(royaltyNFT.ownerOf(90), buyer, "Buyer should own NFT");
    }

    // =========================================================================
    // Group 9: Getter Facet Accuracy (1 test - BONUS)
    // =========================================================================

    /**
     * @notice Test getAllowedCurrencies with large array
     * @dev Verifies getter accuracy with adding/removing currencies
     */
    function testGetAllowedCurrenciesWithLargeArray() public {
        // Verify initial state (76 currencies from DiamondInit + 4 added in setUp)
        address[] memory currencies1 = getter.getAllowedCurrencies();
        assertEq(currencies1.length, 76 + 4, "Should have 76 + 4 (usdc,dai,weth,tiny) currencies");

        // Add 10 more currencies
        MockERC20[] memory newTokens = new MockERC20[](10);
        for (uint256 i = 0; i < 10; i++) {
            newTokens[i] = new MockERC20(
                string(abi.encodePacked("Token", vm.toString(i))), string(abi.encodePacked("TKN", vm.toString(i)))
            );
            vm.prank(owner);
            currencies.addAllowedCurrency(address(newTokens[i]));
        }

        // Verify array length increased
        address[] memory currencies2 = getter.getAllowedCurrencies();
        assertEq(currencies2.length, 90, "Should have 90 currencies");

        // Remove 5 currencies
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(owner);
            currencies.removeAllowedCurrency(address(newTokens[i]));
        }

        // Verify array length decreased
        address[] memory currencies3 = getter.getAllowedCurrencies();
        assertEq(currencies3.length, 85, "Should have 85 currencies");

        // Verify removed currencies NOT in array
        for (uint256 i = 0; i < 5; i++) {
            bool found = false;
            for (uint256 j = 0; j < currencies3.length; j++) {
                if (currencies3[j] == address(newTokens[i])) {
                    found = true;
                    break;
                }
            }
            assertFalse(found, "Removed currency should not be in array");
        }

        // Verify remaining currencies still in array
        for (uint256 i = 5; i < 10; i++) {
            bool found = false;
            for (uint256 j = 0; j < currencies3.length; j++) {
                if (currencies3[j] == address(newTokens[i])) {
                    found = true;
                    break;
                }
            }
            assertTrue(found, "Remaining currency should be in array");
        }
    }
}
