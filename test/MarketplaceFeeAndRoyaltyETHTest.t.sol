// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

/**
 * @title MarketplaceFeeAndRoyaltyETHTest
 * @notice ETH-path fee snapshots, fee boundaries, and ERC2981 royalty behavior.
 */
contract MarketplaceFeeAndRoyaltyETHTest is MarketTestBase {
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
