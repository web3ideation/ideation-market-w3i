// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

/**
 * @title ERC20MarketplaceTest
 * @notice Unit tests for ERC20-denominated listing and purchase behavior in the marketplace.
 * @dev Coverage groups:
 * - ERC20 purchase success path for ERC1155 full-quantity fills and non-custodial balance invariants.
 * - ERC20 payment-path guards (non-zero msg.value, insufficient allowance, insufficient balance).
 * - ERC20 listing cancellation behavior and event payload currency correctness.
 * - Focuses on ERC20 marketplace mechanics; deep payment-distribution edge coverage is delegated to ERC20PaymentDistribution/SEC tests.
 */
contract ERC20MarketplaceTest is MarketTestBase {
    // Reuse MockERC20 from CurrencyWhitelistFacetTest
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;

    event ListingCreated(
        uint128 indexed listingId,
        address indexed tokenAddress,
        uint256 indexed tokenId,
        uint256 erc1155Quantity,
        uint256 price,
        address currency,
        uint32 feeRate,
        address seller,
        bool buyerWhitelistEnabled,
        bool partialBuyEnabled,
        address desiredTokenAddress,
        uint256 desiredTokenId,
        uint256 desiredErc1155Quantity
    );

    event ListingPurchased(
        uint128 indexed listingId,
        address indexed tokenAddress,
        uint256 indexed tokenId,
        uint256 erc1155Quantity,
        bool partialBuy,
        uint256 price,
        address currency,
        uint32 feeRate,
        address seller,
        address buyer,
        address desiredTokenAddress,
        uint256 desiredTokenId,
        uint256 desiredErc1155Quantity
    );

    function setUp() public virtual override {
        super.setUp();
        tokenA = new MockERC20("TokenA", "TKA");
        tokenB = new MockERC20("TokenB", "TKB");

        // Add tokens to allowlist
        vm.startPrank(owner);
        currencies.addAllowedCurrency(address(tokenA));
        currencies.addAllowedCurrency(address(tokenB));
        vm.stopPrank();
    }

    // ----------------------------------------------------------
    // Group 1: Purchases & Payment Flow (ERC20 specific)
    // ----------------------------------------------------------
    // NOTE: Full payment distribution testing is in ERC20PaymentDistributionTest
    // This file focuses on ERC20-specific marketplace behavior

    function testPurchaseERC1155WithERC20FullQuantity() public {
        uint128 listingId = _createERC1155ListingInERC20(address(tokenB), 10 ether, 5);

        tokenB.mint(buyer, 10 ether);
        vm.prank(buyer);
        tokenB.approve(address(diamond), 10 ether);

        uint256 ownerStart = tokenB.balanceOf(owner);
        uint256 sellerStart = tokenB.balanceOf(seller);

        vm.prank(buyer);
        market.purchaseListing(listingId, 10 ether, address(tokenB), 5, address(0), 0, 0, 5, address(0));

        uint256 ownerEnd = tokenB.balanceOf(owner);
        uint256 sellerEnd = tokenB.balanceOf(seller);

        uint256 fee = (10 ether * uint256(INNOVATION_FEE)) / 100000;
        uint256 sellerProceeds = 10 ether - fee;

        assertEq(ownerEnd - ownerStart, fee);
        assertEq(sellerEnd - sellerStart, sellerProceeds);
        assertEq(tokenB.balanceOf(address(diamond)), 0);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingId));
        getter.getListingByListingId(listingId);
    }

    function testPurchaseWithMsgValueRevertsForERC20() public {
        uint128 listingId = _createERC721ListingInERC20(address(tokenA), 5 ether, 1);

        tokenA.mint(buyer, 5 ether);
        vm.prank(buyer);
        tokenA.approve(address(diamond), 5 ether);

        vm.prank(buyer);
        (bool ok, bytes memory revertData) = address(diamond).call{value: 1 wei}(
            abi.encodeWithSelector(
                market.purchaseListing.selector, listingId, 5 ether, address(tokenA), 0, address(0), 0, 0, 0, address(0)
            )
        );
        assertFalse(ok, "ERC20 purchase with msg.value should revert");
        assertEq(revertData.length, 0, "Expected empty revert data for this path");
    }

    // ----------------------------------------------------------
    // Group 3: Approval & Balance Guards
    // ----------------------------------------------------------

    function testPurchaseWithInsufficientAllowanceReverts() public {
        uint128 listingId = _createERC721ListingInERC20(address(tokenA), 5 ether, 1);

        tokenA.mint(buyer, 5 ether);
        vm.prank(buyer);
        tokenA.approve(address(diamond), 2 ether);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__ERC20TransferFailed.selector, address(tokenA), seller));
        market.purchaseListing(listingId, 5 ether, address(tokenA), 0, address(0), 0, 0, 0, address(0));
    }

    function testPurchaseWithInsufficientBalanceReverts() public {
        uint128 listingId = _createERC721ListingInERC20(address(tokenA), 5 ether, 1);

        tokenA.mint(buyer, 2 ether);
        vm.prank(buyer);
        tokenA.approve(address(diamond), 5 ether);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__ERC20TransferFailed.selector, address(tokenA), seller));
        market.purchaseListing(listingId, 5 ether, address(tokenA), 0, address(0), 0, 0, 0, address(0));
    }

    // ----------------------------------------------------------
    // Group 5: Cancel & Events
    // ----------------------------------------------------------

    function testCancelERC20ListingSucceedsAndZeroBalance() public {
        uint128 listingId = _createERC721ListingInERC20(address(tokenA), 5 ether, 1);

        uint256 diamondBalanceBefore = tokenA.balanceOf(address(diamond));
        assertEq(diamondBalanceBefore, 0);

        vm.prank(seller);
        market.cancelListing(listingId);

        uint256 diamondBalanceAfter = tokenA.balanceOf(address(diamond));
        assertEq(diamondBalanceAfter, 0);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingId));
        getter.getListingByListingId(listingId);
    }

    function testEventsEmitCurrencyAddress() public {
        _whitelistCollectionAndApproveERC721();

        vm.expectEmit(true, true, true, true, address(diamond));
        emit ListingCreated(
            getter.getNextListingId(),
            address(erc721),
            1,
            0,
            3 ether,
            address(tokenA),
            INNOVATION_FEE,
            seller,
            false,
            false,
            address(0),
            0,
            0
        );

        vm.startPrank(seller);
        market.createListing(
            address(erc721),
            1,
            address(0),
            3 ether,
            address(tokenA),
            address(0),
            0,
            0,
            0,
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();
    }
}
