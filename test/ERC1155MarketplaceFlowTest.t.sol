// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import {
    IdeationMarket__InvalidUnitPrice,
    IdeationMarket__InvalidPurchaseQuantity,
    IdeationMarket__PartialBuyNotPossible,
    IdeationMarketFacet
} from "../src/facets/IdeationMarketFacet.sol";

/**
 * @title ERC1155MarketplaceFlowTest
 * @notice ERC1155-specific listing, update, purchase, and quantity rules.
 */
contract ERC1155MarketplaceFlowTest is MarketTestBase {
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

    function testERC1155PartialBuyDisabledReverts() public {
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.stopPrank();

        vm.startPrank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0)
        );
        vm.stopPrank();

        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__PartialBuyNotPossible.selector);
        market.purchaseListing{value: 5 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 5, address(0));
        vm.stopPrank();
    }
}
