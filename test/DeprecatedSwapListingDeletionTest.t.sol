// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

contract DeprecatedSwapListingDeletionTest is MarketTestBase {
    uint256 internal constant ID = 1; // reuse id=1 for ERC1155 and ERC721 in these tests

    // --- tests ---

    /// Case 1: remaining == listed qty  => NOT deleted
    function test_SwapCleanup_DeprecatedListing_NotDeleted_WhenRemainingEqualsListedQty() public {
        uint256 initial = 10;
        uint256 desiredQty = 4; // buyer sends 4
        uint256 remaining = initial - desiredQty; // 6
        uint256 depQty = remaining; // 6

        _deprecatedSwap_mintAndApproveForBuyer(ID, initial);

        uint128 depId = _deprecatedSwap_listBuyerERC1155(ID, depQty, 1 ether);
        uint128 swapId = _deprecatedSwap_listSellerERC721Swap(ID, desiredQty);

        _deprecatedSwap_purchaseSwap(swapId, ID, desiredQty);

        // should still exist (NOT deleted)
        Listing memory listing = getter.getListingByListingId(depId);
        assertEq(listing.seller, buyer, "seller mismatch");
        assertEq(listing.erc1155Quantity, depQty, "erc1155Quantity changed");
    }

    /// Case 2: remaining > listed qty  => NOT deleted
    function test_SwapCleanup_DeprecatedListing_NotDeleted_WhenRemainingGreaterThanListedQty() public {
        uint256 initial = 10;
        uint256 desiredQty = 3; // buyer sends 3
        uint256 depQty = 5; // listed < remaining

        _deprecatedSwap_mintAndApproveForBuyer(ID, initial);

        uint128 depId = _deprecatedSwap_listBuyerERC1155(ID, depQty, 1 ether);
        uint128 swapId = _deprecatedSwap_listSellerERC721Swap(ID, desiredQty);

        _deprecatedSwap_purchaseSwap(swapId, ID, desiredQty);

        // should still exist (NOT deleted)
        Listing memory listing = getter.getListingByListingId(depId);
        assertEq(listing.seller, buyer, "seller mismatch");
        assertEq(listing.erc1155Quantity, depQty, "erc1155Quantity changed");
    }

    /// Case 3: remaining < listed qty  => invalid
    function test_SwapCleanup_DeprecatedListing_Deleted_WhenRemainingLessThanListedQty() public {
        uint256 initial = 10;
        uint256 desiredQty = 4; // buyer sends 4
        uint256 depQty = 7; // listed > remaining  => should be deleted

        _deprecatedSwap_mintAndApproveForBuyer(ID, initial);

        uint128 depId = _deprecatedSwap_listBuyerERC1155(ID, depQty, 1 ether);
        uint128 swapId = _deprecatedSwap_listSellerERC721Swap(ID, desiredQty);

        // No on-chain auto-cleanup: swap does not delete the buyer's now-invalid ERC1155 listing.
        _deprecatedSwap_purchaseSwap(swapId, ID, desiredQty);

        // Listing remains, but is invalid (buyer balance is now < depQty)
        Listing memory listing = getter.getListingByListingId(depId);
        assertEq(listing.seller, buyer, "seller mismatch");
        assertEq(listing.erc1155Quantity, depQty, "erc1155Quantity changed");

        // Anyone can clean invalid listings.
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(depId, address(erc1155), ID, buyer, operator);
        vm.prank(operator);
        market.cleanListing(depId);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, depId));
        getter.getListingByListingId(depId);
    }
}
