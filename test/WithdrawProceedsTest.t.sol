// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

/// Receiver with NO payable receive/fallback — any ETH send will revert
contract NonPayableReceiver {
    // no receive(), no payable fallback => value transfers revert
    fallback() external {}
}

/// Receiver that burns gas in receive() but does not revert
contract BusyReceiver {
    receive() external payable {
        unchecked {
            uint256 s;
            for (uint256 i; i < 30_000; ++i) {
                s += i;
            }
        }
    }
}

contract ProgrammedReceiver {
    bool public accept;

    function setAccept(bool v) external {
        accept = v;
    }

    receive() external payable {
        if (!accept) revert("ProgrammedReceiver: blocked");
        // (optional) reset behavior here if you want one-shot: accept = false;
    }
}

contract WithdrawTargetsTest is MarketTestBase {
    uint256 private _nextTokenId = 10001;

    /// seeds proceeds for `who` via a simple ERC721 listing sold to `buyer`
    function _seedProceedsFor(address who, uint256 price) internal returns (uint256 proceedsBefore) {
        _whitelist(address(erc721));

        uint256 tokenId = _nextTokenId++;
        erc721.mint(who, tokenId);

        vm.startPrank(who);
        erc721.approve(address(diamond), tokenId);
        market.createListing(
            address(erc721), tokenId, address(0), price, address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        uint128 listingId = getter.getNextListingId() - 1;

        vm.deal(buyer, price);
        vm.prank(buyer);
        market.purchaseListing{value: price}(listingId, price, 0, address(0), 0, 0, 0, address(0));

        proceedsBefore = getter.getProceeds(who);
        assertGt(proceedsBefore, 0, "proceeds not credited");
    }

    /// 1) Contract with payable receive (EOA-like) should succeed
    function testWithdraw_MinimalContractReceiver_Succeeds() public {
        NonReceiver r = new NonReceiver(); // from MarketTestBase (payable receive)
        uint256 price = 1 ether;
        uint256 credited = _seedProceedsFor(address(r), price);

        uint256 balBefore = address(r).balance;
        uint256 diamondBefore = address(diamond).balance;

        vm.prank(address(r));
        market.withdrawProceeds();

        assertEq(getter.getProceeds(address(r)), 0, "credit not zeroed");
        assertEq(address(r).balance, balBefore + credited, "receiver balance mismatch");
        assertEq(address(diamond).balance, diamondBefore - credited, "diamond balance mismatch");
    }

    /// 2) Intermittently reverting receiver: first attempt reverts & preserves credit; second succeeds
    function testWithdraw_ProgrammedReceiver_RevertThenSucceed() public {
        ProgrammedReceiver r = new ProgrammedReceiver();
        uint256 price = 1 ether;
        uint256 credited = _seedProceedsFor(address(r), price);

        // First: program to reject, withdrawal must revert and credit stays
        r.setAccept(false);
        vm.expectRevert(IdeationMarket__TransferFailed.selector);
        vm.prank(address(r));
        market.withdrawProceeds();
        assertEq(getter.getProceeds(address(r)), credited, "credit changed on failed payout");

        // Second: program to accept, withdrawal must succeed and zero the credit
        r.setAccept(true);
        uint256 balBefore = address(r).balance;
        vm.prank(address(r));
        market.withdrawProceeds();
        assertEq(getter.getProceeds(address(r)), 0, "credit not zeroed after success");
        assertEq(address(r).balance, balBefore + credited, "receiver balance mismatch after success");
    }

    /// 3) Non-payable receiver must always revert; credit stays intact
    function testWithdraw_NonPayableReceiver_AlwaysReverts_PreservesCredit() public {
        NonPayableReceiver r = new NonPayableReceiver();
        uint256 price = 0.7 ether;
        uint256 credited = _seedProceedsFor(address(r), price);
        uint256 diamondBefore = address(diamond).balance;

        vm.expectRevert(IdeationMarket__TransferFailed.selector);
        vm.prank(address(r));
        market.withdrawProceeds();

        assertEq(getter.getProceeds(address(r)), credited, "credit must remain after failed withdrawal");
        assertEq(address(diamond).balance, diamondBefore, "diamond balance changed on failed withdrawal");
    }

    /// 4) Gas-hungry receiver should still succeed because `.call` forwards gas
    function testWithdraw_BusyReceiver_Succeeds() public {
        BusyReceiver r = new BusyReceiver();
        uint256 price = 1.3 ether;
        uint256 credited = _seedProceedsFor(address(r), price);

        uint256 balBefore = address(r).balance;
        uint256 diamondBefore = address(diamond).balance;

        vm.prank(address(r));
        market.withdrawProceeds();

        assertEq(getter.getProceeds(address(r)), 0, "credit not zeroed");
        assertEq(address(r).balance, balBefore + credited, "receiver balance mismatch");
        assertEq(address(diamond).balance, diamondBefore - credited, "diamond balance mismatch");
    }
}
