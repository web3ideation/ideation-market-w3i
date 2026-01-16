// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title MockUSDTLike_6
/// @notice USDT-like ERC20 used to test non-standard return values and allowance update quirks.
/// @dev Not ERC20 ABI-compliant on purpose:
/// - transfer/transferFrom/approve do NOT return bool
/// - approve enforces "must set allowance to 0 before changing to non-zero"
/// Permissionless minting for testnet UX.
contract MockUSDTLike_6 {
    string public constant name = "Mock USDT";
    string public constant symbol = "mUSDT";
    uint8 public constant decimals = 6;

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 value) external {
        uint256 current = allowance[msg.sender][spender];
        if (value != 0 && current != 0) revert("USDTLike: must reset allowance to 0");
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
    }

    function transfer(address to, uint256 value) external {
        _transfer(msg.sender, to, value);
    }

    function transferFrom(address from, address to, uint256 value) external {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < value) revert("USDTLike: insufficient allowance");
            allowance[from][msg.sender] = allowed - value;
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }
        _transfer(from, to, value);
    }

    function _transfer(address from, address to, uint256 value) internal {
        if (to == address(0)) revert("USDTLike: transfer to zero");
        uint256 bal = balanceOf[from];
        if (bal < value) revert("USDTLike: insufficient balance");
        unchecked {
            balanceOf[from] = bal - value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }
}
