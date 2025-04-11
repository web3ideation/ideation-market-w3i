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

    /**
     * @notice Returns the fee configuration details.
     * @return ideationMarketFee The total marketplace fee.
     * @return founder1 The first founder's address.
     * @return founder1Ratio The fee ratio for founder1.
     * @return founder2 The second founder's address.
     * @return founder2Ratio The fee ratio for founder2.
     * @return founder3 The third founder's address.
     * @return founder3Ratio The fee ratio for founder3.
     */
    function getFeeValues()
        external
        view
        returns (
            uint256 ideationMarketFee,
            address founder1,
            uint32 founder1Ratio,
            address founder2,
            uint32 founder2Ratio,
            address founder3,
            uint32 founder3Ratio
        )
    {
        AppStorage storage s = LibAppStorage.appStorage();
        return
            (s.ideationMarketFee, s.founder1, s.founder1Ratio, s.founder2, s.founder2Ratio, s.founder3, s.founder3Ratio);
    }

    /**
     * @notice Returns the current listing ID counter.
     * @return The current listing ID.
     */
    function getCurrentListingId() external view returns (uint128) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.listingId;
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

    // !!!W should i add the getNextListingId? I deleted this from the marketplace facet, maybe because its obsolete?
}
