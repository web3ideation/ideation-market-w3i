// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {MockERC20_18} from "../src/mocks/MockERC20_18.sol";
import {MockFixedRateSwap} from "../src/mocks/MockFixedRateSwap.sol";
import {MockUSDC_6} from "../src/mocks/MockUSDC_6.sol";
import {MockWBTC_8} from "../src/mocks/MockWBTC_8.sol";
import {MockEURS_2} from "../src/mocks/MockEURS_2.sol";
import {MockUSDTLike_6} from "../src/mocks/MockUSDTLike_6.sol";

/// @title DeployMockSwap
/// @notice Deploys and seeds the fixed-rate mock swap contract using already-deployed mock tokens.
/// @dev Expects token addresses in env vars so token deployment stays separate from swap deployment.
contract DeployMockSwap is Script {
    address internal constant NATIVE_SENTINEL = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 internal constant DEFAULT_ETH_LIQUIDITY = 0.5 ether;

    // Seed oversized mock balances so the backend can quote and swap without
    // frequently tripping over test liquidity ceilings.
    uint256 internal constant LIQUIDITY_18 = 1_000_000_000;
    uint256 internal constant LIQUIDITY_6 = 1_000_000_000;
    uint256 internal constant LIQUIDITY_8 = 1_000_000;
    uint256 internal constant LIQUIDITY_2 = 1_000_000_000;

    uint256 internal constant USD_SCALE = 1e8;
    uint256 internal constant ETH_USD = 2_500 * USD_SCALE;
    uint256 internal constant ERC20_USD = 1 * USD_SCALE;
    uint256 internal constant USDC_USD = 1 * USD_SCALE;
    uint256 internal constant WBTC_USD = 100_000 * USD_SCALE;
    uint256 internal constant EURS_USD = 108_000_000;
    uint256 internal constant USDT_USD = 1 * USD_SCALE;

    function run() external {
        uint256 ethLiquidity = vm.envOr("MOCK_SWAP_ETH_LIQUIDITY_WEI", uint256(DEFAULT_ETH_LIQUIDITY));

        MockERC20_18 t18 = MockERC20_18(vm.envAddress("MOCK_TOKEN_MERC20"));
        MockUSDC_6 usdc = MockUSDC_6(vm.envAddress("MOCK_TOKEN_MUSDC"));
        MockWBTC_8 wbtc = MockWBTC_8(vm.envAddress("MOCK_TOKEN_MWBTC"));
        MockEURS_2 eurs = MockEURS_2(vm.envAddress("MOCK_TOKEN_MEURS"));
        MockUSDTLike_6 usdt = MockUSDTLike_6(vm.envAddress("MOCK_TOKEN_MUSDT"));

        vm.startBroadcast();

        MockFixedRateSwap swapper = new MockFixedRateSwap();

        t18.mint(address(swapper), LIQUIDITY_18 * 1e18);
        usdc.mint(address(swapper), LIQUIDITY_6 * 1e6);
        wbtc.mint(address(swapper), LIQUIDITY_8 * 1e8);
        eurs.mint(address(swapper), LIQUIDITY_2 * 1e2);
        usdt.mint(address(swapper), LIQUIDITY_6 * 1e6);

        (bool funded,) = payable(address(swapper)).call{value: ethLiquidity}("");
        require(funded, "Failed to seed ETH liquidity");

        _configureAllPairs(swapper, address(t18), address(usdc), address(wbtc), address(eurs), address(usdt));

        console.log("Deployed MockFixedRateSwap:", address(swapper));
        console.log("Backend config values:");
        console.log("MOCK_NATIVE_SENTINEL:", NATIVE_SENTINEL);
        console.log("MOCK_SWAP_ADDRESS:", address(swapper));
        console.log("MOCK_TOKEN_MERC20:", address(t18));
        console.log("MOCK_TOKEN_MUSDC:", address(usdc));
        console.log("MOCK_TOKEN_MWBTC:", address(wbtc));
        console.log("MOCK_TOKEN_MEURS:", address(eurs));
        console.log("MOCK_TOKEN_MUSDT:", address(usdt));
        console.log("MOCK_SWAP_FUNDED_ETH_WEI:", ethLiquidity);

        vm.stopBroadcast();
    }

    function _configureAllPairs(
        MockFixedRateSwap swapper,
        address t18,
        address usdc,
        address wbtc,
        address eurs,
        address usdt
    ) internal {
        address[6] memory assets = [address(0), t18, usdc, wbtc, eurs, usdt];
        uint8[6] memory decimals = [18, 18, 6, 8, 2, 6];
        uint256[6] memory usdPrices = [ETH_USD, ERC20_USD, USDC_USD, WBTC_USD, EURS_USD, USDT_USD];

        for (uint256 i = 0; i < assets.length; i++) {
            for (uint256 j = 0; j < assets.length; j++) {
                if (i == j) {
                    continue;
                }

                uint256 numerator = usdPrices[i] * _scale(decimals[j]);
                uint256 denominator = usdPrices[j] * _scale(decimals[i]);

                swapper.setPair(assets[i], assets[j], numerator, denominator, _defaultFeeBps(i, j));
            }
        }
    }

    function _defaultFeeBps(uint256 srcIndex, uint256 dstIndex) internal pure returns (uint16) {
        bool srcStable = _isStable(srcIndex);
        bool dstStable = _isStable(dstIndex);

        if (srcStable && dstStable) {
            return 10;
        }

        if (srcIndex == 3 || dstIndex == 3) {
            return 35;
        }

        if (srcIndex == 0 || dstIndex == 0) {
            return 20;
        }

        return 25;
    }

    function _isStable(uint256 assetIndex) internal pure returns (bool) {
        return assetIndex == 2 || assetIndex == 4 || assetIndex == 5;
    }

    function _scale(uint8 decimals_) internal pure returns (uint256) {
        return 10 ** uint256(decimals_);
    }
}
