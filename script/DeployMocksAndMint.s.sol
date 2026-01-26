// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {MockERC20_18} from "../src/mocks/MockERC20_18.sol";
import {MockUSDC_6} from "../src/mocks/MockUSDC_6.sol";
import {MockWBTC_8} from "../src/mocks/MockWBTC_8.sol";
import {MockEURS_2} from "../src/mocks/MockEURS_2.sol";
import {MockUSDTLike_6} from "../src/mocks/MockUSDTLike_6.sol";

/// @title DeployMocksAndMint
/// @notice Deploys mock ERC20 tokens and mints balances to a set of test addresses.
/// @dev Permissionless mint on the mocks means anyone can top up later; this script just seeds initial balances.
contract DeployMocksAndMint is Script {
    // Recipients provided by you
    address internal constant RECIPIENT_1 = 0xE8dF60a93b2B328397a8CBf73f0d732aaa11e33D;
    address internal constant RECIPIENT_2 = 0x8a200122f666af83aF2D4f425aC7A35fa5491ca7;
    address internal constant RECIPIENT_3 = 0xf034e8ad11F249c8081d9da94852bE1734bc11a4;

    // "Good amount" per recipient (human units)
    uint256 internal constant HUMAN_AMOUNT = 1_000_000;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEV_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy tokens
        MockERC20_18 t18 = new MockERC20_18();
        MockUSDC_6 usdc = new MockUSDC_6();
        MockWBTC_8 wbtc = new MockWBTC_8();
        MockEURS_2 eurs = new MockEURS_2();
        MockUSDTLike_6 usdt = new MockUSDTLike_6();

        console.log("Deployed MockERC20_18:", address(t18));
        console.log("Deployed MockUSDC_6:", address(usdc));
        console.log("Deployed MockWBTC_8:", address(wbtc));
        console.log("Deployed MockEURS_2:", address(eurs));
        console.log("Deployed MockUSDTLike_6:", address(usdt));

        address[3] memory recipients = [RECIPIENT_1, RECIPIENT_2, RECIPIENT_3];

        uint256 amount18 = HUMAN_AMOUNT * 1e18;
        uint256 amount6 = HUMAN_AMOUNT * 1e6;
        uint256 amount8 = HUMAN_AMOUNT * 1e8;
        uint256 amount2 = HUMAN_AMOUNT * 1e2;

        for (uint256 i = 0; i < recipients.length; i++) {
            address to = recipients[i];

            t18.mint(to, amount18);
            usdc.mint(to, amount6);
            wbtc.mint(to, amount8);
            eurs.mint(to, amount2);
            usdt.mint(to, amount6);

            console.log("Minted to:", to);
        }

        vm.stopBroadcast();
    }
}
