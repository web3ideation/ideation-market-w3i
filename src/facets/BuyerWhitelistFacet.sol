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
        uint256 len = allowedBuyers.length;

        validateWhitelistBatch(s, listingId, len);

        mapping(address => bool) storage listingWhitelist = s.whitelistedBuyersByListingId[listingId];

        for (uint256 i = 0; i < len;) {
            address allowedBuyer = allowedBuyers[i];
            if (allowedBuyer == address(0)) revert BuyerWhitelist__ZeroAddress();

            if (!listingWhitelist[allowedBuyer]) {
                listingWhitelist[allowedBuyer] = true;
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
        uint256 len = disallowedBuyers.length;

        validateWhitelistBatch(s, listingId, len);

        mapping(address => bool) storage listingWhitelist = s.whitelistedBuyersByListingId[listingId];

        for (uint256 i = 0; i < len;) {
            address disallowedBuyer = disallowedBuyers[i];
            if (disallowedBuyer == address(0)) revert BuyerWhitelist__ZeroAddress();

            if (listingWhitelist[disallowedBuyer]) {
                listingWhitelist[disallowedBuyer] = false;
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
        if (batchSize == 0) revert BuyerWhitelist__EmptyCalldata();
        if (batchSize > s.buyerWhitelistMaxBatchSize) {
            revert BuyerWhitelist__ExceedsMaxBatchSize();
        }

        address seller = s.listings[listingId].seller;
        if (seller == address(0)) revert BuyerWhitelist__ListingDoesNotExist();

        uint256 erc1155Quantity = s.listings[listingId].erc1155Quantity;
        address tokenAddress = s.listings[listingId].tokenAddress;
        uint256 tokenId = s.listings[listingId].tokenId;
        if (erc1155Quantity > 0) {
            IERC1155 token = IERC1155(tokenAddress);
            if (msg.sender != seller && !token.isApprovedForAll(seller, msg.sender)) {
                revert BuyerWhitelist__NotAuthorizedOperator();
            }
        } else {
            IERC721 token = IERC721(tokenAddress);
            address tokenHolder = token.ownerOf(tokenId);
            if (
                msg.sender != tokenHolder && msg.sender != token.getApproved(tokenId)
                    && !token.isApprovedForAll(tokenHolder, msg.sender)
            ) revert BuyerWhitelist__NotAuthorizedOperator();
        }
    }
}
