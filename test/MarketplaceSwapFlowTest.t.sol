// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

/**
 * @title MarketplaceSwapFlowTest
 * @notice ERC721/ERC1155 swap-path behavior and swap-related guardrails.
 */
contract MarketplaceSwapFlowTest is MarketTestBase {
    function testWhitelist_BlocksSwap_ERC721toERC721() public {
        MockERC721 a = new MockERC721();
        MockERC721 b = new MockERC721();

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(a));
        collections.addWhitelistedCollection(address(b));
        vm.stopPrank();

        a.mint(seller, 100);
        b.mint(operator, 200); // operator will be the allowed swapper

        vm.prank(seller);
        a.approve(address(diamond), 100);
        vm.prank(operator);
        b.approve(address(diamond), 200);

        address[] memory allow = new address[](1);
        allow[0] = operator;

        vm.prank(seller);
        market.createListing(address(a), 100, address(0), 0, address(0), address(b), 200, 0, 0, true, false, allow);
        uint128 id = getter.getNextListingId() - 1;

        // Non-whitelisted buyer is blocked
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__BuyerNotWhitelisted.selector, id, buyer));
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(b), 200, 0, 0, address(0));

        // Whitelisted operator succeeds
        vm.prank(operator);
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(b), 200, 0, 0, address(0));
        assertEq(a.ownerOf(100), operator);
        assertEq(b.ownerOf(200), seller);
    }

    function testWhitelist_BlocksSwap_ERC721toERC1155() public {
        MockERC721 a = new MockERC721();

        vm.prank(owner);
        collections.addWhitelistedCollection(address(a)); // listed collection

        // Seller has A#1; operator has desired 1155
        a.mint(seller, 1);
        vm.prank(seller);
        a.approve(address(diamond), 1);

        erc1155.mint(operator, 77, 5);
        vm.prank(operator);
        erc1155.setApprovalForAll(address(diamond), true);

        address[] memory allow = new address[](1);
        allow[0] = operator;

        // Want 3 units of id=77
        vm.prank(seller);
        market.createListing(address(a), 1, address(0), 0, address(0), address(erc1155), 77, 3, 0, true, false, allow);
        uint128 id = getter.getNextListingId() - 1;

        // Non-whitelisted buyer blocked
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__BuyerNotWhitelisted.selector, id, buyer));
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(erc1155), 77, 3, 0, operator);

        // Whitelisted operator succeeds
        vm.prank(operator);
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(erc1155), 77, 3, 0, operator);
        assertEq(a.ownerOf(1), operator);
        assertEq(erc1155.balanceOf(operator, 77), 2);
        assertEq(erc1155.balanceOf(seller, 77), 3);
    }

    function testSwapWithEth_ERC721toERC721_HappyPath() public {
        // Fresh collections to avoid interference with other tests
        MockERC721 a = new MockERC721();
        MockERC721 b = new MockERC721();

        // Only the listed collection must be whitelisted, but whitelisting both is harmless
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(a));
        collections.addWhitelistedCollection(address(b));
        vm.stopPrank();

        // Seller owns A#100, buyer owns B#200
        a.mint(seller, 100);
        b.mint(buyer, 200);

        // Approvals for marketplace transfers
        vm.prank(seller);
        a.approve(address(diamond), 100);
        vm.prank(buyer);
        b.approve(address(diamond), 200);

        // Seller lists A#100 wanting B#200 *and* 0.4 ETH
        vm.prank(seller);
        market.createListing(
            address(a),
            100,
            seller,
            0.4 ether, // price > 0: buyer must pay ETH in addition to providing desired token
            address(0),
            address(b), // desired ERC721
            200,
            0, // desiredErc1155Quantity = 0 (since desired is ERC721)
            0, // erc1155Quantity = 0 (listed is ERC721)
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer executes swap + ETH
        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;
        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);

        uint32 feeSnap = getter.getListingByListingId(id).feeRate;
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingPurchased(
            id, address(a), 100, 0, false, 0.4 ether, address(0), feeSnap, seller, buyer, address(b), 200, 0
        );

        market.purchaseListing{value: 0.4 ether}(
            id,
            0.4 ether, // expectedPrice
            address(0), // expectedCurrency
            0, // expectedErc1155Quantity (listed is ERC721)
            address(b), // expectedDesiredTokenAddress
            200, // expectedDesiredTokenId
            0, // expectedDesiredErc1155Quantity
            0, // erc1155PurchaseQuantity (ERC721 path)
            address(0) // desiredErc1155Holder N/A for ERC721
        );
        vm.stopPrank();

        // Ownership swapped and proceeds credited (fee 1% of 0.4 = 0.004)
        assertEq(a.ownerOf(100), buyer);
        assertEq(b.ownerOf(200), seller);
        assertEq(seller.balance - sellerBalBefore, 0.396 ether);
        assertEq(owner.balance - ownerBalBefore, 0.004 ether);
    }

    function testSwapWithEth_ERC721toERC1155_HappyPath() public {
        // Listed collection must be whitelisted; desired ERC1155 only needs to pass interface checks.
        MockERC721 a = new MockERC721();
        MockERC1155 m1155 = new MockERC1155();

        vm.prank(owner);
        collections.addWhitelistedCollection(address(a));

        // Seller owns A#101
        a.mint(seller, 101);
        vm.prank(seller);
        a.approve(address(diamond), 101);

        // Buyer holds 5 units of desired ERC1155 id=77 and approves marketplace
        uint256 desiredId = 77;
        m1155.mint(buyer, desiredId, 5);
        vm.prank(buyer);
        m1155.setApprovalForAll(address(diamond), true);

        // Seller lists A#101 wanting 3x (ERC1155 id=77) *and* 0.3 ETH
        vm.prank(seller);
        market.createListing(
            address(a),
            101,
            address(0),
            0.3 ether, // ETH component
            address(0), // currency
            address(m1155), // desired ERC1155
            desiredId,
            3, // desiredErc1155Quantity > 0
            0, // erc1155Quantity = 0 (listed is ERC721)
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer executes swap + ETH (must pass desiredErc1155Holder)
        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;
        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);

        uint32 feeSnap = getter.getListingByListingId(id).feeRate;
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingPurchased(
            id, address(a), 101, 0, false, 0.3 ether, address(0), feeSnap, seller, buyer, address(m1155), desiredId, 3
        );

        market.purchaseListing{value: 0.3 ether}(
            id,
            0.3 ether, // expectedPrice
            address(0), // expectedCurrency
            0, // expectedErc1155Quantity (listed is ERC721)
            address(m1155), // expectedDesiredTokenAddress
            desiredId, // expectedDesiredTokenId
            3, // expectedDesiredErc1155Quantity
            0, // erc1155PurchaseQuantity (ERC721 path)
            buyer // desiredErc1155Holder (buyer is the holder)
        );
        vm.stopPrank();

        // Token and balance changes; proceeds reflect fee 1% of 0.3 = 0.003
        assertEq(a.ownerOf(101), buyer);
        assertEq(m1155.balanceOf(buyer, desiredId), 2);
        assertEq(m1155.balanceOf(seller, desiredId), 3);
        assertEq(seller.balance - sellerBalBefore, 0.297 ether);
        assertEq(owner.balance - ownerBalBefore, 0.003 ether);
    }

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

    /// Swap (ERC721→ERC1155) purchase must revert if buyer has insufficient ERC1155 balance.
    function testSwapERC1155DesiredBalanceInsufficientReverts() public {
        // fresh ERC721 collection
        MockERC721 a = new MockERC721();
        a.mint(seller, 1);
        vm.prank(owner);
        collections.addWhitelistedCollection(address(a));
        vm.prank(seller);
        a.approve(address(diamond), 1);

        // Seller lists token #1 wanting 5 units of ERC1155 id=1
        vm.prank(seller);
        market.createListing(
            address(a), 1, address(0), 0, address(0), address(erc1155), 1, 5, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer only holds 2 units of that ERC1155 and approves
        erc1155.mint(buyer, 1, 2);
        vm.prank(buyer);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IdeationMarket__InsufficientSwapTokenBalance.selector,
                5, // required
                2 // available
            )
        );
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(erc1155), 1, 5, 0, buyer);
    }

    /// Swap (ERC721→ERC721) purchase must revert if buyer has not approved desired token for marketplace transfer.
    function testSwapERC721DesiredNotApprovedReverts() public {
        MockERC721 a = new MockERC721();
        MockERC721 b = new MockERC721();
        a.mint(seller, 10);
        b.mint(buyer, 20);

        vm.prank(owner);
        collections.addWhitelistedCollection(address(a));
        vm.prank(seller);
        a.approve(address(diamond), 10);

        vm.prank(seller);
        market.createListing(
            address(a), 10, address(0), 0, address(0), address(b), 20, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer did not approve b#20 to marketplace
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(b), 20, 0, 0, address(0));
    }

    /// Swap (ERC721→ERC721) must revert if buyer is neither owner nor approved operator of desired token.
    function testSwapERC721BuyerNotOwnerOrOperatorReverts() public {
        MockERC721 a = new MockERC721();
        MockERC721 b = new MockERC721();
        a.mint(seller, 1);
        b.mint(operator, 2); // desired token held by operator

        vm.prank(owner);
        collections.addWhitelistedCollection(address(a));
        vm.prank(seller);
        a.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(a), 1, address(0), 0, address(0), address(b), 2, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // buyer attempts purchase but has no rights over b#2
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotAuthorizedOperator.selector);
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(b), 2, 0, 0, address(0));
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

    function testUpdatePriceZeroWithoutSwapReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__FreeListingsNotSupported.selector);
        market.updateListing(id, 0, address(0), address(0), 0, 0, 0, false, false, new address[](0));
    }

    /// No-swap listings must not specify a non-zero desiredTokenId.
    function testInvalidNoSwapDesiredTokenIdReverts() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__InvalidNoSwapParameters.selector);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 1, 0, 0, false, false, new address[](0)
        );
    }

    /// No-swap listings must not specify a non-zero desiredErc1155Quantity.
    function testInvalidNoSwapDesiredErc1155QuantityReverts() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__InvalidNoSwapParameters.selector);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 1, 0, false, false, new address[](0)
        );
    }

    /// No-swap updates must not specify a non-zero desiredTokenId.
    function testUpdateInvalidNoSwapDesiredTokenIdReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__InvalidNoSwapParameters.selector);
        market.updateListing(id, 1 ether, address(0), address(0), 1, 0, 0, false, false, new address[](0));
    }

    /// No-swap updates must not specify a non-zero desiredErc1155Quantity.
    function testUpdateInvalidNoSwapDesiredErc1155QuantityReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__InvalidNoSwapParameters.selector);
        market.updateListing(id, 1 ether, address(0), address(0), 0, 1, 0, false, false, new address[](0));
    }

    /// Swap listings requiring ERC1155 (desiredErc1155Quantity > 0) must specify an ERC1155 contract.
    function testSwapDesiredTypeMismatchERC1155Reverts() public {
        _whitelistCollectionAndApproveERC721();

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotSupportedTokenStandard.selector);
        market.createListing(
            address(erc721), 1, address(0), 0, address(0), address(erc721), 2, 1, 0, false, false, new address[](0)
        );
    }

    /// Swap updates requiring ERC1155 (desiredErc1155Quantity > 0) must specify an ERC1155 contract.
    function testUpdateSwapDesiredTypeMismatchERC1155Reverts() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotSupportedTokenStandard.selector);
        market.updateListing(id, 0, address(0), address(erc721), 2, 1, 0, false, false, new address[](0));
    }

    /// Swap listings requiring ERC721 (desiredErc1155Quantity == 0) must specify an ERC721 contract.
    function testSwapDesiredTypeMismatchERC721Reverts() public {
        _whitelistCollectionAndApproveERC721();

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotSupportedTokenStandard.selector);
        market.createListing(
            address(erc721), 1, address(0), 0, address(0), address(erc1155), 1, 0, 0, false, false, new address[](0)
        );
    }

    /// Swap updates requiring ERC721 (desiredErc1155Quantity == 0) must specify an ERC721 contract.
    function testUpdateSwapDesiredTypeMismatchERC721Reverts() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotSupportedTokenStandard.selector);
        market.updateListing(id, 0, address(0), address(erc1155), 1, 0, 0, false, false, new address[](0));
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

    /// Partial buys cannot be enabled on swap listings (desiredTokenAddress != 0).
    function testPartialBuyWithSwapReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 102;
        erc1155.mint(seller, tokenId, 4);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // Listing wants a swap and partials are enabled, so create must revert.
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__PartialBuyNotPossible.selector);
        market.createListing(
            address(erc1155),
            tokenId,
            seller,
            4 ether,
            address(0),
            address(erc721),
            1,
            0,
            4,
            false,
            true,
            new address[](0)
        );
    }

    /// Updating partial buy while introducing a swap must revert.
    function testUpdatePartialBuyWithSwapReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 204;
        erc1155.mint(seller, tokenId, 5);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), tokenId, seller, 5 ether, address(0), address(0), 0, 0, 5, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__PartialBuyNotPossible.selector);
        market.updateListing(id, 5 ether, address(0), address(erc721), 1, 0, 5, false, true, new address[](0));
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

    function testSwapExpectedDesiredFieldsMismatchReverts() public {
        // Create 721->721 swap listing (price 0)
        _whitelistCollectionAndApproveERC721();
        MockERC721 other = new MockERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(other));
        other.mint(buyer, 42);
        vm.prank(buyer);
        other.approve(address(diamond), 42);

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 0, address(0), address(other), 42, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Wrong expectedDesiredTokenId must trip listing freshness guard.
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__ListingTermsChanged.selector);
        market.purchaseListing{value: 0}(id, 0, address(0), 0, address(other), 999, 0, 0, address(0));
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
