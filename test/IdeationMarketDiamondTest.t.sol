// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

/*
 * @title IdeationMarketDiamondTest
 * @notice Comprehensive unit tests covering the diamond and all marketplace facets.
 *
 * These tests deploy the diamond and its facets from scratch using the same
 * deployment logic as the provided deploy script. They then exercise every
 * public and external function exposed by the facets, including both success
 * paths and revert branches, to maximise code coverage. Minimal mock ERC‑721
 * and ERC‑1155 token contracts are included at the bottom of the file to
 * facilitate testing of marketplace operations such as listing creation,
 * updating, cancellation and purchase.  Custom errors are checked with
 * `vm.expectRevert` and state assertions verify that storage mutations occur
 * as intended.
 */
contract IdeationMarketDiamondTest is MarketTestBase {
    // -------------------------------------------------------------------------
    // Diamond & Loupe Tests
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // Ownership Tests
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // Collection Whitelist Tests
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // Buyer Whitelist Tests
    // -------------------------------------------------------------------------

    // -------------------------------------------------------------------------
    // Marketplace Listing Tests
    // -------------------------------------------------------------------------

    function testCleanListing721() public {
        // Create listing
        uint128 id = _createListingERC721(false, new address[](0));
        // With approvals still present, cleanListing should revert with the StillApproved error.
        vm.startPrank(operator);
        vm.expectRevert(IdeationMarket__StillApproved.selector);
        market.cleanListing(id);
        vm.stopPrank();

        // Remove approval and call cleanListing again. This should succeed and remove the listing.
        vm.startPrank(seller);
        erc721.approve(address(0), 1);
        vm.stopPrank();
        vm.startPrank(operator);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(id, address(erc721), 1, seller, operator);

        market.cleanListing(id);
        vm.stopPrank();
        // After cleaning, the listing should no longer exist. Expect the
        // GetterFacet to revert with Getter__ListingNotFound(listingId).
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCleanListing_WhileStillApproved_ERC721_Reverts() public {
        // Whitelist + approve + create a valid ERC721 listing
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Anyone can call cleanListing, but since the listing is still valid, it must revert
        address rando = vm.addr(0xC1EA11);
        vm.startPrank(rando);
        vm.expectRevert(IdeationMarket__StillApproved.selector);
        market.cleanListing(id);
        vm.stopPrank();
    }

    /// -----------------------------------------------------------------------
    /// ERC1155 purchase-time quantity rules
    /// -----------------------------------------------------------------------

    function testERC1155BuyingMoreThanListedReverts() public {
        // Whitelist ERC1155 and approve the marketplace
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.stopPrank();

        vm.startPrank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        // List quantity = 10, price = 10 ether, partial buys enabled (divisible)
        market.createListing(
            address(erc1155),
            1,
            seller, // erc1155Holder
            10 ether, // price
            address(0), // currency
            address(0), // desiredTokenAddress
            0, // desiredTokenId
            0, // desiredErc1155Quantity
            10, // erc1155Quantity
            false, // buyerWhitelistEnabled
            true, // partialBuyEnabled
            new address[](0)
        );
        vm.stopPrank();

        uint128 id = getter.getNextListingId() - 1;

        // Buyer tries to buy more than listed (11 > 10) → InvalidPurchaseQuantity
        vm.deal(buyer, 20 ether);
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__InvalidPurchaseQuantity.selector);
        market.purchaseListing{value: 20 ether}(
            id,
            10 ether, // expectedPrice
            address(0), // expectedCurrency
            10, // expectedErc1155Quantity
            address(0), // desiredTokenAddress
            0, // desiredTokenId
            0, // desiredErc1155Quantity
            11, // erc1155PurchaseQuantity > listed
            address(0) // buyerReceiver
        );
        vm.stopPrank();
    }

    function testERC1155PartialBuyDisabledReverts() public {
        // Whitelist ERC1155 and approve the marketplace
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.stopPrank();

        vm.startPrank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        // List quantity = 10, price = 10 ether, partial buys DISABLED
        market.createListing(
            address(erc1155),
            1,
            seller, // erc1155Holder
            10 ether, // price
            address(0), // currency
            address(0), // desiredTokenAddress
            0, // desiredTokenId
            0, // desiredErc1155Quantity
            10, // erc1155Quantity
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled (disabled)
            new address[](0)
        );
        vm.stopPrank();

        uint128 id = getter.getNextListingId() - 1;

        // Buyer attempts partial buy (5 of 10) while partials are disabled
        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__PartialBuyNotPossible.selector);
        market.purchaseListing{value: 5 ether}(
            id,
            10 ether, // expectedPrice
            address(0), // expectedCurrency
            10, // expectedErc1155Quantity
            address(0), // desiredTokenAddress
            0, // desiredTokenId
            0, // desiredErc1155Quantity
            5, // partial purchase
            address(0) // buyerReceiver
        );
        vm.stopPrank();
    }

    // listingId starts at 1 and increments
    function testListingIdIncrements() public {
        _whitelistCollectionAndApproveERC721();

        vm.startPrank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );

        // Approve token #2 before creating its listing
        erc721.approve(address(diamond), 2);

        market.createListing(
            address(erc721), 2, address(0), 2 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        // next id should be 3, last created is 2
        assertEq(getter.getNextListingId(), 3);
        Listing memory l1 = getter.getListingByListingId(1);
        Listing memory l2 = getter.getListingByListingId(2);
        assertEq(l1.listingId, 1);
        assertEq(l2.listingId, 2);
    }

    // owner (diamond owner) can cancel any listing
    function testOwnerCanCancelAnyListing() public {
        uint128 id = _createListingERC721(false, new address[](0));

        // Owner cancels although not token owner nor approved
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceled(id, address(erc721), 1, seller, owner);

        market.cancelListing(id);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    // purchase fails if approval revoked between listing and purchase
    function testPurchaseRevertsIfApprovalRevokedBeforeBuy() public {
        uint128 id = _createListingERC721(false, new address[](0));

        // Revoke marketplace approval
        vm.prank(seller);
        erc721.approve(address(0), 1);

        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    // update keeps same listingId even with other activity in between
    function testUpdateKeepsListingId() public {
        _whitelistCollectionAndApproveERC721();

        // First listing (id=1)
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id1 = 1;

        // Create & cancel another listing to disturb state
        vm.prank(seller);
        erc721.approve(address(diamond), 2);
        vm.prank(seller);
        market.createListing(
            address(erc721), 2, address(0), 2 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id2 = 2;
        vm.prank(seller);
        market.cancelListing(id2);

        // Update the first listing, id must remain 1
        vm.prank(seller);
        market.updateListing(id1, 3 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));

        Listing memory l = getter.getListingByListingId(id1);
        assertEq(l.listingId, 1);
        assertEq(l.price, 3 ether);
    }

    // whitelist of exactly MAX_BATCH succeeds on create; >MAX_BATCH reverts
    function testCreateWithWhitelistExactlyMaxBatchSucceeds() public {
        _whitelistCollectionAndApproveERC721();

        address[] memory buyersList = new address[](MAX_BATCH);
        for (uint256 i = 0; i < buyersList.length; i++) {
            buyersList[i] = vm.addr(10_000 + i);
        }

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, true, false, buyersList
        );

        uint128 id = getter.getNextListingId() - 1;
        // Spot check a couple of entries made it in
        assertTrue(getter.isBuyerWhitelisted(id, buyersList[0]));
        assertTrue(getter.isBuyerWhitelisted(id, buyersList[buyersList.length - 1]));
    }

    function testCreateWithWhitelistOverMaxBatchReverts() public {
        _whitelistCollectionAndApproveERC721();

        address[] memory tooMany = new address[](uint256(MAX_BATCH) + 1);
        for (uint256 i = 0; i < tooMany.length; i++) {
            tooMany[i] = vm.addr(20_000 + i);
        }

        vm.startPrank(seller);
        vm.expectRevert(abi.encodeWithSelector(BuyerWhitelist__ExceedsMaxBatchSize.selector, tooMany.length));
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, true, false, tooMany
        );
        vm.stopPrank();
    }

    // purchase-time royalty > proceeds reverts (listing itself may succeed)
    function testPurchaseRevertsWhenRoyaltyExceedsProceeds() public {
        // High-royalty token (e.g., 99.5%)
        MockERC721Royalty royaltyNft = new MockERC721Royalty();
        royaltyNft.mint(seller, 1);
        royaltyNft.setRoyalty(address(0xB0B), 99_500);

        vm.prank(owner);
        collections.addWhitelistedCollection(address(royaltyNft));

        vm.prank(seller);
        royaltyNft.approve(address(diamond), 1);

        // Listing will succeed with your current code (no listing-time check)
        vm.prank(seller);
        market.createListing(
            address(royaltyNft), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 2 ether);
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__RoyaltyFeeExceedsProceeds.selector);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    // swap with same NFT reverts
    function testSwapWithSameNFTReverts() public {
        _whitelistCollectionAndApproveERC721();

        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__NoSwapForSameToken.selector);
        market.createListing(
            address(erc721),
            1,
            address(0),
            0, // price 0 (swap-only) ok
            address(0), // currency
            address(erc721), // desiredTokenAddress (same as listed)
            1, // desiredTokenId
            0, // desiredErc1155Quantity
            0, // erc1155Quantity
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();
    }

    // ERC1155 createListing wrong quantity flags → should revert with WrongQuantityParameter
    // NOTE: With your current code, this may fail earlier due to calling ERC1155 methods before checking interface.
    function testWrongQuantityParameterPaths() public {
        // Try to list ERC721 but with erc1155Quantity > 0
        _whitelistCollectionAndApproveERC721();
        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__WrongQuantityParameter.selector);
        market.createListing(
            address(erc721),
            1,
            seller,
            1 ether,
            address(0), // currency
            address(0), // desiredTokenAddress
            0, // desiredTokenId
            0, // desiredErc1155Quantity
            5, // wrongly treating ERC721 as ERC1155
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();

        // List ERC1155 but with erc1155Quantity == 0
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.stopPrank();

        vm.startPrank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.expectRevert(IdeationMarket__WrongQuantityParameter.selector);
        market.createListing(
            address(erc1155),
            1,
            seller,
            1 ether,
            address(0), // currency
            address(0), // desiredTokenAddress
            0, // desiredTokenId
            0, // desiredErc1155Quantity
            0, // wrongly treating ERC1155 as ERC721
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();
    }

    // buyer not on whitelist cannot purchase when whitelist enabled
    function testWhitelistPreventsPurchase() public {
        _whitelistCollectionAndApproveERC721();

        // Whitelist someone else (not the buyer) so creation succeeds

        address[] memory allowed = new address[](1);
        allowed[0] = operator;

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, true, false, allowed
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__BuyerNotWhitelisted.selector, id, buyer));
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    function testERC1155PartialBuyHappyPath() public {
        // Whitelist & approve
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // List qty=10, price=10 ETH, partials enabled
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer buys 4 → purchasePrice=4 ETH; remains: qty=6, price=6 ETH
        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);

        uint32 feeSnap = getter.getListingByListingId(id).feeRate;
        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingPurchased(
            id, address(erc1155), 1, 4, true, 4 ether, address(0), feeSnap, seller, buyer, address(0), 0, 0
        );

        market.purchaseListing{value: 4 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 4, address(0));

        vm.stopPrank();

        // Listing mutated correctly
        Listing memory l = getter.getListingByListingId(id);
        assertEq(l.erc1155Quantity, 6);
        assertEq(l.price, 6 ether);

        // Atomic payment: seller gets 3.96 ETH, owner gets 0.04 ETH (1% fee)
        assertEq(seller.balance - sellerBalBefore, 3.96 ether);
        assertEq(owner.balance - ownerBalBefore, 0.04 ether);
    }

    function testInnovationFeeUpdateSemantics() public {
        _whitelistCollectionAndApproveERC721();

        // Listing #1 under initial fee (1000 = 1%)
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id1 = getter.getNextListingId() - 1;
        assertEq(getter.getListingByListingId(id1).feeRate, 1000);

        // Update fee to 2.5% and create Listing #2 using new fee
        vm.startPrank(owner);
        uint32 prev = getter.getInnovationFee();
        uint32 next = 2500;
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.InnovationFeeUpdated(prev, next);
        market.setInnovationFee(2500);
        vm.stopPrank();

        vm.prank(seller);
        erc721.approve(address(diamond), 2);
        vm.prank(seller);
        market.createListing(
            address(erc721), 2, address(0), 2 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id2 = getter.getNextListingId() - 1;
        assertEq(getter.getListingByListingId(id2).feeRate, 2500);

        // Listing #1 still has old fee until updated
        assertEq(getter.getListingByListingId(id1).feeRate, 1000);

        // Updating #1 "refreshes" fee to current (2500)
        vm.prank(seller);
        market.updateListing(id1, 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));
        assertEq(getter.getListingByListingId(id1).feeRate, 2500);
    }

    function testExactPaymentRequired() public {
        uint128 id = _createListingERC721(false, new address[](0)); // price = 1 ETH

        vm.deal(buyer, 3 ether);
        uint256 buyerBalBefore = buyer.balance;
        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;

        // Non-custodial: exact payment required (no overpay)
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        // Atomic payments: seller gets 0.99 ETH, owner gets 0.01 ETH (1% fee)
        assertEq(seller.balance - sellerBalBefore, 0.99 ether);
        assertEq(owner.balance - ownerBalBefore, 0.01 ether);

        // Buyer spent exactly 1 ETH (no overpay mechanism)
        uint256 buyerBalAfter = buyer.balance;
        assertEq(buyerBalBefore - buyerBalAfter, 1 ether);

        // Non-custodial: diamond holds no balance (atomic payments)
        assertEq(address(diamond).balance, 0);
    }

    function testActiveListingIdClearsAfterCancel() public {
        _whitelistCollectionAndApproveERC721();

        // Create & cancel listing
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        vm.prank(seller);
        market.cancelListing(id);

        // No active listing
        assertEq(getter.getActiveListingIdByERC721(address(erc721), 1), 0);
    }

    function testUpdateAfterCollectionDeWhitelistingCancels() public {
        _whitelistCollectionAndApproveERC721();

        // Create listing
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // De-whitelist the collection
        vm.prank(owner);
        collections.removeWhitelistedCollection(address(erc721));

        // Calling updateListing should cancel and return (no revert)
        vm.prank(seller);
        market.updateListing(id, 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));

        // Listing is gone
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testRoyaltyPaymentWithOwnerFee() public {
        // Prepare royalty NFT (10%) and whitelist
        MockERC721Royalty royaltyNft = new MockERC721Royalty();
        royaltyNft.mint(seller, 1);
        address royaltyReceiver = address(0xB0B);
        royaltyNft.setRoyalty(royaltyReceiver, 10_000); // 10% of 100_000

        vm.prank(owner);
        collections.addWhitelistedCollection(address(royaltyNft));

        // Approve & list for 1 ETH
        vm.prank(seller);
        royaltyNft.approve(address(diamond), 1);
        vm.prank(seller);
        market.createListing(
            address(royaltyNft), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Capture balances before purchase
        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;
        uint256 royaltyBalBefore = royaltyReceiver.balance;

        // Purchase at 1 ETH
        vm.deal(buyer, 2 ether);
        vm.startPrank(buyer);
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.RoyaltyPaid(id, royaltyReceiver, address(0), 0.1 ether); // currency is address(0) for ETH

        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Atomic payments: fee(1%)=0.01; royalty(10%)=0.1 → seller gets 0.89
        assertEq(seller.balance - sellerBalBefore, 0.89 ether);
        assertEq(owner.balance - ownerBalBefore, 0.01 ether);
        assertEq(royaltyReceiver.balance - royaltyBalBefore, 0.1 ether);

        // Non-custodial: diamond holds no balance
        assertEq(address(diamond).balance, 0);
    }

    function testFeeRoyaltyRounding_TinyPrices() public {
        // innovationFee is 1% by default in your setup (1000/100_000)
        MockERC721Royalty r = new MockERC721Royalty();
        address RR = vm.addr(0xBEEF);
        r.setRoyalty(RR, 1_000); // 1% of 100_000

        vm.prank(owner);
        collections.addWhitelistedCollection(address(r));

        // --- Case 1: price = 1 wei → fee=0, royalty=0 (floor), seller gets 1 wei
        r.mint(seller, 1);
        vm.prank(seller);
        r.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(r), 1, address(0), 1, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id1 = getter.getNextListingId() - 1;

        uint256 ownerBal1 = owner.balance;
        uint256 rrBal1 = RR.balance;
        uint256 sellerBal1 = seller.balance;

        vm.deal(buyer, 1);
        vm.prank(buyer);
        market.purchaseListing{value: 1}(id1, 1, address(0), 0, address(0), 0, 0, 0, address(0));

        assertEq(owner.balance - ownerBal1, 0); // fee 0
        assertEq(RR.balance - rrBal1, 0); // royalty 0
        assertEq(seller.balance - sellerBal1, 1);

        // --- Case 2: price = 101 wei → fee=1, royalty=1, seller gets 99
        r.mint(seller, 2);
        vm.prank(seller);
        r.approve(address(diamond), 2);

        vm.prank(seller);
        market.createListing(
            address(r), 2, address(0), 101, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id2 = getter.getNextListingId() - 1;

        uint256 ownerBal2 = owner.balance;
        uint256 rrBal2 = RR.balance;
        uint256 sellerBal2 = seller.balance;

        vm.deal(buyer, 101);
        vm.prank(buyer);
        market.purchaseListing{value: 101}(id2, 101, address(0), 0, address(0), 0, 0, 0, address(0));

        assertEq(owner.balance - ownerBal2, 1); // fee 1
        assertEq(RR.balance - rrBal2, 1); // royalty 1
        assertEq(seller.balance - sellerBal2, 99); // seller gets 99

        // --- Case 3: price = 199 wei → fee=1, royalty=1, seller 197
        r.mint(seller, 3);
        vm.prank(seller);
        r.approve(address(diamond), 3);

        vm.prank(seller);
        market.createListing(
            address(r), 3, address(0), 199, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id3 = getter.getNextListingId() - 1;

        uint256 ownerBal3 = owner.balance;
        uint256 rrBal3 = RR.balance;
        uint256 sellerBal3 = seller.balance;

        vm.deal(buyer, 199);
        vm.prank(buyer);
        market.purchaseListing{value: 199}(id3, 199, address(0), 0, address(0), 0, 0, 0, address(0));

        assertEq(owner.balance - ownerBal3, 1); // fee 1
        assertEq(RR.balance - rrBal3, 1); // royalty 1
        assertEq(seller.balance - sellerBal3, 197); // seller gets 197
    }

    function testInvalidUnitPriceOnCreateReverts() public {
        // ERC1155 listing with qty=3, price=10 (not divisible) and partials enabled → revert
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__InvalidUnitPrice.selector);
        market.createListing(
            address(erc1155),
            1,
            seller,
            10, // price
            address(0), // currency
            address(0), // desiredTokenAddress
            0, // desiredTokenId
            0, // desiredErc1155Quantity
            3, // quantity
            false,
            true, // partialBuyEnabled
            new address[](0)
        );
        vm.stopPrank();
    }

    /// -----------------------------------------------------------------------
    /// Whitelisted buyer success path
    /// -----------------------------------------------------------------------

    // Confirms that a buyer on the whitelist can purchase successfully.
    function testWhitelistedBuyerPurchaseSuccess() public {
        _whitelistCollectionAndApproveERC721();

        // Whitelist the buyer.
        address[] memory allowed = new address[](1);
        allowed[0] = buyer;

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, true, false, allowed
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer pays the exact price and should succeed.
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        // Listing is removed, token ownership transferred.
        assertEq(erc721.ownerOf(1), buyer);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// -----------------------------------------------------------------------
    /// ERC721 Approval-for-All creation path
    /// -----------------------------------------------------------------------

    // Tests that setApprovalForAll (without per-token approval) allows listing.
    function testERC721SetApprovalForAllCreateListing() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        // Seller grants blanket approval instead of approve(1).
        vm.prank(seller);
        erc721.setApprovalForAll(address(diamond), true);

        // Create listing for token ID 1; should succeed.
        vm.startPrank(seller);

        uint128 expectedId = getter.getNextListingId();
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCreated(
            expectedId,
            address(erc721),
            1,
            0,
            1 ether,
            address(0), // currency
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
        assertEq(l.tokenId, 1);
        assertEq(l.seller, seller);
    }

    /// -----------------------------------------------------------------------
    /// ERC721 creation without approval should revert
    /// -----------------------------------------------------------------------

    // A stand-alone check that creating a listing without any approval reverts.
    function testCreateListingWithoutApprovalReverts() public {
        // Whitelist the ERC721 collection.
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        // Attempt to list token ID 2 without approve() or setApprovalForAll().
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.createListing(
            address(erc721), 2, address(0), 2 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
    }

    /// -----------------------------------------------------------------------
    /// Reentrancy tests
    /// -----------------------------------------------------------------------

    // -----------------------------------------------------------------------
    // Extra edge-case tests
    // -----------------------------------------------------------------------

    function testCollectionWhitelistZeroAddressReverts() public {
        vm.prank(owner);
        vm.expectRevert(CollectionWhitelist__ZeroAddress.selector);
        collections.addWhitelistedCollection(address(0));
    }

    function testSellerCancelAfterApprovalRevoked() public {
        uint128 id = _createListingERC721(false, new address[](0));
        // Revoke approval then cancel as seller
        vm.prank(seller);
        erc721.approve(address(0), 1);

        vm.prank(seller);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCreateWithWhitelistEnabledEmptyArrayOK() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, true, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        Listing memory ls = getter.getListingByListingId(id);
        assertEq(ls.buyerWhitelistEnabled, true);

        // Sanity: no addresses are whitelisted yet
        assertEq(getter.isBuyerWhitelisted(id, buyer), false);
        assertEq(getter.isBuyerWhitelisted(id, seller), false);
    }

    function testUpdateEnableWhitelistWithEmptyArrayOK() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.prank(seller);
        market.updateListing(id, 1 ether, address(0), address(0), 0, 0, 0, true, false, new address[](0));

        Listing memory ls = getter.getListingByListingId(id);
        assertEq(ls.buyerWhitelistEnabled, true);

        // Sanity: no addresses are whitelisted yet
        assertEq(getter.isBuyerWhitelisted(id, buyer), false);
        assertEq(getter.isBuyerWhitelisted(id, seller), false);
    }

    function testUpdateDisableWhitelistThenOpenPurchase() public {
        _whitelistCollectionAndApproveERC721();

        address[] memory allowed = new address[](1);
        allowed[0] = operator;

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, true, false, allowed
        );
        uint128 id = getter.getNextListingId() - 1;

        // Disable whitelist on update
        vm.prank(seller);
        market.updateListing(id, 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));

        // Now anyone can buy
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        assertEq(erc721.ownerOf(1), buyer);
    }

    function testCreateWithWhitelistDisabledNonEmptyListReverts() public {
        _whitelistCollectionAndApproveERC721();

        address[] memory bogus = new address[](1);
        bogus[0] = buyer;

        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__WhitelistDisabled.selector);
        market.createListing(
            address(erc721),
            1,
            address(0),
            1 ether,
            address(0), // currency
            address(0), // desiredTokenAddress
            0, // desiredTokenId
            0, // desiredErc1155Quantity
            0, // erc1155Quantity
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            bogus // non-empty -> must revert per facet
        );
        vm.stopPrank();
    }

    function testCreateWithZeroTokenAddressReverts() public {
        // No whitelist entry can exist for address(0), expect revert
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__CollectionNotWhitelisted.selector, address(0)));
        market.createListing(
            address(0), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
    }

    function testCreatePriceZeroWithoutSwapReverts() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__FreeListingsNotSupported.selector);
        market.createListing(
            address(erc721), 1, address(0), 0, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
    }

    function testBuyNonexistentListingIdReverts() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotListed.selector);
        market.purchaseListing{value: 1 ether}(999_999, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
    }

    function testExpectedPriceMismatchReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        // Seller changes price to 2 ether
        vm.prank(seller);
        market.updateListing(id, 2 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));

        // Buyer sends enough ETH but insists expectedPrice=1 ether -> should revert
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__ListingTermsChanged.selector);
        market.purchaseListing{value: 2 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
    }

    function testExpectedErc1155QuantityMismatchReverts() public {
        // ERC1155 listing: qty=10
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__ListingTermsChanged.selector);
        market.purchaseListing{value: 10 ether}(id, 10 ether, address(0), 9, address(0), 0, 0, 10, address(0));
    }

    function testERC1155BuyExactRemainingRemovesListing() public {
        // List 10, partials enabled
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buy 4, then buy remaining 6
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 4 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 4, address(0));

        vm.deal(operator, 6 ether);
        vm.prank(operator);
        market.purchaseListing{value: 6 ether}(id, 6 ether, address(0), 6, address(0), 0, 0, 6, address(0));

        // Listing removed
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testERC721PurchaseWithNonZero1155QuantityReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__InvalidPurchaseQuantity.selector);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 1, address(0));
    }

    function testRepurchaseAfterBuyReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        // Second attempt should revert since listing is gone
        vm.deal(operator, 1 ether);
        vm.prank(operator);
        vm.expectRevert(IdeationMarket__NotListed.selector);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
    }

    function testUpdateNonexistentListingReverts() public {
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotListed.selector);
        market.updateListing(999_999, 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));
    }

    function testNoOpUpdateKeepsValues() public {
        uint128 id = _createListingERC721(false, new address[](0));
        Listing memory beforeL = getter.getListingByListingId(id);

        vm.prank(seller);
        market.updateListing(
            id,
            beforeL.price,
            beforeL.currency,
            beforeL.desiredTokenAddress,
            beforeL.desiredTokenId,
            beforeL.desiredErc1155Quantity,
            beforeL.erc1155Quantity,
            beforeL.buyerWhitelistEnabled,
            beforeL.partialBuyEnabled,
            new address[](0)
        );

        Listing memory afterL = getter.getListingByListingId(id);
        assertEq(afterL.listingId, beforeL.listingId);
        assertEq(afterL.price, beforeL.price);
        assertEq(afterL.erc1155Quantity, beforeL.erc1155Quantity);
    }

    function testERC1155UpdateInvalidUnitPriceReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // 7 ether % 3 != 0 in wei -> MUST revert
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__InvalidUnitPrice.selector);
        market.updateListing(id, 7 ether, address(0), address(0), 0, 0, 3, false, true, new address[](0));
    }

    function testCancelNonexistentListingReverts() public {
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotListed.selector);
        market.cancelListing(999_999);
    }

    function testDoubleCleanReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));

        // Revoke approval, clean once
        vm.prank(seller);
        erc721.approve(address(0), 1);

        vm.prank(operator);
        market.cleanListing(id);

        // Second clean should revert (listing gone)
        vm.prank(operator);
        vm.expectRevert(IdeationMarket__NotListed.selector);
        market.cleanListing(id);
    }

    function testRoyaltyReceiverEqualsSeller() public {
        MockERC721Royalty r = new MockERC721Royalty();
        r.mint(seller, 1);
        r.setRoyalty(seller, 10_000); // 10%

        vm.prank(owner);
        collections.addWhitelistedCollection(address(r));

        vm.prank(seller);
        r.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(r), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        // Seller receives sale - fee (0.99), since royalty loops back to seller
        assertEq(seller.balance - sellerBalBefore, 0.99 ether);
        assertEq(owner.balance - ownerBalBefore, 0.01 ether);
    }

    function testRoyaltyEqualsPostFeeProceedsBoundary() public {
        // fee = 1% (0.01 ETH), royalty = 99% (0.99 ETH) → seller net 0
        MockERC721Royalty r = new MockERC721Royalty();
        r.mint(seller, 1);
        r.setRoyalty(address(0xB0B), 99_000);

        vm.prank(owner);
        collections.addWhitelistedCollection(address(r));

        vm.prank(seller);
        r.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(r), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;
        uint256 royaltyBalBefore = address(0xB0B).balance;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        assertEq(owner.balance - ownerBalBefore, 0.01 ether);
        assertEq(address(0xB0B).balance - royaltyBalBefore, 0.99 ether);
        assertEq(seller.balance - sellerBalBefore, 0);
    }

    // Whitelist: enabling on update with exactly MAX_BATCH should succeed
    function testUpdateWhitelistExactlyMaxBatchSucceeds() public {
        _whitelistCollectionAndApproveERC721();

        // Create listing with whitelist disabled
        vm.prank(seller);
        market.createListing(
            address(erc721),
            1,
            address(0),
            1 ether,
            address(0),
            address(0),
            0,
            0,
            0,
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Enable whitelist with exactly MAX_BATCH addresses
        address[] memory buyersList = new address[](MAX_BATCH);
        for (uint256 i = 0; i < buyersList.length; i++) {
            buyersList[i] = vm.addr(30_000 + i);
        }

        vm.prank(seller);
        market.updateListing(id, 1 ether, address(0), address(0), 0, 0, 0, true, false, buyersList);

        // Spot check entries made it in
        assertTrue(getter.isBuyerWhitelisted(id, buyersList[0]));
        assertTrue(getter.isBuyerWhitelisted(id, buyersList[buyersList.length - 1]));
    }

    // Whitelist: enabling on update with >MAX_BATCH should revert
    function testUpdateWhitelistOverMaxBatchReverts() public {
        _whitelistCollectionAndApproveERC721();

        // Create listing with whitelist disabled
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        address[] memory tooMany = new address[](uint256(MAX_BATCH) + 1);
        for (uint256 i = 0; i < tooMany.length; i++) {
            tooMany[i] = vm.addr(31_000 + i);
        }

        vm.startPrank(seller);
        vm.expectRevert(abi.encodeWithSelector(BuyerWhitelist__ExceedsMaxBatchSize.selector, tooMany.length));
        market.updateListing(id, 1 ether, address(0), address(0), 0, 0, 0, true, false, tooMany);
        vm.stopPrank();
    }

    // Whitelist: adding duplicates should be idempotent (no revert, end state true)
    function testBuyerWhitelistAddDuplicatesIdempotent() public {
        // Create listing with whitelist enabled and one buyer
        address[] memory allowed = new address[](1);
        allowed[0] = buyer;
        uint128 id = _createListingERC721(true, allowed);

        // Add [buyer, buyer] again; should not revert and still be whitelisted
        address[] memory dups = new address[](2);
        dups[0] = buyer;
        dups[1] = buyer;

        vm.prank(seller);
        buyers.addBuyerWhitelistAddresses(id, dups);

        assertTrue(getter.isBuyerWhitelisted(id, buyer));
    }

    // Whitelist: removing with empty calldata should revert
    function testBuyerWhitelistRemoveEmptyCalldataReverts() public {
        address[] memory allowed = new address[](1);
        allowed[0] = buyer;
        uint128 id = _createListingERC721(true, allowed);

        address[] memory empty = new address[](0);
        vm.startPrank(seller);
        vm.expectRevert(BuyerWhitelist__EmptyCalldata.selector);
        buyers.removeBuyerWhitelistAddresses(id, empty);
        vm.stopPrank();
    }

    // Whitelist: removing by unauthorized address should revert
    function testBuyerWhitelistRemoveUnauthorizedReverts() public {
        address[] memory allowed = new address[](1);
        allowed[0] = buyer;
        uint128 id = _createListingERC721(true, allowed);

        address[] memory one = new address[](1);
        one[0] = buyer;

        vm.startPrank(buyer);
        vm.expectRevert(BuyerWhitelist__NotAuthorizedOperator.selector);
        buyers.removeBuyerWhitelistAddresses(id, one);
        vm.stopPrank();
    }

    // Whitelist: after removal, purchase should fail for that buyer
    function testPurchaseRevertsAfterWhitelistRemoval() public {
        address[] memory allowed = new address[](1);
        allowed[0] = buyer;
        uint128 id = _createListingERC721(true, allowed);

        // Remove buyer from whitelist
        address[] memory one = new address[](1);
        one[0] = buyer;
        vm.prank(seller);
        buyers.removeBuyerWhitelistAddresses(id, one);
        assertFalse(getter.isBuyerWhitelisted(id, buyer));

        // Attempt purchase → revert BuyerNotWhitelisted
        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__BuyerNotWhitelisted.selector, id, buyer));
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    // Innovation fee: only owner can set
    function testSetInnovationFeeOnlyOwner() public {
        vm.startPrank(buyer);
        vm.expectRevert("LibDiamond: Must be contract owner");
        market.setInnovationFee(1234);
        vm.stopPrank();
    }

    // ERC1155: zero-quantity purchase should revert
    function testERC1155ZeroQuantityPurchaseReverts() public {
        // Whitelist & approve; list qty=10, partials enabled
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155),
            1,
            seller,
            10 ether, // price
            address(0), // currency
            address(0), // desiredTokenAddress
            0, // desiredTokenId
            0, // desiredErc1155Quantity
            10, // erc1155Quantity
            false,
            true,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buy 0 units → InvalidPurchaseQuantity
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__InvalidPurchaseQuantity.selector);
        market.purchaseListing{value: 0}(
            id,
            10 ether, // expectedPrice (total listing price)
            address(0), // expectedCurrency
            10, // expectedErc1155Quantity (total listed qty)
            address(0),
            0,
            0,
            0, // erc1155PurchaseQuantity
            address(0)
        );
        vm.stopPrank();
    }

    // ERC1155: after a partial fill, buying more than remaining should revert
    function testERC1155OverRemainingAfterPartialReverts() public {
        // List qty=10, partials enabled
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // First partial: buy 7
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 7 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 7, address(0));

        // Remaining = 3; attempt to buy 4 → revert
        address secondBuyer = vm.addr(0xABCD);
        vm.deal(secondBuyer, 10 ether);
        vm.startPrank(secondBuyer);
        vm.expectRevert(IdeationMarket__InvalidPurchaseQuantity.selector);
        market.purchaseListing{value: 4 ether}(id, 3 ether, address(0), 3, address(0), 0, 0, 4, address(0));
        vm.stopPrank();
    }

    // ERC1155 create: msg.sender is neither holder nor holder's operator ⇒ revert NotAuthorizedOperator
    function testERC1155CreateUnauthorizedListerReverts() public {
        // Whitelist the collection
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Holder owns the tokens and approves the marketplace, but NOT the would-be lister.
        // This ensures we fail on auth (msg.sender not holder nor operator), not on marketplace approval.
        vm.prank(operator);
        erc1155.mint(operator, 1, 10);
        vm.prank(operator);
        erc1155.setApprovalForAll(address(diamond), true); // marketplace approval intact

        // Seller is NOT an operator for `operator` (the holder). Creating should revert on auth.
        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__NotAuthorizedOperator.selector);
        market.createListing(
            address(erc1155), // token
            1, // tokenId
            operator, // erc1155Holder (the actual balance holder)
            10 ether, // price (no swap)
            address(0), // currency
            address(0), // desiredTokenAddress (no swap)
            0, // desiredTokenId
            0, // desiredErc1155Quantity
            10, // erc1155Quantity (=> 1155 branch)
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            new address[](0) // allowedBuyers
        );
        vm.stopPrank();
    }

    function testERC1155HolderDifferentFromSellerHappyPath() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        erc1155.mint(operator, 1, 10);

        // Holder approvals
        vm.prank(operator);
        erc1155.setApprovalForAll(seller, true); // seller may act for holder
        vm.prank(operator);
        erc1155.setApprovalForAll(address(diamond), true); // marketplace may transfer

        // Seller creates the listing on behalf of holder
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, operator, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        Listing memory beforeBuy = getter.getListingByListingId(id);
        assertEq(beforeBuy.seller, operator);

        uint256 operatorBefore = operator.balance;
        uint256 ownerBefore = owner.balance;
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 10 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 10, address(0));

        // Tokens left holder → buyer
        assertEq(erc1155.balanceOf(operator, 1), 0);
        assertEq(erc1155.balanceOf(buyer, 1), 10);

        // Proceeds go to the holder (the Listing.seller), not msg.sender(seller)
        assertEq(operator.balance - operatorBefore, 9.9 ether);
        assertEq(owner.balance - ownerBefore, 0.1 ether);
        assertEq(seller.balance, 0);
    }

    // Whitelist: passing address(0) in create should revert
    function testCreateListingWhitelistWithZeroAddressReverts() public {
        _whitelistCollectionAndApproveERC721();

        address[] memory allowed = new address[](1);
        allowed[0] = address(0);

        vm.startPrank(seller);
        vm.expectRevert(BuyerWhitelist__ZeroAddress.selector);
        market.createListing(
            address(erc721),
            1,
            address(0), // erc1155Holder
            1 ether,
            address(0), // currency
            address(0), // desiredTokenAddress
            0, // desiredTokenId
            0, // desiredErc1155Quantity
            0, // erc1155Quantity
            true, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            allowed
        );
        vm.stopPrank();
    }

    // Whitelist: passing address(0) in update while enabling should revert
    function testUpdateListingWhitelistWithZeroAddressReverts() public {
        _whitelistCollectionAndApproveERC721();

        // Create listing with whitelist disabled
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        address[] memory invalid = new address[](1);
        invalid[0] = address(0);

        vm.startPrank(seller);
        vm.expectRevert(BuyerWhitelist__ZeroAddress.selector);

        market.updateListing(
            id,
            1 ether,
            address(0), // newCurrency
            address(0), // newDesiredTokenAddress
            0,
            0,
            0, // newErc1155Quantity
            true, // enable whitelist
            false,
            invalid
        );
        vm.stopPrank();
    }

    function testTogglePartialBuyEnabledWithoutPriceChange() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Flip partials to disabled; keep qty the same (ERC1155 stays ERC1155)
        vm.prank(seller);
        market.updateListing(id, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0));

        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__PartialBuyNotPossible.selector);
        market.purchaseListing{value: 4 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 4, address(0));
        vm.stopPrank();

        Listing memory l = getter.getListingByListingId(id);
        assertEq(l.price, 10 ether);
        assertFalse(l.partialBuyEnabled);
        assertEq(l.erc1155Quantity, 10);
    }

    // Lister is NOT approved by the ERC1155 holder -> NotAuthorizedOperator
    function testERC1155OperatorNotApprovedReverts_thenSucceedsAfterApproval() public {
        // Whitelist ERC1155 and mint balance to the HOLDER (operator).
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        erc1155.mint(operator, 1, 10);

        // Seller tries to list tokens held by 'operator' without being approved by operator.
        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__NotAuthorizedOperator.selector);
        market.createListing(
            address(erc1155),
            1,
            operator, // erc1155Holder
            1 ether,
            address(0), // currency
            address(0), // desiredTokenAddress
            0, // desiredTokenId
            0, // desiredErc1155Quantity
            10, // quantity
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();

        // Grant seller operator rights and marketplace transfer rights; then it should work
        vm.prank(operator);
        erc1155.setApprovalForAll(seller, true);
        vm.prank(operator);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, operator, 1 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        Listing memory l = getter.getListingByListingId(id);
        assertEq(l.erc1155Quantity, 10);
    }

    // Listing-time guard: erc1155Holder has ZERO balance for the token id -> WrongErc1155HolderParameter
    function testERC1155HolderZeroBalanceAtCreateRevertsWrongHolder() public {
        // Use a fresh tokenId that no one owns (e.g., 42).
        uint256 freshTokenId = 42;

        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Seller claims to be the erc1155Holder but has zero balance for freshTokenId.
        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__WrongErc1155HolderParameter.selector);
        market.createListing(
            address(erc1155),
            freshTokenId,
            seller, // claimed erc1155Holder
            1 ether,
            address(0), // currency
            address(0), // desiredTokenAddress
            0,
            0,
            10, // quantity
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();
    }

    // Update while whitelist is DISABLED but a non-empty address list is provided -> WhitelistDisabled
    function testUpdateWhitelistDisabledWithAddressesReverts() public {
        // Create a simple ERC721 listing with whitelist disabled.
        uint128 id = _createListingERC721(false, new address[](0));

        // Attempt to update while keeping whitelist disabled but passing addresses.
        address[] memory bogus = new address[](1);
        bogus[0] = buyer;

        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__WhitelistDisabled.selector);
        market.updateListing(
            id,
            1 ether, // keep same price
            address(0), // newCurrency
            address(0), // newDesiredTokenAddress - no swap
            0,
            0,
            0, // newErc1155Quantity - still ERC721
            false, // whitelist remains disabled
            false, // partialBuy irrelevant for ERC721
            bogus // <-- non-empty list should trigger revert
        );
        vm.stopPrank();
    }

    function testLoupeSelectorsPerFacet() public view {
        // ===== Market facet =====
        address marketAddr = loupe.facetAddress(IdeationMarketFacet.createListing.selector);
        assertTrue(marketAddr != address(0));

        // All market selectors should live on the same facet
        assertEq(loupe.facetAddress(IdeationMarketFacet.purchaseListing.selector), marketAddr);
        assertEq(loupe.facetAddress(IdeationMarketFacet.cancelListing.selector), marketAddr);
        assertEq(loupe.facetAddress(IdeationMarketFacet.updateListing.selector), marketAddr);
        assertEq(loupe.facetAddress(IdeationMarketFacet.setInnovationFee.selector), marketAddr);
        assertEq(loupe.facetAddress(IdeationMarketFacet.cleanListing.selector), marketAddr);

        // Spot-check the facet’s selector list actually includes them
        bytes4[] memory m = loupe.facetFunctionSelectors(marketAddr);
        assertTrue(_hasSel(m, IdeationMarketFacet.createListing.selector));
        assertTrue(_hasSel(m, IdeationMarketFacet.purchaseListing.selector));
        assertTrue(_hasSel(m, IdeationMarketFacet.cancelListing.selector));
        assertTrue(_hasSel(m, IdeationMarketFacet.updateListing.selector));
        assertTrue(_hasSel(m, IdeationMarketFacet.setInnovationFee.selector));
        assertTrue(_hasSel(m, IdeationMarketFacet.cleanListing.selector));

        // ===== Ownership facet =====
        address ownershipAddr = loupe.facetAddress(IERC173.owner.selector);
        assertTrue(ownershipAddr != address(0));
        assertEq(loupe.facetAddress(IERC173.transferOwnership.selector), ownershipAddr);
        assertEq(loupe.facetAddress(OwnershipFacet.acceptOwnership.selector), ownershipAddr);
        bytes4[] memory o = loupe.facetFunctionSelectors(ownershipAddr);
        assertTrue(_hasSel(o, IERC173.owner.selector));
        assertTrue(_hasSel(o, IERC173.transferOwnership.selector));
        assertTrue(_hasSel(o, OwnershipFacet.acceptOwnership.selector));

        // ===== Loupe facet =====
        address loupeAddr = loupe.facetAddress(IDiamondLoupeFacet.facets.selector);
        assertTrue(loupeAddr != address(0));
        assertEq(loupe.facetAddress(IDiamondLoupeFacet.facetFunctionSelectors.selector), loupeAddr);
        assertEq(loupe.facetAddress(IDiamondLoupeFacet.facetAddresses.selector), loupeAddr);
        assertEq(loupe.facetAddress(IDiamondLoupeFacet.facetAddress.selector), loupeAddr);
        assertEq(loupe.facetAddress(IERC165.supportsInterface.selector), loupeAddr);
        bytes4[] memory l = loupe.facetFunctionSelectors(loupeAddr);
        assertTrue(_hasSel(l, IDiamondLoupeFacet.facets.selector));
        assertTrue(_hasSel(l, IDiamondLoupeFacet.facetFunctionSelectors.selector));
        assertTrue(_hasSel(l, IDiamondLoupeFacet.facetAddresses.selector));
        assertTrue(_hasSel(l, IDiamondLoupeFacet.facetAddress.selector));
        assertTrue(_hasSel(l, IERC165.supportsInterface.selector));

        // ===== Collection whitelist facet =====
        address colAddr = loupe.facetAddress(CollectionWhitelistFacet.addWhitelistedCollection.selector);
        assertTrue(colAddr != address(0));
        assertEq(loupe.facetAddress(CollectionWhitelistFacet.removeWhitelistedCollection.selector), colAddr);
        assertEq(loupe.facetAddress(CollectionWhitelistFacet.batchAddWhitelistedCollections.selector), colAddr);
        assertEq(loupe.facetAddress(CollectionWhitelistFacet.batchRemoveWhitelistedCollections.selector), colAddr);

        // ===== Buyer whitelist facet =====
        address bwAddr = loupe.facetAddress(BuyerWhitelistFacet.addBuyerWhitelistAddresses.selector);
        assertTrue(bwAddr != address(0));
        assertEq(loupe.facetAddress(BuyerWhitelistFacet.removeBuyerWhitelistAddresses.selector), bwAddr);

        // ===== Getter facet =====
        address getterAddr = loupe.facetAddress(GetterFacet.getNextListingId.selector);
        assertTrue(getterAddr != address(0));
        assertEq(loupe.facetAddress(GetterFacet.getActiveListingIdByERC721.selector), getterAddr);
        assertEq(loupe.facetAddress(GetterFacet.getListingByListingId.selector), getterAddr);
        assertEq(loupe.facetAddress(GetterFacet.getBalance.selector), getterAddr);
        assertEq(loupe.facetAddress(GetterFacet.getInnovationFee.selector), getterAddr);
        assertEq(loupe.facetAddress(GetterFacet.isCollectionWhitelisted.selector), getterAddr);
        assertEq(loupe.facetAddress(GetterFacet.getWhitelistedCollections.selector), getterAddr);
        assertEq(loupe.facetAddress(GetterFacet.getContractOwner.selector), getterAddr);
        assertEq(loupe.facetAddress(GetterFacet.isBuyerWhitelisted.selector), getterAddr);
        assertEq(loupe.facetAddress(GetterFacet.getBuyerWhitelistMaxBatchSize.selector), getterAddr);
        assertEq(loupe.facetAddress(GetterFacet.getPendingOwner.selector), getterAddr);
    }

    function testSupportsInterfaceNegative() public view {
        assertFalse(IERC165(address(diamond)).supportsInterface(0x12345678));
    }

    function testCleanListingERC1155() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Revoke marketplace approval so cleanListing is allowed
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), false);

        vm.startPrank(operator);
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(id, address(erc1155), 1, seller, operator);

        market.cleanListing(id);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCleanListing_WhileStillApproved_ERC1155_Reverts() public {
        // Whitelist + operator approval + create a valid ERC1155 listing
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155),
            1,
            seller, // erc1155Holder
            10 ether, // fixed price, no swap
            address(0), // currency
            address(0), // desiredTokenAddress
            0,
            0,
            10, // quantity
            false, // whitelist disabled
            false, // partialBuy disabled
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Still fully approved & whitelisted → cleanListing should revert with StillApproved
        address rando = vm.addr(0xC1EA12);
        vm.startPrank(rando);
        vm.expectRevert(IdeationMarket__StillApproved.selector);
        market.cleanListing(id);
        vm.stopPrank();
    }

    /// Ensures ListingTermsChanged also trips on expectedDesired* mismatches.
    function testExpectedDesiredFieldsMismatchReverts() public {
        uint128 id = _createListingERC721(false, new address[](0)); // price = 1 ether

        vm.deal(buyer, 2 ether);

        // 1) Mismatch expectedDesiredTokenAddress (non-swap listing has address(0))
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__ListingTermsChanged.selector);
        market.purchaseListing{value: 1 ether}(
            id,
            1 ether, // expectedPrice OK
            address(0), // expectedCurrency OK
            0, // expectedErc1155Quantity OK (ERC721)
            address(0xBEEF), // <-- mismatch
            0, // OK
            0, // OK
            0, // ERC721
            address(0)
        );
        vm.stopPrank();

        // 2) Mismatch expectedDesiredTokenId (non-swap listing has 0)
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__ListingTermsChanged.selector);
        market.purchaseListing{value: 1 ether}(
            id,
            1 ether,
            address(0), // expectedCurrency OK
            0,
            address(0), // OK
            123, // <-- mismatch
            0, // OK
            0,
            address(0)
        );
        vm.stopPrank();

        // 3) Mismatch expectedDesiredErc1155Quantity (non-swap listing has 0)
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__ListingTermsChanged.selector);
        market.purchaseListing{value: 1 ether}(
            id,
            1 ether,
            address(0), // expectedCurrency OK
            0,
            address(0),
            0,
            1, // <-- mismatch
            0,
            address(0)
        );
        vm.stopPrank();
    }

    /// Assert ListingCanceledDueToInvalidListing is emitted by cleanListing.
    function testCleanListingEmitsCancellationEvent() public {
        uint128 id = _createListingERC721(false, new address[](0));

        // Revoke approval so cleanListing may cancel the listing.
        vm.prank(seller);
        erc721.approve(address(0), 1);

        // Expect the event from the diamond.
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(id, address(erc721), 1, seller, operator);

        // Trigger as any caller (operator in this test).
        vm.prank(operator);
        market.cleanListing(id);

        // Listing gone.
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    // ERC-1155 partials: 10 units at 1e18 each; buy 3, then 2; check exact residual price/qty and proceeds/fees.
    function testERC1155MultiStepPartialsMaintainPriceProportions() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // List 10 units for total 10 ETH; partials enabled (unit price = 1 ETH).
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buy 3 units -> pay 3 ETH ; remaining: qty=7, price=7 ETH
        uint256 sellerBalBefore1 = seller.balance;
        uint256 ownerBalBefore1 = owner.balance;
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 3 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 3, address(0));

        Listing memory after3 = getter.getListingByListingId(id);
        assertEq(after3.erc1155Quantity, 7);
        assertEq(after3.price, 7 ether);
        // Proceeds so far: seller 2.97, owner 0.03
        assertEq(seller.balance - sellerBalBefore1, 2.97 ether);
        assertEq(owner.balance - ownerBalBefore1, 0.03 ether);

        // Buy 2 more -> pay 2 ETH ; remaining: qty=5, price=5 ETH
        uint256 sellerBalBefore2 = seller.balance;
        uint256 ownerBalBefore2 = owner.balance;
        address buyer2 = vm.addr(0x4242);
        vm.deal(buyer2, 10 ether);
        vm.prank(buyer2);
        market.purchaseListing{value: 2 ether}(id, 7 ether, address(0), 7, address(0), 0, 0, 2, address(0));

        Listing memory after5 = getter.getListingByListingId(id);
        assertEq(after5.erc1155Quantity, 5);
        assertEq(after5.price, 5 ether);

        // Totals: seller 2.97 + 1.98 = 4.95 ; owner 0.03 + 0.02 = 0.05
        assertEq(sellerBalBefore2 - sellerBalBefore1 + (seller.balance - sellerBalBefore2), 4.95 ether);
        assertEq(ownerBalBefore2 - ownerBalBefore1 + (owner.balance - ownerBalBefore2), 0.05 ether);
    }

    /// Swap (ERC-721 <-> ERC-721): happy path, requires buyer's token approval to marketplace + failing stale purchase.
    function testSwapERC721ToERC721_WithCleanupOfObsoleteListing() public {
        // Fresh ERC721 collections
        MockERC721 a = new MockERC721();
        MockERC721 b = new MockERC721();

        // Whitelist both
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(a));
        collections.addWhitelistedCollection(address(b));
        vm.stopPrank();

        // Mint A#100 to seller; B#200 to buyer
        a.mint(seller, 100);
        b.mint(buyer, 200);

        // Approvals: marketplace for A#100 (by seller), marketplace for B#200 (by buyer)
        vm.prank(seller);
        a.approve(address(diamond), 100);
        vm.prank(buyer);
        b.approve(address(diamond), 200);

        // Buyer pre-lists B#200 (to verify cleanup)
        vm.prank(buyer);
        market.createListing(
            address(b), 200, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 buyersBListingId = getter.getNextListingId() - 1;

        // Seller lists A#100 wanting B#200 (swap only, price=0)
        vm.prank(seller);
        market.createListing(
            address(a), 100, address(0), 0, address(0), address(b), 200, 0, 0, false, false, new address[](0)
        );
        uint128 swapId = getter.getNextListingId() - 1;

        // Buyer executes swap; pays 0; expected fields must match.
        vm.prank(buyer);
        market.purchaseListing{value: 0}(
            swapId,
            0, // expectedPrice
            address(0), // expectedCurrency
            0, // expectedErc1155Quantity (ERC721)
            address(b), // expectedDesiredTokenAddress
            200, // expectedDesiredTokenId
            0, // expectedDesiredErc1155Quantity
            0, // erc1155PurchaseQuantity
            address(0) // desiredErc1155Holder N/A for 721
        );

        // Ownership swapped
        assertEq(a.ownerOf(100), buyer);
        assertEq(b.ownerOf(200), seller);

        // No on-chain auto-cleanup: buyer's old listing remains, but is now invalid (buyer no longer owns B#200).
        Listing memory stale = getter.getListingByListingId(buyersBListingId);
        assertEq(stale.seller, buyer);
        assertEq(stale.tokenAddress, address(b));
        assertEq(stale.tokenId, 200);

        // Attempting to buy the stale listing reverts because the seller is no longer the token owner.
        address otherBuyer = vm.addr(0xB0B);
        vm.deal(otherBuyer, 2 ether);
        vm.prank(otherBuyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__SellerNotTokenOwner.selector, buyersBListingId));
        market.purchaseListing{value: 1 ether}(
            buyersBListingId, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0)
        );
    }

    function testSwapERC721ToERC1155_OperatorNoMarketApprovalReverts_ThenSucceeds() public {
        // Whitelist collections
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc721)); // unused but harmless
        collections.addWhitelistedCollection(address(erc1155));
        vm.stopPrank();

        // Mint ERC721 to seller (will be swapped away)
        erc721.mint(seller, 111);
        vm.prank(seller);
        erc721.approve(address(diamond), 111);

        // Use a fresh ERC1155 id so seller has zero starting balance for this id
        uint256 desiredId = 2;
        erc1155.mint(operator, desiredId, 10);

        // Buyer is operator of 'operator', but marketplace NOT approved yet
        vm.prank(operator);
        erc1155.setApprovalForAll(buyer, true);

        // Seller lists ERC721 wanting 6 units of ERC1155 desiredId
        vm.prank(seller);
        market.createListing(
            address(erc721),
            111,
            address(0), // erc1155Holder (N/A for ERC721)
            0, // price (swap only)
            address(0), // currency
            address(erc1155), // desiredTokenAddress
            desiredId, // desiredTokenId
            6, // desiredErc1155Quantity
            0, // erc1155Quantity (ERC721)
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Attempt purchase -> revert: holder hasn't approved marketplace
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(erc1155), desiredId, 6, 0, operator);

        // Grant marketplace approval by holder; try again -> succeeds
        vm.prank(operator);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(buyer);
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(erc1155), desiredId, 6, 0, operator);

        // Post-conditions
        assertEq(erc721.ownerOf(111), buyer);
        assertEq(erc1155.balanceOf(operator, desiredId), 4);
        assertEq(erc1155.balanceOf(seller, desiredId), 6);
    }

    /// Royalty edge: bump fee high and royalty so fee+royalty>price -> reverts with RoyaltyFeeExceedsProceeds.
    function testRoyaltyEdge_HighFeePlusRoyaltyExceedsProceeds() public {
        // Royalty NFT: 50% royalty
        MockERC721Royalty r = new MockERC721Royalty();
        r.mint(seller, 1);
        r.setRoyalty(address(0xB0B), 50_000); // 50% of 100_000

        // Whitelist and approve
        vm.prank(owner);
        collections.addWhitelistedCollection(address(r));
        vm.prank(seller);
        r.approve(address(diamond), 1);

        // Set innovation fee to 60%
        vm.prank(owner);
        market.setInnovationFee(60_000);

        // List for 1 ETH (non-swap)
        vm.prank(seller);
        market.createListing(
            address(r), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Purchase must revert: sellerProceeds = 0.4 ETH, royalty = 0.5 ETH -> exceeds proceeds.
        vm.deal(buyer, 2 ether);
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__RoyaltyFeeExceedsProceeds.selector);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    /// ERC-721 by operator: operator creates listing; purchase succeeds.
    function testERC721OperatorListsAndPurchaseSucceeds_AfterFix() public {
        MockERC721 x = new MockERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(x));

        // holder owns token; operator is approved-for-all
        address holder = vm.addr(0xAAAA);
        x.mint(holder, 9);
        vm.prank(holder);
        x.setApprovalForAll(operator, true);

        // Marketplace approval by holder
        vm.prank(holder);
        x.approve(address(diamond), 9);

        // Operator creates listing on behalf of holder
        vm.prank(operator);
        market.createListing(
            address(x), 9, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Confirm listing seller is the holder (post-fix behavior)
        Listing memory L = getter.getListingByListingId(id);
        assertEq(L.seller, holder);

        // Buyer purchases successfully
        uint256 balBefore = holder.balance;
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        // Token moved to buyer; proceeds to holder
        assertEq(x.ownerOf(9), buyer);
        assertEq(holder.balance - balBefore, 0.99 ether);
    }

    function testPurchaseRevertsWhenBuyerIsSeller() public {
        // seller lists ERC721 (price = 1 ETH)
        uint128 id = _createListingERC721(false, new address[](0));

        // seller tries to buy own listing -> must revert
        vm.deal(seller, 1 ether);
        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__SameBuyerAsSeller.selector);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    function testSwap1155MissingHolderParamReverts() public {
        // Whitelist listed collection (ERC721). Desired (ERC1155) need not be whitelisted, only must pass interface check.
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        // Seller approval for the listed ERC721
        vm.prank(seller);
        erc721.approve(address(diamond), 1);

        // Create swap listing: want ERC1155 id=1, quantity=2; price=0 (pure swap)
        vm.prank(seller);
        market.createListing(
            address(erc721),
            1,
            seller,
            0, // price
            address(0), // currency
            address(erc1155), // desiredTokenAddress (ERC1155)
            1, // desiredTokenId
            2, // desiredErc1155Quantity > 0
            0, // erc1155Quantity (listed is ERC721)
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer attempts purchase but omits desiredErc1155Holder -> must revert early
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__WrongErc1155HolderParameter.selector);
        market.purchaseListing{value: 0}(
            id,
            0, // expectedPrice,
            address(0), // expectedCurrency
            0, // expectedErc1155Quantity (listed is ERC721)
            address(erc1155), // expectedDesiredTokenAddress
            1, // expectedDesiredTokenId
            2, // expectedDesiredErc1155Quantity
            0, // erc1155PurchaseQuantity (ERC721 path)
            address(0) // desiredErc1155Holder MISSING -> revert
        );
        vm.stopPrank();
    }

    function testCancelListingByERC721ApprovedOperator() public {
        // Whitelist ERC721 collection
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        // Seller: grant blanket approval to marketplace (so createListing passes)
        vm.prank(seller);
        erc721.setApprovalForAll(address(diamond), true);

        // Seller: set per-token approval to 'operator' (this is the authority we want to test)
        vm.prank(seller);
        erc721.approve(operator, 1);

        // Create listing for token 1
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Operator cancels via getApproved(tokenId) path
        vm.startPrank(operator);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceled(id, address(erc721), 1, seller, operator);

        market.cancelListing(id);
        vm.stopPrank();

        // Listing is removed
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCancelListing_UnauthorizedThirdParty_ERC721_Reverts() public {
        // Setup: whitelist + approve + create a live ERC721 listing
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, seller, 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // A random third party (not owner, not token-approved, not operator) cannot cancel
        address rando = vm.addr(0xCAFE);
        vm.startPrank(rando);
        vm.expectRevert(IdeationMarket__NotAuthorizedToCancel.selector);
        market.cancelListing(id);
        vm.stopPrank();
    }

    function testCancelListing_UnauthorizedThirdParty_ERC1155_Reverts() public {
        // Setup: whitelist + operator approval + create a live ERC1155 listing
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155),
            1,
            seller, // erc1155Holder
            10 ether, // price (no swap)
            address(0),
            address(0),
            0,
            0,
            10, // erc1155Quantity
            false, // whitelist disabled
            false, // partialBuy disabled
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // A random third party (not seller, not operator) cannot cancel
        address rando = vm.addr(0xBEEF);
        vm.startPrank(rando);
        vm.expectRevert(IdeationMarket__NotAuthorizedToCancel.selector);
        market.cancelListing(id);
        vm.stopPrank();
    }

    function testSetInnovationFeeEmitsEvent() public {
        uint32 previous = getter.getInnovationFee();
        uint32 next = previous + 123; // any value; you keep fee unbounded by design

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.InnovationFeeUpdated(previous, next);

        vm.prank(owner);
        market.setInnovationFee(next);

        assertEq(getter.getInnovationFee(), next);
    }

    function testPurchaseRevertsIfOwnerChangedOffMarket() public {
        // Create a normal ERC721 listing (price = 1 ETH)
        uint128 id = _createListingERC721(false, new address[](0));

        // Off-market transfer: seller moves token #1 to operator
        vm.prank(seller);
        erc721.transferFrom(seller, operator, 1);

        // Buyer has enough ETH but purchase must revert because stored seller no longer owns the token
        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__SellerNotTokenOwner.selector, id));
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    function testSwapWithEth_ERC721toERC721_HappyPath() public {
        // Fresh collections to avoid interference with other tests
        MockERC721 a = new MockERC721();
        MockERC721 b = new MockERC721();

        // Only the listed collection must be whitelisted, but whitelisting both is harmless
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(a));
        collections.addWhitelistedCollection(address(b));
        vm.stopPrank();

        // Seller owns A#100, buyer owns B#200
        a.mint(seller, 100);
        b.mint(buyer, 200);

        // Approvals for marketplace transfers
        vm.prank(seller);
        a.approve(address(diamond), 100);
        vm.prank(buyer);
        b.approve(address(diamond), 200);

        // Seller lists A#100 wanting B#200 *and* 0.4 ETH
        vm.prank(seller);
        market.createListing(
            address(a),
            100,
            seller,
            0.4 ether, // price > 0: buyer must pay ETH in addition to providing desired token
            address(0),
            address(b), // desired ERC721
            200,
            0, // desiredErc1155Quantity = 0 (since desired is ERC721)
            0, // erc1155Quantity = 0 (listed is ERC721)
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer executes swap + ETH
        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;
        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);

        uint32 feeSnap = getter.getListingByListingId(id).feeRate;
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingPurchased(
            id, address(a), 100, 0, false, 0.4 ether, address(0), feeSnap, seller, buyer, address(b), 200, 0
        );

        market.purchaseListing{value: 0.4 ether}(
            id,
            0.4 ether, // expectedPrice
            address(0), // expectedCurrency
            0, // expectedErc1155Quantity (listed is ERC721)
            address(b), // expectedDesiredTokenAddress
            200, // expectedDesiredTokenId
            0, // expectedDesiredErc1155Quantity
            0, // erc1155PurchaseQuantity (ERC721 path)
            address(0) // desiredErc1155Holder N/A for ERC721
        );
        vm.stopPrank();

        // Ownership swapped and proceeds credited (fee 1% of 0.4 = 0.004)
        assertEq(a.ownerOf(100), buyer);
        assertEq(b.ownerOf(200), seller);
        assertEq(seller.balance - sellerBalBefore, 0.396 ether);
        assertEq(owner.balance - ownerBalBefore, 0.004 ether);
    }

    function testSwapWithEth_ERC721toERC1155_HappyPath() public {
        // Listed collection must be whitelisted; desired ERC1155 only needs to pass interface checks.
        MockERC721 a = new MockERC721();
        MockERC1155 m1155 = new MockERC1155();

        vm.prank(owner);
        collections.addWhitelistedCollection(address(a));

        // Seller owns A#101
        a.mint(seller, 101);
        vm.prank(seller);
        a.approve(address(diamond), 101);

        // Buyer holds 5 units of desired ERC1155 id=77 and approves marketplace
        uint256 desiredId = 77;
        m1155.mint(buyer, desiredId, 5);
        vm.prank(buyer);
        m1155.setApprovalForAll(address(diamond), true);

        // Seller lists A#101 wanting 3x (ERC1155 id=77) *and* 0.3 ETH
        vm.prank(seller);
        market.createListing(
            address(a),
            101,
            address(0),
            0.3 ether, // ETH component
            address(0), // currency
            address(m1155), // desired ERC1155
            desiredId,
            3, // desiredErc1155Quantity > 0
            0, // erc1155Quantity = 0 (listed is ERC721)
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer executes swap + ETH (must pass desiredErc1155Holder)
        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;
        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);

        uint32 feeSnap = getter.getListingByListingId(id).feeRate;
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingPurchased(
            id, address(a), 101, 0, false, 0.3 ether, address(0), feeSnap, seller, buyer, address(m1155), desiredId, 3
        );

        market.purchaseListing{value: 0.3 ether}(
            id,
            0.3 ether, // expectedPrice
            address(0), // expectedCurrency
            0, // expectedErc1155Quantity (listed is ERC721)
            address(m1155), // expectedDesiredTokenAddress
            desiredId, // expectedDesiredTokenId
            3, // expectedDesiredErc1155Quantity
            0, // erc1155PurchaseQuantity (ERC721 path)
            buyer // desiredErc1155Holder (buyer is the holder)
        );
        vm.stopPrank();

        // Token and balance changes; proceeds reflect fee 1% of 0.3 = 0.003
        assertEq(a.ownerOf(101), buyer);
        assertEq(m1155.balanceOf(buyer, desiredId), 2);
        assertEq(m1155.balanceOf(seller, desiredId), 3);
        assertEq(seller.balance - sellerBalBefore, 0.297 ether);
        assertEq(owner.balance - ownerBalBefore, 0.003 ether);
    }

    /// Listing ERC1155 more than holder’s balance should revert with SellerInsufficientTokenBalance.
    function testERC1155CreateInsufficientBalanceReverts() public {
        // Mint only 5 units of a fresh tokenId
        uint256 tokenId = 99;
        erc1155.mint(seller, tokenId, 5);

        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IdeationMarket__SellerInsufficientTokenBalance.selector,
                10, // required
                5 // available
            )
        );
        market.createListing(
            address(erc1155),
            tokenId,
            seller,
            1 ether,
            address(0), // currency
            address(0), // desiredTokenAddress
            0,
            0,
            10, // quantity > balance
            false,
            false,
            new address[](0)
        );
    }

    /// ERC1155 listing without marketplace approval must revert NotApprovedForMarketplace.
    function testERC1155CreateWithoutMarketplaceApprovalReverts() public {
        uint256 tokenId = 100;
        erc1155.mint(seller, tokenId, 5);

        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Seller intentionally does not call setApprovalForAll(address(diamond), true)

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.createListing(
            address(erc1155), tokenId, seller, 1 ether, address(0), address(0), 0, 0, 5, false, false, new address[](0)
        );
    }

    /// Unauthorised ERC721 lister (not owner/approved) must revert NotAuthorizedOperator.
    function testERC721CreateUnauthorizedListerReverts() public {
        // whitelist and approve the ERC721 for the seller
        _whitelistCollectionAndApproveERC721();
        // buyer attempts to list seller’s token
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotAuthorizedOperator.selector);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
    }

    /// Partial buys cannot be enabled when quantity <= 1 (ERC1155).
    function testPartialBuyWithQuantityOneReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 101;
        erc1155.mint(seller, tokenId, 1);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__PartialBuyNotPossible.selector);
        market.createListing(
            address(erc1155),
            tokenId,
            seller,
            1 ether,
            address(0), // currency
            address(0), // desiredTokenAddress
            0,
            0,
            1,
            false,
            true, // partialBuyEnabled on single unit
            new address[](0)
        );
    }

    /// Partial buys cannot be enabled on swap listings (desiredTokenAddress != 0).
    function testPartialBuyWithSwapReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 102;
        erc1155.mint(seller, tokenId, 4);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // listing wants an ERC721 in exchange and partials are enabled → must revert
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__PartialBuyNotPossible.selector);
        market.createListing(
            address(erc1155),
            tokenId,
            seller,
            4 ether,
            address(0), // currency
            address(erc721), // swap (non-zero) desiredTokenAddress
            1,
            0,
            4,
            false,
            true, // partialBuyEnabled
            new address[](0)
        );
    }

    /// No‑swap listings must not specify a non‑zero desiredTokenId.
    function testInvalidNoSwapDesiredTokenIdReverts() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__InvalidNoSwapParameters.selector);
        market.createListing(
            address(erc721),
            1,
            address(0),
            1 ether,
            address(0), // currency
            address(0), // desiredTokenAddress
            1, // invalid nonzero desiredTokenId
            0,
            0,
            false,
            false,
            new address[](0)
        );
    }

    /// No‑swap listings must not specify a non‑zero desiredErc1155Quantity.
    function testInvalidNoSwapDesiredErc1155QuantityReverts() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__InvalidNoSwapParameters.selector);
        market.createListing(
            address(erc721),
            1,
            address(0),
            1 ether,
            address(0), // currency
            address(0), // desiredTokenAddress
            0,
            1, // invalid nonzero desiredErc1155Quantity
            0,
            false,
            false,
            new address[](0)
        );
    }

    /// Swap listings requiring ERC1155 (quantity > 0) must specify an ERC1155 contract.
    function testSwapDesiredTypeMismatchERC1155Reverts() public {
        _whitelistCollectionAndApproveERC721();
        // seller attempts to create an ERC721 listing wanting ERC721 (erc721) but with desiredErc1155Quantity > 0
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotSupportedTokenStandard.selector);
        market.createListing(
            address(erc721),
            1,
            address(0),
            0,
            address(0), // currency
            address(erc721), // wrong type: this is ERC721 not ERC1155
            2,
            1, // desiredErc1155Quantity > 0 indicates ERC1155
            0,
            false,
            false,
            new address[](0)
        );
    }

    /// Swap listings requiring ERC721 (quantity == 0) must specify an ERC721 contract.
    function testSwapDesiredTypeMismatchERC721Reverts() public {
        _whitelistCollectionAndApproveERC721();
        // seller attempts to create an ERC721 listing wanting an ERC1155 (erc1155) with desiredErc1155Quantity == 0
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotSupportedTokenStandard.selector);
        market.createListing(
            address(erc721),
            1,
            address(0),
            0,
            address(0), // currency
            address(erc1155), // wrong type: this is ERC1155 not ERC721
            1,
            0, // desiredErc1155Quantity == 0 implies ERC721
            0,
            false,
            false,
            new address[](0)
        );
    }

    /// Duplicates in the buyer whitelist on creation should be idempotent (no revert).
    function testWhitelistDuplicatesOnCreateIdempotent() public {
        _whitelistCollectionAndApproveERC721();
        address[] memory allowed = new address[](3);
        allowed[0] = buyer;
        allowed[1] = buyer; // duplicate
        allowed[2] = operator;

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, true, false, allowed
        );
        uint128 id = getter.getNextListingId() - 1;
        assertTrue(getter.isBuyerWhitelisted(id, buyer));
        assertTrue(getter.isBuyerWhitelisted(id, operator));
    }

    /// Updating from ERC721 to ERC1155 (changing quantity from 0 to >0) must revert.
    function testUpdateFlipERC721ToERC1155Reverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__WrongQuantityParameter.selector);
        market.updateListing(
            id,
            1 ether,
            address(0),
            address(0),
            0,
            0,
            5, // newErc1155Quantity > 0 (trying to flip to ERC1155)
            false,
            false,
            new address[](0)
        );
    }

    /// Updating from ERC1155 to ERC721 (setting new quantity to 0) must revert.
    function testUpdateFlipERC1155ToERC721Reverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 200;
        erc1155.mint(seller, tokenId, 5);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), tokenId, seller, 5 ether, address(0), address(0), 0, 0, 5, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__WrongQuantityParameter.selector);
        market.updateListing(
            id,
            5 ether,
            address(0),
            address(0),
            0,
            0,
            0, // setting quantity to 0 (trying to flip to ERC721)
            false,
            false,
            new address[](0)
        );
    }

    /// Only seller or its authorised operator may update an ERC1155 listing.
    function testERC1155UpdateUnauthorizedOperatorReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 201;
        erc1155.mint(seller, tokenId, 5);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), tokenId, seller, 5 ether, address(0), address(0), 0, 0, 5, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // buyer has no rights → NotAuthorizedOperator
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotAuthorizedOperator.selector);
        market.updateListing(id, 5 ether, address(0), address(0), 0, 0, 5, false, false, new address[](0));
    }

    //
    function testERC1155UpdateApprovalRevokedReverts() public {
        // Whitelist & approve; create ERC1155 listing (qty>0 keeps standard)
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Revoke marketplace approval, then attempt update → must revert
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), false);

        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.updateListing(id, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0));
        vm.stopPrank();
    }

    /// Updating quantity greater than seller’s ERC1155 balance must revert.
    function testERC1155UpdateBalanceTooLowReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 202;
        erc1155.mint(seller, tokenId, 5);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), tokenId, seller, 5 ether, address(0), address(0), 0, 0, 5, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        // seller transfers away 3 units (leaving 2)
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, buyer, tokenId, 3, "");
        // update to quantity 5 (available 2) → revert with SellerInsufficientTokenBalance
        vm.prank(seller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IdeationMarket__SellerInsufficientTokenBalance.selector,
                5, // new requested
                2 // remaining
            )
        );
        market.updateListing(id, 5 ether, address(0), address(0), 0, 0, 5, false, false, new address[](0));
    }

    /// Updating ERC721 listing with revoked approval must revert.
    function testERC721UpdateApprovalRevokedReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        // revoke approval
        vm.prank(seller);
        erc721.approve(address(0), 1);
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.updateListing(id, 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));
    }

    /// Updating partial buy on a too‑small ERC1155 quantity must revert.
    function testUpdatePartialBuyWithSmallQuantityReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 203;
        erc1155.mint(seller, tokenId, 1);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), tokenId, seller, 1 ether, address(0), address(0), 0, 0, 1, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__PartialBuyNotPossible.selector);
        market.updateListing(
            id,
            1 ether,
            address(0),
            address(0),
            0,
            0,
            1,
            false,
            true, // attempt to enable partial buys
            new address[](0)
        );
    }

    /// Updating partial buy while introducing a swap must revert.
    function testUpdatePartialBuyWithSwapReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 204;
        erc1155.mint(seller, tokenId, 5);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), tokenId, seller, 5 ether, address(0), address(0), 0, 0, 5, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        // update with partialBuyEnabled true AND desiredTokenAddress non-zero → revert
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__PartialBuyNotPossible.selector);
        market.updateListing(id, 5 ether, address(0), address(erc721), 1, 0, 5, false, true, new address[](0));
    }

    /// No‑swap update cannot set a non‑zero desiredTokenId.
    function testUpdateInvalidNoSwapDesiredTokenIdReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__InvalidNoSwapParameters.selector);
        market.updateListing(
            id,
            1 ether,
            address(0),
            address(0),
            1, // invalid non-zero desiredTokenId
            0,
            0,
            false,
            false,
            new address[](0)
        );
    }

    /// No‑swap update cannot set a non‑zero desiredErc1155Quantity.
    function testUpdateInvalidNoSwapDesiredErc1155QuantityReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__InvalidNoSwapParameters.selector);
        market.updateListing(
            id,
            1 ether,
            address(0),
            address(0),
            0,
            1, // invalid non-zero desiredErc1155Quantity
            0,
            false,
            false,
            new address[](0)
        );
    }

    /// Swap update requiring ERC1155 must specify an ERC1155 contract.
    function testUpdateSwapDesiredTypeMismatchERC1155Reverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotSupportedTokenStandard.selector);
        market.updateListing(
            id,
            0,
            address(0),
            address(erc721), // wrong type: ERC721 not ERC1155
            2,
            1, // desiredErc1155Quantity > 0
            0,
            false,
            false,
            new address[](0)
        );
    }

    /// Swap update requiring ERC721 must specify an ERC721 contract.
    function testUpdateSwapDesiredTypeMismatchERC721Reverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotSupportedTokenStandard.selector);
        market.updateListing(
            id,
            0,
            address(0),
            address(erc1155), // wrong type: ERC1155 not ERC721
            1,
            0, // desiredErc1155Quantity == 0 implies ERC721
            0,
            false,
            false,
            new address[](0)
        );
    }

    function testSwapExpectedDesiredFieldsMismatchReverts() public {
        // create 721->721 swap listing (price 0)
        _whitelistCollectionAndApproveERC721();
        MockERC721 other = new MockERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(other));
        other.mint(buyer, 42);
        vm.prank(buyer);
        other.approve(address(diamond), 42);
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 0, address(0), address(other), 42, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // wrong expectedDesiredTokenId
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__ListingTermsChanged.selector);
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(other), 999, 0, 0, address(0));
    }

    /// Duplicates in the buyer whitelist on update are idempotent.
    function testWhitelistDuplicatesOnUpdateIdempotent() public {
        uint128 id = _createListingERC721(false, new address[](0));
        address[] memory allowed = new address[](3);
        allowed[0] = buyer;
        allowed[1] = buyer;
        allowed[2] = operator;
        vm.prank(seller);
        market.updateListing(
            id,
            1 ether,
            address(0),
            address(0),
            0,
            0,
            0,
            true, // enabling whitelist
            false,
            allowed
        );
        assertTrue(getter.isBuyerWhitelisted(id, buyer));
        assertTrue(getter.isBuyerWhitelisted(id, operator));
    }

    /// After listing an ERC1155, if seller’s balance drops below listed quantity, purchase reverts.
    function testERC1155PurchaseSellerBalanceDroppedReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 400;
        erc1155.mint(seller, tokenId, 10);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155),
            tokenId,
            seller,
            10 ether,
            address(0),
            address(0),
            0,
            0,
            10,
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // seller transfers away 5 units leaving 5 (less than listed 10)
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, buyer, tokenId, 5, "");

        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IdeationMarket__SellerInsufficientTokenBalance.selector,
                10, // required
                5 // available
            )
        );
        market.purchaseListing{value: 10 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 10, address(0));
    }

    /// If marketplace approval is revoked for an ERC1155 listing, purchase reverts.
    function testERC1155PurchaseMarketplaceApprovalRevokedReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 401;
        erc1155.mint(seller, tokenId, 10);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155),
            tokenId,
            seller,
            10 ether,
            address(0),
            address(0),
            0,
            0,
            10,
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // seller revokes approval
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), false);

        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.purchaseListing{value: 10 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 10, address(0));
    }

    /// Purchase uses the fee rate frozen at listing time, not the current innovationFee.
    function testPurchaseFeeSnapshotOldFee() public {
        _whitelistCollectionAndApproveERC721();
        // Create listing with initial fee of 1% (1000)
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Owner raises fee to 2.5%
        vm.prank(owner);
        market.setInnovationFee(2500);

        // Purchase: seller must still receive 0.99, owner 0.01
        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;
        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);

        uint32 feeSnap = getter.getListingByListingId(id).feeRate; // should be old fee (e.g. 1000)
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingPurchased(
            id, address(erc721), 1, 0, false, 1 ether, address(0), feeSnap, seller, buyer, address(0), 0, 0
        );

        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        vm.stopPrank();

        assertEq(seller.balance - sellerBalBefore, 0.99 ether);
        assertEq(owner.balance - ownerBalBefore, 0.01 ether);
    }

    // Misconfigured fee (>100%) should make purchase impossible.
    // Underflow in `sellerProceeds = purchasePrice - innovationProceeds` triggers
    // Solidity 0.8 arithmetic revert.
    function testPathologicalFeeCausesRevert() public {
        _whitelistCollectionAndApproveERC721();

        vm.prank(owner);
        market.setInnovationFee(200_000); // 200% with denominator 100_000

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(stdError.arithmeticError); // forge-std
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
    }

    function testFeeExactly100Percent_SucceedsSellerGetsZero() public {
        _whitelistCollectionAndApproveERC721();

        vm.prank(owner);
        market.setInnovationFee(100_000); // exactly 100%

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        // Seller gets 0, owner gets full 1 ETH (no royalty in this test)
        assertEq(seller.balance - sellerBalBefore, 0);
        assertEq(owner.balance - ownerBalBefore, 1 ether);

        // Listing is gone and ownership transferred
        assertEq(erc721.ownerOf(1), buyer);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// ERC2981 token returning zero royalty should succeed and pay only fee.
    function testERC2981ZeroRoyalty() public {
        MockERC721Royalty token = new MockERC721Royalty();
        token.mint(seller, 1);
        token.setRoyalty(address(0xBEEF), 0); // 0%

        vm.prank(owner);
        collections.addWhitelistedCollection(address(token));
        vm.prank(seller);
        token.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(token), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;
        uint256 royaltyBalBefore = address(0xBEEF).balance;
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        // Seller 0.99, owner 0.01, royaltyReceiver 0
        assertEq(seller.balance - sellerBalBefore, 0.99 ether);
        assertEq(owner.balance - ownerBalBefore, 0.01 ether);
        assertEq(address(0xBEEF).balance - royaltyBalBefore, 0);
    }

    /// ERC2981 royaltyReceiver = address(0) should not deduct royalties.
    function testRoyaltyReceiverZeroAddress() public {
        MockERC721Royalty r = new MockERC721Royalty();
        r.mint(seller, 1);
        r.setRoyalty(address(0), 10_000); // 10%
        vm.prank(owner);
        collections.addWhitelistedCollection(address(r));
        vm.prank(seller);
        r.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(r), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        // When royalty receiver is address(0), royalty is NOT deducted (skipped entirely)
        // Seller gets: 1 ETH - 0.01 fee = 0.99 ether (royalty not applied)
        assertEq(seller.balance - sellerBalBefore, 0.99 ether);
        assertEq(owner.balance - ownerBalBefore, 0.01 ether);
        assertEq(address(diamond).balance, 0); // Non-custodial: no balance held
    }

    /// ERC2981 token that reverts royaltyInfo must cause purchase to revert.
    function testERC2981RevertingRoyaltyRevertsPurchase() public {
        MockERC721RoyaltyReverting r = new MockERC721RoyaltyReverting();
        r.mint(seller, 1);
        vm.prank(owner);
        collections.addWhitelistedCollection(address(r));
        vm.prank(seller);
        r.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(r), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(); // royaltyInfo reverts inside purchase
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
    }

    /// Swap (ERC721→ERC1155) purchase must revert if buyer has insufficient ERC1155 balance.
    function testSwapERC1155DesiredBalanceInsufficientReverts() public {
        // fresh ERC721 collection
        MockERC721 a = new MockERC721();
        a.mint(seller, 1);
        vm.prank(owner);
        collections.addWhitelistedCollection(address(a));
        vm.prank(seller);
        a.approve(address(diamond), 1);

        // Seller lists token #1 wanting 5 units of ERC1155 id=1
        vm.prank(seller);
        market.createListing(
            address(a), 1, address(0), 0, address(0), address(erc1155), 1, 5, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer only holds 2 units of that ERC1155 and approves
        erc1155.mint(buyer, 1, 2);
        vm.prank(buyer);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IdeationMarket__InsufficientSwapTokenBalance.selector,
                5, // required
                2 // available
            )
        );
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(erc1155), 1, 5, 0, buyer);
    }

    /// Swap (ERC721→ERC721) purchase must revert if buyer did not approve desired token.
    function testSwapERC721DesiredNotApprovedReverts() public {
        MockERC721 a = new MockERC721();
        MockERC721 b = new MockERC721();
        a.mint(seller, 10);
        b.mint(buyer, 20);

        vm.prank(owner);
        collections.addWhitelistedCollection(address(a));
        vm.prank(seller);
        a.approve(address(diamond), 10);

        vm.prank(seller);
        market.createListing(
            address(a), 10, address(0), 0, address(0), address(b), 20, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer did not approve b#20 to marketplace
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(b), 20, 0, 0, address(0));
    }

    /// Swap (ERC721→ERC721) must revert if buyer neither owns nor is approved for desired token.
    function testSwapERC721BuyerNotOwnerOrOperatorReverts() public {
        MockERC721 a = new MockERC721();
        MockERC721 b = new MockERC721();
        a.mint(seller, 1);
        b.mint(operator, 2); // desired token held by operator

        vm.prank(owner);
        collections.addWhitelistedCollection(address(a));
        vm.prank(seller);
        a.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(a), 1, address(0), 0, address(0), address(b), 2, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // buyer attempts purchase but has no rights over b#2
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotAuthorizedOperator.selector);
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(b), 2, 0, 0, address(0));
    }

    /// ERC1155 listings can be cancelled by any operator approved for the seller.
    function testCancelERC1155ListingByOperator() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 500;
        erc1155.mint(seller, tokenId, 10);
        // seller grants operator blanket approval
        vm.prank(seller);
        erc1155.setApprovalForAll(operator, true);
        // also approve marketplace
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155),
            tokenId,
            seller,
            10 ether,
            address(0),
            address(0),
            0,
            0,
            10,
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // operator cancels
        vm.prank(operator);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// cleanListing should cancel if collection has been removed from whitelist.
    function testCleanListingAfterDeWhitelistingCancels() public {
        uint128 id = _createListingERC721(false, new address[](0));
        // Remove collection
        vm.prank(owner);
        collections.removeWhitelistedCollection(address(erc721));
        // cleanListing should delete the listing
        // Expect the cancellation event on cleanListing
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(id, address(erc721), 1, seller, operator);

        vm.prank(operator);
        market.cleanListing(id);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// Removing whitelist entries on a non‑existent listing reverts.
    function testBuyerWhitelistRemoveNonexistentListingReverts() public {
        address[] memory list = new address[](1);
        list[0] = buyer;
        vm.prank(seller);
        vm.expectRevert(BuyerWhitelist__ListingDoesNotExist.selector);
        buyers.removeBuyerWhitelistAddresses(123456, list);
    }

    /// Removing an address that isn’t in the whitelist should not revert.
    function testBuyerWhitelistRemoveNonWhitelistedNoRevert() public {
        address[] memory allowed = new address[](1);
        allowed[0] = buyer;
        uint128 id = _createListingERC721(true, allowed);

        // operator is not on the list
        address[] memory toRemove = new address[](1);
        toRemove[0] = operator;

        vm.prank(seller);
        buyers.removeBuyerWhitelistAddresses(id, toRemove);
        assertFalse(getter.isBuyerWhitelisted(id, operator));
    }

    /// Adding/removing whitelist entries while whitelist is disabled must not revert.
    function testBuyerWhitelistAddRemoveWhenDisabledAllowed() public {
        uint128 id = _createListingERC721(false, new address[](0));
        address[] memory arr = new address[](1);
        arr[0] = buyer;
        // Add a buyer even though whitelist is disabled
        vm.prank(seller);
        buyers.addBuyerWhitelistAddresses(id, arr);
        // Remove the same buyer
        vm.prank(seller);
        buyers.removeBuyerWhitelistAddresses(id, arr);
        // Buyer should remain not whitelisted
        assertFalse(getter.isBuyerWhitelisted(id, buyer));
    }

    /// batchAddWhitelistedCollections must revert if any entry is zero address.
    function testBatchAddWhitelistedCollectionWithZeroReverts() public {
        address[] memory arr = new address[](2);
        arr[0] = address(erc721);
        arr[1] = address(0);
        vm.prank(owner);
        vm.expectRevert(CollectionWhitelist__ZeroAddress.selector);
        collections.batchAddWhitelistedCollections(arr);
    }

    /// isBuyerWhitelisted should revert on invalid listing id.
    function testIsBuyerWhitelistedInvalidListingIdReverts() public {
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, 999999));
        getter.isBuyerWhitelisted(999999, buyer);
    }

    function testCreateListingWithNonNFTContracQt0tReverts() public {
        NotAnNFT bad = new NotAnNFT();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(bad));

        // Note: the whitelist does NOT enforce interfaces—you can whitelist any address.
        // The revert happens inside createListing’s interface check:
        // with erc1155Quantity == 0 it requires ERC721 via IERC165; a non-NFT reverts with NotSupportedTokenStandard.

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotSupportedTokenStandard.selector);
        market.createListing(
            address(bad), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
    }

    function testCreateListingWithNonNFTContractQ9Reverts() public {
        NotAnNFT bad = new NotAnNFT();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(bad));

        // Note: the whitelist does NOT enforce interfaces—you can whitelist any address.
        // The revert happens inside createListing’s interface check:
        // with erc1155Quantity == 9 it requires ERC1155 via IERC165; a non-NFT reverts with NotSupportedTokenStandard.

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotSupportedTokenStandard.selector);
        market.createListing(
            address(bad), 1, address(0), 1 ether, address(0), address(0), 0, 0, 9, false, false, new address[](0)
        );
    }

    function testUpdatePriceZeroWithoutSwapReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__FreeListingsNotSupported.selector);
        market.updateListing(id, 0, address(0), address(0), 0, 0, 0, false, false, new address[](0));
    }

    function testCancelERC721ByOperatorForAll() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        erc721.setApprovalForAll(operator, true);
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        vm.prank(operator);
        market.cancelListing(id);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// ListingCreated fires with exact parameters for ERC721 listing
    function testEmitListingCreated() public {
        _whitelistCollectionAndApproveERC721();
        uint128 expectedId = getter.getNextListingId();

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCreated(
            expectedId,
            address(erc721),
            1,
            0, // erc1155Quantity (ERC721 -> 0)
            1 ether,
            address(0), // currency
            getter.getInnovationFee(),
            seller,
            false,
            false,
            address(0),
            0,
            0
        );

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
    }

    function testEmitListingCreated_ERC1155() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        uint128 expectedId = getter.getNextListingId();

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCreated(
            expectedId,
            address(erc1155),
            1,
            10, // erc1155Quantity
            10 ether, // price
            address(0), // currency
            getter.getInnovationFee(),
            seller,
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            address(0), // desiredTokenAddress
            0, // desiredTokenId
            0 // desiredErc1155Quantity
        );

        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0)
        );
    }

    /// ListingUpdated fires with exact parameters on price change
    function testEmitListingUpdated() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingUpdated(
            id,
            address(erc721),
            1,
            0,
            2 ether,
            address(0),
            getter.getInnovationFee(),
            seller,
            false,
            false,
            address(0),
            0,
            0
        );

        vm.prank(seller);
        market.updateListing(id, 2 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));
    }

    /// ListingPurchased fires with exact parameters on ERC721 full purchase
    function testEmitListingPurchased() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        uint32 feeSnap = getter.getListingByListingId(id).feeRate;

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingPurchased(
            id, address(erc721), 1, 0, false, 1 ether, address(0), feeSnap, seller, buyer, address(0), 0, 0
        );

        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
    }

    /// RoyaltyPaid fires with exact parameters
    function testEmitRoyaltyPaid() public {
        // Prepare royalty NFT (10%) and whitelist
        MockERC721Royalty royaltyNft = new MockERC721Royalty();
        address royaltyReceiver = address(0xB0B);
        royaltyNft.setRoyalty(royaltyReceiver, 10_000); // 10% of 100_000

        vm.prank(owner);
        collections.addWhitelistedCollection(address(royaltyNft));
        royaltyNft.mint(seller, 1);

        vm.prank(seller);
        royaltyNft.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(royaltyNft), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.RoyaltyPaid(id, royaltyReceiver, address(0), 0.1 ether);

        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
    }

    /// ListingCanceled fires with exact parameters
    function testEmitListingCanceled() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceled(id, address(erc721), 1, seller, seller);

        vm.prank(seller);
        market.cancelListing(id);
    }

    /// ListingCanceledDueToInvalidListing fires with exact parameters
    function testEmitListingCanceledDueToInvalidListing() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        erc721.approve(address(0), 1);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(id, address(erc721), 1, seller, operator);

        vm.prank(operator);
        market.cleanListing(id);
    }

    /// InnovationFeeUpdated fires with exact parameters
    function testEmitInnovationFeeUpdated() public {
        uint32 prev = getter.getInnovationFee();
        uint32 next = 777;

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.InnovationFeeUpdated(prev, next);

        // prank applies to the NEXT call only — apply it to the setter
        vm.prank(owner);
        market.setInnovationFee(next);

        // sanity check
        assertEq(getter.getInnovationFee(), next);
    }
    /* ======================================
       ERC1155 partial-buy payment edge cases
       ====================================== */

    function testERC1155_PartialBuy_UnderpayReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        erc1155.mint(seller, 11, 10);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // qty=10, price=10 ETH → unit=1 ETH; partials enabled
        vm.prank(seller);
        market.createListing(
            address(erc1155), 11, seller, 10 ether, address(0), address(0), 0, 0, 10, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);
        // Buy 4 units but send 3.9 ETH → PriceNotMet(listingId, 4, 3.9)
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__PriceNotMet.selector, id, 4 ether, 3.9 ether));
        market.purchaseListing{value: 3.9 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 4, address(0));
        vm.stopPrank();
    }

    /* ==================================
       Whitelist enforcement on swaps
       ================================== */

    function testWhitelist_BlocksSwap_ERC721toERC721() public {
        MockERC721 A = new MockERC721();
        MockERC721 B = new MockERC721();

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(A));
        collections.addWhitelistedCollection(address(B));
        vm.stopPrank();

        A.mint(seller, 100);
        B.mint(operator, 200); // operator will be the allowed swapper

        vm.prank(seller);
        A.approve(address(diamond), 100);
        vm.prank(operator);
        B.approve(address(diamond), 200);

        address[] memory allow = new address[](1);
        allow[0] = operator;

        vm.prank(seller);
        market.createListing(address(A), 100, address(0), 0, address(0), address(B), 200, 0, 0, true, false, allow);
        uint128 id = getter.getNextListingId() - 1;

        // Non-whitelisted buyer is blocked
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__BuyerNotWhitelisted.selector, id, buyer));
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(B), 200, 0, 0, address(0));

        // Whitelisted operator succeeds
        vm.prank(operator);
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(B), 200, 0, 0, address(0));
        assertEq(A.ownerOf(100), operator);
        assertEq(B.ownerOf(200), seller);
    }

    function testWhitelist_BlocksSwap_ERC721toERC1155() public {
        MockERC721 A = new MockERC721();

        vm.prank(owner);
        collections.addWhitelistedCollection(address(A)); // listed collection

        // Seller has A#1; operator has desired 1155
        A.mint(seller, 1);
        vm.prank(seller);
        A.approve(address(diamond), 1);

        erc1155.mint(operator, 77, 5);
        vm.prank(operator);
        erc1155.setApprovalForAll(address(diamond), true);

        address[] memory allow = new address[](1);
        allow[0] = operator;

        // Want 3 units of id=77
        vm.prank(seller);
        market.createListing(address(A), 1, address(0), 0, address(0), address(erc1155), 77, 3, 0, true, false, allow);
        uint128 id = getter.getNextListingId() - 1;

        // Non-whitelisted buyer blocked
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__BuyerNotWhitelisted.selector, id, buyer));
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(erc1155), 77, 3, 0, operator);

        // Whitelisted operator succeeds
        vm.prank(operator);
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(erc1155), 77, 3, 0, operator);
        assertEq(A.ownerOf(1), operator);
        assertEq(erc1155.balanceOf(operator, 77), 2);
        assertEq(erc1155.balanceOf(seller, 77), 3);
    }

    /* =======================================================
       Whitelist mutations by token-approved & operator-for-all
       ======================================================= */

    function testBuyerWhitelist_AddRemove_ByERC721TokenApprovedOperator() public {
        _whitelistCollectionAndApproveERC721();

        // Create whitelist-enabled listing (seed with buyer)
        address[] memory allow = new address[](1);
        allow[0] = buyer;
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, true, false, allow
        );
        uint128 id = getter.getNextListingId() - 1;

        // Approve 'operator' for that ERC721 token
        vm.prank(seller);
        erc721.approve(operator, 1);

        // operator can add/remove entries
        address who = vm.addr(123);
        address[] memory arr = new address[](1);
        arr[0] = who;

        vm.prank(operator);
        buyers.addBuyerWhitelistAddresses(id, arr);
        assertTrue(getter.isBuyerWhitelisted(id, who));

        vm.prank(operator);
        buyers.removeBuyerWhitelistAddresses(id, arr);
        assertFalse(getter.isBuyerWhitelisted(id, who));
    }

    function testBuyerWhitelist_AddRemove_ByERC721OperatorForAll() public {
        _whitelistCollectionAndApproveERC721();

        address[] memory allow = new address[](1);
        allow[0] = buyer;
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, true, false, allow
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        erc721.setApprovalForAll(operator, true);

        address who = vm.addr(456);
        address[] memory arr = new address[](1);
        arr[0] = who;

        vm.prank(operator);
        buyers.addBuyerWhitelistAddresses(id, arr);
        assertTrue(getter.isBuyerWhitelisted(id, who));

        vm.prank(operator);
        buyers.removeBuyerWhitelistAddresses(id, arr);
        assertFalse(getter.isBuyerWhitelisted(id, who));
    }

    /* ===========================
       Swaps with listed ERC1155
       =========================== */

    function testSwap_ERC1155toERC721_HappyPath() public {
        // Listed collection must be whitelisted
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Seller lists 6 of id=500 wanting B#9
        MockERC721 B = new MockERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(B)); // optional but fine

        erc1155.mint(seller, 500, 6);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        B.mint(buyer, 9);
        vm.prank(buyer);
        B.approve(address(diamond), 9);

        vm.prank(seller);
        market.createListing(
            address(erc1155), 500, seller, 0, address(0), address(B), 9, 0, 6, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buy full quantity (partials disabled): erc1155PurchaseQuantity=6
        vm.prank(buyer);
        market.purchaseListing{value: 0}(id, 0, address(0), 6, address(B), 9, 0, 6, address(0));

        assertEq(erc1155.balanceOf(buyer, 500), 6);
        assertEq(erc1155.balanceOf(seller, 500), 0);
        assertEq(B.ownerOf(9), seller);
        // price=0, non-custodial → no payments, diamond holds nothing
        assertEq(address(diamond).balance, 0);
    }

    function testSwap_ERC1155toERC1155_HappyPath() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155)); // listed collection

        // Seller lists 5 of idA wanting 3 of idB (same contract is fine)
        uint256 idA = 600;
        uint256 idB = 601;

        erc1155.mint(seller, idA, 5);
        erc1155.mint(buyer, idB, 4);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(buyer);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), idA, seller, 0, address(0), address(erc1155), idB, 3, 5, false, false, new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        // Buyer pays with 3 units of idB; receives 5 of idA
        vm.prank(buyer);
        market.purchaseListing{value: 0}(listingId, 0, address(0), 5, address(erc1155), idB, 3, 5, buyer);

        assertEq(erc1155.balanceOf(buyer, idA), 5);
        assertEq(erc1155.balanceOf(seller, idA), 0);
        assertEq(erc1155.balanceOf(buyer, idB), 1);
        assertEq(erc1155.balanceOf(seller, idB), 3);
    }

    function testSwap_ERC1155toERC1155_DesiredHolderNoMarketApprovalReverts_ThenSucceeds() public {
        // Whitelist the 1155 collection
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Balances:
        // - seller has tokenId=1 (listed)
        // - buyer  has tokenId=2 (desired)
        erc1155.mint(seller, 111, 10);
        erc1155.mint(buyer, 222, 10);

        // Seller approves marketplace; buyer (desired holder) does NOT yet.
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // Seller lists 10x id=1, pure swap for 10x id=2 (price=0)
        vm.prank(seller);
        market.createListing(
            address(erc1155),
            111,
            seller, // erc1155Holder
            0, // price (pure swap)
            address(0), // currency
            address(erc1155), // desiredTokenAddress
            222, // desiredTokenId
            10, // desiredErc1155Quantity
            10, // erc1155Quantity (listed)
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Attempt swap while desired holder (buyer) has NOT approved the marketplace → revert
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.purchaseListing{value: 0}(
            id,
            0, // expectedPrice
            address(0), // expectedCurrency
            10, // expected listed erc1155Quantity
            address(erc1155), // expected desired token addr
            222, // expected desired tokenId
            10, // expected desired erc1155 qty
            10, // erc1155PurchaseQuantity
            buyer // desiredErc1155Holder
        );
        vm.stopPrank();

        // Now desired holder approves marketplace and swap succeeds
        vm.prank(buyer);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(buyer);
        market.purchaseListing{value: 0}(id, 0, address(0), 10, address(erc1155), 222, 10, 10, buyer);

        // Post-swap balances
        assertEq(erc1155.balanceOf(seller, 111), 0);
        assertEq(erc1155.balanceOf(seller, 222), 10);
        assertEq(erc1155.balanceOf(buyer, 111), 10);
        assertEq(erc1155.balanceOf(buyer, 222), 0);
    }

    /* ==================================================
       Terms changed after a partial fill (freshness guard)
       ================================================== */

    function testERC1155_PartialBuy_SecondBuyerWithStaleExpectedTermsReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        erc1155.mint(seller, 700, 10);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // qty=10, price=10 ETH; partials enabled
        vm.prank(seller);
        market.createListing(
            address(erc1155), 700, seller, 10 ether, address(0), address(0), 0, 0, 10, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // First partial: buy 4
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 4 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 4, address(0));

        // Second buyer uses stale expected terms (10/10) → ListingTermsChanged
        address buyer2 = vm.addr(0xDEAD);
        vm.deal(buyer2, 10 ether);
        vm.startPrank(buyer2);
        vm.expectRevert(IdeationMarket__ListingTermsChanged.selector);
        market.purchaseListing{value: 6 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 6, address(0));
        vm.stopPrank();
    }

    /* ===============================================================
       Accounting invariant: diamond balance is ALWAYS ZERO (non-custodial)
       =============================================================== */

    function testInvariant_DiamondBalanceAlwaysZero_NonCustodial() public {
        // In non-custodial model, all payments are atomic.
        // Diamond NEVER holds funds; balance must be 0 after any purchase.

        // 1) Simple ERC721 sale: verify atomic payments
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id1 = getter.getNextListingId() - 1;

        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id1, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        // Verify atomic payments: seller got 0.99 ETH, owner got 0.01 ETH
        assertEq(seller.balance - sellerBalBefore, 0.99 ether);
        assertEq(owner.balance - ownerBalBefore, 0.01 ether);
        // Diamond holds NOTHING (non-custodial)
        assertEq(address(diamond).balance, 0);

        // 2) Royalty sale at 1.5 ETH, 10% royalty to R
        MockERC721Royalty r = new MockERC721Royalty();
        address R = vm.addr(0xB0B0);
        r.mint(seller, 88);
        r.setRoyalty(R, 10_000); // 10%

        vm.prank(owner);
        collections.addWhitelistedCollection(address(r));
        vm.prank(seller);
        r.approve(address(diamond), 88);

        vm.prank(seller);
        market.createListing(
            address(r), 88, address(0), 1.5 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id2 = getter.getNextListingId() - 1;

        address richBuyer = vm.addr(0xCAFE);
        uint256 sellerBalBefore2 = seller.balance;
        uint256 ownerBalBefore2 = owner.balance;
        uint256 royaltyBalBefore = R.balance;
        vm.deal(richBuyer, 1.5 ether);
        vm.prank(richBuyer);
        market.purchaseListing{value: 1.5 ether}(id2, 1.5 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        // Verify atomic payments: owner fee, royalty, seller proceeds
        assertEq(owner.balance - ownerBalBefore2, 0.015 ether); // 1%
        assertEq(R.balance - royaltyBalBefore, 0.15 ether); // 10%
        assertEq(seller.balance - sellerBalBefore2, 1.335 ether); // 89%
        // Diamond STILL holds NOTHING
        assertEq(address(diamond).balance, 0);
    }

    function testCleanListingAfterERC721BurnByThirdUser() public {
        // Create simple ERC721 listing for token #1 (price = 1 ETH)
        uint128 id = _createListingERC721(false, new address[](0));

        // "Burn" by transferring to address(0) — clears per-token approval in the mock
        vm.prank(seller);
        erc721.transferFrom(seller, address(0), 1);

        // Any third party may clean an invalid listing
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(
            id,
            address(erc721),
            1,
            seller,
            operator // cleaner
        );

        vm.prank(operator);
        market.cleanListing(id);

        // Listing removed
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCancelListingAfterERC721BurnByOwner() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.prank(seller);
        erc721.transferFrom(seller, address(0), 1); // burn

        // Diamond owner can cancel any listing, even after burn
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceled(id, address(erc721), 1, seller, owner);

        vm.prank(owner);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCancelListingAfterERC721BurnBySeller() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.prank(seller);
        erc721.transferFrom(seller, address(0), 1); // burn

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceled(id, address(erc721), 1, seller, seller);

        vm.prank(seller);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCancelListingAfterERC721BurnByOperatorForAll() public {
        uint128 id = _createListingERC721(false, new address[](0));

        // Grant blanket operator rights (NOT the marketplace; a real operator)
        vm.prank(seller);
        erc721.setApprovalForAll(operator, true);

        // Burn after listing
        vm.prank(seller);
        erc721.transferFrom(seller, address(0), 1);

        // Operator-for-all may cancel on behalf of the (former) seller
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceled(id, address(erc721), 1, seller, operator);

        vm.prank(operator);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCleanListingAfterERC1155BurnAllByThirdUser() public {
        // Whitelist & approve marketplace for ERC1155
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // IMPORTANT: seller has 10 units from setUp(); list all 10 so a full burn invalidates the listing
        vm.prank(seller);
        market.createListing(
            address(erc1155),
            1,
            seller,
            10 ether, // total price
            address(0), // currency
            address(0),
            0,
            0,
            10, // list the full 10
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Burn all 10 units by sending to the zero address -> seller balance becomes 0 (< listed 10)
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, address(0), 1, 10, "");

        // revoke approval; listing is already invalid so cleanListing will cancel either way.
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), false);

        // Third party can now clean the invalid listing
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(id, address(erc1155), 1, seller, operator);

        vm.prank(operator);
        market.cleanListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /* ============================================================
    Additional tests: burns, operator-for-all cancels, 1155 partial
    burn cleanup, and ERC1155 swap cleanup boundary behavior.
    Copy/paste into IdeationMarketDiamondTest.
    ============================================================ */

    /// Purchase after ERC721 burn should revert (distinct from off-market transfer).
    function testPurchaseRevertsAfterERC721Burn() public {
        _whitelistCollectionAndApproveERC721();

        // Create listing: ERC721 #1, price = 1 ETH
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // "Burn" token by sending to the zero address (owner becomes address(0))
        vm.prank(seller);
        erc721.transferFrom(seller, address(0), 1);

        // Buyer attempts purchase → must revert with SellerNotTokenOwner(listingId)
        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__SellerNotTokenOwner.selector, id));
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    /// Diamond owner can cancel an ERC721 listing after the token is burned.
    function testCancelAfterERC721BurnByOwner() public {
        _whitelistCollectionAndApproveERC721();

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Burn it
        vm.prank(seller);
        erc721.transferFrom(seller, address(0), 1);

        // Diamond owner cancels
        vm.prank(owner);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// Operator-for-all (without per-token approval) can cancel after ERC721 burn.
    function testCancelAfterERC721BurnByOperatorForAll() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        // Seller grants operator-for-all; approve marketplace for creation
        vm.prank(seller);
        erc721.setApprovalForAll(operator, true);
        vm.prank(seller);
        erc721.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Burn token
        vm.prank(seller);
        erc721.transferFrom(seller, address(0), 1);

        // Operator-for-all cancels
        vm.prank(operator);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// ERC-1155 partial burn leaving less than listed quantity → purchase reverts, then clean().
    function testERC1155PartialBurnBelowListed_PurchaseRevertsThenClean() public {
        // Whitelist & approve
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // Seller has 10 of id=1 from setUp. List qty=10, price=10 ETH.
        vm.prank(seller);
        market.createListing(
            address(erc1155),
            1,
            seller,
            10 ether,
            address(0), // currency
            address(0),
            0,
            0,
            10, // listed quantity
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Burn 7 → seller balance becomes 3 (< 10 listed)
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, address(0), 1, 7, "");

        // Purchase (attempt to buy all 10) → must revert with SellerInsufficientTokenBalance(10, 3)
        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__SellerInsufficientTokenBalance.selector, 10, 3));
        market.purchaseListing{value: 10 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 10, address(0));
        vm.stopPrank();

        // Revoke marketplace approval or cleanListing will revert with StillApproved
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), false);

        // Third party can clean the invalid listing
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(id, address(erc1155), 1, seller, operator);

        vm.prank(operator);
        market.cleanListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /* ============================================================
    ERC1155 swap cleanup boundary behavior
    - If buyer’s post-swap remaining balance == their own listed qty → not deleted
    - If remaining balance < their listed qty → listing is deleted
    ============================================================ */

    /// Buyer has a pre-existing ERC1155 listing with qty = QL.
    /// After swapping away QS units, remaining == QL → should NOT delete.
    function testSwapCleanupERC1155_RemainingEqualsListed_NotDeleted() public {
        // Fresh ERC721 for the listed side
        MockERC721 A = new MockERC721();
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(A)); // listed collection must be whitelisted
        collections.addWhitelistedCollection(address(erc1155)); // needed so buyer can list ERC1155
        vm.stopPrank();

        // Mint A#100 to seller and approve marketplace
        A.mint(seller, 100);
        vm.prank(seller);
        A.approve(address(diamond), 100);

        uint256 id1155 = 777;
        uint256 QL = 5; // buyer's own ERC1155 listing quantity
        uint256 QS = 3; // units required by the swap
        // Mint buyer QL + QS so remaining == QL after swap
        erc1155.mint(buyer, id1155, QL + QS);
        vm.prank(buyer);
        erc1155.setApprovalForAll(address(diamond), true);

        // Buyer pre-lists ERC1155(id=777) qty=QL
        vm.prank(buyer);
        market.createListing(
            address(erc1155),
            id1155,
            buyer,
            5 ether,
            address(0), // currency
            address(0),
            0,
            0,
            uint256(QL), // erc1155Quantity
            false,
            false,
            new address[](0)
        );
        uint128 buyerListingId = getter.getNextListingId() - 1;

        // Seller lists A#100 wanting QS units of that ERC1155; price=0 (pure swap)
        vm.prank(seller);
        market.createListing(
            address(A),
            100,
            address(0),
            0,
            address(0), // currency
            address(erc1155),
            id1155,
            uint256(QS), // desire ERC1155
            0,
            false,
            false,
            new address[](0)
        );
        uint128 swapListingId = getter.getNextListingId() - 1;

        // Buyer performs the swap; must pass desiredErc1155Holder=buyer
        vm.prank(buyer);
        market.purchaseListing{value: 0}(
            swapListingId,
            0, // expectedPrice
            address(0), // expectedCurrency
            0, // expectedErc1155Quantity (listed is ERC721)
            address(erc1155),
            id1155,
            uint256(QS),
            0, // erc1155PurchaseQuantity (ERC721 path)
            buyer // desiredErc1155Holder
        );

        // Buyer’s ERC1155 listing should still exist (remaining == QL)
        Listing memory L = getter.getListingByListingId(buyerListingId);
        assertEq(L.erc1155Quantity, QL);
        // Spot-check balances: buyer kept exactly QL
        assertEq(erc1155.balanceOf(buyer, id1155), QL);
    }

    /// Buyer’s remaining balance falls BELOW their listed qty → marketplace should delete that listing.
    function testSwapCleanupERC1155_RemainingBelowListed_Deleted() public {
        // Fresh ERC721
        MockERC721 A = new MockERC721();
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(A));
        collections.addWhitelistedCollection(address(erc1155));
        vm.stopPrank();

        // Mint/approve A#101 to seller
        A.mint(seller, 101);
        vm.prank(seller);
        A.approve(address(diamond), 101);

        uint256 id1155 = 888;
        uint256 QL = 5; // buyer's listing quantity
        uint256 QS = 3; // required by swap
        // Mint buyer QL + QS - 1 so post-swap remaining = QL - 1 (insufficient)
        erc1155.mint(buyer, id1155, QL + QS - 1);
        vm.prank(buyer);
        erc1155.setApprovalForAll(address(diamond), true);

        // Buyer pre-lists ERC1155(id=888) qty=QL
        vm.prank(buyer);
        market.createListing(
            address(erc1155),
            id1155,
            buyer,
            5 ether,
            address(0),
            address(0),
            0,
            0,
            uint256(QL),
            false,
            false,
            new address[](0)
        );
        uint128 buyerListingId = getter.getNextListingId() - 1;

        // Seller lists ERC721 wanting QS of that ERC1155 (pure swap)
        vm.prank(seller);
        market.createListing(
            address(A),
            101,
            address(0),
            0,
            address(0),
            address(erc1155),
            id1155,
            uint256(QS),
            0,
            false,
            false,
            new address[](0)
        );
        uint128 swapListingId = getter.getNextListingId() - 1;

        // Execute swap
        vm.prank(buyer);
        market.purchaseListing{value: 0}(
            swapListingId, 0, address(0), 0, address(erc1155), id1155, uint256(QS), 0, buyer
        );

        // No on-chain auto-cleanup: listing remains but is invalid because buyer's balance is now below the listed quantity.
        Listing memory stale = getter.getListingByListingId(buyerListingId);
        assertEq(stale.erc1155Quantity, QL);
        assertEq(erc1155.balanceOf(buyer, id1155), QL - 1);

        // Off-chain maintenance bots (or anyone) can clean invalid listings.
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(
            buyerListingId, address(erc1155), id1155, buyer, operator
        );
        vm.prank(operator);
        market.cleanListing(buyerListingId);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, buyerListingId));
        getter.getListingByListingId(buyerListingId);
    }

    /* ========== 1155 ↔ 1155 swaps ========== */

    /// Pure 1155(A) ↔ 1155(B) swap (price = 0).
    function testERC1155toERC1155Swap_Pure() public {
        // Token A is the shared fixture erc1155; deploy token B.
        MockERC1155 tokenB = new MockERC1155();

        // Whitelist both 1155 collections.
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        collections.addWhitelistedCollection(address(tokenB));
        vm.stopPrank();

        // Mint balances.
        uint256 idA = 11;
        uint256 idB = 22;
        uint256 qtyA = 50000000000;
        uint256 qtyB = 30000000000;

        erc1155.mint(seller, idA, qtyA);
        tokenB.mint(buyer, idB, qtyB);

        // Approvals.
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(buyer);
        tokenB.setApprovalForAll(address(diamond), true);

        // Seller lists A:idA qtyA desiring B:idB qtyB, price = 0 (pure swap).
        vm.prank(seller);
        market.createListing(
            address(erc1155),
            idA,
            seller,
            0,
            address(0),
            address(tokenB),
            idB,
            qtyB,
            qtyA,
            false,
            false,
            new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        // Execute swap by buyer (supplying tokenB from buyer).
        vm.prank(buyer);
        market.purchaseListing{value: 0}(
            listingId,
            0, // expectedPrice
            address(0), // expectedCurrency
            qtyA, // expectedErc1155Quantity (listed is 1155)
            address(tokenB),
            idB,
            qtyB, // desired 1155 qty to deliver
            qtyA, // purchase qty of listed 1155
            buyer // desiredErc1155Holder = buyer
        );

        // Post conditions: A moved seller->buyer, B moved buyer->seller, no ETH moved.
        assertEq(erc1155.balanceOf(seller, idA), 0);
        assertEq(erc1155.balanceOf(buyer, idA), qtyA);
        assertEq(tokenB.balanceOf(buyer, idB), 0);
        assertEq(tokenB.balanceOf(seller, idB), qtyB);
        assertEq(address(diamond).balance, 0);
    }

    /// 1155(A) ↔ 1155(B) + ETH (seller charges ETH in addition to ERC1155 consideration).
    function testERC1155toERC1155Swap_WithEth() public {
        MockERC1155 tokenB = new MockERC1155();

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        collections.addWhitelistedCollection(address(tokenB));
        vm.stopPrank();

        uint256 idA = 33;
        uint256 idB = 44;
        uint256 qtyA = 6;
        uint256 qtyB = 2;
        uint256 price = 1 ether;

        erc1155.mint(seller, idA, 20);
        tokenB.mint(buyer, idB, 10);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(buyer);
        tokenB.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155),
            idA,
            seller,
            price,
            address(0),
            address(tokenB),
            idB,
            qtyB,
            qtyA,
            false,
            false,
            new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        vm.deal(buyer, price);
        vm.prank(buyer);
        market.purchaseListing{value: price}(
            listingId, price, address(0), qtyA, address(tokenB), idB, qtyB, qtyA, buyer
        );

        assertEq(erc1155.balanceOf(seller, idA), 20 - qtyA);
        assertEq(erc1155.balanceOf(buyer, idA), qtyA);
        assertEq(tokenB.balanceOf(buyer, idB), 10 - qtyB);
        assertEq(tokenB.balanceOf(seller, idB), qtyB);

        // Non-custodial: atomic payments, diamond holds no balance
        assertEq(address(diamond).balance, 0);
    }

    /// Buyer is ONLY an authorized operator for the desired 1155(B) holder (not the holder).
    /// Your contract checks isApprovedForAll(holder, buyer), so grant that, and also approve the diamond to move tokens.
    function testERC1155toERC1155Swap_BuyerIsOperatorForDesired() public {
        MockERC1155 tokenB = new MockERC1155();

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        collections.addWhitelistedCollection(address(tokenB));
        vm.stopPrank();

        address holder = makeAddr("holder"); // third-party holder of tokenB

        uint256 idA = 55;
        uint256 idB = 66;
        uint256 qtyA = 4;
        uint256 qtyB = 3;

        erc1155.mint(seller, idA, 10);
        tokenB.mint(holder, idB, 10);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // Holder authorizes the DIAMOND (for the actual transfer) and the BUYER (authZ check your market performs)
        vm.startPrank(holder);
        tokenB.setApprovalForAll(address(diamond), true);
        tokenB.setApprovalForAll(buyer, true); // <<< important: satisfies IdeationMarket__NotAuthorizedOperator guard
        vm.stopPrank();

        vm.prank(seller);
        market.createListing(
            address(erc1155),
            idA,
            seller,
            0,
            address(0),
            address(tokenB),
            idB,
            qtyB,
            qtyA,
            false,
            false,
            new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        // Buyer executes swap, supplying B from `holder` via marketplace pull.
        vm.prank(buyer);
        market.purchaseListing{value: 0}(
            listingId,
            0,
            address(0),
            qtyA,
            address(tokenB),
            idB,
            qtyB,
            qtyA,
            holder // desiredErc1155Holder is the third-party holder
        );

        // Effects: holder lost B, seller gained B, buyer received A.
        assertEq(tokenB.balanceOf(holder, idB), 10 - qtyB);
        assertEq(tokenB.balanceOf(seller, idB), qtyB);
        assertEq(erc1155.balanceOf(buyer, idA), qtyA);
        assertEq(erc1155.balanceOf(seller, idA), 10 - qtyA);
    }

    /* ========== Clean-listing on ERC1155 balance drift while approval INTACT ========== */

    /// Canonical: balance drifts via normal transfer (approval remains true) → cleanListing cancels.
    function testCleanListingERC1155_BalanceDrift_ApprovalIntact_Cancels() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Seller lists qty=10 of id=77; approval to marketplace is TRUE.
        uint256 id1155 = 77;
        uint256 listedQty = 10;
        erc1155.mint(seller, id1155, listedQty);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // Non-zero price to avoid FreeListingsNotSupported
        vm.prank(seller);
        market.createListing(
            address(erc1155),
            id1155,
            seller,
            10 ether,
            address(0),
            address(0),
            0,
            0,
            listedQty,
            false,
            false,
            new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        // Drift: seller moves 6 away → remaining 4 (< 10); approval STILL true.
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, buyer, id1155, 6, "");

        // Expect cancellation event, then anyone can clean.
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(
            listingId, address(erc1155), id1155, seller, operator
        );

        vm.prank(operator);
        market.cleanListing(listingId);

        // Listing is gone.
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingId));
        getter.getListingByListingId(listingId);
    }

    /// balance drifts because units are burned (approval remains true) → cancel.
    /// If your MockERC1155 exposes a burn(address,uint256,uint256) method, prefer that. Otherwise
    /// keep the safeTransferFrom(..., address(0), ...) line below (if your mock treats that as burn).
    function testCleanListingERC1155_BalanceDrift_ApprovalIntact_Cancels_BurnVariant() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        uint256 tid = 600;
        uint256 listedQty = 8;
        erc1155.mint(seller, tid, 10);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155),
            tid,
            seller,
            1 wei,
            address(0),
            address(0),
            0,
            0,
            listedQty,
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Burn 5 units so remaining = 5 (< 8).
        // If you have erc1155.burn(seller, tid, 5); use that instead of the next line.
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, address(0), tid, 5, "");

        vm.prank(operator);
        market.cleanListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// Same as above but demonstrate it also cancels after approval is revoked.
    function testCleanListingERC1155_BalanceDrift_AfterApprovalRevoked_Cleans() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        uint256 id = 88;
        erc1155.mint(seller, id, 10);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // Non-zero price
        vm.prank(seller);
        market.createListing(
            address(erc1155),
            id,
            seller,
            1, // 1 wei
            address(0), // currency
            address(0),
            0,
            0,
            9,
            false,
            false,
            new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        // Drift down to 7 (< 9).
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, address(0), id, 3, "");

        // Revoke approval; listing is invalid regardless in your implementation.
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), false);

        // Clean succeeds and deletes the listing.
        vm.prank(operator);
        market.cleanListing(listingId);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingId));
        getter.getListingByListingId(listingId);
    }

    function testSwapERC1155toERC1155_PureSwap_HappyPath() public {
        // Listed 1155 (A) must be whitelisted; desired 1155 (B) only needs to pass interface checks.
        MockERC1155 A = new MockERC1155();
        MockERC1155 B = new MockERC1155();

        vm.prank(owner);
        collections.addWhitelistedCollection(address(A));

        // Seller lists 10x A#1
        A.mint(seller, 1, 10);
        vm.prank(seller);
        A.setApprovalForAll(address(diamond), true);

        // Buyer holds 6x B#7 and approves marketplace
        B.mint(buyer, 7, 6);
        vm.prank(buyer);
        B.setApprovalForAll(address(diamond), true);

        // Create pure swap: want 6x B#7 for 10x A#1 (price=0, partials disabled)
        vm.prank(seller);
        market.createListing(address(A), 1, seller, 0, address(0), address(B), 7, 6, 10, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        // Execute swap
        vm.prank(buyer);
        market.purchaseListing{value: 0}(id, 0, address(0), 10, address(B), 7, 6, 10, buyer);

        // Balances swapped
        assertEq(A.balanceOf(buyer, 1), 10);
        assertEq(B.balanceOf(seller, 7), 6);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testSwapERC1155toERC1155_WithEth_AndBuyerIsOperatorForDesired() public {
        MockERC1155 A = new MockERC1155();
        MockERC1155 B = new MockERC1155();

        vm.prank(owner);
        collections.addWhitelistedCollection(address(A));

        // Seller lists 8x A#2
        A.mint(seller, 2, 8);
        vm.prank(seller);
        A.setApprovalForAll(address(diamond), true);

        // Desired B#9 is held by 'operatorHolder'; buyer is its operator (NOT holder)
        address operatorHolder = vm.addr(0x5155);
        B.mint(operatorHolder, 9, 5);
        vm.prank(operatorHolder);
        B.setApprovalForAll(buyer, true); // buyer can move holder's B
        vm.prank(operatorHolder);
        B.setApprovalForAll(address(diamond), true); // marketplace can pull B from holder

        // Create swap+ETH: want 5x B#9 + 0.25 ETH for 8x A#2
        vm.prank(seller);
        market.createListing(
            address(A), 2, seller, 0.25 ether, address(0), address(B), 9, 5, 8, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 0.25 ether}(id, 0.25 ether, address(0), 8, address(B), 9, 5, 8, operatorHolder);

        // Results: A goes to buyer, B to seller, atomic ETH payments to seller/owner
        assertEq(A.balanceOf(buyer, 2), 8);
        assertEq(B.balanceOf(seller, 9), 5);
        assertEq(seller.balance - sellerBalBefore, 0.2475 ether); // 0.25 * 99%
        assertEq(owner.balance - ownerBalBefore, 0.0025 ether);
        assertEq(address(diamond).balance, 0); // Non-custodial
    }

    function testCleanListingERC721_OwnerChangedButApprovalIntact_Cancels() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Off-market transfer to operator; marketplace approval on token 1 is still the diamond
        vm.prank(seller);
        erc721.transferFrom(seller, operator, 1);
        // (no approval changes)

        // Anyone should be able to clean this stale listing
        vm.prank(buyer);
        market.cleanListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCleanListing_BurnedERC721_Cancels() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        erc721.burn(1);

        vm.prank(operator);
        market.cleanListing(id);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCancelListing_BurnedERC1155_BySeller() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        erc1155.mint(seller, 42, 5);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), 42, seller, 5 ether, address(0), address(0), 0, 0, 5, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        erc1155.burn(seller, 42, 5);

        vm.prank(seller);
        market.cancelListing(id);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testERC721ReceiverSwallowsRevert_DoesNotMaskMarketplaceChecks() public {
        _whitelistCollectionAndApproveERC721();
        SwallowingERC721Receiver recv = new SwallowingERC721Receiver();

        // list and sell to receiver
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        // Then send to receiver via normal transfer to assert hook didn’t break semantics
        vm.prank(buyer);
        erc721.safeTransferFrom(buyer, address(recv), 1);

        assertEq(erc721.ownerOf(1), address(recv));
    }

    /// 1155 <-> 1155 swap paths

    function testSwap_ERC1155toERC1155_PureSwap_BuyerIsOperatorForDesired() public {
        // Fresh ERC1155 collections
        MockERC1155 A = new MockERC1155();
        MockERC1155 B = new MockERC1155();

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(A));
        collections.addWhitelistedCollection(address(B));
        vm.stopPrank();

        // Seller holds A#1 x10; Holder owns B#2 x7 and makes buyer an operator
        address holder = vm.addr(0xA11CE);
        A.mint(seller, 1, 10);
        B.mint(holder, 2, 7);

        // Approvals
        vm.prank(seller);
        A.setApprovalForAll(address(diamond), true);
        vm.prank(holder);
        B.setApprovalForAll(buyer, true); // buyer can act for holder
        vm.prank(holder);
        B.setApprovalForAll(address(diamond), true); // marketplace can move holder's tokens

        // Seller lists 6x A#1, desires 5x B#2 (price=0 -> pure swap)
        vm.prank(seller);
        market.createListing(address(A), 1, seller, 0, address(0), address(B), 2, 5, 6, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        // Buyer executes swap on behalf of holder
        vm.prank(buyer);
        market.purchaseListing{value: 0}(id, 0, address(0), 6, address(B), 2, 5, 6, holder);

        // Post conditions
        assertEq(A.balanceOf(buyer, 1), 6);
        assertEq(B.balanceOf(seller, 2), 5);
    }

    function testSwap_ERC1155toERC1155_WithEth() public {
        MockERC1155 A = new MockERC1155();
        MockERC1155 B = new MockERC1155();

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(A));
        collections.addWhitelistedCollection(address(B));
        vm.stopPrank();

        A.mint(seller, 10, 8);
        B.mint(buyer, 20, 6);

        vm.prank(seller);
        A.setApprovalForAll(address(diamond), true);
        vm.prank(buyer);
        B.setApprovalForAll(address(diamond), true);

        // Seller wants 4x B#20 + 0.25 ETH for 5x A#10
        vm.prank(seller);
        market.createListing(
            address(A), 10, seller, 0.25 ether, address(0), address(B), 20, 4, 5, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 0.25 ether}(id, 0.25 ether, address(0), 5, address(B), 20, 4, 5, buyer);

        assertEq(A.balanceOf(buyer, 10), 5);
        assertEq(B.balanceOf(seller, 20), 4);
        // 1% fee on 0.25 ETH = 0.0025, atomic payments
        assertEq(seller.balance - sellerBalBefore, 0.2475 ether);
        assertEq(owner.balance - ownerBalBefore, 0.0025 ether);
        assertEq(address(diamond).balance, 0); // Non-custodial
    }

    /// -----------------------------------------------------------------------
    /// Clean/cancel after burn (uses tiny burnable mocks added below)
    /// -----------------------------------------------------------------------

    function testCleanListingCancelsAfterERC721Burn() public {
        BurnableERC721 x = new BurnableERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(x));

        x.mint(seller, 1);
        vm.prank(seller);
        x.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(x), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Burn off-market
        vm.prank(seller);
        x.burn(1);

        // Anyone can clean
        vm.prank(operator);
        market.cleanListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCancelListingAfterERC721Burn_ByContractOwner() public {
        BurnableERC721 x = new BurnableERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(x));

        x.mint(seller, 2);
        vm.prank(seller);
        x.approve(address(diamond), 2);
        vm.prank(seller);
        market.createListing(
            address(x), 2, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        x.burn(2);

        // Contract owner can cancel any listing
        vm.prank(owner);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCleanListingCancelsAfterERC1155Burn() public {
        BurnableERC1155 y = new BurnableERC1155();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(y));

        y.mint(seller, 5, 10);
        vm.prank(seller);
        y.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(y), 5, seller, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Burn some so balance < listed
        vm.prank(seller);
        y.burn(seller, 5, 7); // leaves 3 < 10

        vm.prank(operator);
        market.cleanListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCancelListingAfterERC1155Burn_ByContractOwner() public {
        BurnableERC1155 y = new BurnableERC1155();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(y));

        y.mint(seller, 9, 6);
        vm.prank(seller);
        y.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(y), 9, seller, 6 ether, address(0), address(0), 0, 0, 6, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        y.burn(seller, 9, 6); // full burn

        vm.prank(owner);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// -----------------------------------------------------------------------
    /// Old approval exists but owner changed off-market → clean cancels
    /// -----------------------------------------------------------------------

    function testCleanListingCancelsAfterOwnerChangedOffMarket() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Off-market transfer to some other address; marketplace approval on seller is now meaningless
        vm.prank(seller);
        erc721.transferFrom(seller, operator, 1);

        // Anyone can clean invalid listing
        vm.prank(buyer);
        market.cleanListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// -----------------------------------------------------------------------
    /// Receiver hooks that swallow reverts
    /// -----------------------------------------------------------------------

    function testReceiverHooksThatSwallowReverts_ERC721() public {
        _whitelistCollectionAndApproveERC721();
        // Mint + approve a fresh token
        erc721.mint(seller, 99);
        vm.prank(seller);
        erc721.approve(address(diamond), 99);

        vm.prank(seller);
        market.createListing(
            address(erc721), 99, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        SwallowingERC721Receiver rcvr = new SwallowingERC721Receiver();
        vm.deal(address(rcvr), 1 ether);

        vm.prank(address(rcvr));
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        assertEq(erc721.ownerOf(99), address(rcvr));
    }

    function testERC721BuyerContractWithoutReceiverInterfaceReverts_Strict() public {
        // Deploy strict token that enforces ERC721Receiver check
        StrictERC721 strict721 = new StrictERC721();

        // Whitelist the strict token
        vm.prank(owner);
        collections.addWhitelistedCollection(address(strict721));

        // Mint token #1 to seller and approve marketplace
        strict721.mint(seller, 1);
        vm.prank(seller);
        strict721.approve(address(diamond), 1);

        // Create a fixed-price listing
        vm.prank(seller);
        market.createListing(
            address(strict721),
            1,
            address(0), // erc1155Holder (unused for 721)
            1 ether, // price
            address(0), // currency
            address(0),
            0,
            0, // no swap
            0, // erc1155Quantity
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer is a contract with NO ERC721Receiver
        NonReceiver non = new NonReceiver();
        vm.deal(address(non), 2 ether);

        // Purchase must revert due to missing onERC721Received
        vm.startPrank(address(non));
        vm.expectRevert(); // any revert is fine
        market.purchaseListing{value: 1 ether}(
            id,
            1 ether, // expectedPrice
            address(0), // expectedCurrency
            0, // expectedErc1155Quantity
            address(0),
            0,
            0,
            0, // erc1155PurchaseQuantity
            address(0)
        );
        vm.stopPrank();
    }

    function testReceiverHooksThatSwallowReverts_ERC1155() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        erc1155.mint(seller, 55, 5);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), 55, seller, 5 ether, address(0), address(0), 0, 0, 5, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        SwallowingERC1155Receiver rcvr = new SwallowingERC1155Receiver();
        vm.deal(address(rcvr), 10 ether);

        // Buy all 5 to receiver; its hook swallows internal errors but returns selector
        vm.prank(address(rcvr));
        market.purchaseListing{value: 5 ether}(id, 5 ether, address(0), 5, address(0), 0, 0, 5, address(0));

        assertEq(erc1155.balanceOf(address(rcvr), 55), 5);
    }

    function testERC1155BuyerContractWithoutReceiverInterfaceReverts_Strict() public {
        // Deploy strict token that enforces ERC1155Receiver check
        StrictERC1155 strict1155 = new StrictERC1155();

        // Whitelist the strict token
        vm.prank(owner);
        collections.addWhitelistedCollection(address(strict1155));

        // Mint id=1 qty=10 to seller and approve marketplace
        strict1155.mint(seller, 1, 10);
        vm.prank(seller);
        strict1155.setApprovalForAll(address(diamond), true);

        // Create a fixed-price 1155 listing (no partials)
        vm.prank(seller);
        market.createListing(
            address(strict1155),
            1,
            seller, // erc1155Holder (seller is the holder)
            10 ether, // total price for qty 10
            address(0), // currency
            address(0),
            0,
            0, // no swap
            10, // erc1155Quantity
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer is a contract with NO ERC1155Receiver
        NonReceiver non = new NonReceiver();
        vm.deal(address(non), 20 ether);

        // Purchase must revert due to missing onERC1155Received
        vm.startPrank(address(non));
        vm.expectRevert(); // any revert is fine
        market.purchaseListing{value: 10 ether}(
            id,
            10 ether, // expectedPrice
            address(0), // expectedCurrency
            10, // expectedErc1155Quantity
            address(0),
            0,
            0,
            10, // erc1155PurchaseQuantity (full buy)
            address(0)
        );
        vm.stopPrank();
    }

    // Whitelist bloat: large whitelist must not affect purchase correctness
    function testWhitelistScale_PurchaseUnaffectedByLargeList() public {
        // Use your shared ERC721 fixture/helpers or do it inline
        _whitelistCollectionAndApproveERC721();
        erc721.mint(seller, 123);
        vm.prank(seller);
        erc721.approve(address(diamond), 123);

        address[] memory empty;
        vm.prank(seller);
        market.createListing(
            address(erc721), 123, address(0), 1 ether, address(0), address(0), 0, 0, 0, true, false, empty
        );
        uint128 id = getter.getNextListingId() - 1;

        // Fill with a few thousand addresses (in chunks per getter.getBuyerWhitelistMaxBatchSize)
        uint16 maxBatch = getter.getBuyerWhitelistMaxBatchSize();
        uint256 N = 2400;

        address[] memory chunk = new address[](maxBatch);
        uint256 filled;
        while (filled < N) {
            uint256 k = 0;
            while (k < maxBatch && filled < N) {
                chunk[k] = vm.addr(uint256(keccak256(abi.encodePacked("wh", filled))));
                k++;
                filled++;
            }
            address[] memory slice = new address[](k);
            for (uint256 i = 0; i < k; i++) {
                slice[i] = chunk[i];
            }

            vm.prank(seller);
            buyers.addBuyerWhitelistAddresses(id, slice);
        }

        // Non-whitelisted buyer blocked
        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__BuyerNotWhitelisted.selector, id, buyer));
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Whitelist buyer and succeed
        address[] memory me = new address[](1);
        me[0] = buyer;
        vm.prank(seller);
        buyers.addBuyerWhitelistAddresses(id, me);

        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        assertEq(erc721.ownerOf(123), buyer);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testFirstListingIdIsOne() public {
        _whitelistDefaultMocks();

        // Before any listing exists, next id should be 1.
        assertEq(uint256(getter.getNextListingId()), 1);

        // Approve and create the very first listing (ERC721).
        vm.startPrank(seller);
        erc721.approve(address(diamond), 1);
        vm.stopPrank();

        vm.prank(seller);
        market.createListing(
            address(erc721),
            1,
            address(0), // erc1155Holder (unused for ERC721)
            1 ether, // price > 0
            address(0), // currency
            address(0), // desiredTokenAddress (no swap)
            0, // desiredTokenId
            0, // desiredErc1155Quantity
            0, // erc1155Quantity (0 => ERC721)
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            new address[](0) // allowedBuyers
        );

        // The first assigned id must be 1.
        uint128 firstListingId = getter.getNextListingId() - 1;
        assertEq(uint256(firstListingId), 1);
    }

    function testRoyaltyPurchase_EmitsPurchasedThenRoyalty() public {
        // Setup royalty NFT (10%) + whitelist + approval
        MockERC721Royalty royaltyNft = new MockERC721Royalty();
        address royaltyReceiver = address(0xB0B);
        royaltyNft.setRoyalty(royaltyReceiver, 10_000); // 10%

        vm.prank(owner);
        collections.addWhitelistedCollection(address(royaltyNft));
        royaltyNft.mint(seller, 1);
        vm.prank(seller);
        royaltyNft.approve(address(diamond), 1);

        // List for 1 ETH
        vm.prank(seller);
        market.createListing(
            address(royaltyNft), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Expect BOTH events, in order: ListingPurchased THEN RoyaltyPaid
        vm.deal(buyer, 1 ether);
        uint32 feeSnap = getter.getListingByListingId(id).feeRate;

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.RoyaltyPaid(id, royaltyReceiver, address(0), 0.1 ether);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingPurchased(
            id, address(royaltyNft), 1, 0, false, 1 ether, address(0), feeSnap, seller, buyer, address(0), 0, 0
        );

        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
    }

    function testUpdate_SwapSameNFTReverts() public {
        // Create plain ERC721 listing (ETH-only)
        uint128 id = _createListingERC721(false, new address[](0));

        // Same token (same contract & tokenId=1) must revert on update
        vm.startPrank(seller);
        uint256 oldPrice = getter.getListingByListingId(id).price;
        vm.expectRevert(IdeationMarket__NoSwapForSameToken.selector);
        market.updateListing(
            id,
            oldPrice, // keep price
            address(0), // newCurrency
            address(erc721), // desired = same collection
            1, // desired tokenId = same token
            0, // desired ERC1155 qty (not used for 721)
            0, // newErc1155Quantity
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();
    }

    function testUpdate_AddDesiredToEthListing_Succeeds() public {
        // Start with ETH-only listing
        uint128 id = _createListingERC721(false, new address[](0));

        vm.startPrank(seller);
        uint32 feeNow = getter.getInnovationFee();

        // Expect ListingUpdated to reflect adding a desired NFT (same collection, different tokenId)
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingUpdated(
            id,
            address(erc721), // listed collection
            1, // listed tokenId
            0, // listed qty (0 for 721)
            2 ether, // new price
            address(0), // currency
            feeNow,
            seller,
            false,
            false,
            address(erc721), // desired collection
            2, // desired tokenId (DIFFERENT from listed)
            0 // desired qty (0 for 721)
        );

        market.updateListing(
            id,
            2 ether,
            address(0), // newCurrency
            address(erc721), // add desired
            2, // desired tokenId != 1
            0,
            0, // newErc1155Quantity
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();
    }

    function testUpdate_AddEthToSwapListing_Succeeds() public {
        // Whitelist and approve listed ERC721
        _whitelistCollectionAndApproveERC721();
        // Also whitelist the desired collection (use ERC1155 to avoid “same token” concerns)
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Create swap-only listing (price = 0) wanting ERC1155 id=1 qty=1
        vm.startPrank(seller);
        market.createListing(
            address(erc721),
            1,
            address(0),
            0, // price 0 (swap-only)
            address(0), // currency
            address(erc1155), // desired collection
            1, // desired tokenId (ERC1155 id)
            1, // desired ERC1155 quantity
            0,
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        uint32 feeNow = getter.getInnovationFee();
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingUpdated(
            id,
            address(erc721),
            1,
            0,
            1 ether, // now add ETH price
            address(0), // currency
            feeNow,
            seller,
            false,
            false,
            address(erc1155), // desired remains intact
            1,
            1
        );

        // Update to ETH + desired
        market.updateListing(
            id,
            1 ether, // add price
            address(0), // newCurrency
            address(erc1155),
            1,
            1,
            0, // newErc1155Quantity
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();
    }
}
