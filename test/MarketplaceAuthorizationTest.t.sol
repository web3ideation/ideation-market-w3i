// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

/**
 * @title MarketplaceAuthorizationTest
 * @notice Authorization and approval invariants across create/update/purchase/cancel flows.
 */
contract MarketplaceAuthorizationTest is MarketTestBase {
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

    // setApprovalForAll (without per-token approval) allows ERC721 listing creation
    function testERC721SetApprovalForAllCreateListing() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        vm.prank(seller);
        erc721.setApprovalForAll(address(diamond), true);

        vm.startPrank(seller);

        uint128 expectedId = getter.getNextListingId();
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCreated(
            expectedId,
            address(erc721),
            1,
            0,
            1 ether,
            address(0),
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

    // create fails when marketplace has no ERC721 approval (neither approve nor setApprovalForAll)
    function testCreateListingWithoutApprovalReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.createListing(
            address(erc721), 2, address(0), 2 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
    }

    // unauthorized third party cannot list someone else's ERC721
    function testERC721CreateUnauthorizedListerReverts() public {
        // whitelist and approve the ERC721 for the seller
        _whitelistCollectionAndApproveERC721();

        // buyer attempts to list seller's token
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotAuthorizedOperator.selector);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
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

    // update fails if approval revoked between listing and update
    function testERC721UpdateApprovalRevokedReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.prank(seller);
        erc721.approve(address(0), 1);

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.updateListing(id, 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));
    }
}
