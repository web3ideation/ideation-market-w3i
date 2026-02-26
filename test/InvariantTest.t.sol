// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import "forge-std/StdInvariant.sol";

/**
 * @title IdeationMarketInvariantTest
 * @notice Scope/category: stateful invariant fuzzing for marketplace liveness/safety
 * using `InvariantHandler` randomized listing/purchase flows.
 *
 * Covered invariant category:
 * - Non-custodial ETH accounting: diamond balance remains zero after arbitrary handler actions
 * - Non-custodial ERC20 accounting: diamond ERC20 balance remains zero across ERC20 listing/purchase flows
 * - ERC20 purchase conservation accounting: buyer spend equals seller + owner fee + royalty credits
 */
contract IdeationMarketInvariantTest is StdInvariant, MarketTestBase {
    InvariantHandler internal handler;

    address internal buyer1;
    address internal buyer2;
    address internal buyer3;

    MockERC721Royalty internal erc721Roy;
    MockERC1155 internal erc1155New;
    MockERC20 internal erc20Inv;

    uint256 internal constant INITIAL_ERC20_BUYER_FLOAT = 3_000_000 ether;

    function setUp() public override {
        super.setUp();

        // Fresh mock tokens for randomized flows
        erc721Roy = new MockERC721Royalty();
        erc1155New = new MockERC1155();
        erc20Inv = new MockERC20("Invariant Token", "ITKN");

        // Whitelist them
        _whitelist(address(erc721Roy));
        _whitelist(address(erc1155New));
        vm.prank(owner);
        currencies.addAllowedCurrency(address(erc20Inv));

        // Prefund a small buyer pool generously
        buyer1 = vm.addr(0xB001);
        buyer2 = vm.addr(0xB002);
        buyer3 = vm.addr(0xB003);
        vm.deal(buyer1, 1_000 ether);
        vm.deal(buyer2, 1_000 ether);
        vm.deal(buyer3, 1_000 ether);

        erc20Inv.mint(buyer1, 1_000_000 ether);
        erc20Inv.mint(buyer2, 1_000_000 ether);
        erc20Inv.mint(buyer3, 1_000_000 ether);

        vm.prank(buyer1);
        erc20Inv.approve(address(diamond), type(uint256).max);
        vm.prank(buyer2);
        erc20Inv.approve(address(diamond), type(uint256).max);
        vm.prank(buyer3);
        erc20Inv.approve(address(diamond), type(uint256).max);

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
            address(erc20Inv),
            owner,
            seller,
            pool
        );

        // Deterministically exercise one ERC20 listing + purchase path up front
        // so ERC20 non-custodial invariant checks are never vacuous.
        handler.list721ERC20(1);
        handler.purchaseERC20(0, 0);

        // Tell the fuzzer to target handler's public/external mutating functions
        targetContract(address(handler));
    }

    /// @notice In non-custodial model, diamond should hold zero balance (all payments are atomic)
    function invariant_DiamondBalanceIsZero() public view {
        uint256 dbal = address(diamond).balance;
        assertEq(dbal, 0, "Diamond balance should be zero (non-custodial: atomic payments)");
    }

    /// @notice In ERC20 payment model, marketplace transfers from buyer to recipients directly; diamond must not custody ERC20 funds.
    function invariant_DiamondERC20BalanceIsZero() public view {
        uint256 dbal = erc20Inv.balanceOf(address(diamond));
        assertEq(dbal, 0, "Diamond ERC20 balance should be zero (non-custodial token flow)");
    }

    /// @notice For successful ERC20 purchases, buyers' aggregate token outflow must equal credits to seller + owner fee + royalty receiver.
    function invariant_ERC20PurchaseDeltaAccountingConserved() public view {
        uint256 successful = handler.successfulERC20Purchases();
        assertGt(successful, 0, "Expected at least one successful ERC20 purchase in invariant run");

        uint256 buyersNow = erc20Inv.balanceOf(buyer1) + erc20Inv.balanceOf(buyer2) + erc20Inv.balanceOf(buyer3);
        uint256 buyersSpent = INITIAL_ERC20_BUYER_FLOAT - buyersNow;

        uint256 recipientsCredited = erc20Inv.balanceOf(seller) + erc20Inv.balanceOf(owner)
            + erc20Inv.balanceOf(handler.royaltyReceiver()) + erc20Inv.balanceOf(address(diamond));

        assertEq(buyersSpent, recipientsCredited, "ERC20 delta accounting mismatch across buyer/seller/fee/royalty");
    }
}
