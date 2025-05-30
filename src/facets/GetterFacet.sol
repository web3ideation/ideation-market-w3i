// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";

contract GetterFacet {
    /**
     * @notice Returns the listing details for a specific NFT.
     */
    function getListingIdsByNFT(address nftAddress, uint256 tokenId) external view /*!!!multiple arrays*/ {
        AppStorage storage s = LibAppStorage.appStorage();
        uint128[] storage listingArray = s.nftTokenToListingIds[nftAddress][tokenId];
        for (uint256 i; i < listingArray.length; ++i) {
            // !!! here an Listings Array should get filled which then gets returned so that when the user enters nftAddress and tokenId he would get all listing Structs
        }
    }

    /// @notice Returns the Listing struct for a given listingId.
    /// @param listingId The ID of the listing to retrieve.
    /// @return listing The Listing struct.
    function getListingByListingId(uint128 listingId) external view returns (Listing memory) {
        return LibAppStorage.appStorage().listings[listingId];
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
        return s.whitelistedBuyersByListingId[listingId][buyer];
    }
}
