// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IERC1155.sol";

error BuyerWhitelist__ListingDoesNotExist();
error BuyerWhitelist__NotAuthorizedOperator();
error BuyerWhitelist__ExceedsMaxBatchSize();
error BuyerWhitelist__ZeroAddress();
error BuyerWhitelist__EmptyCalldata();

contract BuyerWhitelistFacet {
    event BuyerWhitelisted(uint128 indexed listingId, address indexed buyer);
    event BuyerRemovedFromWhitelist(uint128 indexed listingId, address indexed buyer);

    /// @notice Batch adds buyer addresses to a listing's whitelist.
    /// @param listingId The ID number of the Listing.
    /// @param allowedBuyers An array of buyer addresses to add.
    function addBuyerWhitelistAddresses(uint128 listingId, address[] calldata allowedBuyers) external {
        AppStorage storage s = LibAppStorage.appStorage();

        if (allowedBuyers.length > s.buyerWhitelistMaxBatchSize) revert BuyerWhitelist__ExceedsMaxBatchSize();

        if (allowedBuyers.length == 0) revert BuyerWhitelist__EmptyCalldata();

        // Ensure listing exists
        Listing memory listedItem = s.listings[listingId];
        if (listedItem.seller == address(0)) revert BuyerWhitelist__ListingDoesNotExist();

        // check if the user is an authorized operator
        if (listedItem.quantity > 0) {
            IERC1155 nft = IERC1155(listedItem.nftAddress);
            // check if the user is authorized
            if (msg.sender != listedItem.seller && !nft.isApprovedForAll(listedItem.seller, msg.sender)) {
                revert BuyerWhitelist__NotAuthorizedOperator();
            }
        } else {
            IERC721 nft = IERC721(listedItem.nftAddress);
            address tokenHolder = nft.ownerOf(listedItem.tokenId);
            if (
                msg.sender != tokenHolder && msg.sender != nft.getApproved(listedItem.tokenId)
                    && !nft.isApprovedForAll(tokenHolder, msg.sender)
            ) {
                revert BuyerWhitelist__NotAuthorizedOperator();
            }
        }

        for (uint256 i = 0; i < allowedBuyers.length;) {
            address allowedBuyer = allowedBuyers[i];
            if (allowedBuyer == address(0)) revert BuyerWhitelist__ZeroAddress();

            if (!s.whitelistedBuyersByListingId[listingId][allowedBuyer]) {
                s.whitelistedBuyersByListingId[listingId][allowedBuyer] = true;
                emit BuyerWhitelisted(listingId, allowedBuyer);
            }
            unchecked {
                i++;
            }
        }
    }

    /// @notice Batch removes buyer addresses from a listing's whitelist.
    /// @param listingId The ID number of the Listing.
    /// @param disallowedBuyers An array of buyer addresses to remove.
    function removeBuyerWhitelistAddresses(uint128 listingId, address[] calldata disallowedBuyers) external {
        AppStorage storage s = LibAppStorage.appStorage();

        if (disallowedBuyers.length > s.buyerWhitelistMaxBatchSize) revert BuyerWhitelist__ExceedsMaxBatchSize();

        if (disallowedBuyers.length == 0) revert BuyerWhitelist__EmptyCalldata();

        // Ensure listing exists
        Listing memory listedItem = s.listings[listingId];
        if (listedItem.seller == address(0)) revert BuyerWhitelist__ListingDoesNotExist();

        // check if the user is an authorized operator
        if (listedItem.quantity > 0) {
            IERC1155 nft = IERC1155(listedItem.nftAddress);
            // check if the user is authorized
            if (msg.sender != listedItem.seller && !nft.isApprovedForAll(listedItem.seller, msg.sender)) {
                revert BuyerWhitelist__NotAuthorizedOperator();
            }
        } else {
            IERC721 nft = IERC721(listedItem.nftAddress);
            address tokenHolder = nft.ownerOf(listedItem.tokenId);
            if (
                msg.sender != tokenHolder && msg.sender != nft.getApproved(listedItem.tokenId)
                    && !nft.isApprovedForAll(tokenHolder, msg.sender)
            ) {
                revert BuyerWhitelist__NotAuthorizedOperator();
            }
        }

        for (uint256 i = 0; i < disallowedBuyers.length;) {
            address disallowedBuyer = disallowedBuyers[i];
            if (disallowedBuyer == address(0)) revert BuyerWhitelist__ZeroAddress();

            if (s.whitelistedBuyersByListingId[listingId][disallowedBuyer]) {
                s.whitelistedBuyersByListingId[listingId][disallowedBuyer] = false;
                emit BuyerRemovedFromWhitelist(listingId, disallowedBuyer);
            }
            unchecked {
                i++;
            }
        }
    }
}
