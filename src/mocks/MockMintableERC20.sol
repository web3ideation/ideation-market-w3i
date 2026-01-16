// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @title MockMintableERC20
/// @notice Simple ERC20 with configurable decimals and permissionless minting.
/// @dev Intended ONLY for testnets / local testing.
contract MockMintableERC20 is ERC20 {
    uint8 private immutable _tokenDecimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _tokenDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _tokenDecimals;
    }

    /// @notice Permissionless mint, for testnet UX.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
