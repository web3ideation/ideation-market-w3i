// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MockMintableERC20} from "./MockMintableERC20.sol";

/// @notice 8-decimal mintable ERC20 (WBTC-like decimals).
contract MockWBTC_8 is MockMintableERC20 {
    constructor() MockMintableERC20("Mock WBTC", "mWBTC", 8) {}
}
