// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

/// @title DiamondReceiveAndGetterBalanceTest
/// @notice Verifies that direct ETH receipts update the internal balance,
///         and that purchases (incl. overpay) keep `getter.getBalance()`
///         in sync with `address(diamond).balance`.
contract DiamondReceiveAndGetterBalanceTest is MarketTestBase {
    /// Direct ETH to the diamond (empty calldata -> receive) increases both
    /// the on-chain balance and the getter-reported balance by the same amount.
    function testReceive_DirectETH_IncreasesGetterAndNativeBalance() public {
        uint256 beforeGetter = getter.getBalance();
        uint256 beforeNative = address(diamond).balance;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        (bool ok,) = address(diamond).call{value: 1 ether}("");
        require(ok, "send failed");

        assertEq(getter.getBalance(), beforeGetter + 1 ether);
        assertEq(address(diamond).balance, beforeNative + 1 ether);
    }

    /// Non-empty calldata with an unknown selector should revert via the
    /// diamond fallback and *not* change balances.
    function testFallback_UnknownSelectorWithValue_Reverts_NoBalanceChange() public {
        uint256 beforeGetter = getter.getBalance();
        uint256 beforeNative = address(diamond).balance;

        bytes memory bogus = abi.encodeWithSelector(bytes4(keccak256("nope()")));

        vm.deal(buyer, 0.123 ether);
        vm.prank(buyer);
        vm.expectRevert(Diamond__FunctionDoesNotExist.selector);
        // value won't be transferred because the call reverts
        (bool ok,) = address(diamond).call{value: 0.123 ether}(bogus);
        ok; // silence warning

        assertEq(getter.getBalance(), beforeGetter);
        assertEq(address(diamond).balance, beforeNative);
    }

    /// A simple ERC721 sale with overpay credits buyer, splits fee to owner,
    /// pays seller proceeds, and total recorded proceeds equal both balances.
    function testPurchaseERC721_Overpay_ProceedsSumEqualsBalances() public {
        _whitelistDefaultMocks();
        // Approve & list an already-whitelisted mock ERC721 from the base
        // (MarketTestBase whitelists `erc721` in setUp and mints tokenId 1 & 2 to `seller`)
        vm.prank(seller);
        erc721.approve(address(diamond), 2);

        uint256 price = 1 ether;
        vm.prank(seller);
        market.createListing(
            address(erc721), // nft
            2, // tokenId
            address(0), // desired NFT (swap disabled)
            price, // price
            address(0), // desired token addr (swap disabled)
            0, // desired tokenId
            0, // unit price (only for 1155)
            0, // erc1155 qty (ERC721 -> 0)
            false, // partial buy disabled
            false, // whitelist disabled
            new address[](0) // whitelist
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer overpays by 0.2 ether (credit should be recorded for buyer)
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1.2 ether}(
            id, // listing id
            price, // expected price
            0, // expected qty (ERC721)
            address(0), // expected desired addr
            0, // expected desired id
            0, // expected unit price
            0, // expected desired qty
            address(0) // expected royalty receiver (0 for "don't care")
        );

        // Sum up the plausible recipients:
        // - seller receives (price - fee - royalty)
        // - owner (contract owner) receives fee
        // - buyer receives 0.2 ether credit (overpay)
        uint256 sum = getter.getProceeds(seller) + getter.getProceeds(owner) + getter.getProceeds(buyer);

        assertEq(sum, getter.getBalance(), "sum(proceeds) != getter.getBalance()");
        assertEq(getter.getBalance(), address(diamond).balance, "getter.getBalance() != native balance");
    }
}
