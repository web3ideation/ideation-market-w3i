// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

/**
 * @title MarketplaceAuthorizationTest
 * @notice Authorization and approval invariants across create/update/purchase/cancel flows.
 */
contract MarketplaceAuthorizationTest is MarketTestBase {
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
}
