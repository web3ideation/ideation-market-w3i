// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {LegacyNFT} from "../src/LegacyNFT.sol";

contract DeployLegacyNFT is Script {
    function run() external returns (LegacyNFT) {
        vm.startBroadcast();
        LegacyNFT legacyNFT = new LegacyNFT();
        vm.stopBroadcast();
        return legacyNFT;
    }
}

// forge script script/DeployLegacyNFTAnvil.s.sol --rpc-url http://localhost:8545 --broadcast --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
