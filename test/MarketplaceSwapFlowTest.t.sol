// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

/**
 * @title MarketplaceSwapFlowTest
 * @notice ERC721/ERC1155 swap-path behavior and swap-related guardrails.
 */
contract MarketplaceSwapFlowTest is MarketTestBase {
    function testSwap1155MissingHolderParamReverts() public {
        // Whitelist listed collection (ERC721). Desired (ERC1155) need not be whitelisted, only must pass interface check.
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        // Seller approval for the listed ERC721
        vm.prank(seller);
        erc721.approve(address(diamond), 1);

        // Create swap listing: want ERC1155 id=1, quantity=2; price=0 (pure swap)
        vm.prank(seller);
        market.createListing(
            address(erc721),
            1,
            seller,
            0, // price
            address(0), // currency
            address(erc1155), // desiredTokenAddress (ERC1155)
            1, // desiredTokenId
            2, // desiredErc1155Quantity > 0
            0, // erc1155Quantity (listed is ERC721)
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer attempts purchase but omits desiredErc1155Holder -> must revert early
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__WrongErc1155HolderParameter.selector);
        market.purchaseListing{value: 0}(
            id,
            0, // expectedPrice,
            address(0), // expectedCurrency
            0, // expectedErc1155Quantity (listed is ERC721)
            address(erc1155), // expectedDesiredTokenAddress
            1, // expectedDesiredTokenId
            2, // expectedDesiredErc1155Quantity
            0, // erc1155PurchaseQuantity (ERC721 path)
            address(0) // desiredErc1155Holder MISSING -> revert
        );
        vm.stopPrank();
    }

    // no-swap listing with zero price must revert
    function testCreatePriceZeroWithoutSwapReverts() public {
        _whitelistCollectionAndApproveERC721();

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__FreeListingsNotSupported.selector);
        market.createListing(
            address(erc721), 1, address(0), 0, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
    }

    // swap with same NFT reverts
    function testSwapWithSameNFTReverts() public {
        _whitelistCollectionAndApproveERC721();

        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__NoSwapForSameToken.selector);
        market.createListing(
            address(erc721),
            1,
            address(0),
            0, // price 0 (swap-only) ok
            address(0), // currency
            address(erc721), // desiredTokenAddress (same as listed)
            1, // desiredTokenId
            0, // desiredErc1155Quantity
            0, // erc1155Quantity
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();
    }

    /// Swap (ERC-721 <-> ERC-721): happy path plus stale pre-listing behavior.
    function testSwapERC721ToERC721_WithCleanupOfObsoleteListing() public {
        // Fresh ERC721 collections
        MockERC721 a = new MockERC721();
        MockERC721 b = new MockERC721();

        // Whitelist both
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(a));
        collections.addWhitelistedCollection(address(b));
        vm.stopPrank();

        // Mint A#100 to seller; B#200 to buyer
        a.mint(seller, 100);
        b.mint(buyer, 200);

        // Approvals: marketplace for A#100 (by seller), marketplace for B#200 (by buyer)
        vm.prank(seller);
        a.approve(address(diamond), 100);
        vm.prank(buyer);
        b.approve(address(diamond), 200);

        // Buyer pre-lists B#200 (to verify stale listing behavior after swap)
        vm.prank(buyer);
        market.createListing(
            address(b), 200, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 buyersBListingId = getter.getNextListingId() - 1;

        // Seller lists A#100 wanting B#200 (swap only, price=0)
        vm.prank(seller);
        market.createListing(
            address(a), 100, address(0), 0, address(0), address(b), 200, 0, 0, false, false, new address[](0)
        );
        uint128 swapId = getter.getNextListingId() - 1;

        // Buyer executes swap; pays 0; expected fields must match.
        vm.prank(buyer);
        market.purchaseListing{value: 0}(swapId, 0, address(0), 0, address(b), 200, 0, 0, address(0));

        // Ownership swapped
        assertEq(a.ownerOf(100), buyer);
        assertEq(b.ownerOf(200), seller);

        // No on-chain auto-cleanup: buyer's old listing remains, but is now invalid.
        Listing memory stale = getter.getListingByListingId(buyersBListingId);
        assertEq(stale.seller, buyer);
        assertEq(stale.tokenAddress, address(b));
        assertEq(stale.tokenId, 200);

        // Buying the stale listing fails because stored seller no longer owns B#200.
        address otherBuyer = vm.addr(0xB0B);
        vm.deal(otherBuyer, 2 ether);
        vm.prank(otherBuyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__SellerNotTokenOwner.selector, buyersBListingId));
        market.purchaseListing{value: 1 ether}(
            buyersBListingId, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0)
        );
    }

    function testSwapERC721ToERC1155_OperatorNoMarketApprovalReverts_ThenSucceeds() public {
        // Whitelist collections
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc721)); // unused but harmless
        collections.addWhitelistedCollection(address(erc1155));
        vm.stopPrank();

        // Mint ERC721 to seller (will be swapped away)
        erc721.mint(seller, 111);
        vm.prank(seller);
        erc721.approve(address(diamond), 111);

        // Use a fresh ERC1155 id so seller has zero starting balance for this id
        uint256 desiredId = 2;
        erc1155.mint(operator, desiredId, 10);

        // Buyer is operator of 'operator', but marketplace NOT approved yet
        vm.prank(operator);
        erc1155.setApprovalForAll(buyer, true);

        // Seller lists ERC721 wanting 6 units of ERC1155 desiredId
        vm.prank(seller);
        market.createListing(
            address(erc721),
            111,
            address(0), // erc1155Holder (N/A for ERC721)
            0, // price (swap only)
            address(0), // currency
            address(erc1155), // desiredTokenAddress
            desiredId, // desiredTokenId
            6, // desiredErc1155Quantity
            0, // erc1155Quantity (ERC721)
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Attempt purchase -> revert: holder hasn't approved marketplace
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(erc1155), desiredId, 6, 0, operator);

        // Grant marketplace approval by holder; try again -> succeeds
        vm.prank(operator);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(buyer);
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(erc1155), desiredId, 6, 0, operator);

        // Post-conditions
        assertEq(erc721.ownerOf(111), buyer);
        assertEq(erc1155.balanceOf(operator, desiredId), 4);
        assertEq(erc1155.balanceOf(seller, desiredId), 6);
    }
}
