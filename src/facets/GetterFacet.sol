// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";

error Getter__ListingNotFound(uint128 listingId);

/// @title GetterFacet
/// @notice Read-only queries for listings, proceeds, owner/config, and whitelist state.
/// @dev All functions are `view` and read from `LibAppStorage` / `LibDiamond` storage.
contract GetterFacet {
    /// @notice Returns the active listing id for an ERC-721 token.
    /// @dev Returns 0 if there is no active listing.
    function getActiveListingIdByERC721(address tokenAddress, uint256 tokenId) external view returns (uint128) {
        return LibAppStorage.appStorage().activeListingIdByERC721[tokenAddress][tokenId];
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

    // Currency Allowlist Getters

    /// @notice Check if a currency is allowed for new listings.
    /// @param currency Token address to check (address(0) = native ETH).
    /// @return True if currency can be used in createListing.
    function isCurrencyAllowed(address currency) external view returns (bool) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.allowedCurrencies[currency];
    }

    /// @notice Get all allowed currencies as an array.
    /// @return currencies Array of all allowed token addresses (includes address(0) for ETH if added).
    function getAllowedCurrencies() external view returns (address[] memory currencies) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.allowedCurrenciesArray;
    }

    // Diamond Versioning Getters

    /// @notice Returns the current version information.
    /// @return version Semantic version string.
    /// @return implementationId Hash of current diamond configuration.
    /// @return timestamp When this version was set.
    function getVersion() external view returns (string memory version, bytes32 implementationId, uint256 timestamp) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return (ds.currentVersion, ds.currentImplementationId, ds.currentVersionTimestamp);
    }

    /// @notice Returns the previous version information (before last upgrade).
    /// @return version Previous semantic version string.
    /// @return implementationId Hash of previous diamond configuration.
    /// @return timestamp When that version was set.
    function getPreviousVersion()
        external
        view
        returns (string memory version, bytes32 implementationId, uint256 timestamp)
    {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return (ds.previousVersion, ds.previousImplementationId, ds.previousVersionTimestamp);
    }

    /// @notice Returns the current version string only.
    /// @dev Convenience method for simple version checks.
    function getVersionString() external view returns (string memory) {
        return LibDiamond.diamondStorage().currentVersion;
    }

    /// @notice Returns the current implementation ID only.
    /// @dev Convenience method for configuration verification.
    function getImplementationId() external view returns (bytes32) {
        return LibDiamond.diamondStorage().currentImplementationId;
    }

    /// @notice Returns whether the marketplace is currently paused.
    /// @return paused True if paused (createListing, purchaseListing, updateListing disabled), false otherwise.
    function isPaused() external view returns (bool) {
        return LibDiamond.diamondStorage().paused;
    }
}
