// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

/**
 * @title DiamondReceiveAndGetterBalanceTest
 * @notice Scope/category: non-custodial ETH receive/fallback behavior and
 * GetterFacet native balance reporting consistency.
 *
 * Covered categories:
 * - Direct ETH transfer rejection (no receive function) with unchanged balances
 * - Unknown selector fallback revert path with unchanged balances
 * - ERC721 purchase payment path keeps diamond native balance unchanged and getter in sync
 */
contract DiamondReceiveAndGetterBalanceTest is MarketTestBase {
    /// Direct ETH to the diamond (empty calldata -> receive) REVERTS in non-custodial model.
    /// The diamond has no receive() function, so direct ETH transfers should fail.
    function testReceive_DirectETH_RevertsAndBalanceUnchanged() public {
        uint256 beforeGetter = getter.getBalance();
        uint256 beforeNative = address(diamond).balance;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        (bool ok,) = address(diamond).call{value: 1 ether}("");

        // Non-custodial diamond rejects direct ETH transfers
        assertFalse(ok, "direct ETH should fail - no receive() function");
        assertEq(getter.getBalance(), beforeGetter, "getter balance should not change");
        assertEq(address(diamond).balance, beforeNative, "diamond balance should not change");
    }

    /// Non-empty calldata with an unknown selector should revert via the
    /// diamond fallback and *not* change balances.
    function testFallback_UnknownSelectorWithValue_Reverts_NoBalanceChange() public {
        uint256 beforeGetter = getter.getBalance();
        uint256 beforeNative = address(diamond).balance;

        bytes memory bogus = abi.encodeWithSelector(bytes4(keccak256("nope()")));

        vm.deal(buyer, 0.123 ether);
        vm.prank(buyer);
        // value won't be transferred because fallback path reverts
        (bool ok,) = address(diamond).call{value: 0.123 ether}(bogus);
        assertFalse(ok, "unknown selector call should fail");

        assertEq(getter.getBalance(), beforeGetter);
        assertEq(address(diamond).balance, beforeNative);
    }

    /// A simple ERC721 sale with atomic payment: seller and owner receive funds directly,
    /// and diamond balance returns to zero after the purchase (non-custodial).
    function testPurchaseERC721_AtomicPayment_DiamondBalanceZero() public {
        _whitelistDefaultMocks();
        // Approve & list an already-whitelisted mock ERC721 from the base
        // (MarketTestBase whitelists `erc721` in setUp and mints tokenId 1 & 2 to `seller`)
        vm.prank(seller);
        erc721.approve(address(diamond), 2);

        uint256 price = 1 ether;
        vm.prank(seller);
        market.createListing(
            address(erc721), // tokenAddress
            2, // tokenId
            address(0), // erc1155Holder (not used for ERC721)
            price, // price
            address(0), // currency: ETH
            address(0), // desiredTokenAddress (swap disabled)
            0, // desiredTokenId
            0, // desiredErc1155Quantity (swap disabled)
            0, // erc1155Quantity (0 = ERC721)
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            new address[](0) // allowedBuyers
        );
        uint128 id = getter.getNextListingId() - 1;

        // Capture balances before purchase (non-custodial: atomic payment)
        uint256 diamondBalBefore = address(diamond).balance;
        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;

        // Buyer pays exact amount (no overpay allowed in non-custodial)
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        market.purchaseListing{value: price}(
            id, // listing id
            price, // expected price
            address(0), // expected currency: ETH
            0, // expected qty (ERC721)
            address(0), // expected desired addr
            0, // expected desired id
            0, // expected desired qty
            0, // erc1155PurchaseQuantity (not used for ERC721)
            address(0) // desiredErc1155Holder (not used)
        );

        // Non-custodial: diamond should NOT hold any balance after purchase
        assertEq(
            address(diamond).balance, diamondBalBefore, "diamond balance changed (should be unchanged in non-custodial)"
        );
        assertEq(getter.getBalance(), diamondBalBefore, "getter.getBalance() != diamond balance");

        // Verify seller and owner received their shares (fee split atomic during purchase)
        uint256 fee = (price * getter.getInnovationFee()) / 100_000;
        assertEq(seller.balance, sellerBalBefore + (price - fee), "seller did not receive net proceeds");
        assertEq(owner.balance, ownerBalBefore + fee, "owner did not receive fee");
    }
}
