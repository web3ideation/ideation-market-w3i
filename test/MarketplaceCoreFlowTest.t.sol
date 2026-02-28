// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import {Getter__ListingNotFound} from "../src/facets/GetterFacet.sol";
import {
    IdeationMarket__CollectionNotWhitelisted,
    IdeationMarket__AlreadyListed,
    IdeationMarket__PriceNotMet,
    IdeationMarket__NotAuthorizedToCancel,
    IdeationMarketFacet
} from "../src/facets/IdeationMarketFacet.sol";

/**
 * @title MarketplaceCoreFlowTest
 * @notice Baseline marketplace lifecycle tests (create, update, purchase, cancel, clean)
 * @dev Keep only core happy/revert flow coverage here; specialized edge/security/integration cases stay in topical suites.
 */
contract MarketplaceCoreFlowTest is MarketTestBase {
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

    function testCancelListing() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__NotAuthorizedToCancel.selector);
        market.cancelListing(id);
        vm.stopPrank();

        vm.startPrank(seller);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceled(id, address(erc721), 1, seller, seller);

        market.cancelListing(id);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }
}
