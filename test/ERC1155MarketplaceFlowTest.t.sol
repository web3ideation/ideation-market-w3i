// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import {
    IdeationMarket__InvalidUnitPrice,
    IdeationMarket__InvalidPurchaseQuantity,
    IdeationMarket__PartialBuyNotPossible,
    IdeationMarket__WrongQuantityParameter,
    IdeationMarketFacet
} from "../src/facets/IdeationMarketFacet.sol";

/**
 * @title ERC1155MarketplaceFlowTest
 * @notice ERC1155-specific listing, update, purchase, and quantity rules.
 */
contract ERC1155MarketplaceFlowTest is MarketTestBase {
    /// Listing ERC1155 more than holder's balance should revert with SellerInsufficientTokenBalance.
    function testERC1155CreateInsufficientBalanceReverts() public {
        // Mint only 5 units of a fresh tokenId
        uint256 tokenId = 99;
        erc1155.mint(seller, tokenId, 5);

        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IdeationMarket__SellerInsufficientTokenBalance.selector,
                10, // required
                5 // available
            )
        );
        market.createListing(
            address(erc1155),
            tokenId,
            seller,
            1 ether,
            address(0), // currency
            address(0), // desiredTokenAddress
            0,
            0,
            10, // quantity > balance
            false,
            false,
            new address[](0)
        );
    }

    /// ERC1155 listing without marketplace approval must revert NotApprovedForMarketplace.
    function testERC1155CreateWithoutMarketplaceApprovalReverts() public {
        uint256 tokenId = 100;
        erc1155.mint(seller, tokenId, 5);

        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Seller intentionally does not call setApprovalForAll(address(diamond), true)

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.createListing(
            address(erc1155), tokenId, seller, 1 ether, address(0), address(0), 0, 0, 5, false, false, new address[](0)
        );
    }

    function testTogglePartialBuyEnabledWithoutPriceChange() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Flip partials to disabled; keep qty the same (ERC1155 stays ERC1155)
        vm.prank(seller);
        market.updateListing(id, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0));

        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__PartialBuyNotPossible.selector);
        market.purchaseListing{value: 4 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 4, address(0));
        vm.stopPrank();

        Listing memory l = getter.getListingByListingId(id);
        assertEq(l.price, 10 ether);
        assertFalse(l.partialBuyEnabled);
        assertEq(l.erc1155Quantity, 10);
    }

    /// Updating partial buy on a too-small ERC1155 quantity must revert.
    function testUpdatePartialBuyWithSmallQuantityReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 203;
        erc1155.mint(seller, tokenId, 1);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), tokenId, seller, 1 ether, address(0), address(0), 0, 0, 1, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__PartialBuyNotPossible.selector);
        market.updateListing(id, 1 ether, address(0), address(0), 0, 0, 1, false, true, new address[](0));
    }

    /// Updating an ERC721 listing to ERC1155 semantics (newErc1155Quantity > 0) must revert.
    function testUpdateFlipERC721ToERC1155Reverts() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__WrongQuantityParameter.selector);
        market.updateListing(id, 1 ether, address(0), address(0), 0, 0, 5, false, false, new address[](0));
    }

    /// Updating ERC1155 listing with revoked marketplace approval must revert.
    function testERC1155UpdateApprovalRevokedReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), false);

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.updateListing(id, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0));
    }

    /// Updating quantity greater than seller's ERC1155 balance must revert.
    function testERC1155UpdateBalanceTooLowReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 202;
        erc1155.mint(seller, tokenId, 5);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), tokenId, seller, 5 ether, address(0), address(0), 0, 0, 5, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        erc1155.safeTransferFrom(seller, buyer, tokenId, 3, "");

        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__SellerInsufficientTokenBalance.selector, 5, 2));
        market.updateListing(id, 5 ether, address(0), address(0), 0, 0, 5, false, false, new address[](0));
    }

    /// Updating an ERC1155 listing to ERC721 semantics (newErc1155Quantity == 0) must revert.
    function testUpdateFlipERC1155ToERC721Reverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 200;
        erc1155.mint(seller, tokenId, 5);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), tokenId, seller, 5 ether, address(0), address(0), 0, 0, 5, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__WrongQuantityParameter.selector);
        market.updateListing(id, 5 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));
    }

    /// Only seller or its approved operator may update an ERC1155 listing.
    function testERC1155UpdateUnauthorizedOperatorReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 201;
        erc1155.mint(seller, tokenId, 5);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), tokenId, seller, 5 ether, address(0), address(0), 0, 0, 5, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotAuthorizedOperator.selector);
        market.updateListing(id, 5 ether, address(0), address(0), 0, 0, 5, false, false, new address[](0));
    }

    function testERC1155HolderDifferentFromSellerHappyPath() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        erc1155.mint(operator, 1, 10);

        // Holder approvals
        vm.prank(operator);
        erc1155.setApprovalForAll(seller, true); // seller may act for holder
        vm.prank(operator);
        erc1155.setApprovalForAll(address(diamond), true); // marketplace may transfer

        // Seller creates the listing on behalf of holder
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, operator, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        Listing memory beforeBuy = getter.getListingByListingId(id);
        assertEq(beforeBuy.seller, operator);

        uint256 operatorBefore = operator.balance;
        uint256 ownerBefore = owner.balance;
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 10 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 10, address(0));

        // Tokens left holder -> buyer
        assertEq(erc1155.balanceOf(operator, 1), 0);
        assertEq(erc1155.balanceOf(buyer, 1), 10);

        // Proceeds go to the holder (the Listing.seller), not msg.sender(seller)
        assertEq(operator.balance - operatorBefore, 9.9 ether);
        assertEq(owner.balance - ownerBefore, 0.1 ether);
        assertEq(seller.balance, 0);
    }

    /// After listing an ERC1155, if seller's balance drops below listed quantity, purchase reverts.
    function testERC1155PurchaseSellerBalanceDroppedReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 400;
        erc1155.mint(seller, tokenId, 10);

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

        // Seller transfers away 5 units leaving 5 (less than listed 10).
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, buyer, tokenId, 5, "");

        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IdeationMarket__SellerInsufficientTokenBalance.selector,
                10, // required
                5 // available
            )
        );
        market.purchaseListing{value: 10 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 10, address(0));
    }

    /// If marketplace approval is revoked for an ERC1155 listing, purchase reverts.
    function testERC1155PurchaseMarketplaceApprovalRevokedReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 401;
        erc1155.mint(seller, tokenId, 10);

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

        // seller revokes approval
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), false);

        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.purchaseListing{value: 10 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 10, address(0));
    }

    function testERC1155OperatorNotApprovedReverts_thenSucceedsAfterApproval() public {
        // Whitelist ERC1155 and mint balance to the holder.
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        erc1155.mint(operator, 1, 10);

        // Seller is not approved by holder yet, so listing must revert.
        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__NotAuthorizedOperator.selector);
        market.createListing(
            address(erc1155), 1, operator, 1 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0)
        );
        vm.stopPrank();

        // After approvals are granted, the same listing path should succeed.
        vm.prank(operator);
        erc1155.setApprovalForAll(seller, true);
        vm.prank(operator);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, operator, 1 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        Listing memory l = getter.getListingByListingId(id);
        assertEq(l.erc1155Quantity, 10);
        assertEq(l.seller, operator);
    }

    function testERC1155HolderZeroBalanceAtCreateRevertsWrongHolder() public {
        // Use a fresh token id that has zero balance for the claimed holder.
        uint256 freshTokenId = 42;

        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__WrongErc1155HolderParameter.selector);
        market.createListing(
            address(erc1155),
            freshTokenId,
            seller,
            1 ether,
            address(0),
            address(0),
            0,
            0,
            10,
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();
    }

    function testERC1155ZeroQuantityPurchaseReverts() public {
        // Whitelist & approve; list qty=10, partials enabled
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155),
            1,
            seller,
            10 ether, // price
            address(0), // currency
            address(0), // desiredTokenAddress
            0, // desiredTokenId
            0, // desiredErc1155Quantity
            10, // erc1155Quantity
            false,
            true,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buy 0 units -> InvalidPurchaseQuantity
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__InvalidPurchaseQuantity.selector);
        market.purchaseListing{value: 0}(
            id,
            10 ether, // expectedPrice (total listing price)
            address(0), // expectedCurrency
            10, // expectedErc1155Quantity (total listed qty)
            address(0),
            0,
            0,
            0, // erc1155PurchaseQuantity
            address(0)
        );
        vm.stopPrank();
    }

    function testERC1155UpdateInvalidUnitPriceReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // 7 ether % 3 != 0 in wei -> MUST revert
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__InvalidUnitPrice.selector);
        market.updateListing(id, 7 ether, address(0), address(0), 0, 0, 3, false, true, new address[](0));
    }

    function testInvalidUnitPriceOnCreateReverts() public {
        // ERC1155 listing with qty=3, price=10 (not divisible) and partials enabled → revert
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__InvalidUnitPrice.selector);
        market.createListing(
            address(erc1155),
            1,
            seller,
            10, // price
            address(0), // currency
            address(0), // desiredTokenAddress
            0, // desiredTokenId
            0, // desiredErc1155Quantity
            3, // quantity
            false,
            true, // partialBuyEnabled
            new address[](0)
        );
        vm.stopPrank();
    }

    /// Partial buys cannot be enabled when quantity <= 1 on ERC1155 create.
    function testPartialBuyWithQuantityOneReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 101;
        erc1155.mint(seller, tokenId, 1);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__PartialBuyNotPossible.selector);
        market.createListing(
            address(erc1155), tokenId, seller, 1 ether, address(0), address(0), 0, 0, 1, false, true, new address[](0)
        );
    }

    function testERC1155CreateUnauthorizedListerReverts() public {
        // Whitelist the collection
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Holder owns tokens and marketplace approval is intact.
        // This isolates the auth check to msg.sender vs holder/operator.
        vm.prank(operator);
        erc1155.mint(operator, 1, 10);
        vm.prank(operator);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__NotAuthorizedOperator.selector);
        market.createListing(
            address(erc1155), 1, operator, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0)
        );
        vm.stopPrank();
    }

    function testERC1155PartialBuyHappyPath() public {
        // Whitelist & approve
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // List qty=10, price=10 ETH, partials enabled
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer buys 4 → purchasePrice=4 ETH; remains: qty=6, price=6 ETH
        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);

        uint32 feeSnap = getter.getListingByListingId(id).feeRate;
        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingPurchased(
            id, address(erc1155), 1, 4, true, 4 ether, address(0), feeSnap, seller, buyer, address(0), 0, 0
        );

        market.purchaseListing{value: 4 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 4, address(0));

        vm.stopPrank();

        // Listing mutated correctly
        Listing memory l = getter.getListingByListingId(id);
        assertEq(l.erc1155Quantity, 6);
        assertEq(l.price, 6 ether);

        // Atomic payment: seller gets 3.96 ETH, owner gets 0.04 ETH (1% fee)
        assertEq(seller.balance - sellerBalBefore, 3.96 ether);
        assertEq(owner.balance - ownerBalBefore, 0.04 ether);
    }

    function testERC1155_PartialBuy_UnderpayReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        erc1155.mint(seller, 11, 10);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // qty=10, price=10 ETH -> unit=1 ETH; partials enabled
        vm.prank(seller);
        market.createListing(
            address(erc1155), 11, seller, 10 ether, address(0), address(0), 0, 0, 10, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);
        // Buy 4 units but send 3.9 ETH -> PriceNotMet(listingId, 4, 3.9)
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__PriceNotMet.selector, id, 4 ether, 3.9 ether));
        market.purchaseListing{value: 3.9 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 4, address(0));
        vm.stopPrank();
    }

    // ERC-1155 partials: 10 units at 1e18 each; buy 3, then 2; check exact residual price/qty and proceeds/fees.
    function testERC1155MultiStepPartialsMaintainPriceProportions() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // List 10 units for total 10 ETH; partials enabled (unit price = 1 ETH).
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buy 3 units -> pay 3 ETH; remaining: qty=7, price=7 ETH.
        uint256 sellerBalBefore1 = seller.balance;
        uint256 ownerBalBefore1 = owner.balance;
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 3 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 3, address(0));

        Listing memory after3 = getter.getListingByListingId(id);
        assertEq(after3.erc1155Quantity, 7);
        assertEq(after3.price, 7 ether);
        assertEq(seller.balance - sellerBalBefore1, 2.97 ether);
        assertEq(owner.balance - ownerBalBefore1, 0.03 ether);

        // Buy 2 more -> pay 2 ETH; remaining: qty=5, price=5 ETH.
        uint256 sellerBalBefore2 = seller.balance;
        uint256 ownerBalBefore2 = owner.balance;
        address buyer2 = vm.addr(0x4242);
        vm.deal(buyer2, 10 ether);
        vm.prank(buyer2);
        market.purchaseListing{value: 2 ether}(id, 7 ether, address(0), 7, address(0), 0, 0, 2, address(0));

        Listing memory after5 = getter.getListingByListingId(id);
        assertEq(after5.erc1155Quantity, 5);
        assertEq(after5.price, 5 ether);

        // Totals: seller 2.97 + 1.98 = 4.95; owner 0.03 + 0.02 = 0.05.
        assertEq(sellerBalBefore2 - sellerBalBefore1 + (seller.balance - sellerBalBefore2), 4.95 ether);
        assertEq(ownerBalBefore2 - ownerBalBefore1 + (owner.balance - ownerBalBefore2), 0.05 ether);
    }

    function testERC1155OverRemainingAfterPartialReverts() public {
        // List qty=10, partials enabled
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // First partial: buy 7
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 7 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 7, address(0));

        // Remaining = 3; attempt to buy 4 -> revert
        address secondBuyer = vm.addr(0xABCD);
        vm.deal(secondBuyer, 10 ether);
        vm.startPrank(secondBuyer);
        vm.expectRevert(IdeationMarket__InvalidPurchaseQuantity.selector);
        market.purchaseListing{value: 4 ether}(id, 3 ether, address(0), 3, address(0), 0, 0, 4, address(0));
        vm.stopPrank();
    }

    function testERC1155BuyExactRemainingRemovesListing() public {
        // List 10, partials enabled
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buy 4, then buy remaining 6
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 4 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 4, address(0));

        vm.deal(operator, 6 ether);
        vm.prank(operator);
        market.purchaseListing{value: 6 ether}(id, 6 ether, address(0), 6, address(0), 0, 0, 6, address(0));

        // Listing removed
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testERC1155BuyingMoreThanListedReverts() public {
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.stopPrank();

        vm.startPrank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, true, new address[](0)
        );
        vm.stopPrank();

        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 20 ether);
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__InvalidPurchaseQuantity.selector);
        market.purchaseListing{value: 20 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 11, address(0));
        vm.stopPrank();
    }

    function testERC1155PartialBuyDisabledReverts() public {
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.stopPrank();

        vm.startPrank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0)
        );
        vm.stopPrank();

        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__PartialBuyNotPossible.selector);
        market.purchaseListing{value: 5 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 5, address(0));
        vm.stopPrank();
    }
}
