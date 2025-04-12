// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";

error CollectionWhitelist__AlreadyWhitelisted();
error CollectionWhitelist__NotWhitelisted();

// these are relevant storage Variables defined in the LibAppStorage.sol
// mapping(address => bool) whitelistedCollections; // whitelisted collection (NFT) Address => true (or false if this collection has not been whitelisted)
// address[] whitelistedCollectionsArray; // for lookups
// mapping(address => uint256) whitelistedCollectionsIndex; // to make lookups and deletions more efficient

contract CollectionWhitelistFacet {
    // Only diamond owner can update the whitelist.
    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    /// @notice Adds a single NFT contract address to the whitelist.
    /// @param nftAddress The NFT contract address to whitelist.
    function addWhitelistedCollection(address nftAddress) public onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();
        if (s.whitelistedCollections[nftAddress]) revert CollectionWhitelist__AlreadyWhitelisted();

        s.whitelistedCollections[nftAddress] = true;
        s.whitelistedCollectionsIndex[nftAddress] = s.whitelistedCollectionsArray.length;
        s.whitelistedCollectionsArray.push(nftAddress);
    }

    // when removing collections from the whitelist consider canceling active listings of such
    /// @notice Removes a single NFT contract address from the whitelist.
    /// @param nftAddress The NFT contract address to remove.
    function removeWhitelistedCollection(address nftAddress) public onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();
        if (!s.whitelistedCollections[nftAddress]) revert CollectionWhitelist__NotWhitelisted();

        // Get the index of the element to remove.
        uint256 index = s.whitelistedCollectionsIndex[nftAddress];
        uint256 lastIndex = s.whitelistedCollectionsArray.length - 1;
        address lastAddress = s.whitelistedCollectionsArray[lastIndex];

        // Swap the element with the last element if it's not the one to remove.
        if (index != lastIndex) {
            s.whitelistedCollectionsArray[index] = lastAddress;
            s.whitelistedCollectionsIndex[lastAddress] = index;
        }

        // Remove the last element.
        s.whitelistedCollectionsArray.pop();
        delete s.whitelistedCollectionsIndex[nftAddress];
        s.whitelistedCollections[nftAddress] = false;
    }

    /// @notice Batch adds multiple NFT contract addresses to the whitelist.
    /// @param nftAddresses Array of NFT contract addresses to whitelist.
    function addWhitelistedCollections(address[] calldata nftAddresses) external onlyOwner {
        for (uint256 i = 0; i < nftAddresses.length; i++) {
            // Only add if not already whitelisted.
            if (!LibAppStorage.appStorage().whitelistedCollections[nftAddresses[i]]) {
                addWhitelistedCollection(nftAddresses[i]);
            }
        }
    }

    // when removing collections from the whitelist consider canceling active listings of such
    /// @notice Batch removes multiple NFT contract addresses from the whitelist.
    /// @param nftAddresses Array of NFT contract addresses to remove.
    function removeWhitelistedCollections(address[] calldata nftAddresses) external onlyOwner {
        for (uint256 i = 0; i < nftAddresses.length; i++) {
            // Only remove if the address is currently whitelisted.
            if (LibAppStorage.appStorage().whitelistedCollections[nftAddresses[i]]) {
                removeWhitelistedCollection(nftAddresses[i]);
            }
        }
    }
}
