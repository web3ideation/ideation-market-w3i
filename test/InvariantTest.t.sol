// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import "forge-std/StdInvariant.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "../src/libraries/LibAppStorage.sol"; // for Listing struct

/// @dev Invariant test: randomize via handler; assert conservation of value across all flows.
contract IdeationMarketInvariantTest is StdInvariant, MarketTestBase {
    InvariantHandler internal handler;

    address internal buyer1;
    address internal buyer2;
    address internal buyer3;

    MockERC721Royalty internal erc721Roy;
    MockERC1155 internal erc1155New;

    function setUp() public override {
        super.setUp();

        // Fresh mock tokens for randomized flows
        erc721Roy = new MockERC721Royalty();
        erc1155New = new MockERC1155();

        // Whitelist them
        _whitelist(address(erc721Roy));
        _whitelist(address(erc1155New));

        // Prefund a small buyer pool generously
        buyer1 = vm.addr(0xB001);
        buyer2 = vm.addr(0xB002);
        buyer3 = vm.addr(0xB003);
        vm.deal(buyer1, 1_000 ether);
        vm.deal(buyer2, 1_000 ether);
        vm.deal(buyer3, 1_000 ether);

        // Deploy handler
        address[] memory pool = new address[](3);
        pool[0] = buyer1;
        pool[1] = buyer2;
        pool[2] = buyer3;

        handler = new InvariantHandler(
            address(market),
            address(getter),
            address(collections),
            address(erc721Roy),
            address(erc1155New),
            owner,
            seller,
            pool
        );

        // Tell the fuzzer to target handler's public/external mutating functions
        targetContract(address(handler));
    }

    /// @notice In non-custodial model, diamond should hold zero balance (all payments are atomic)
    function invariant_DiamondBalanceIsZero() public view {
        uint256 dbal = address(diamond).balance;
        assertEq(dbal, 0, "Diamond balance should be zero (non-custodial: atomic payments)");
    }
}
