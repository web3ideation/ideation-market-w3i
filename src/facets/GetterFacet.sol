// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";

error Getter__ListingNotFound(uint128 listingId);
error Getter__NoActiveListings(address tokenAddress, uint256 tokenId);

/// @title GetterFacet
/// @notice Read-only queries for listings, proceeds, owner/config, and whitelist state.
/// @dev All functions are `view` and read from `LibAppStorage` / `LibDiamond` storage.
contract GetterFacet {
    /// @notice Returns all active listings for a given NFT (ERC-721 or ERC-1155).
    /// @param tokenAddress The address of the NFT contract.
    /// @param tokenId The tokenId within that contract.
    /// @return listings An array of Listing structs that are still active.
    /// @dev Reverts `Getter__NoActiveListings` if none found. Only listings with `seller != address(0)` are returned.
    function getListingsByNFT(address tokenAddress, uint256 tokenId)
        external
        view
        returns (Listing[] memory listings)
    {
        AppStorage storage s = LibAppStorage.appStorage();
        uint128[] storage listingArray = s.tokenToListingIds[tokenAddress][tokenId];
        uint256 totalIds = listingArray.length;

        // First pass: count how many listings are still active (seller != address(0))
        uint256 activeCount = 0;
        for (uint256 i = 0; i < totalIds;) {
            if (s.listings[listingArray[i]].seller != address(0)) {
                activeCount++;
            }
            unchecked {
                i++;
            }
        }

        if (activeCount == 0) {
            revert Getter__NoActiveListings(tokenAddress, tokenId);
        }

        // Allocate a memory array of exactly activeCount size
        listings = new Listing[](activeCount);

        // Second pass: fill that array with active listings
        uint256 arrayIndex = 0;
        for (uint256 i = 0; i < totalIds;) {
            Listing storage current = s.listings[listingArray[i]];
            if (current.seller != address(0)) {
                listings[arrayIndex] = current;
                arrayIndex++;
            }
            unchecked {
                i++;
            }
        }

        return listings;
    }

    /// @notice Returns the Listing struct for a given listingId.
    /// @param listingId The ID of the listing to retrieve.
    /// @return listing The Listing struct.
    /// @dev Reverts `Getter__ListingNotFound` if the listing was removed or never existed.
    function getListingByListingId(uint128 listingId) external view returns (Listing memory listing) {
        AppStorage storage s = LibAppStorage.appStorage();
        listing = s.listings[listingId];
        if (listing.seller == address(0)) {
            revert Getter__ListingNotFound(listingId);
        }
        return listing;
    }

    /// @notice Returns the contract's Ether balance.
    /// @return The balance of the contract in wei.
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Returns the current marketplace fee rate.
    /// @return innovationFee The fee rate with denominator 100_000 (e.g., 1_000 = 1%).
    function getInnovationFee() external view returns (uint32 innovationFee) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.innovationFee;
    }

    /// @notice Returns the upcoming listing ID, i.e., the current counter + 1.
    /// @return The next listing ID.
    function getNextListingId() external view returns (uint128) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.listingIdCounter + 1;
    }

    /// @notice Checks if a given NFT collection is whitelisted.
    /// @param collection The address of the NFT collection.
    /// @return True if the collection is whitelisted, false otherwise.
    function isCollectionWhitelisted(address collection) external view returns (bool) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.whitelistedCollections[collection];
    }

    /// @notice Returns the array of whitelisted NFT collection addresses.
    /// @return An array of addresses that are whitelisted.
    /// @dev Returns an in-memory copy of the tracked array (gas scales with size).
    function getWhitelistedCollections() external view returns (address[] memory) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.whitelistedCollectionsArray;
    }

    /// @notice Returns the contract owner address.
    /// @return The address of the contract owner.
    function getContractOwner() external view returns (address) {
        return LibDiamond.contractOwner();
    }

    /// @notice Checks if a buyer is whitelisted for a specific listing.
    /// @param listingId ID number of the Listing.
    /// @param buyer The buyer address to check.
    /// @return True if the buyer is whitelisted, false otherwise.
    /// @dev Reverts `Getter__ListingNotFound` if the listing no longer exists.
    function isBuyerWhitelisted(uint128 listingId, address buyer) external view returns (bool) {
        AppStorage storage s = LibAppStorage.appStorage();
        if (s.listings[listingId].seller == address(0)) {
            revert Getter__ListingNotFound(listingId);
        }
        return s.whitelistedBuyersByListingId[listingId][buyer];
    }

    /// @notice Returns the maximum number of buyers you can whitelist in one batch.
    /// @return maxBatchSize The `buyerWhitelistMaxBatchSize` (e.g., 300).
    function getBuyerWhitelistMaxBatchSize() external view returns (uint16 maxBatchSize) {
        return LibAppStorage.appStorage().buyerWhitelistMaxBatchSize;
    }

    /// @notice Returns the address nominated to become owner (if any).
    /// @return The pending owner address or address(0) if none.
    function getPendingOwner() external view returns (address) {
        return LibDiamond.diamondStorage().pendingContractOwner;
    }

    // Multi-Currency Proceeds Getters

    /// @notice Get proceeds balance for a user in a specific currency.
    /// @param user Address to query (seller, royalty receiver, etc.).
    /// @param currency Token address (address(0) = ETH).
    /// @return amount Available proceeds in that currency.
    function getProceeds(address user, address currency) external view returns (uint256 amount) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.proceedsByToken[user][currency];
    }

    /// @notice Get ALL proceeds for a user across all currencies in one call.
    /// @dev Iterates through all allowed currencies and returns only those with non-zero balances.
    /// @param user Address to query (seller, royalty receiver, etc.).
    /// @return currencies Array of token addresses where user has proceeds.
    /// @return amounts Array of proceeds amounts (same order as currencies).
    function getAllProceeds(address user)
        external
        view
        returns (address[] memory currencies, uint256[] memory amounts)
    {
        AppStorage storage s = LibAppStorage.appStorage();

        // Get all allowed currencies
        address[] memory allCurrencies = s.allowedCurrenciesArray;
        uint256 totalCurrencies = allCurrencies.length;

        // First pass: count how many currencies have non-zero balance
        uint256 nonZeroCount = 0;
        for (uint256 i = 0; i < totalCurrencies;) {
            if (s.proceedsByToken[user][allCurrencies[i]] > 0) {
                nonZeroCount++;
            }
            unchecked {
                i++;
            }
        }

        // Allocate memory arrays of exact size needed
        currencies = new address[](nonZeroCount);
        amounts = new uint256[](nonZeroCount);

        // Second pass: populate arrays with non-zero balances
        uint256 arrayIndex = 0;
        for (uint256 i = 0; i < totalCurrencies;) {
            address currency = allCurrencies[i];
            uint256 balance = s.proceedsByToken[user][currency];
            if (balance > 0) {
                currencies[arrayIndex] = currency;
                amounts[arrayIndex] = balance;
                arrayIndex++;
            }
            unchecked {
                i++;
            }
        }

        return (currencies, amounts);
    }

    // Currency Allowlist Getters

    /// @notice Check if a currency is allowed for new listings.
    /// @param currency Token address to check.
    /// @return allowed True if currency can be used in createListing.
    function isAllowedCurrency(address currency) external view returns (bool allowed) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.allowedCurrencies[currency];
    }

    /// @notice Get all allowed currencies as an array.
    /// @dev Array includes address(0) for ETH.
    /// @return currencies Array of all allowed token addresses.
    function getAllowedCurrencies() external view returns (address[] memory currencies) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.allowedCurrenciesArray;
    }
}
