// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import {Getter__ListingNotFound} from "../src/facets/GetterFacet.sol";
import {
    IdeationMarket__StillApproved,
    IdeationMarket__NotAuthorizedToCancel,
    IdeationMarket__NotListed,
    IdeationMarketFacet
} from "../src/facets/IdeationMarketFacet.sol";

/**
 * @title MarketplaceCancellationAndCleanupTest
 * @notice Cancellation and cleanup lifecycle behavior for listings.
 */
contract MarketplaceCancellationAndCleanupTest is MarketTestBase {
    /// cleanListing should cancel if collection has been removed from whitelist.
    function testCleanListingAfterDeWhitelistingCancels() public {
        uint128 id = _createListingERC721(false, new address[](0));
        // Remove collection
        vm.prank(owner);
        collections.removeWhitelistedCollection(address(erc721));
        // cleanListing should delete the listing
        // Expect the cancellation event on cleanListing
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(id, address(erc721), 1, seller, operator);

        vm.prank(operator);
        market.cleanListing(id);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// ERC1155 listings can be cancelled by any operator approved for the seller.
    function testCancelERC1155ListingByOperator() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 500;
        erc1155.mint(seller, tokenId, 10);
        // seller grants operator blanket approval
        vm.prank(seller);
        erc1155.setApprovalForAll(operator, true);
        // also approve marketplace
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155),
            tokenId,
            seller,
            10 ether,
            address(0),
            address(0),
            0,
            0,
            10,
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // operator cancels
        vm.prank(operator);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCancelListing_UnauthorizedThirdParty_ERC1155_Reverts() public {
        // Setup: whitelist + operator approval + create a live ERC1155 listing
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155),
            1,
            seller, // erc1155Holder
            10 ether, // price (no swap)
            address(0),
            address(0),
            0,
            0,
            10, // erc1155Quantity
            false, // whitelist disabled
            false, // partialBuy disabled
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // A random third party (not seller, not operator) cannot cancel
        address rando = vm.addr(0xBEEF);
        vm.startPrank(rando);
        vm.expectRevert(IdeationMarket__NotAuthorizedToCancel.selector);
        market.cancelListing(id);
        vm.stopPrank();
    }

    function testCancelListing_UnauthorizedThirdParty_ERC721_Reverts() public {
        // Setup: whitelist + approve + create a live ERC721 listing
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, seller, 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // A random third party (not owner, not token-approved, not operator) cannot cancel
        address rando = vm.addr(0xCAFE);
        vm.startPrank(rando);
        vm.expectRevert(IdeationMarket__NotAuthorizedToCancel.selector);
        market.cancelListing(id);
        vm.stopPrank();
    }

    function testCancelListingByERC721ApprovedOperator() public {
        // Whitelist ERC721 collection
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        // Seller: grant blanket approval to marketplace (so createListing passes)
        vm.prank(seller);
        erc721.setApprovalForAll(address(diamond), true);

        // Seller: set per-token approval to 'operator' (this is the authority we want to test)
        vm.prank(seller);
        erc721.approve(operator, 1);

        // Create listing for token 1
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Operator cancels via getApproved(tokenId) path
        vm.startPrank(operator);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceled(id, address(erc721), 1, seller, operator);

        market.cancelListing(id);
        vm.stopPrank();

        // Listing is removed
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCancelERC721ByOperatorForAll() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        erc721.setApprovalForAll(operator, true);
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        vm.prank(operator);
        market.cancelListing(id);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// ListingCanceled fires with exact parameters
    function testEmitListingCanceled() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceled(id, address(erc721), 1, seller, seller);

        vm.prank(seller);
        market.cancelListing(id);
    }

    /// ListingCanceledDueToInvalidListing fires with exact parameters
    function testEmitListingCanceledDueToInvalidListing() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        erc721.approve(address(0), 1);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(id, address(erc721), 1, seller, operator);

        vm.prank(operator);
        market.cleanListing(id);
    }

    function testCancelNonexistentListingReverts() public {
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotListed.selector);
        market.cancelListing(999_999);
    }

    function testDoubleCleanReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));

        // Revoke approval, clean once
        vm.prank(seller);
        erc721.approve(address(0), 1);

        vm.prank(operator);
        market.cleanListing(id);

        // Second clean should revert (listing gone)
        vm.prank(operator);
        vm.expectRevert(IdeationMarket__NotListed.selector);
        market.cleanListing(id);
    }

    function testSellerCancelAfterApprovalRevoked() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.prank(seller);
        erc721.approve(address(0), 1);

        vm.prank(seller);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testUpdateAfterCollectionDeWhitelistingCancels() public {
        _whitelistCollectionAndApproveERC721();

        // Create listing
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // De-whitelist the collection
        vm.prank(owner);
        collections.removeWhitelistedCollection(address(erc721));

        // Calling updateListing should cancel and return (no revert)
        vm.prank(seller);
        market.updateListing(id, 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));

        // Listing is gone
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testActiveListingIdClearsAfterCancel() public {
        _whitelistCollectionAndApproveERC721();

        // Create & cancel listing
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        vm.prank(seller);
        market.cancelListing(id);

        // No active listing
        assertEq(getter.getActiveListingIdByERC721(address(erc721), 1), 0);
    }

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

    function testCleanListingERC1155() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Revoke marketplace approval so cleanListing is allowed.
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), false);

        vm.startPrank(operator);
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(id, address(erc1155), 1, seller, operator);
        market.cleanListing(id);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCleanListing_WhileStillApproved_ERC721_Reverts() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        address rando = vm.addr(0xC1EA11);
        vm.startPrank(rando);
        vm.expectRevert(IdeationMarket__StillApproved.selector);
        market.cleanListing(id);
        vm.stopPrank();
    }

    function testCleanListing_WhileStillApproved_ERC1155_Reverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Still fully approved & whitelisted means cleanListing must revert.
        address rando = vm.addr(0xC1EA12);
        vm.startPrank(rando);
        vm.expectRevert(IdeationMarket__StillApproved.selector);
        market.cleanListing(id);
        vm.stopPrank();
    }

    function testOwnerCanCancelAnyListing() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceled(id, address(erc721), 1, seller, owner);
        market.cancelListing(id);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }
}
