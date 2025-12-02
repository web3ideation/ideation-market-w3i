// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

contract BuyerWhitelistFacetTest is MarketTestBase {
    // internal helper listERC1155WithOperatorAndWhitelistEnabled
    function listERC1155WithOperatorAndWhitelistEnabled(uint256 tokenId, uint256 quantity, uint256 price)
        internal
        returns (uint128 listingId)
    {
        // Snapshot the next id that will be assigned
        listingId = uint128(getter.getNextListingId());

        // approvals
        vm.startPrank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        erc1155.setApprovalForAll(operator, true);
        vm.stopPrank();

        // list
        vm.prank(operator);
        market.createListing(
            address(erc1155),
            tokenId,
            seller, // erc1155Holder
            price,
            address(0), // currency (ETH)
            address(0), // desiredTokenAddress (no swap)
            0, // desiredTokenId
            0, // desiredErc1155Quantity
            quantity, // erc1155Quantity
            true, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            new address[](0) // allowedBuyers
        );
    }

    function testBuyerWhitelist_AddNonexistentListingReverts() public {
        address[] memory addrs = new address[](1);
        addrs[0] = vm.addr(0xABCD);

        vm.expectRevert(BuyerWhitelist__ListingDoesNotExist.selector);
        buyers.addBuyerWhitelistAddresses(type(uint128).max, addrs);
    }

    function testBuyerWhitelist_AddZeroAddressReverts() public {
        _whitelistDefaultMocks();
        uint128 listingId = listERC1155WithOperatorAndWhitelistEnabled(1, 6, 10 ether);

        address[] memory addrs = new address[](1);
        addrs[0] = address(0);

        vm.prank(operator);
        vm.expectRevert(BuyerWhitelist__ZeroAddress.selector);
        buyers.addBuyerWhitelistAddresses(listingId, addrs);
    }

    function testBuyerWhitelist_AddExceedsMaxBatchReverts() public {
        _whitelistDefaultMocks();
        uint128 listingId = listERC1155WithOperatorAndWhitelistEnabled(1, 6, 10 ether);

        uint16 max = getter.getBuyerWhitelistMaxBatchSize();
        address[] memory addrs = new address[](uint256(max) + 1);
        for (uint256 i = 0; i < addrs.length; i++) {
            addrs[i] = vm.addr(0xF0000 + i);
        }

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(BuyerWhitelist__ExceedsMaxBatchSize.selector, max + 1));
        buyers.addBuyerWhitelistAddresses(listingId, addrs);
    }

    function testBuyerWhitelist_AddRemove_ByERC1155OperatorForAll() public {
        _whitelistDefaultMocks();
        uint128 listingId = listERC1155WithOperatorAndWhitelistEnabled(1, 6, 10 ether);

        address[] memory allow = new address[](1);
        allow[0] = vm.addr(0xB111);

        vm.prank(operator);
        buyers.addBuyerWhitelistAddresses(listingId, allow);
        assertTrue(getter.isBuyerWhitelisted(listingId, allow[0]));

        vm.prank(operator);
        buyers.removeBuyerWhitelistAddresses(listingId, allow);
        assertFalse(getter.isBuyerWhitelisted(listingId, allow[0]));

        vm.prank(seller);
        buyers.addBuyerWhitelistAddresses(listingId, allow);
        assertTrue(getter.isBuyerWhitelisted(listingId, allow[0]));
    }

    function testBuyerWhitelist_AddWhileDisabled_SucceedsAndStores() public {
        _whitelistDefaultMocks();

        vm.startPrank(seller);
        erc721.approve(address(diamond), 1);
        vm.stopPrank();

        vm.prank(seller);
        market.createListing(
            address(erc721),
            1,
            address(0),
            1 ether,
            address(0), // currency (ETH)
            address(0),
            0,
            0,
            0,
            false, // disabled
            false,
            new address[](0)
        );

        uint128 listingId = getter.getNextListingId() - 1;

        address[] memory addrs = new address[](1);
        addrs[0] = buyer;

        // Adding to the list is allowed while disabled
        vm.prank(seller);
        buyers.addBuyerWhitelistAddresses(listingId, addrs);

        // Stored correctly
        assertTrue(getter.isBuyerWhitelisted(listingId, buyer));

        // Optional: enable later without re-supplying the list; the prefilled entry should gate purchases.
        vm.prank(seller);
        market.updateListing(
            listingId,
            1 ether,
            address(0), // newCurrency (keep ETH)
            address(0),
            0,
            0, // no swap
            0, // still ERC721
            true, // enable whitelist
            false, // partialBuy
            new address[](0) // no new entries
        );
        // Now enforcement is on; a non-whitelisted address would be blocked.
        // (You already have tests for purchase gating—no need to duplicate here.)
    }

    // ERC721: seller cannot edit whitelist once token is transferred off-market
    function testERC721_WhitelistEdit_BlockedAfterOffMarketTransfer_BySeller() public {
        address[] memory allowed = new address[](1);
        allowed[0] = buyer;
        uint128 listingId = _createListingERC721(true, allowed);

        Listing memory listing = getter.getListingByListingId(listingId);
        address newOwner = vm.addr(0xA11CE);

        // off-market transfer by seller
        vm.prank(seller);
        IERC721(listing.tokenAddress).safeTransferFrom(seller, newOwner, listing.tokenId);

        // attempt to edit whitelist should revert with SellerIsNotERC721Owner(seller, newOwner)
        address[] memory addrs = new address[](1);
        addrs[0] = vm.addr(0xBEEF);

        vm.startPrank(seller);
        vm.expectRevert(abi.encodeWithSelector(BuyerWhitelist__SellerIsNotERC721Owner.selector, seller, newOwner));
        buyers.addBuyerWhitelistAddresses(listingId, addrs);
        vm.stopPrank();
    }

    // ERC721: anyone (incl. new owner) cannot edit whitelist after transfer
    function testERC721_WhitelistEdit_BlockedAfterOffMarketTransfer_ByAnyone() public {
        address[] memory allowed = new address[](1);
        allowed[0] = buyer;
        uint128 listingId = _createListingERC721(true, allowed);

        Listing memory listing = getter.getListingByListingId(listingId);
        address newOwner = vm.addr(0xCAFE);

        // off-market transfer by seller
        vm.prank(seller);
        IERC721(listing.tokenAddress).safeTransferFrom(seller, newOwner, listing.tokenId);

        // attempt to edit whitelist by a random address still hits the owner-mismatch check first
        address rando = vm.addr(0xDEAD);
        address[] memory addrs = new address[](1);
        addrs[0] = vm.addr(0xF00D);

        vm.startPrank(rando);
        vm.expectRevert(abi.encodeWithSelector(BuyerWhitelist__SellerIsNotERC721Owner.selector, seller, newOwner));
        buyers.addBuyerWhitelistAddresses(listingId, addrs);
        vm.stopPrank();
    }

    function testERC1155_WhitelistEdit_BlockedAfterBalanceFallsBelowListed_ByOperator() public {
        // Arrange: create an ERC1155 listing (e.g. qty=5) and pre-whitelist someone
        address[] memory seed = new address[](1);
        seed[0] = buyer;
        uint128 listingId = _createListingERC1155(5, true, seed);
        Listing memory listing = getter.getListingByListingId(listingId);

        // Move enough so seller balance < listed quantity
        uint256 sellerBal = erc1155.balanceOf(seller, listing.tokenId);
        address sink = vm.addr(0xBEEF);
        uint256 toMove = sellerBal - (listing.erc1155Quantity - 1); // leaves listedQty-1
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, sink, listing.tokenId, toMove, "");

        // Grant operator approval & try to edit whitelist as operator
        address operator = vm.addr(0xC0FFEE);
        vm.prank(seller);
        erc1155.setApprovalForAll(operator, true);

        address[] memory addrs = new address[](1);
        addrs[0] = vm.addr(0xCAFE);

        vm.startPrank(operator);
        vm.expectRevert(abi.encodeWithSelector(BuyerWhitelist__SellerIsNotERC1155Owner.selector, seller));
        buyers.addBuyerWhitelistAddresses(listingId, addrs);
        vm.stopPrank();
    }

    function testERC1155_WhitelistEdit_BlockedAfterBalanceFallsBelowListed_BySeller() public {
        // Arrange
        address[] memory seed = new address[](1);
        seed[0] = buyer;
        uint128 listingId = _createListingERC1155(5, true, seed);
        Listing memory listing = getter.getListingByListingId(listingId);

        // Move enough so seller balance < listed quantity
        uint256 sellerBal = erc1155.balanceOf(seller, listing.tokenId);
        address sink = vm.addr(0xABCD);
        uint256 toMove = sellerBal - (listing.erc1155Quantity - 1);
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, sink, listing.tokenId, toMove, "");

        // Seller tries to edit whitelist → should revert
        address[] memory addrs = new address[](1);
        addrs[0] = vm.addr(0xD00D);

        vm.startPrank(seller);
        vm.expectRevert(abi.encodeWithSelector(BuyerWhitelist__SellerIsNotERC1155Owner.selector, seller));
        buyers.addBuyerWhitelistAddresses(listingId, addrs);
        vm.stopPrank();
    }

    function testERC1155_WhitelistEdit_AllowedWhenBalanceEqualsListed() public {
        address[] memory seed = new address[](1);
        seed[0] = buyer;
        uint128 listingId = _createListingERC1155(5, true, seed);
        Listing memory listing = getter.getListingByListingId(listingId);

        // Reduce to exactly listedQty
        uint256 sellerBal = erc1155.balanceOf(seller, listing.tokenId);
        address sink = vm.addr(0xFEED);
        uint256 toMove = sellerBal - listing.erc1155Quantity; // leaves exactly listedQty
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, sink, listing.tokenId, toMove, "");

        // Seller can still update whitelist
        address[] memory addrs = new address[](1);
        addrs[0] = vm.addr(0xADD);
        vm.prank(seller);
        buyers.addBuyerWhitelistAddresses(listingId, addrs);
        assertTrue(getter.isBuyerWhitelisted(listingId, addrs[0]));
    }
}
