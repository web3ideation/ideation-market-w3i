// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import "../src/libraries/LibAppStorage.sol"; // for Listing struct

/**
 * @title IdeationMarketGasTest
 * @notice Scope/category: deterministic gas-regression guardrails for hottest
 * protocol paths in `IdeationMarketFacet`, excluding setup from metering.
 *
 * Covered categories:
 * - ERC721 lifecycle costs: create, purchase, update
 * - ERC1155 lifecycle costs: create, full purchase, update
 * - Swap path cost: ERC721 listing purchased with desired ERC721 fulfillment
 * - Cleanup path cost: clean invalid ERC721 listing after off-market ownership change
 */
contract IdeationMarketGasTest is MarketTestBase {
    // ---------------------------------------------------------------------
    // Gas budgets (tighten after your first snapshot on your machine/CI)
    // ---------------------------------------------------------------------
    // Tightened with ~5–10% headroom over measured baseline
    uint256 private constant CREATE_721_BUDGET = 225_000;
    uint256 private constant PURCHASE_721_BUDGET = 180_000;
    uint256 private constant UPDATE_721_BUDGET = 90_000;

    uint256 private constant CREATE_1155_BUDGET = 245_000;
    uint256 private constant PURCHASE_1155_BUDGET = 190_000; // full-qty buy, partial disabled
    uint256 private constant UPDATE_1155_BUDGET = 90_000;

    uint256 private constant SWAP_721_PURCHASE_BUDGET = 200_000;
    uint256 private constant CLEAN_721_BUDGET = 80_000;

    // ---------------------------------------------------------------------
    // ERC721: create listing
    // ---------------------------------------------------------------------
    function testGas_Create_ERC721_underBudget() public {
        vm.pauseGasMetering();
        _whitelistCollectionAndApproveERC721(); // approves tokenId 1 to diamond
        address[] memory empty = new address[](0);
        vm.startPrank(seller);
        vm.resumeGasMetering();

        uint256 gasBefore = gasleft();
        market.createListing(
            address(erc721),
            1,
            address(0), // erc1155Holder (unused for 721)
            1 ether, // price
            address(0), // currency (ETH)
            address(0), // desiredTokenAddress
            0, // desiredTokenId
            0, // desiredErc1155Quantity (no swap)
            0, // erc1155Quantity = 0 => ERC721
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            empty // allowedBuyers
        );
        uint256 gasUsed = gasBefore - gasleft();

        vm.pauseGasMetering();
        vm.stopPrank();

        uint128 listingId = getter.getNextListingId() - 1;
        Listing memory created = getter.getListingByListingId(listingId);
        assertEq(created.seller, seller);
        assertEq(created.tokenAddress, address(erc721));
        assertEq(created.tokenId, 1);
        assertEq(created.erc1155Quantity, 0);

        assertLe(gasUsed, CREATE_721_BUDGET, "ERC721 createListing gas regression");
        vm.resumeGasMetering();
    }

    // ---------------------------------------------------------------------
    // ERC721 swap: purchase listing (seller wants buyer's ERC721)
    // ---------------------------------------------------------------------
    function testGas_Purchase_Swap_ERC721_underBudget() public {
        vm.pauseGasMetering();
        // Whitelist collection and approve seller's tokenId 1
        _whitelistCollectionAndApproveERC721();

        // Mint a desired token to the buyer and approve the marketplace
        erc721.mint(buyer, 3);
        vm.startPrank(buyer);
        erc721.approve(address(diamond), 3);
        vm.stopPrank();

        // Seller creates a swap listing: sell tokenId 1, desire buyer's tokenId 3
        address[] memory empty = new address[](0);
        vm.startPrank(seller);
        market.createListing(
            address(erc721),
            1,
            address(0), // erc1155Holder (unused for 721)
            1 ether, // price (plus swap)
            address(0), // currency (ETH)
            address(erc721), // desiredTokenAddress (ERC721)
            3, // desiredTokenId
            0, // desiredErc1155Quantity (0 for ERC721)
            0, // erc1155Quantity (0 => ERC721 listing)
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            empty
        );
        vm.stopPrank();

        uint128 listingId = getter.getNextListingId() - 1;
        Listing memory listing = getter.getListingByListingId(listingId);
        vm.deal(buyer, listing.price);
        vm.resumeGasMetering();

        // Purchase as buyer, providing expected terms
        vm.startPrank(buyer);
        uint256 gasBefore = gasleft();
        market.purchaseListing{value: listing.price}(
            listingId,
            listing.price,
            address(0), // expectedCurrency (ETH)
            0, // expectedErc1155Quantity
            listing.desiredTokenAddress,
            listing.desiredTokenId,
            listing.desiredErc1155Quantity,
            0, // erc1155PurchaseQuantity (0 for 721)
            address(0) // desiredErc1155Holder (unused for 721 swap)
        );
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        vm.pauseGasMetering();
        assertEq(erc721.ownerOf(1), buyer);
        assertEq(erc721.ownerOf(3), seller);
        vm.expectRevert(abi.encodeWithSignature("Getter__ListingNotFound(uint128)", listingId));
        getter.getListingByListingId(listingId);
        assertLe(gasUsed, SWAP_721_PURCHASE_BUDGET, "ERC721 swap purchase gas regression");
        vm.resumeGasMetering();
    }

    // ---------------------------------------------------------------------
    // cleanListing: remove invalid ERC721 listing (owner changed off-market)
    // ---------------------------------------------------------------------
    function testGas_CleanListing_ERC721_underBudget() public {
        vm.pauseGasMetering();
        // Create a normal ERC721 listing
        uint128 listingId = _createListingERC721(false, new address[](0));
        // Invalidate listing by transferring the token off-market
        vm.startPrank(seller);
        erc721.transferFrom(seller, operator, 1);
        vm.stopPrank();
        vm.resumeGasMetering();

        // Measure gas for cleanListing
        uint256 gasBefore = gasleft();
        market.cleanListing(listingId);
        uint256 gasUsed = gasBefore - gasleft();

        vm.pauseGasMetering();
        vm.expectRevert(abi.encodeWithSignature("Getter__ListingNotFound(uint128)", listingId));
        getter.getListingByListingId(listingId);
        assertLe(gasUsed, CLEAN_721_BUDGET, "cleanListing ERC721 gas regression");
        vm.resumeGasMetering();
    }
    // ---------------------------------------------------------------------
    // ERC721: purchase listing
    // ---------------------------------------------------------------------

    function testGas_Purchase_ERC721_underBudget() public {
        vm.pauseGasMetering();
        uint128 listingId = _createListingERC721(false, new address[](0));
        Listing memory listing = getter.getListingByListingId(listingId);
        vm.deal(buyer, listing.price);
        vm.resumeGasMetering();

        vm.startPrank(buyer);
        uint256 gasBefore = gasleft();
        market.purchaseListing{value: listing.price}(
            listingId,
            listing.price,
            address(0), // expectedCurrency (ETH)
            0, // expectedErc1155Quantity
            address(0), // expectedDesiredTokenAddress
            0, // expectedDesiredTokenId
            0, // expectedDesiredErc1155Quantity
            0, // erc1155PurchaseQuantity (0 for 721)
            address(0) // desiredErc1155Holder
        );
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        vm.pauseGasMetering();
        assertEq(erc721.ownerOf(1), buyer);
        vm.expectRevert(abi.encodeWithSignature("Getter__ListingNotFound(uint128)", listingId));
        getter.getListingByListingId(listingId);
        assertLe(gasUsed, PURCHASE_721_BUDGET, "ERC721 purchaseListing gas regression");
        vm.resumeGasMetering();
    }

    // ---------------------------------------------------------------------
    // ERC721: update listing
    // ---------------------------------------------------------------------
    function testGas_Update_ERC721_underBudget() public {
        vm.pauseGasMetering();
        uint128 listingId = _createListingERC721(false, new address[](0));
        address[] memory none = new address[](0);
        vm.startPrank(seller);
        vm.resumeGasMetering();

        uint256 gasBefore = gasleft();
        market.updateListing(
            listingId,
            0.9 ether, // new price
            address(0), // newCurrency (ETH)
            address(0), // newDesiredTokenAddress
            0, // newDesiredTokenId
            0, // newDesiredErc1155Quantity (no swap)
            0, // still ERC721 quantity
            false, // whitelist
            false, // partialBuy
            none
        );
        uint256 gasUsed = gasBefore - gasleft();
        vm.pauseGasMetering();
        vm.stopPrank();

        Listing memory updated = getter.getListingByListingId(listingId);
        assertEq(updated.price, 0.9 ether);
        assertEq(updated.erc1155Quantity, 0);

        assertLe(gasUsed, UPDATE_721_BUDGET, "ERC721 updateListing gas regression");
        vm.resumeGasMetering();
    }

    // ---------------------------------------------------------------------
    // ERC1155: create listing (qty>0, partial disabled)
    // ---------------------------------------------------------------------
    function testGas_Create_ERC1155_underBudget() public {
        vm.pauseGasMetering();
        _whitelistCollectionAndApproveERC1155();
        address[] memory empty = new address[](0);
        vm.startPrank(seller);
        vm.resumeGasMetering();

        uint256 gasBefore = gasleft();
        market.createListing(
            address(erc1155),
            1,
            seller, // erc1155Holder
            1 ether, // price (TOTAL for all 5 units)
            address(0), // currency (ETH)
            address(0), // desiredTokenAddress
            0, // desiredTokenId
            0, // desiredErc1155Quantity (no swap)
            5, // erc1155Quantity
            false, // whitelist disabled
            false, // partialBuy disabled
            empty
        );
        uint256 gasUsed = gasBefore - gasleft();
        vm.pauseGasMetering();
        vm.stopPrank();

        uint128 listingId = getter.getNextListingId() - 1;
        Listing memory created = getter.getListingByListingId(listingId);
        assertEq(created.seller, seller);
        assertEq(created.tokenAddress, address(erc1155));
        assertEq(created.tokenId, 1);
        assertEq(created.erc1155Quantity, 5);

        assertLe(gasUsed, CREATE_1155_BUDGET, "ERC1155 createListing gas regression");
        vm.resumeGasMetering();
    }

    // ---------------------------------------------------------------------
    // ERC1155: purchase listing (full-qty buy, partial disabled)
    // ---------------------------------------------------------------------
    function testGas_Purchase_ERC1155_underBudget() public {
        vm.pauseGasMetering();
        uint128 listingId = _createListingERC1155(5, false, new address[](0));
        Listing memory listing = getter.getListingByListingId(listingId);
        vm.deal(buyer, listing.price);
        vm.resumeGasMetering();

        vm.startPrank(buyer);
        uint256 gasBefore = gasleft();
        market.purchaseListing{value: listing.price}(
            listingId,
            listing.price,
            address(0), // expectedCurrency (ETH)
            listing.erc1155Quantity, // expectedErc1155Quantity
            address(0), // expectedDesiredTokenAddress
            0, // expectedDesiredTokenId
            0, // expectedDesiredErc1155Quantity
            listing.erc1155Quantity, // full purchase
            address(0) // desiredErc1155Holder
        );
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        vm.pauseGasMetering();
        assertEq(erc1155.balanceOf(buyer, 1), 5);
        vm.expectRevert(abi.encodeWithSignature("Getter__ListingNotFound(uint128)", listingId));
        getter.getListingByListingId(listingId);
        assertLe(gasUsed, PURCHASE_1155_BUDGET, "ERC1155 purchaseListing gas regression");
        vm.resumeGasMetering();
    }

    // ---------------------------------------------------------------------
    // ERC1155: update listing (same qty, new price)
    // ---------------------------------------------------------------------
    function testGas_Update_ERC1155_underBudget() public {
        vm.pauseGasMetering();
        uint128 listingId = _createListingERC1155(5, false, new address[](0));
        address[] memory none = new address[](0);
        vm.startPrank(seller);
        vm.resumeGasMetering();

        uint256 gasBefore = gasleft();
        market.updateListing(
            listingId,
            0.8 ether, // new price
            address(0), // newCurrency (ETH)
            address(0), // newDesiredTokenAddress
            0, // newDesiredTokenId
            0, // newDesiredErc1155Quantity (no swap)
            5, // same qty
            false, // whitelist
            false, // partialBuy
            none
        );
        uint256 gasUsed = gasBefore - gasleft();
        vm.pauseGasMetering();
        vm.stopPrank();

        Listing memory updated = getter.getListingByListingId(listingId);
        assertEq(updated.price, 0.8 ether);
        assertEq(updated.erc1155Quantity, 5);

        assertLe(gasUsed, UPDATE_1155_BUDGET, "ERC1155 updateListing gas regression");
        vm.resumeGasMetering();
    }
}
