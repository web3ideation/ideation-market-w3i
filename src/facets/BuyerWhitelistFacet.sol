// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IERC1155.sol";
import "../interfaces/IBuyerWhitelistFacet.sol";

error BuyerWhitelist__ListingDoesNotExist();
error BuyerWhitelist__NotAuthorizedOperator();
error BuyerWhitelist__ExceedsMaxBatchSize(uint256 batchSize);
error BuyerWhitelist__ZeroAddress();
error BuyerWhitelist__EmptyCalldata();
error BuyerWhitelist__SellerIsNotERC1155Owner(address seller);
error BuyerWhitelist__SellerIsNotERC721Owner(address seller, address owner);

/// @title BuyerWhitelistFacet
/// @notice Per-listing buyer whitelist management (add/remove addresses).
/// @dev Caller must be the seller or an authorized operator for the listed token.
/// Touches `AppStorage.whitelistedBuyersByListingId`. Duplicates are ignored; zero addresses revert.
contract BuyerWhitelistFacet is IBuyerWhitelistFacet {
    event BuyerWhitelisted(uint128 indexed listingId, address indexed buyer);
    event BuyerRemovedFromWhitelist(uint128 indexed listingId, address indexed buyer);

    /// @notice Batch adds buyer addresses to a listing's whitelist.
    /// @param listingId The ID number of the Listing.
    /// @param allowedBuyers An array of buyer addresses to add.
    /// @dev Reverts if: empty array; batch exceeds `buyerWhitelistMaxBatchSize`;
    /// listing does not exist; caller not authorized; seller no longer owns/holds sufficient token; any zero address.
    function addBuyerWhitelistAddresses(uint128 listingId, address[] calldata allowedBuyers) external override {
        AppStorage storage s = LibAppStorage.appStorage();
        uint256 len = allowedBuyers.length;

        validateWhitelistBatch(s, listingId, len);

        mapping(address buyer => bool isWhitelisted) storage listingWhitelist =
            s.whitelistedBuyersByListingId[listingId];

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
    /// @dev Reverts on same prechecks as add. Non-whitelisted addresses are ignored.
    function removeBuyerWhitelistAddresses(uint128 listingId, address[] calldata disallowedBuyers) external override {
        AppStorage storage s = LibAppStorage.appStorage();
        uint256 len = disallowedBuyers.length;

        validateWhitelistBatch(s, listingId, len);

        mapping(address buyer => bool isWhitelisted) storage listingWhitelist =
            s.whitelistedBuyersByListingId[listingId];

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

    /// @notice Common prechecks for whitelist mutations.
    /// @dev Reverts if `batchSize == 0`, exceeds cap, listing missing, seller not owner/holder,
    /// or caller not seller/approved operator. For ERC1155, verifies sufficient balance.
    function validateWhitelistBatch(AppStorage storage s, uint128 listingId, uint256 batchSize) internal view {
        if (batchSize == 0) revert BuyerWhitelist__EmptyCalldata();
        if (batchSize > s.buyerWhitelistMaxBatchSize) {
            revert BuyerWhitelist__ExceedsMaxBatchSize(batchSize);
        }

        address seller = s.listings[listingId].seller;
        if (seller == address(0)) revert BuyerWhitelist__ListingDoesNotExist();

        uint256 erc1155Quantity = s.listings[listingId].erc1155Quantity;
        address tokenAddress = s.listings[listingId].tokenAddress;
        uint256 tokenId = s.listings[listingId].tokenId;
        if (erc1155Quantity > 0) {
            IERC1155 token = IERC1155(tokenAddress);
            // Seller must still be able to fulfill the listed quantity
            if (token.balanceOf(seller, tokenId) < erc1155Quantity) {
                revert BuyerWhitelist__SellerIsNotERC1155Owner(seller);
            }
            // msg.sender must be the seller or an authorized operator
            if (msg.sender != seller && !token.isApprovedForAll(seller, msg.sender)) {
                revert BuyerWhitelist__NotAuthorizedOperator();
            }
        } else {
            IERC721 token = IERC721(tokenAddress);
            address tokenHolder = token.ownerOf(tokenId);
            // the seller must still own the token
            if (tokenHolder != seller) revert BuyerWhitelist__SellerIsNotERC721Owner(seller, tokenHolder);
            // msg.sender must be the seller or an authorized operator
            if (
                msg.sender != seller && msg.sender != token.getApproved(tokenId)
                    && !token.isApprovedForAll(seller, msg.sender)
            ) revert BuyerWhitelist__NotAuthorizedOperator();
        }
    }
}
