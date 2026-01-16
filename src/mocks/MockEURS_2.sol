// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MockMintableERC20} from "./MockMintableERC20.sol";

/// @notice 2-decimal mintable ERC20 (EURS mainnet decimals are 2).
contract MockEURS_2 is MockMintableERC20 {
    constructor() MockMintableERC20("Mock EURS", "mEURS", 2) {}
}
