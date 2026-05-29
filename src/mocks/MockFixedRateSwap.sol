// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

/// @title MockFixedRateSwap
/// @notice Deterministic exact-input swap mock for a small testnet token set.
/// @dev Uses contract-prefunded liquidity only and low-level ERC20 calls so it can work with USDT-like tokens.
contract MockFixedRateSwap {
    using Math for uint256;

    struct PairConfig {
        uint256 rateNumerator;
        uint256 rateDenominator;
        uint16 feeBps;
        bool enabled;
    }

    error MockFixedRateSwap__NotOwner();
    error MockFixedRateSwap__InvalidAddress();
    error MockFixedRateSwap__InvalidRate();
    error MockFixedRateSwap__InvalidFeeBps();
    error MockFixedRateSwap__PairNotEnabled(address srcToken, address dstToken);
    error MockFixedRateSwap__IdenticalTokens();
    error MockFixedRateSwap__InsufficientMsgValue(uint256 expected, uint256 actual);
    error MockFixedRateSwap__UnexpectedMsgValue(uint256 actual);
    error MockFixedRateSwap__InsufficientLiquidity(address token, uint256 required, uint256 available);
    error MockFixedRateSwap__InsufficientOutputAmount(uint256 minAmountOut, uint256 actualAmountOut);
    error MockFixedRateSwap__ERC20TransferFailed(address token, address to, uint256 amount);
    error MockFixedRateSwap__ERC20TransferFromFailed(address token, address from, address to, uint256 amount);
    error MockFixedRateSwap__ETHTransferFailed(address to, uint256 amount);

    event PairConfigured(
        address indexed srcToken,
        address indexed dstToken,
        uint256 rateNumerator,
        uint256 rateDenominator,
        uint16 feeBps
    );
    event SwapExecuted(
        address indexed sender,
        address indexed recipient,
        address indexed srcToken,
        address dstToken,
        uint256 amountIn,
        uint256 amountOut,
        uint256 minAmountOut
    );
    event TokenWithdrawn(address indexed token, address indexed to, uint256 amount);
    event ETHWithdrawn(address indexed to, uint256 amount);

    bytes4 private constant TRANSFER_SELECTOR = 0xa9059cbb;
    bytes4 private constant TRANSFER_FROM_SELECTOR = 0x23b872dd;

    address public immutable owner;

    mapping(address => mapping(address => PairConfig)) public pairConfigs;

    modifier onlyOwner() {
        if (msg.sender != owner) revert MockFixedRateSwap__NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    receive() external payable {}

    function setPair(address srcToken, address dstToken, uint256 rateNumerator, uint256 rateDenominator, uint16 feeBps)
        external
        onlyOwner
    {
        if (srcToken == dstToken) revert MockFixedRateSwap__IdenticalTokens();
        if (rateNumerator == 0 || rateDenominator == 0) revert MockFixedRateSwap__InvalidRate();
        if (feeBps > 10_000) revert MockFixedRateSwap__InvalidFeeBps();

        pairConfigs[srcToken][dstToken] =
            PairConfig({rateNumerator: rateNumerator, rateDenominator: rateDenominator, feeBps: feeBps, enabled: true});

        emit PairConfigured(srcToken, dstToken, rateNumerator, rateDenominator, feeBps);
    }

    function disablePair(address srcToken, address dstToken) external onlyOwner {
        PairConfig storage config = pairConfigs[srcToken][dstToken];
        if (!config.enabled) revert MockFixedRateSwap__PairNotEnabled(srcToken, dstToken);
        config.enabled = false;
    }

    function quoteExactInput(address srcToken, address dstToken, uint256 amountIn)
        public
        view
        returns (uint256 amountOut)
    {
        if (srcToken == dstToken) revert MockFixedRateSwap__IdenticalTokens();

        PairConfig memory config = pairConfigs[srcToken][dstToken];
        if (!config.enabled) revert MockFixedRateSwap__PairNotEnabled(srcToken, dstToken);

        uint256 grossAmountOut = amountIn.mulDiv(config.rateNumerator, config.rateDenominator);
        amountOut = grossAmountOut.mulDiv(10_000 - config.feeBps, 10_000);
    }

    function swapExactInput(
        address srcToken,
        address dstToken,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient
    ) external payable returns (uint256 amountOut) {
        if (recipient == address(0)) revert MockFixedRateSwap__InvalidAddress();

        amountOut = quoteExactInput(srcToken, dstToken, amountIn);
        if (amountOut < minAmountOut) {
            revert MockFixedRateSwap__InsufficientOutputAmount(minAmountOut, amountOut);
        }

        if (srcToken == address(0)) {
            if (msg.value != amountIn) revert MockFixedRateSwap__InsufficientMsgValue(amountIn, msg.value);
        } else {
            if (msg.value != 0) revert MockFixedRateSwap__UnexpectedMsgValue(msg.value);
            _safeTransferFrom(srcToken, msg.sender, address(this), amountIn);
        }

        if (dstToken == address(0)) {
            uint256 availableETH = address(this).balance;
            if (availableETH < amountOut) {
                revert MockFixedRateSwap__InsufficientLiquidity(address(0), amountOut, availableETH);
            } else {
                (bool success,) = recipient.call{value: amountOut}("");
                if (!success) revert MockFixedRateSwap__ETHTransferFailed(recipient, amountOut);
            }
        } else {
            uint256 availableToken = _balanceOf(dstToken, address(this));
            if (availableToken < amountOut) {
                revert MockFixedRateSwap__InsufficientLiquidity(dstToken, amountOut, availableToken);
            }
            _safeTransfer(dstToken, recipient, amountOut);
        }

        emit SwapExecuted(msg.sender, recipient, srcToken, dstToken, amountIn, amountOut, minAmountOut);
    }

    function withdrawToken(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert MockFixedRateSwap__InvalidAddress();
        uint256 availableToken = _balanceOf(token, address(this));
        if (availableToken < amount) {
            revert MockFixedRateSwap__InsufficientLiquidity(token, amount, availableToken);
        }
        _safeTransfer(token, to, amount);
        emit TokenWithdrawn(token, to, amount);
    }

    function withdrawETH(address payable to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert MockFixedRateSwap__InvalidAddress();
        uint256 availableETH = address(this).balance;
        if (availableETH < amount) {
            revert MockFixedRateSwap__InsufficientLiquidity(address(0), amount, availableETH);
        }
        (bool success,) = to.call{value: amount}("");
        if (!success) revert MockFixedRateSwap__ETHTransferFailed(to, amount);
        emit ETHWithdrawn(to, amount);
    }

    function availableLiquidity(address token) external view returns (uint256 balance) {
        if (token == address(0)) {
            return address(this).balance;
        }

        return _balanceOf(token, address(this));
    }

    function _balanceOf(address token, address account) internal view returns (uint256 balance) {
        (bool success, bytes memory returndata) =
            token.staticcall(abi.encodeWithSignature("balanceOf(address)", account));
        if (!success || returndata.length < 32) {
            revert MockFixedRateSwap__ERC20TransferFailed(token, account, 0);
        }
        balance = abi.decode(returndata, (uint256));
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        if (token.code.length == 0) revert MockFixedRateSwap__InvalidAddress();

        (bool success, bytes memory returndata) = token.call(abi.encodeWithSelector(TRANSFER_SELECTOR, to, amount));
        if (!success || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
            revert MockFixedRateSwap__ERC20TransferFailed(token, to, amount);
        }
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        if (token.code.length == 0) revert MockFixedRateSwap__InvalidAddress();

        (bool success, bytes memory returndata) =
            token.call(abi.encodeWithSelector(TRANSFER_FROM_SELECTOR, from, to, amount));
        if (!success || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
            revert MockFixedRateSwap__ERC20TransferFromFailed(token, from, to, amount);
        }
    }
}
