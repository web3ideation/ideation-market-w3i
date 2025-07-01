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

        validateWhitelistBatch(s, listingId, allowedBuyers.length);

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

        validateWhitelistBatch(s, listingId, disallowedBuyers.length);

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

    /// @dev Reverts if batchSize is zero/exceeds cap,
    ///      if listing.seller==0, or msg.sender isn’t authorized.
    function validateWhitelistBatch(AppStorage storage s, uint128 listingId, uint256 batchSize) internal view {
        Listing memory listedItem = s.listings[listingId];

        if (batchSize == 0) revert BuyerWhitelist__EmptyCalldata();
        if (batchSize > s.buyerWhitelistMaxBatchSize) {
            revert BuyerWhitelist__ExceedsMaxBatchSize();
        }
        if (listedItem.seller == address(0)) revert BuyerWhitelist__ListingDoesNotExist();

        if (listedItem.quantity > 0) {
            IERC1155 token = IERC1155(listedItem.tokenAddress);
            if (msg.sender != listedItem.seller && !token.isApprovedForAll(listedItem.seller, msg.sender)) {
                revert BuyerWhitelist__NotAuthorizedOperator();
            }
        } else {
            IERC721 token = IERC721(listedItem.tokenAddress);
            address tokenHolder = token.ownerOf(listedItem.tokenId);
            if (
                msg.sender != tokenHolder && msg.sender != token.getApproved(listedItem.tokenId)
                    && !token.isApprovedForAll(tokenHolder, msg.sender)
            ) revert BuyerWhitelist__NotAuthorizedOperator();
        }
    }
}
