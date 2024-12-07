// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {LegacyNFT} from "../src/LegacyNFT.sol";

contract DeployLegacyNFTSepolia is Script {
    function run() external returns (LegacyNFT) {
        // Start broadcasting the transaction
        vm.startBroadcast();

        // Deploy the SimpleERC721 contract
        LegacyNFT legacyNFT = new LegacyNFT();

        // Stop broadcasting the transaction
        vm.stopBroadcast();

        return legacyNFT;
    }
}

// to deploy run: source .env AND forge script script/DeployLegacyNFTSepolia.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify --account defaultKey --sender 0xe8df60a93b2b328397a8cbf73f0d732aaa11e33d
