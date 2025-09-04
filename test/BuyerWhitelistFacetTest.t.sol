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
        vm.expectRevert(BuyerWhitelist__ExceedsMaxBatchSize.selector);
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
}
