// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import {Getter__ListingNotFound} from "../src/facets/GetterFacet.sol";
import {IdeationMarket__StillApproved, IdeationMarketFacet} from "../src/facets/IdeationMarketFacet.sol";

/**
 * @title MarketplaceCancellationAndCleanupTest
 * @notice Cancellation and cleanup lifecycle behavior for listings.
 */
contract MarketplaceCancellationAndCleanupTest is MarketTestBase {
    function testCleanListing721() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.startPrank(operator);
        vm.expectRevert(IdeationMarket__StillApproved.selector);
        market.cleanListing(id);
        vm.stopPrank();

        vm.startPrank(seller);
        erc721.approve(address(0), 1);
        vm.stopPrank();

        vm.startPrank(operator);
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(id, address(erc721), 1, seller, operator);
        market.cleanListing(id);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }
}
