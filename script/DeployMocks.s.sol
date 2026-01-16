// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {MockERC20_18} from "../src/mocks/MockERC20_18.sol";
import {MockUSDC_6} from "../src/mocks/MockUSDC_6.sol";
import {MockWBTC_8} from "../src/mocks/MockWBTC_8.sol";
import {MockEURS_2} from "../src/mocks/MockEURS_2.sol";
import {MockUSDTLike_6} from "../src/mocks/MockUSDTLike_6.sol";

/// @title DeployMocks
/// @notice Deploys mintable mock ERC20 tokens for Sepolia testing.
/// @dev Uses DEV_PRIVATE_KEY like your other scripts.
contract DeployMocks is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEV_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MockERC20_18 t18 = new MockERC20_18();
        MockUSDC_6 usdc = new MockUSDC_6();
        MockWBTC_8 wbtc = new MockWBTC_8();
        MockEURS_2 eurs = new MockEURS_2();
        MockUSDTLike_6 usdt = new MockUSDTLike_6();

        console.log("MockERC20_18:", address(t18));
        console.log("MockUSDC_6:", address(usdc));
        console.log("MockWBTC_8:", address(wbtc));
        console.log("MockEURS_2:", address(eurs));
        console.log("MockUSDTLike_6:", address(usdt));

        vm.stopBroadcast();
    }
}

// How to deploy to Sepolia
// forge script script/DeployMocks.s.sol:DeployMocks --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv
// How your FE dev mints
// Call mint(devAddress, amount) on any of the deployed mock token contracts (no owner needed).
