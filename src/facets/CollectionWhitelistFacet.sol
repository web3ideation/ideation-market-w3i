// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../libraries/LibDiamond.sol";

error CollectionWhitelist__AlreadyWhitelisted();
error CollectionWhitelist__NotWhitelisted();
error CollectionWhitelist__ZeroAddress();

/// @title CollectionWhitelistFacet
/// @notice Owner-gated management of globally whitelisted NFT collection addresses (for Curation).
/// @dev A de-whitelisted collection cannot be purchased/updated (other facets enforce), but listings are not
/// automatically deleted here; cleanup occurs via `updateListing`/`cleanListing`.
contract CollectionWhitelistFacet {
    /// @notice Emitted when a collection is added.
    event CollectionAddedToWhitelist(address indexed tokenAddress);

    /// @notice Emitted when a collection is removed.
    event CollectionRemovedFromWhitelist(address indexed tokenAddress);

    /// @notice Only diamond owner can update the whitelist.
    modifier onlyOwner() {
        LibDiamond.enforceIsContractOwner();
        _;
    }

    /// @notice Adds a single NFT contract address to the whitelist.
    /// @param tokenAddress The NFT contract address to whitelist.
    /// @dev Reverts if already whitelisted or if `tokenAddress` is zero.
    function addWhitelistedCollection(address tokenAddress) external onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();
        if (s.whitelistedCollections[tokenAddress]) revert CollectionWhitelist__AlreadyWhitelisted();
        if (tokenAddress == address(0)) revert CollectionWhitelist__ZeroAddress();

        s.whitelistedCollections[tokenAddress] = true;
        s.whitelistedCollectionsIndex[tokenAddress] = s.whitelistedCollectionsArray.length;
        s.whitelistedCollectionsArray.push(tokenAddress);

        emit CollectionAddedToWhitelist(tokenAddress);
    }

    /// @notice Removes a single NFT contract address from the whitelist.
    /// @param tokenAddress The NFT contract address to remove.
    /// @dev Reverts if not whitelisted. Uses swap-and-pop to keep the array compact.
    /// When removing collections from the whitelist consider canceling active listings of such collections.
    function removeWhitelistedCollection(address tokenAddress) external onlyOwner {
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
    /// @dev Ignores addresses already whitelisted. Reverts on zero address entries.
    function batchAddWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();
        address[] storage arr = s.whitelistedCollectionsArray;

        uint256 len = tokenAddresses.length;

        for (uint256 i = 0; i < len;) {
            address addr = tokenAddresses[i];
            if (addr == address(0)) revert CollectionWhitelist__ZeroAddress();

            if (!s.whitelistedCollections[addr]) {
                s.whitelistedCollections[addr] = true;
                s.whitelistedCollectionsIndex[addr] = arr.length;
                arr.push(addr);

                emit CollectionAddedToWhitelist(addr);
            }

            unchecked {
                i++;
            }
        }
    }

    /// @notice Batch removes multiple NFT contract addresses from the whitelist.
    /// @param tokenAddresses Array of NFT contract addresses to remove.
    /// @dev Ignores addresses not whitelisted. Uses swap-and-pop per removal.
    /// When removing collections from the whitelist consider canceling active listings of such collections.
    function batchRemoveWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {
        AppStorage storage s = LibAppStorage.appStorage();
        address[] storage arr = s.whitelistedCollectionsArray;

        uint256 len = tokenAddresses.length;

        for (uint256 i = 0; i < len;) {
            address addr = tokenAddresses[i];

            if (s.whitelistedCollections[addr]) {
                // Get the index of the element to remove.
                uint256 index = s.whitelistedCollectionsIndex[addr];
                uint256 lastIndex = arr.length - 1;
                address lastAddress = arr[lastIndex];

                // Swap the element with the last element if it's not the one to remove.
                if (index != lastIndex) {
                    arr[index] = lastAddress;
                    s.whitelistedCollectionsIndex[lastAddress] = index;
                }

                // Remove the last element.
                arr.pop();
                delete s.whitelistedCollectionsIndex[addr];
                s.whitelistedCollections[addr] = false;

                emit CollectionRemovedFromWhitelist(addr);
            }

            unchecked {
                i++;
            }
        }
    }
}
