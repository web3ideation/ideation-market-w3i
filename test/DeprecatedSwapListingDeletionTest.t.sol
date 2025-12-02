// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

contract DeprecatedSwapListingDeletionTest is MarketTestBase {
    uint256 internal constant ID = 1; // reuse id=1 for ERC1155 and ERC721 in these tests

    // --- helpers ---

    function _mintAndApproveForBuyer(uint256 amount1155) internal {
        // whitelist both token contracts used
        _whitelistDefaultMocks();

        // mint buyer's ERC1155 balance and approvals
        erc1155.mint(buyer, ID, amount1155);
        vm.prank(buyer);
        erc1155.setApprovalForAll(address(diamond), true);

        // approve seller's ERC721 to marketplace
        vm.prank(seller);
        erc721.approve(address(diamond), ID);
    }

    function _listBuyerERC1155(uint256 depQty, uint256 priceWei) internal returns (uint128 depId) {
        depId = uint128(getter.getNextListingId());
        vm.prank(buyer);
        market.createListing(
            address(erc1155),
            ID,
            buyer, // erc1155Holder
            priceWei, // price (any, irrelevant for this test)
            address(0), // currency (ETH)
            address(0), // desiredTokenAddress (no swap)
            0, // desiredTokenId
            0, // desiredErc1155Quantity
            depQty, // erc1155Quantity
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            new address[](0) // allowedBuyers
        );
    }

    function _listSellerERC721Swap(uint256 desiredQty) internal returns (uint128 swapId) {
        swapId = uint128(getter.getNextListingId());
        vm.prank(seller);
        market.createListing(
            address(erc721),
            ID,
            address(0), // erc1155Holder (unused for ERC721)
            0, // price (0 ok for swap listings)
            address(0), // currency (ETH)
            address(erc1155), // desiredTokenAddress (want ERC1155)
            ID, // desiredTokenId
            desiredQty, // desiredErc1155Quantity (>0 => ERC1155 swap)
            0, // erc1155Quantity (0 => ERC721 listing)
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            new address[](0) // allowedBuyers
        );
    }

    function _purchaseSwap(uint128 swapId, uint256 desiredQty) internal {
        vm.prank(buyer);
        market.purchaseListing(
            swapId,
            0, // expectedPrice
            address(0), // expectedCurrency (ETH)
            0, // expectedErc1155Quantity (listing is ERC721)
            address(erc1155), // expectedDesiredTokenAddress
            ID, // expectedDesiredTokenId
            desiredQty, // expectedDesiredErc1155Quantity
            0, // erc1155PurchaseQuantity (not used for ERC721 listing)
            buyer // desiredErc1155Holder (buyer provides the ERC1155)
        );
    }

    // --- tests ---

    /// Case 1: remaining == listed qty  => NOT deleted
    function test_SwapCleanup_DeprecatedListing_NotDeleted_WhenRemainingEqualsListedQty() public {
        uint256 initial = 10;
        uint256 desiredQty = 4; // buyer sends 4
        uint256 remaining = initial - desiredQty; // 6
        uint256 depQty = remaining; // 6

        _mintAndApproveForBuyer(initial);

        uint128 depId = _listBuyerERC1155(depQty, 1 ether);
        uint128 swapId = _listSellerERC721Swap(desiredQty);

        _purchaseSwap(swapId, desiredQty);

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

        _mintAndApproveForBuyer(initial);

        uint128 depId = _listBuyerERC1155(depQty, 1 ether);
        uint128 swapId = _listSellerERC721Swap(desiredQty);

        _purchaseSwap(swapId, desiredQty);

        // should still exist (NOT deleted)
        Listing memory listing = getter.getListingByListingId(depId);
        assertEq(listing.seller, buyer, "seller mismatch");
        assertEq(listing.erc1155Quantity, depQty, "erc1155Quantity changed");
    }

    /// Case 3: remaining < listed qty  => deleted
    function test_SwapCleanup_DeprecatedListing_Deleted_WhenRemainingLessThanListedQty() public {
        uint256 initial = 10;
        uint256 desiredQty = 4; // buyer sends 4
        uint256 depQty = 7; // listed > remaining  => should be deleted

        _mintAndApproveForBuyer(initial);

        uint128 depId = _listBuyerERC1155(depQty, 1 ether);
        uint128 swapId = _listSellerERC721Swap(desiredQty);

        // Expect the cleanup to cancel the buyer's deprecated listing.
        // ListingCanceled(uint128 listingId, address tokenAddress, uint256 tokenId, address seller, address triggeredBy)
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceled(depId, address(erc1155), ID, buyer, address(diamond));

        _purchaseSwap(swapId, desiredQty);

        // getter should now revert for the deleted listing
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, depId));
        getter.getListingByListingId(depId);
    }
}
