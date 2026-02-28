// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import {IdeationMarket__InvalidPurchaseQuantity} from "../src/facets/IdeationMarketFacet.sol";

/**
 * @title ERC1155MarketplaceFlowTest
 * @notice ERC1155-specific listing, update, purchase, and quantity rules.
 */
contract ERC1155MarketplaceFlowTest is MarketTestBase {
    function testERC1155BuyingMoreThanListedReverts() public {
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.stopPrank();

        vm.startPrank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, true, new address[](0)
        );
        vm.stopPrank();

        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 20 ether);
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__InvalidPurchaseQuantity.selector);
        market.purchaseListing{value: 20 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 11, address(0));
        vm.stopPrank();
    }
}
