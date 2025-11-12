// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";

error PaymentFacet__NoProceeds();
error PaymentFacet__TransferFailed();
error PaymentFacet__CurrencyAlreadyAllowed();
error PaymentFacet__CurrencyNotAllowed();
error PaymentFacet__ArrayLengthMismatch();
error PaymentFacet__Reentrant();

/// @title PaymentFacet
/// @notice Manages multi-currency proceeds withdrawals and currency allowlist for IdeationMarket.
/// @dev This facet isolates payment logic from marketplace logic for cleaner separation of concerns.
/// All proceeds are tracked in `proceedsByToken[seller][currency]` mapping in AppStorage.
/// Supports both ETH (address(0)) and ERC-20 tokens.
contract PaymentFacet {
    /// @notice Emitted when a user withdraws proceeds in a specific currency.
    /// @param seller Address that withdrew proceeds.
    /// @param currency Token address (address(0) = ETH).
    /// @param amount Amount withdrawn.
    event ProceedsWithdrawn(address indexed seller, address indexed currency, uint256 amount);

    /// @notice Emitted when a currency is added to the allowlist.
    /// @param currency Token address added (address(0) = ETH).
    event CurrencyAllowed(address indexed currency);

    /// @notice Emitted when a currency is removed from the allowlist.
    /// @param currency Token address removed.
    event CurrencyRemoved(address indexed currency);

    ///////////////
    // Modifiers //
    ///////////////

    /// @notice Prevents reentrancy attacks using a simple boolean lock.
    /// @dev Uses AppStorage.reentrancyLock to work across all facets in the diamond.
    modifier nonReentrant() {
        AppStorage storage s = LibAppStorage.appStorage();
        if (s.reentrancyLock) revert PaymentFacet__Reentrant();
        s.reentrancyLock = true;
        _;
        s.reentrancyLock = false;
    }

    //////////////////////////
    // Withdrawal Functions //
    //////////////////////////

    /// @notice Withdraw proceeds in a specific currency.
    /// @dev Sends entire balance of `currency` to msg.sender and zeros out the balance.
    /// For ETH: Uses low-level call{value} for security (avoids 2300 gas stipend limit).
    /// For ERC-20: Uses SafeERC20-style transfer (handles USDT and other non-standard tokens).
    /// @param currency Token address to withdraw (address(0) = ETH).
    function withdrawProceeds(address currency) external nonReentrant {
        AppStorage storage s = LibAppStorage.appStorage();

        // Get seller's balance in this currency
        uint256 amount = s.proceedsByToken[msg.sender][currency];

        // Revert if nothing to withdraw
        if (amount == 0) revert PaymentFacet__NoProceeds();

        // Zero out balance before transfer
        s.proceedsByToken[msg.sender][currency] = 0;

        // Transfer based on currency type
        if (currency == address(0)) {
            // ETH withdrawal: Use call instead of transfer for compatibility with multisig wallets
            (bool success,) = payable(msg.sender).call{value: amount}("");
            if (!success) revert PaymentFacet__TransferFailed();
        } else {
            // ERC-20 withdrawal: Use SafeERC20-style transfer
            // This handles tokens like USDT that don't return bool
            _safeTransfer(currency, msg.sender, amount);
        }

        emit ProceedsWithdrawn(msg.sender, currency, amount);
    }

    /// @notice Withdraw ALL proceeds across all currencies automatically.
    /// @dev Iterates through all allowed currencies and withdraws any with non-zero balance.
    function withdrawAllProceeds() external nonReentrant {
        AppStorage storage s = LibAppStorage.appStorage();

        // Get all allowed currencies
        address[] memory allCurrencies = s.allowedCurrenciesArray;
        uint256 totalCurrencies = allCurrencies.length;

        // Track if at least one withdrawal succeeded
        bool hasWithdrawn = false;

        // Iterate through all currencies and withdraw if balance > 0
        for (uint256 i = 0; i < totalCurrencies;) {
            address currency = allCurrencies[i];
            uint256 amount = s.proceedsByToken[msg.sender][currency];

            // Skip if no balance
            if (amount > 0) {
                // Zero out balance before transfer
                s.proceedsByToken[msg.sender][currency] = 0;

                // Transfer based on currency type
                if (currency == address(0)) {
                    (bool success,) = payable(msg.sender).call{value: amount}("");
                    if (!success) revert PaymentFacet__TransferFailed();
                } else {
                    _safeTransfer(currency, msg.sender, amount);
                }

                emit ProceedsWithdrawn(msg.sender, currency, amount);
                hasWithdrawn = true;
            }

            unchecked {
                i++;
            }
        }

        // Revert if no proceeds in any currency
        if (!hasWithdrawn) revert PaymentFacet__NoProceeds();
    }

    ////////////////////////////////////////////////
    // Currency Allowlist Management (Owner Only) //
    ////////////////////////////////////////////////

    /// @notice Add a currency to the allowlist (enables it for new listings, does NOT affect existing listings).
    /// IMPORTANT: Only add tokens that are:
    /// - Battle-tested and widely used (USDC, WETH, etc.)
    /// - NOT fee-on-transfer (balance delta must equal transfer amount)
    /// - NOT rebasing (supply changes would break accounting)
    /// - NOT pausable by untrusted parties
    /// @param currency Token address to allow.
    function addAllowedCurrency(address currency) external {
        LibDiamond.enforceIsContractOwner(); // Only multisig can add currencies
        AppStorage storage s = LibAppStorage.appStorage();

        // Check if already allowed (prevent duplicate entries)
        if (s.allowedCurrencies[currency]) revert PaymentFacet__CurrencyAlreadyAllowed();

        // Add to mapping
        s.allowedCurrencies[currency] = true;

        // Add to array for enumeration (frontend needs this for dropdown menus)
        s.allowedCurrenciesIndex[currency] = s.allowedCurrenciesArray.length; // Store index before push
        s.allowedCurrenciesArray.push(currency);
        emit CurrencyAllowed(currency);
    }

    /// @notice Remove a currency from the allowlist (prevents new listings in that currency, does NOT affect existing listings or proceeds).
    /// @param currency Token address to remove.
    function removeAllowedCurrency(address currency) external {
        LibDiamond.enforceIsContractOwner(); // Only multisig can remove currencies
        AppStorage storage s = LibAppStorage.appStorage();

        // Check if currency is in the allowlist
        if (!s.allowedCurrencies[currency]) revert PaymentFacet__CurrencyNotAllowed();

        // Remove from mapping
        s.allowedCurrencies[currency] = false;

        // Remove from array using swap-and-pop pattern (O(1) removal)
        uint256 index = s.allowedCurrenciesIndex[currency];
        uint256 lastIndex = s.allowedCurrenciesArray.length - 1;

        // If not the last element, swap with last element
        if (index != lastIndex) {
            address lastCurrency = s.allowedCurrenciesArray[lastIndex];
            s.allowedCurrenciesArray[index] = lastCurrency;
            s.allowedCurrenciesIndex[lastCurrency] = index; // Update swapped element's index
        }

        // Remove last element
        s.allowedCurrenciesArray.pop();

        // Clear index mapping
        delete s.allowedCurrenciesIndex[currency];

        emit CurrencyRemoved(currency);
    }

    //////////////////////////////
    //Internal Helper Functions //
    //////////////////////////////

    /// @notice SafeERC20-style transfer that handles non-standard tokens.
    /// @dev Handles tokens like USDT that don't return bool, and tokens that return false on failure.
    /// Uses low-level call to avoid ABI decoding issues with non-compliant tokens.
    /// @param token ERC-20 token address.
    /// @param to Recipient address.
    /// @param amount Amount to transfer.
    function _safeTransfer(address token, address to, uint256 amount) private {
        // Build the calldata for ERC20.transfer(address,uint256)
        // Function selector: bytes4(keccak256("transfer(address,uint256)")) = 0xa9059cbb
        bytes memory data = abi.encodeWithSelector(0xa9059cbb, to, amount);

        // Call the token contract
        (bool success, bytes memory returndata) = token.call(data);

        // Check for success:
        // 1. Call must not revert
        // 2. If returndata exists, it must decode to true (handles tokens that return bool)
        // 3. If no returndata, assume success (handles USDT, XAUt that don't return anything)
        if (!success || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
            revert PaymentFacet__TransferFailed();
        }
    }
}
