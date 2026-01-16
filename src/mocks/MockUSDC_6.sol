// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MockMintableERC20} from "./MockMintableERC20.sol";

/// @notice 6-decimal mintable ERC20 (USDC-like decimals).
contract MockUSDC_6 is MockMintableERC20 {
    constructor() MockMintableERC20("Mock USDC", "mUSDC", 6) {}
}
