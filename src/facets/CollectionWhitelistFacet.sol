// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";

error CollectionWhitelist__AlreadyWhitelisted();
error CollectionWhitelist__NotWhitelisted();

contract CollectionWhitelistFacet {
    /// @notice Emitted when a collection is added.
    event CollectionAddedToWhitelist(address indexed tokenAddress);

    /// @notice Emitted when a collection is removed.
    event CollectionRemovedFromWhitelist(address indexed tokenAddress);

    // Only diamond owner can update the whitelist.
    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    /// @notice Adds a single NFT contract address to the whitelist.
    /// @param tokenAddress The NFT contract address to whitelist.
    function addWhitelistedCollection(address tokenAddress) public onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();
        if (s.whitelistedCollections[tokenAddress]) revert CollectionWhitelist__AlreadyWhitelisted();

        s.whitelistedCollections[tokenAddress] = true;
        s.whitelistedCollectionsIndex[tokenAddress] = s.whitelistedCollectionsArray.length;
        s.whitelistedCollectionsArray.push(tokenAddress);

        emit CollectionAddedToWhitelist(tokenAddress);
    }

    // when removing collections from the whitelist consider canceling active listings of such
    /// @notice Removes a single NFT contract address from the whitelist.
    /// @param tokenAddress The NFT contract address to remove.
    function removeWhitelistedCollection(address tokenAddress) public onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();
        if (!s.whitelistedCollections[tokenAddress]) revert CollectionWhitelist__NotWhitelisted();

        // Get the index of the element to remove.
        uint256 index = s.whitelistedCollectionsIndex[tokenAddress];
        uint256 lastIndex = s.whitelistedCollectionsArray.length - 1;
        address lastAddress = s.whitelistedCollectionsArray[lastIndex];

        // Swap the element with the last element if it's not the one to remove.
        if (index != lastIndex) {
            s.whitelistedCollectionsArray[index] = lastAddress;
            s.whitelistedCollectionsIndex[lastAddress] = index;
        }

        // Remove the last element.
        s.whitelistedCollectionsArray.pop();
        delete s.whitelistedCollectionsIndex[tokenAddress];
        s.whitelistedCollections[tokenAddress] = false;

        emit CollectionRemovedFromWhitelist(tokenAddress);
    }

    /// @notice Batch adds multiple NFT contract addresses to the whitelist.
    /// @param tokenAddresses Array of NFT contract addresses to whitelist.
    function addWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            // Only add if not already whitelisted.
            if (!LibAppStorage.appStorage().whitelistedCollections[tokenAddresses[i]]) {
                addWhitelistedCollection(tokenAddresses[i]);
            }
        }
    }

    // when removing collections from the whitelist consider canceling active listings of such
    /// @notice Batch removes multiple NFT contract addresses from the whitelist.
    /// @param tokenAddresses Array of NFT contract addresses to remove.
    function removeWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            // Only remove if the address is currently whitelisted.
            if (LibAppStorage.appStorage().whitelistedCollections[tokenAddresses[i]]) {
                removeWhitelistedCollection(tokenAddresses[i]);
            }
        }
    }
}
