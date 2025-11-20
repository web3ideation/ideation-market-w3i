// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";

error CurrencyWhitelist__AlreadyAllowed();
error CurrencyWhitelist__NotAllowed();

/// @title CurrencyWhitelistFacet
/// @notice Manages the curated allowlist of payment currencies for marketplace listings.
/// @dev Prevents fee-on-transfer, rebasing, or malicious tokens from being used.
/// Only the contract owner (multisig) can modify the allowlist.
/// Native ETH is represented as address(0).
contract CurrencyWhitelistFacet {
    /// @notice Emitted when a currency is added to the allowlist.
    /// @param currency Token address added (address(0) = native ETH).
    event CurrencyAllowed(address indexed currency);

    /// @notice Emitted when a currency is removed from the allowlist.
    /// @param currency Token address removed.
    event CurrencyRemoved(address indexed currency);

    /// @notice Add a currency to the allowlist, enabling it for new listings.
    /// @dev Owner only. Only add battle-tested tokens that are NOT:
    /// - Fee-on-transfer (e.g., some meme tokens where transfer deducts fees)
    /// - Rebasing (e.g., stETH, aTokens where balances change over time)
    /// - Pausable by untrusted parties
    /// - Upgradeable with malicious potential
    /// Existing listings are unaffected by allowlist changes.
    /// @param currency Token address to allow (address(0) for native ETH).
    function addAllowedCurrency(address currency) external {
        LibDiamond.enforceIsContractOwner();
        AppStorage storage s = LibAppStorage.appStorage();

        if (s.allowedCurrencies[currency]) revert CurrencyWhitelist__AlreadyAllowed();

        s.allowedCurrencies[currency] = true;
        s.allowedCurrenciesIndex[currency] = s.allowedCurrenciesArray.length;
        s.allowedCurrenciesArray.push(currency);

        emit CurrencyAllowed(currency);
    }

    /// @notice Remove a currency from the allowlist, preventing new listings in that currency.
    /// @dev Does NOT affect existing listings or their settlement. Owner only.
    /// Uses swap-and-pop for O(1) array removal.
    /// @param currency Token address to remove.
    function removeAllowedCurrency(address currency) external {
        LibDiamond.enforceIsContractOwner();
        AppStorage storage s = LibAppStorage.appStorage();

        if (!s.allowedCurrencies[currency]) revert CurrencyWhitelist__NotAllowed();

        s.allowedCurrencies[currency] = false;

        // Swap-and-pop removal from array
        uint256 index = s.allowedCurrenciesIndex[currency];
        uint256 lastIndex = s.allowedCurrenciesArray.length - 1;

        if (index != lastIndex) {
            address lastCurrency = s.allowedCurrenciesArray[lastIndex];
            s.allowedCurrenciesArray[index] = lastCurrency;
            s.allowedCurrenciesIndex[lastCurrency] = index;
        }

        s.allowedCurrenciesArray.pop();
        delete s.allowedCurrenciesIndex[currency];

        emit CurrencyRemoved(currency);
    }
}
