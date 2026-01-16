// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MockMintableERC20} from "./MockMintableERC20.sol";

/// @notice Standard 18-decimal mintable ERC20.
contract MockERC20_18 is MockMintableERC20 {
    constructor() MockMintableERC20("Mock ERC20 18", "mERC20", 18) {}
}
