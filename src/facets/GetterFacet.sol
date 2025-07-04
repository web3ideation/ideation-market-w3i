// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";

error GetterFacet__ListingNotFound(uint128 listingId);
error GetterFacet__NoActiveListings(address tokenAddress, uint256 tokenId);

contract GetterFacet {
    /// @notice Returns all active listings for a given NFT (ERC-721 or ERC-1155).
    /// @param tokenAddress The address of the NFT contract.
    /// @param tokenId    The tokenId within that contract.
    /// @return listings  An array of Listing structs that are still active.
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
            revert GetterFacet__NoActiveListings(tokenAddress, tokenId);
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
    function getListingByListingId(uint128 listingId) external view returns (Listing memory listing) {
        AppStorage storage s = LibAppStorage.appStorage();
        listing = s.listings[listingId];
        if (listing.seller == address(0)) {
            revert GetterFacet__ListingNotFound(listingId);
        }
        return listing;
    }

    /**
     * @notice Returns the proceeds available for a seller.
     * @param seller The seller's address.
     * @return The total proceeds for the seller.
     */
    function getProceeds(address seller) external view returns (uint256) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.proceeds[seller];
    }

    /**
     * @notice Returns the contract's Ether balance.
     * @return The balance of the contract in wei.
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // add natspec
    function getInnovationFee() external view returns (uint32 innovationFee) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.innovationFee;
    }

    /**
     * @notice Returns the upcoming listing ID, the current counter + 1.
     * @return The next listing ID.
     */
    function getNextListingId() external view returns (uint128) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.listingIdCounter + 1;
    }

    /**
     * @notice Checks if a given NFT collection is whitelisted.
     * @param collection The address of the NFT collection.
     * @return True if the collection is whitelisted, false otherwise.
     */
    function isCollectionWhitelisted(address collection) external view returns (bool) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.whitelistedCollections[collection];
    }

    /**
     * @notice Returns the array of whitelisted NFT collection addresses.
     * @return An array of addresses that are whitelisted.
     */
    function getWhitelistedCollections() external view returns (address[] memory) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.whitelistedCollectionsArray;
    }

    /**
     * @notice Returns the contract owner address.
     * @return The address of the contract owner.
     */
    function getContractOwner() external view returns (address) {
        return LibDiamond.contractOwner();
    }

    /// @notice Checks if a buyer is whitelisted for a specific listing.
    /// @param listingId ID number of the Listing.
    /// @param buyer The buyer address to check.
    /// @return True if the buyer is whitelisted, false otherwise.
    function isBuyerWhitelisted(uint128 listingId, address buyer) external view returns (bool) {
        AppStorage storage s = LibAppStorage.appStorage();
        if (s.listings[listingId].seller == address(0)) {
            revert GetterFacet__ListingNotFound(listingId);
        }
        return s.whitelistedBuyersByListingId[listingId][buyer];
    }

    /// @notice Returns the maximum number of buyers you can whitelist in one batch.
    /// @return maxBatchSize The `buyerWhitelistMaxBatchSize` (e.g. 300).
    function getBuyerWhitelistMaxBatchSize() external view returns (uint16 maxBatchSize) {
        return LibAppStorage.appStorage().buyerWhitelistMaxBatchSize;
    }
}
