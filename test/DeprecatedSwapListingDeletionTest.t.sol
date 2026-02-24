// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

/**
 * @title DeprecatedSwapListingDeletionTest
 * @notice Unit tests for deprecated ERC721↔ERC1155 swap side-effects on pre-existing ERC1155 listings.
 * @dev Coverage groups:
 * - Deprecated ERC1155 listing remains valid when post-swap holder balance is equal to listed quantity.
 * - Deprecated ERC1155 listing remains valid when post-swap holder balance is above listed quantity.
 * - Deprecated ERC1155 listing becomes invalid (but not auto-deleted) when post-swap holder balance falls below listed quantity.
 * - Invalid deprecated listing is unfulfillable until explicitly removed via `cleanListing`.
 */
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

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, swapId));
        getter.getListingByListingId(swapId);

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

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, swapId));
        getter.getListingByListingId(swapId);

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

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, swapId));
        getter.getListingByListingId(swapId);

        // Listing remains, but is invalid (buyer balance is now < depQty)
        Listing memory listing = getter.getListingByListingId(depId);
        assertEq(listing.seller, buyer, "seller mismatch");
        assertEq(listing.erc1155Quantity, depQty, "erc1155Quantity changed");

        vm.expectRevert(
            abi.encodeWithSelector(IdeationMarket__SellerInsufficientTokenBalance.selector, depQty, depQty - 1)
        );
        vm.deal(operator, 1 ether);
        vm.prank(operator);
        market.purchaseListing{value: 1 ether}(depId, 1 ether, address(0), depQty, address(0), 0, 0, depQty, address(0));

        // Anyone can clean invalid listings.
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(depId, address(erc1155), ID, buyer, operator);
        vm.prank(operator);
        market.cleanListing(depId);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, depId));
        getter.getListingByListingId(depId);
    }

    /// Case 4: remaining == 0 and listed qty > 0  => invalid
    function test_SwapCleanup_DeprecatedListing_Deleted_WhenRemainingZero() public {
        uint256 initial = 10;
        uint256 desiredQty = 10; // buyer sends all
        uint256 depQty = 1; // listed > remaining(0) => should be deleted via clean

        _deprecatedSwap_mintAndApproveForBuyer(ID, initial);

        uint128 depId = _deprecatedSwap_listBuyerERC1155(ID, depQty, 1 ether);
        uint128 swapId = _deprecatedSwap_listSellerERC721Swap(ID, desiredQty);

        _deprecatedSwap_purchaseSwap(swapId, ID, desiredQty);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, swapId));
        getter.getListingByListingId(swapId);

        Listing memory listing = getter.getListingByListingId(depId);
        assertEq(listing.seller, buyer, "seller mismatch");
        assertEq(listing.erc1155Quantity, depQty, "erc1155Quantity changed");

        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__SellerInsufficientTokenBalance.selector, depQty, 0));
        vm.deal(operator, 1 ether);
        vm.prank(operator);
        market.purchaseListing{value: 1 ether}(depId, 1 ether, address(0), depQty, address(0), 0, 0, depQty, address(0));

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(depId, address(erc1155), ID, buyer, operator);
        vm.prank(operator);
        market.cleanListing(depId);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, depId));
        getter.getListingByListingId(depId);
    }
}
