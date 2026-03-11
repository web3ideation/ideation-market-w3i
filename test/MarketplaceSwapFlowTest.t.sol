// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

/**
 * @title MarketplaceSwapFlowTest
 * @notice ERC721/ERC1155 swap-path behavior and swap-related guardrails.
 * @dev Coverage groups:
 * - Swap happy paths across ERC721<->ERC721, ERC721<->ERC1155, and ERC1155<->ERC1155 with/without ETH.
 * - Authorization and approval checks for desired-token holders/operators and marketplace approvals.
 * - Expected-term mismatch protection and stale-listing cleanup interactions.
 * - Create/update swap-parameter validation (type mismatches, no-swap invalid params, same-token swap rejection).
 * - Update behavior for transitioning listing economics while preserving swap intent.
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

    // updating an existing listing to request the same NFT must revert
    function testUpdate_SwapSameNFTReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.startPrank(seller);
        uint256 oldPrice = getter.getListingByListingId(id).price;
        vm.expectRevert(IdeationMarket__NoSwapForSameToken.selector);
        market.updateListing(id, oldPrice, address(0), address(erc721), 1, 0, 0, false, false, new address[](0));
        vm.stopPrank();
    }

    // update a swap-only listing to additionally require ETH payment
    function testUpdate_AddEthToSwapListing_Succeeds() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        vm.startPrank(seller);
        market.createListing(
            address(erc721), 1, address(0), 0, address(0), address(erc1155), 1, 1, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        uint32 feeNow = getter.getInnovationFee();
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingUpdated(
            id, address(erc721), 1, 0, 1 ether, address(0), feeNow, seller, false, false, address(erc1155), 1, 1
        );

        market.updateListing(id, 1 ether, address(0), address(erc1155), 1, 1, 0, false, false, new address[](0));
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

    function testSwap_ERC1155toERC721_HappyPath() public {
        // Listed collection must be whitelisted
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Seller lists 6 of id=500 wanting B#9
        MockERC721 b = new MockERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(b)); // optional but fine

        erc1155.mint(seller, 500, 6);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        b.mint(buyer, 9);
        vm.prank(buyer);
        b.approve(address(diamond), 9);

        vm.prank(seller);
        market.createListing(
            address(erc1155), 500, seller, 0, address(0), address(b), 9, 0, 6, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buy full quantity (partials disabled): erc1155PurchaseQuantity=6
        vm.prank(buyer);
        market.purchaseListing{value: 0}(id, 0, address(0), 6, address(b), 9, 0, 6, address(0));

        assertEq(erc1155.balanceOf(buyer, 500), 6);
        assertEq(erc1155.balanceOf(seller, 500), 0);
        assertEq(b.ownerOf(9), seller);
        // price=0, non-custodial -> no payments, diamond holds nothing
        assertEq(address(diamond).balance, 0);
    }

    function testSwap_ERC1155toERC1155_HappyPath() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155)); // listed collection

        // Seller lists 5 of idA wanting 3 of idB (same contract is fine)
        uint256 idA = 600;
        uint256 idB = 601;

        erc1155.mint(seller, idA, 5);
        erc1155.mint(buyer, idB, 4);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(buyer);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), idA, seller, 0, address(0), address(erc1155), idB, 3, 5, false, false, new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        // Buyer pays with 3 units of idB; receives 5 of idA
        vm.prank(buyer);
        market.purchaseListing{value: 0}(listingId, 0, address(0), 5, address(erc1155), idB, 3, 5, buyer);

        assertEq(erc1155.balanceOf(buyer, idA), 5);
        assertEq(erc1155.balanceOf(seller, idA), 0);
        assertEq(erc1155.balanceOf(buyer, idB), 1);
        assertEq(erc1155.balanceOf(seller, idB), 3);
    }

    function testSwap_ERC1155toERC1155_DesiredHolderNoMarketApprovalReverts_ThenSucceeds() public {
        // Whitelist the 1155 collection
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Balances:
        // - seller has tokenId=1 (listed)
        // - buyer  has tokenId=2 (desired)
        erc1155.mint(seller, 111, 10);
        erc1155.mint(buyer, 222, 10);

        // Seller approves marketplace; buyer (desired holder) does NOT yet.
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // Seller lists 10x id=1, pure swap for 10x id=2 (price=0)
        vm.prank(seller);
        market.createListing(
            address(erc1155),
            111,
            seller, // erc1155Holder
            0, // price (pure swap)
            address(0), // currency
            address(erc1155), // desiredTokenAddress
            222, // desiredTokenId
            10, // desiredErc1155Quantity
            10, // erc1155Quantity (listed)
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Attempt swap while desired holder (buyer) has NOT approved the marketplace -> revert
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.purchaseListing{value: 0}(
            id,
            0, // expectedPrice
            address(0), // expectedCurrency
            10, // expected listed erc1155Quantity
            address(erc1155), // expected desired token addr
            222, // expected desired tokenId
            10, // expected desired erc1155 qty
            10, // erc1155PurchaseQuantity
            buyer // desiredErc1155Holder
        );
        vm.stopPrank();

        // Now desired holder approves marketplace and swap succeeds
        vm.prank(buyer);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(buyer);
        market.purchaseListing{value: 0}(id, 0, address(0), 10, address(erc1155), 222, 10, 10, buyer);

        // Post-swap balances
        assertEq(erc1155.balanceOf(seller, 111), 0);
        assertEq(erc1155.balanceOf(seller, 222), 10);
        assertEq(erc1155.balanceOf(buyer, 111), 10);
        assertEq(erc1155.balanceOf(buyer, 222), 0);
    }

    /// Buyer has a pre-existing ERC1155 listing with qty = QL.
    /// After swapping away QS units, remaining == QL -> should NOT delete.
    function testSwapCleanupERC1155_RemainingEqualsListed_NotDeleted() public {
        // Fresh ERC721 for the listed side
        MockERC721 a = new MockERC721();
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(a));
        collections.addWhitelistedCollection(address(erc1155));
        vm.stopPrank();

        // Mint A#100 to seller and approve marketplace
        a.mint(seller, 100);
        vm.prank(seller);
        a.approve(address(diamond), 100);

        uint256 id1155 = 777;
        uint256 ql = 5;
        uint256 qs = 3;
        // Mint buyer QL + QS so remaining == QL after swap
        erc1155.mint(buyer, id1155, ql + qs);
        vm.prank(buyer);
        erc1155.setApprovalForAll(address(diamond), true);

        // Buyer pre-lists ERC1155(id=777) qty=QL
        vm.prank(buyer);
        market.createListing(
            address(erc1155), id1155, buyer, 5 ether, address(0), address(0), 0, 0, ql, false, false, new address[](0)
        );
        uint128 buyerListingId = getter.getNextListingId() - 1;

        // Seller lists A#100 wanting QS units of that ERC1155; price=0 (pure swap)
        vm.prank(seller);
        market.createListing(
            address(a), 100, address(0), 0, address(0), address(erc1155), id1155, qs, 0, false, false, new address[](0)
        );
        uint128 swapListingId = getter.getNextListingId() - 1;

        // Buyer performs the swap; must pass desiredErc1155Holder=buyer
        vm.prank(buyer);
        market.purchaseListing{value: 0}(swapListingId, 0, address(0), 0, address(erc1155), id1155, qs, 0, buyer);

        // Buyer pre-listing still exists because remaining == listed qty.
        Listing memory l = getter.getListingByListingId(buyerListingId);
        assertEq(l.erc1155Quantity, ql);
        assertEq(erc1155.balanceOf(buyer, id1155), ql);
    }

    /// Buyer's remaining balance falls BELOW their listed qty -> listing becomes invalid and can be cleaned.
    function testSwapCleanupERC1155_RemainingBelowListed_Deleted() public {
        // Fresh ERC721
        MockERC721 a = new MockERC721();
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(a));
        collections.addWhitelistedCollection(address(erc1155));
        vm.stopPrank();

        // Mint/approve A#101 to seller
        a.mint(seller, 101);
        vm.prank(seller);
        a.approve(address(diamond), 101);

        uint256 id1155 = 888;
        uint256 ql = 5;
        uint256 qs = 3;
        // Mint buyer QL + QS - 1 so post-swap remaining = QL - 1 (insufficient)
        erc1155.mint(buyer, id1155, ql + qs - 1);
        vm.prank(buyer);
        erc1155.setApprovalForAll(address(diamond), true);

        // Buyer pre-lists ERC1155(id=888) qty=QL
        vm.prank(buyer);
        market.createListing(
            address(erc1155), id1155, buyer, 5 ether, address(0), address(0), 0, 0, ql, false, false, new address[](0)
        );
        uint128 buyerListingId = getter.getNextListingId() - 1;

        // Seller lists ERC721 wanting QS of that ERC1155 (pure swap)
        vm.prank(seller);
        market.createListing(
            address(a), 101, address(0), 0, address(0), address(erc1155), id1155, qs, 0, false, false, new address[](0)
        );
        uint128 swapListingId = getter.getNextListingId() - 1;

        // Execute swap
        vm.prank(buyer);
        market.purchaseListing{value: 0}(swapListingId, 0, address(0), 0, address(erc1155), id1155, qs, 0, buyer);

        // No on-chain auto-cleanup: listing remains but is invalid because buyer's balance is now below listed qty.
        Listing memory stale = getter.getListingByListingId(buyerListingId);
        assertEq(stale.erc1155Quantity, ql);
        assertEq(erc1155.balanceOf(buyer, id1155), ql - 1);

        // Anyone can clean invalid listings.
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(
            buyerListingId, address(erc1155), id1155, buyer, operator
        );
        vm.prank(operator);
        market.cleanListing(buyerListingId);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, buyerListingId));
        getter.getListingByListingId(buyerListingId);
    }

    /// Pure 1155(A) <-> 1155(B) swap (price = 0).
    function testSwapERC1155toERC1155_PureSwap_HappyPath() public {
        // Listed 1155 (A) must be whitelisted; desired 1155 (B) only needs interface support.
        MockERC1155 tokenA = new MockERC1155();
        MockERC1155 tokenB = new MockERC1155();

        vm.prank(owner);
        collections.addWhitelistedCollection(address(tokenA));

        // Seller lists 10x A#1.
        tokenA.mint(seller, 1, 10);
        vm.prank(seller);
        tokenA.setApprovalForAll(address(diamond), true);

        // Buyer holds 6x B#7 and approves marketplace.
        tokenB.mint(buyer, 7, 6);
        vm.prank(buyer);
        tokenB.setApprovalForAll(address(diamond), true);

        // Pure swap: want 6x B#7 for 10x A#1.
        vm.prank(seller);
        market.createListing(
            address(tokenA), 1, seller, 0, address(0), address(tokenB), 7, 6, 10, false, false, new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        vm.prank(buyer);
        market.purchaseListing{value: 0}(listingId, 0, address(0), 10, address(tokenB), 7, 6, 10, buyer);

        assertEq(tokenA.balanceOf(buyer, 1), 10);
        assertEq(tokenB.balanceOf(seller, 7), 6);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingId));
        getter.getListingByListingId(listingId);
    }

    function testERC1155toERC1155Swap_Pure() public {
        // Token A is the shared fixture erc1155; deploy token B.
        MockERC1155 tokenB = new MockERC1155();

        // Whitelist both 1155 collections.
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        collections.addWhitelistedCollection(address(tokenB));
        vm.stopPrank();

        // Mint balances.
        uint256 idA = 11;
        uint256 idB = 22;
        uint256 qtyA = 50000000000;
        uint256 qtyB = 30000000000;

        erc1155.mint(seller, idA, qtyA);
        tokenB.mint(buyer, idB, qtyB);

        // Approvals.
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(buyer);
        tokenB.setApprovalForAll(address(diamond), true);

        // Seller lists A:idA qtyA desiring B:idB qtyB, price = 0 (pure swap).
        vm.prank(seller);
        market.createListing(
            address(erc1155),
            idA,
            seller,
            0,
            address(0),
            address(tokenB),
            idB,
            qtyB,
            qtyA,
            false,
            false,
            new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        // Execute swap by buyer (supplying tokenB from buyer).
        vm.prank(buyer);
        market.purchaseListing{value: 0}(listingId, 0, address(0), qtyA, address(tokenB), idB, qtyB, qtyA, buyer);

        // Post conditions: A moved seller->buyer, B moved buyer->seller, no ETH moved.
        assertEq(erc1155.balanceOf(seller, idA), 0);
        assertEq(erc1155.balanceOf(buyer, idA), qtyA);
        assertEq(tokenB.balanceOf(buyer, idB), 0);
        assertEq(tokenB.balanceOf(seller, idB), qtyB);
        assertEq(address(diamond).balance, 0);
    }

    /// 1155(A) <-> 1155(B) + ETH (seller charges ETH in addition to ERC1155 consideration).
    function testERC1155toERC1155Swap_WithEth() public {
        MockERC1155 tokenB = new MockERC1155();

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        collections.addWhitelistedCollection(address(tokenB));
        vm.stopPrank();

        uint256 idA = 33;
        uint256 idB = 44;
        uint256 qtyA = 6;
        uint256 qtyB = 2;
        uint256 price = 1 ether;

        erc1155.mint(seller, idA, 20);
        tokenB.mint(buyer, idB, 10);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(buyer);
        tokenB.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155),
            idA,
            seller,
            price,
            address(0),
            address(tokenB),
            idB,
            qtyB,
            qtyA,
            false,
            false,
            new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        vm.deal(buyer, price);
        vm.prank(buyer);
        market.purchaseListing{value: price}(
            listingId, price, address(0), qtyA, address(tokenB), idB, qtyB, qtyA, buyer
        );

        assertEq(erc1155.balanceOf(seller, idA), 20 - qtyA);
        assertEq(erc1155.balanceOf(buyer, idA), qtyA);
        assertEq(tokenB.balanceOf(buyer, idB), 10 - qtyB);
        assertEq(tokenB.balanceOf(seller, idB), qtyB);
        assertEq(address(diamond).balance, 0);
    }

    function testSwapERC1155toERC1155_WithEth_AndBuyerIsOperatorForDesired() public {
        MockERC1155 tokenA = new MockERC1155();
        MockERC1155 tokenB = new MockERC1155();

        // Listed 1155 must be whitelisted; desired 1155 only needs interface support.
        vm.prank(owner);
        collections.addWhitelistedCollection(address(tokenA));

        // Seller lists 8x tokenA#2.
        tokenA.mint(seller, 2, 8);
        vm.prank(seller);
        tokenA.setApprovalForAll(address(diamond), true);

        // Desired tokenB#9 is held by holder; buyer is approved operator for holder.
        address holder = makeAddr("holder_with_eth");
        tokenB.mint(holder, 9, 5);
        vm.prank(holder);
        tokenB.setApprovalForAll(buyer, true);
        vm.prank(holder);
        tokenB.setApprovalForAll(address(diamond), true);

        // Seller wants 5x tokenB#9 + 0.25 ETH for 8x tokenA#2.
        vm.prank(seller);
        market.createListing(
            address(tokenA), 2, seller, 0.25 ether, address(0), address(tokenB), 9, 5, 8, false, false, new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 0.25 ether}(
            listingId, 0.25 ether, address(0), 8, address(tokenB), 9, 5, 8, holder
        );

        assertEq(tokenA.balanceOf(buyer, 2), 8);
        assertEq(tokenB.balanceOf(seller, 9), 5);
        assertEq(seller.balance - sellerBalBefore, 0.2475 ether);
        assertEq(owner.balance - ownerBalBefore, 0.0025 ether);
        assertEq(address(diamond).balance, 0);
    }

    /// Buyer is authorized operator for desired ERC1155 holder (not holder) and swap succeeds.
    function testERC1155toERC1155Swap_BuyerIsOperatorForDesired() public {
        MockERC1155 tokenB = new MockERC1155();

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        collections.addWhitelistedCollection(address(tokenB));
        vm.stopPrank();

        address holder = makeAddr("holder");

        uint256 idA = 55;
        uint256 idB = 66;
        uint256 qtyA = 4;
        uint256 qtyB = 3;

        erc1155.mint(seller, idA, 10);
        tokenB.mint(holder, idB, 10);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // Holder authorizes both marketplace transfer and buyer operator authZ check.
        vm.startPrank(holder);
        tokenB.setApprovalForAll(address(diamond), true);
        tokenB.setApprovalForAll(buyer, true);
        vm.stopPrank();

        vm.prank(seller);
        market.createListing(
            address(erc1155),
            idA,
            seller,
            0,
            address(0),
            address(tokenB),
            idB,
            qtyB,
            qtyA,
            false,
            false,
            new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        vm.prank(buyer);
        market.purchaseListing{value: 0}(listingId, 0, address(0), qtyA, address(tokenB), idB, qtyB, qtyA, holder);

        assertEq(tokenB.balanceOf(holder, idB), 10 - qtyB);
        assertEq(tokenB.balanceOf(seller, idB), qtyB);
        assertEq(erc1155.balanceOf(buyer, idA), qtyA);
        assertEq(erc1155.balanceOf(seller, idA), 10 - qtyA);
    }
}
