// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import {Getter__ListingNotFound} from "../src/facets/GetterFacet.sol";
import {
    IdeationMarket__CollectionNotWhitelisted,
    IdeationMarket__AlreadyListed,
    IdeationMarket__PriceNotMet,
    IdeationMarket__BuyerNotWhitelisted,
    IdeationMarket__NotAuthorizedToCancel,
    IdeationMarketFacet
} from "../src/facets/IdeationMarketFacet.sol";

/**
 * @title MarketplaceCoreFlowTest
 * @notice Baseline marketplace lifecycle tests (create, update, purchase, cancel, clean)
 * @dev Keep only core happy/revert flow coverage here; specialized edge/security/integration cases stay in topical suites.
 */
contract MarketplaceCoreFlowTest is MarketTestBase {
    // whitelist of exactly MAX_BATCH succeeds on create; >MAX_BATCH reverts
    function testCreateWithWhitelistExactlyMaxBatchSucceeds() public {
        _whitelistCollectionAndApproveERC721();

        address[] memory buyersList = new address[](MAX_BATCH);
        for (uint256 i = 0; i < buyersList.length; i++) {
            buyersList[i] = vm.addr(10_000 + i);
        }

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, true, false, buyersList
        );

        uint128 id = getter.getNextListingId() - 1;
        // Spot check a couple of entries made it in
        assertTrue(getter.isBuyerWhitelisted(id, buyersList[0]));
        assertTrue(getter.isBuyerWhitelisted(id, buyersList[buyersList.length - 1]));
    }

    function testCreateWithWhitelistOverMaxBatchReverts() public {
        _whitelistCollectionAndApproveERC721();

        address[] memory tooMany = new address[](uint256(MAX_BATCH) + 1);
        for (uint256 i = 0; i < tooMany.length; i++) {
            tooMany[i] = vm.addr(20_000 + i);
        }

        vm.startPrank(seller);
        vm.expectRevert(abi.encodeWithSelector(BuyerWhitelist__ExceedsMaxBatchSize.selector, tooMany.length));
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, true, false, tooMany
        );
        vm.stopPrank();
    }

    // create with whitelist enabled and empty list should succeed, with no buyer pre-whitelisted
    function testCreateWithWhitelistEnabledEmptyArrayOK() public {
        _whitelistCollectionAndApproveERC721();

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, true, false, new address[](0)
        );

        uint128 id = getter.getNextListingId() - 1;
        Listing memory ls = getter.getListingByListingId(id);
        assertTrue(ls.buyerWhitelistEnabled);

        // Sanity: no addresses are whitelisted yet
        assertFalse(getter.isBuyerWhitelisted(id, buyer));
        assertFalse(getter.isBuyerWhitelisted(id, seller));
    }

    // update can enable whitelist with an empty list and should not auto-whitelist anyone
    function testUpdateEnableWhitelistWithEmptyArrayOK() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.prank(seller);
        market.updateListing(id, 1 ether, address(0), address(0), 0, 0, 0, true, false, new address[](0));

        Listing memory ls = getter.getListingByListingId(id);
        assertTrue(ls.buyerWhitelistEnabled);

        // Sanity: no addresses are whitelisted yet
        assertFalse(getter.isBuyerWhitelisted(id, buyer));
        assertFalse(getter.isBuyerWhitelisted(id, seller));
    }

    // disabling whitelist on update should re-open purchase access
    function testUpdateDisableWhitelistThenOpenPurchase() public {
        _whitelistCollectionAndApproveERC721();

        address[] memory allowed = new address[](1);
        allowed[0] = operator;

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, true, false, allowed
        );
        uint128 id = getter.getNextListingId() - 1;

        // Disable whitelist on update
        vm.prank(seller);
        market.updateListing(id, 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));

        // Now anyone can buy
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        assertEq(erc721.ownerOf(1), buyer);
    }

    function testCreateWithWhitelistDisabledNonEmptyListReverts() public {
        _whitelistCollectionAndApproveERC721();

        address[] memory bogus = new address[](1);
        bogus[0] = buyer;

        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__WhitelistDisabled.selector);
        market.createListing(
            address(erc721),
            1,
            address(0),
            1 ether,
            address(0), // currency
            address(0), // desiredTokenAddress
            0, // desiredTokenId
            0, // desiredErc1155Quantity
            0, // erc1155Quantity
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            bogus // non-empty -> must revert per facet
        );
        vm.stopPrank();
    }

    function testCreateWithZeroTokenAddressReverts() public {
        // No whitelist entry can exist for address(0), expect revert
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__CollectionNotWhitelisted.selector, address(0)));
        market.createListing(
            address(0), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
    }

    // buyer not on whitelist cannot purchase when whitelist enabled
    function testWhitelistPreventsPurchase() public {
        _whitelistCollectionAndApproveERC721();

        // Whitelist someone else (not the buyer) so creation succeeds

        address[] memory allowed = new address[](1);
        allowed[0] = operator;

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, true, false, allowed
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__BuyerNotWhitelisted.selector, id, buyer));
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    // buyer on whitelist can purchase and listing is removed
    function testWhitelistedBuyerPurchaseSuccess() public {
        _whitelistCollectionAndApproveERC721();

        address[] memory allowed = new address[](1);
        allowed[0] = buyer;

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, true, false, allowed
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        assertEq(erc721.ownerOf(1), buyer);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    // update keeps same listingId even with other activity in between
    function testUpdateKeepsListingId() public {
        _whitelistCollectionAndApproveERC721();

        // First listing (id=1)
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id1 = 1;

        // Create & cancel another listing to disturb state
        vm.prank(seller);
        erc721.approve(address(diamond), 2);
        vm.prank(seller);
        market.createListing(
            address(erc721), 2, address(0), 2 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id2 = 2;
        vm.prank(seller);
        market.cancelListing(id2);

        // Update the first listing, id must remain 1
        vm.prank(seller);
        market.updateListing(id1, 3 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));

        Listing memory l = getter.getListingByListingId(id1);
        assertEq(l.listingId, 1);
        assertEq(l.price, 3 ether);
    }

    function testCreateListingERC721() public {
        _whitelistCollectionAndApproveERC721();
        vm.startPrank(seller);

        uint128 expectedId = getter.getNextListingId();
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCreated(
            expectedId,
            address(erc721),
            1,
            0,
            1 ether,
            address(0),
            getter.getInnovationFee(),
            seller,
            false,
            false,
            address(0),
            0,
            0
        );

        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        uint128 id = getter.getNextListingId() - 1;
        Listing memory l = getter.getListingByListingId(id);
        assertEq(l.listingId, id);
        assertEq(l.tokenAddress, address(erc721));
        assertEq(l.tokenId, 1);
        assertEq(l.price, 1 ether);
        assertEq(l.seller, seller);
        assertEq(l.erc1155Quantity, 0);
        assertFalse(l.buyerWhitelistEnabled);
        assertFalse(l.partialBuyEnabled);

        uint128 activeId = getter.getActiveListingIdByERC721(address(erc721), 1);
        assertEq(activeId, id);
    }

    function testCreateListingERC721Reverts() public {
        vm.startPrank(seller);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__CollectionNotWhitelisted.selector, address(erc721)));
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        _whitelistCollectionAndApproveERC721();
        vm.startPrank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.expectRevert(IdeationMarket__AlreadyListed.selector);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();
    }

    function testPurchaseListingERC721() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.deal(buyer, 10 ether);

        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__PriceNotMet.selector, id, 1 ether, 0.5 ether));
        market.purchaseListing{value: 0.5 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        vm.startPrank(buyer);

        uint32 feeSnap = getter.getListingByListingId(id).feeRate;
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingPurchased(
            id, address(erc721), 1, 0, false, 1 ether, address(0), feeSnap, seller, buyer, address(0), 0, 0
        );

        uint256 sellerBalanceBefore = seller.balance;
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
        assertEq(erc721.ownerOf(1), buyer);

        uint256 sellerBalanceAfter = seller.balance;
        assertEq(sellerBalanceAfter - sellerBalanceBefore, 0.99 ether);
    }

    function testERC721PurchaseWithNonZero1155QuantityReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__InvalidPurchaseQuantity.selector);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 1, address(0));
    }

    function testUpdateListing() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__NotAuthorizedOperator.selector);
        market.updateListing(id, 2 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));
        vm.stopPrank();

        vm.startPrank(seller);
        uint32 feeNow = getter.getInnovationFee();
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingUpdated(
            id, address(erc721), 1, 0, 2 ether, address(0), feeNow, seller, false, false, address(0), 0, 0
        );
        market.updateListing(id, 2 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));
        vm.stopPrank();

        Listing memory updated = getter.getListingByListingId(id);
        assertEq(updated.price, 2 ether);

        address[] memory newBuyers = new address[](1);
        newBuyers[0] = buyer;
        vm.startPrank(seller);
        market.updateListing(id, 2 ether, address(0), address(0), 0, 0, 0, true, false, newBuyers);
        vm.stopPrank();

        assertTrue(getter.isBuyerWhitelisted(id, buyer));
    }

    function testUpdateNonexistentListingReverts() public {
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotListed.selector);
        market.updateListing(999_999, 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));
    }

    function testCancelListing() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__NotAuthorizedToCancel.selector);
        market.cancelListing(id);
        vm.stopPrank();

        vm.startPrank(seller);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceled(id, address(erc721), 1, seller, seller);

        market.cancelListing(id);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }
}
