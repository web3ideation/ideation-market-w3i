// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";

error BuyerWhitelist__ListingDoesNotExist();
error BuyerWhitelist__NotListingSeller();
error BuyerWhitelist__ExceedsMaxBatchSize();
error BuyerWhitelist__ZeroAddress();

contract BuyerWhitelistFacet {
    // these are relevant storage Variables defined in the LibAppStorage.sol
    // struct Listing {
    //     bool buyerWhitelistEnabled; // true means only whitelisted buyers can purchase.
    // }
    // mapping(address => mapping(uint256 => mapping(address => bool))) whitelistedBuyersByNFT; // nftAddress => tokenId => whitelistedBuyer => true (or false if the buyers adress is not on the whitelist)
    // uint256 buyerWhitelistMaxBatchSize; // should be 300

    event BuyerWhitelisted(address indexed nftAddress, uint256 indexed tokenId, address indexed buyer);
    event BuyerRemovedFromWhitelist(address indexed nftAddress, uint256 indexed tokenId, address indexed buyer);

    /// @notice Batch adds buyer addresses to a listing's whitelist.
    /// @param nftAddress The NFT contract address.
    /// @param tokenId The token ID.
    /// @param buyers An array of buyer addresses to add.
    function addBuyerWhitelistAddresses(address nftAddress, uint256 tokenId, address[] calldata buyers) external {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing storage listedItem = s.listings[nftAddress][tokenId];
        if (listedItem.seller == address(0)) revert BuyerWhitelist__ListingDoesNotExist();
        if (listedItem.seller != msg.sender) revert BuyerWhitelist__NotListingSeller();
        if (buyers.length > s.buyerWhitelistMaxBatchSize) revert BuyerWhitelist__ExceedsMaxBatchSize();

        for (uint256 i = 0; i < buyers.length;) {
            address buyer = buyers[i];
            if (buyer == address(0)) revert BuyerWhitelist__ZeroAddress();

            if (!s.whitelistedBuyersByNFT[nftAddress][tokenId][buyer]) {
                s.whitelistedBuyersByNFT[nftAddress][tokenId][buyer] = true;
                emit BuyerWhitelisted(nftAddress, tokenId, buyer);
            }
            unchecked {
                i++;
            }
        }
    }

    /// @notice Batch removes buyer addresses from a listing's whitelist.
    /// @param nftAddress The NFT contract address.
    /// @param tokenId The token ID.
    /// @param buyers An array of buyer addresses to remove.
    function removeBuyerWhitelistAddresses(address nftAddress, uint256 tokenId, address[] calldata buyers) external {
        AppStorage storage s = LibAppStorage.appStorage();
        Listing storage listedItem = s.listings[nftAddress][tokenId];
        if (listedItem.seller == address(0)) revert BuyerWhitelist__ListingDoesNotExist();
        if (listedItem.seller != msg.sender) revert BuyerWhitelist__NotListingSeller();
        if (buyers.length > s.buyerWhitelistMaxBatchSize) revert BuyerWhitelist__ExceedsMaxBatchSize();

        for (uint256 i = 0; i < buyers.length;) {
            address buyer = buyers[i];
            if (s.whitelistedBuyersByNFT[nftAddress][tokenId][buyer]) {
                s.whitelistedBuyersByNFT[nftAddress][tokenId][buyer] = false;
                emit BuyerRemovedFromWhitelist(nftAddress, tokenId, buyer);
            }
            unchecked {
                i++;
            }
        }
    }
}
