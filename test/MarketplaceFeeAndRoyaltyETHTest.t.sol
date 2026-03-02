// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import {IdeationMarketFacet} from "../src/facets/IdeationMarketFacet.sol";

/**
 * @title MarketplaceFeeAndRoyaltyETHTest
 * @notice ETH-path fee snapshots, fee boundaries, and ERC2981 royalty behavior.
 */
contract MarketplaceFeeAndRoyaltyETHTest is MarketTestBase {
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
}
