// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";

contract GetterFacet {
    /**
     * @notice Returns the listing details for a specific NFT.
     * @param nftAddress The NFT contract address.
     * @param tokenId The NFT token ID.
     * @return listing The Listing struct containing listing details.
     */
    function getListing(address nftAddress, uint256 tokenId) external view returns (Listing memory) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.listings[nftAddress][tokenId];
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
    /// @param nftAddress The NFT contract address.
    /// @param tokenId The token ID.
    /// @param buyer The buyer address to check.
    /// @return True if the buyer is whitelisted, false otherwise.
    function isBuyerWhitelisted(address nftAddress, uint256 tokenId, address buyer) external view returns (bool) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.whitelistedBuyersByNFT[nftAddress][tokenId][buyer];
    }
}
