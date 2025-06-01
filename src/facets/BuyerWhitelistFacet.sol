// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../libraries/LibAppStorage.sol";
import "../interfaces/IERC721.sol";
import "../interfaces/IERC1155.sol";
import "../interfaces/IERC165.sol";

// !!! add a reset whitelist function that uses struct delete - check if that is really more gas efficient than the batch delete and check if its worth the effort changing the code from the versioning nested mapping to the struct nested mapping.
// !!! add listing Id as primary identifier
error BuyerWhitelist__ListingDoesNotExistOrIsOutdated();
error BuyerWhitelist__NotListingSeller(); // !!! add support for authorized operators
error BuyerWhitelist__ExceedsMaxBatchSize();
error BuyerWhitelist__ZeroAddress();
error BuyerWhitelist__EmptyCalldata();

contract BuyerWhitelistFacet {
    // !!! add listing Id as primary identifier
    event BuyerWhitelisted(uint128 indexed listingId, address indexed buyer);
    event BuyerRemovedFromWhitelist(uint128 indexed listingId, address indexed buyer);

    /// @notice Batch adds buyer addresses to a listing's whitelist.
    /// @param listingId The ID number of the Listing.
    /// @param allowedBuyers An array of buyer addresses to add.
    function addBuyerWhitelistAddresses(uint128 listingId, address[] calldata allowedBuyers) external {
        AppStorage storage s = LibAppStorage.appStorage();

        if (allowedBuyers.length > s.buyerWhitelistMaxBatchSize) revert BuyerWhitelist__ExceedsMaxBatchSize();

        if (allowedBuyers.length == 0) revert BuyerWhitelist__EmptyCalldata();

        // Ensure listing exists & caller is the seller
        Listing storage listedItem = s.listings[listingId];
        if (listedItem.listingId != listingId) revert BuyerWhitelist__ListingDoesNotExistOrIsOutdated();
        if (msg.sender != listedItem.seller) revert BuyerWhitelist__NotListingSeller();

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

        // Ensure listing exists & caller is the seller
        Listing storage listedItem = s.listings[listingId];
        if (listedItem.listingId != listingId) revert BuyerWhitelist__ListingDoesNotExistOrIsOutdated();
        if (msg.sender != listedItem.seller) revert BuyerWhitelist__NotListingSeller();

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
