// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {MockERC20_18} from "../src/mocks/MockERC20_18.sol";
import {MockUSDC_6} from "../src/mocks/MockUSDC_6.sol";
import {MockUSDTLike_6} from "../src/mocks/MockUSDTLike_6.sol";
import {MockWBTC_8} from "../src/mocks/MockWBTC_8.sol";
import {MockFixedRateSwap} from "../src/mocks/MockFixedRateSwap.sol";

contract MockFixedRateSwapTest is Test {
    MockFixedRateSwap internal swap;
    MockERC20_18 internal token18;
    MockUSDC_6 internal usdc;
    MockUSDTLike_6 internal usdt;
    MockWBTC_8 internal wbtc;

    address internal alice = vm.addr(0xA11CE);
    address internal treasury = vm.addr(0xBEEF);

    function setUp() public {
        swap = new MockFixedRateSwap();
        token18 = new MockERC20_18();
        usdc = new MockUSDC_6();
        usdt = new MockUSDTLike_6();
        wbtc = new MockWBTC_8();

        swap.setPair(address(usdc), address(wbtc), 3, 100, 100);
        swap.setPair(address(usdc), address(0), 1e12, 1, 0);
        swap.setPair(address(0), address(usdc), 2, 1e12, 0);
        swap.setPair(address(usdt), address(usdc), 1, 1, 50);
        swap.setPair(address(token18), address(usdc), 2, 1e12, 0);

        usdc.mint(alice, 10_000_000e6);
        usdt.mint(alice, 2_000_000e6);
        token18.mint(alice, 100e18);

        wbtc.mint(address(swap), 10_000_000e8);
        usdc.mint(address(swap), 20_000_000e6);
        vm.deal(address(swap), 1_000 ether);
        vm.deal(alice, 100 ether);
    }

    function testQuoteExactInputAppliesConfiguredFee() public view {
        uint256 amountIn = 1_000_000;
        uint256 amountOut = swap.quoteExactInput(address(usdc), address(wbtc), amountIn);

        // gross = 1_000_000 * 3 / 100 = 30_000, fee = 1%
        assertEq(amountOut, 29_700);
    }

    function testSwapTokenToTokenPullsInputAndPaysOutput() public {
        uint256 amountIn = 1_000_000;
        uint256 minAmountOut = 29_000;

        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        uint256 aliceWbtcBefore = wbtc.balanceOf(alice);

        vm.prank(alice);
        usdc.approve(address(swap), amountIn);

        vm.prank(alice);
        uint256 amountOut = swap.swapExactInput(address(usdc), address(wbtc), amountIn, minAmountOut, alice);

        assertEq(amountOut, 29_700);
        assertEq(usdc.balanceOf(alice), aliceUsdcBefore - amountIn);
        assertEq(wbtc.balanceOf(alice), aliceWbtcBefore + amountOut);
    }

    function testSwapTokenToEthUsesPrefundedEthLiquidity() public {
        uint256 amountIn = 5e6;
        uint256 minAmountOut = 5 ether;
        uint256 aliceEthBefore = alice.balance;

        vm.prank(alice);
        usdc.approve(address(swap), amountIn);

        vm.prank(alice);
        uint256 amountOut = swap.swapExactInput(address(usdc), address(0), amountIn, minAmountOut, alice);

        assertEq(amountOut, 5 ether);
        assertEq(alice.balance, aliceEthBefore + amountOut);
    }

    function testSwapEthToTokenUsesMsgValueAsInput() public {
        uint256 amountIn = 1 ether;
        uint256 minAmountOut = 2e6;
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 amountOut =
            swap.swapExactInput{value: amountIn}(address(0), address(usdc), amountIn, minAmountOut, alice);

        assertEq(amountOut, 2e6);
        assertEq(usdc.balanceOf(alice), aliceUsdcBefore + amountOut);
    }

    function testSwapRevertsWhenMinAmountOutIsTooHigh() public {
        uint256 amountIn = 1_000_000;

        vm.prank(alice);
        usdc.approve(address(swap), amountIn);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                MockFixedRateSwap.MockFixedRateSwap__InsufficientOutputAmount.selector, 30_000, 29_700
            )
        );
        swap.swapExactInput(address(usdc), address(wbtc), amountIn, 30_000, alice);
    }

    function testSwapRevertsWhenPairIsUnsupported() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                MockFixedRateSwap.MockFixedRateSwap__PairNotEnabled.selector, address(wbtc), address(usdc)
            )
        );
        swap.quoteExactInput(address(wbtc), address(usdc), 1e8);
    }

    function testSwapRevertsWhenOutputLiquidityIsInsufficient() public {
        MockFixedRateSwap tinySwap = new MockFixedRateSwap();
        tinySwap.setPair(address(token18), address(usdc), 2, 1e12, 0);

        token18.mint(alice, 10e18);
        usdc.mint(address(tinySwap), 1e6);

        uint256 amountIn = 2e18;

        vm.prank(alice);
        token18.approve(address(tinySwap), amountIn);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                MockFixedRateSwap.MockFixedRateSwap__InsufficientLiquidity.selector, address(usdc), 4e6, 1e6
            )
        );
        tinySwap.swapExactInput(address(token18), address(usdc), amountIn, 1, alice);
    }

    function testSwapSupportsUsdtLikeTokenWithNoBoolReturnValues() public {
        uint256 amountIn = 1_000_000;
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);

        vm.startPrank(alice);
        usdt.approve(address(swap), amountIn);
        uint256 amountOut = swap.swapExactInput(address(usdt), address(usdc), amountIn, 995_000, alice);
        vm.stopPrank();

        // 0.5% fee on a 1:1 route
        assertEq(amountOut, 995_000);
        assertEq(usdc.balanceOf(alice), aliceUsdcBefore + amountOut);
    }

    function testUsdtLikeTokenStillEnforcesZeroFirstAllowanceRule() public {
        vm.startPrank(alice);
        usdt.approve(address(swap), 1_000_000);
        vm.expectRevert(bytes("USDTLike: must reset allowance to 0"));
        usdt.approve(address(swap), 2_000_000);
        usdt.approve(address(swap), 0);
        usdt.approve(address(swap), 2_000_000);
        vm.stopPrank();

        assertEq(usdt.allowance(alice, address(swap)), 2_000_000);
    }

    function testOwnerCanWithdrawPrefundedAssets() public {
        uint256 withdrawAmount = 10e6;
        uint256 treasuryBefore = usdc.balanceOf(treasury);

        swap.withdrawToken(address(usdc), treasury, withdrawAmount);
        swap.withdrawETH(payable(treasury), 1 ether);

        assertEq(usdc.balanceOf(treasury), treasuryBefore + withdrawAmount);
        assertEq(treasury.balance, 1 ether);
    }
}
