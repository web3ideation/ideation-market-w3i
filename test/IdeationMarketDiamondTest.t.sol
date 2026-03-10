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
    /// -----------------------------------------------------------------------
    /// Whitelisted buyer success path
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// ERC721 Approval-for-All creation path
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// ERC721 creation without approval should revert
    /// -----------------------------------------------------------------------

    /// -----------------------------------------------------------------------
    /// Reentrancy tests
    /// -----------------------------------------------------------------------

    // -----------------------------------------------------------------------
    // Extra edge-case tests
    // -----------------------------------------------------------------------

    /* ======================================
       ERC1155 partial-buy payment edge cases
       ====================================== */

    /* ==================================
       Whitelist enforcement on swaps
       ================================== */

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
