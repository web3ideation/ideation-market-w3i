// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IBuyerWhitelistFacet
/// @notice Allows listing facets to add/remove whitelisted buyers by listingId
interface IBuyerWhitelistFacet {
    /// @notice Batch adds buyer addresses to a listing’s whitelist.
    /// @param listingId The ID of the listing (as assigned in IdeationMarketFacet).
    /// @param allowedBuyers The array of buyer addresses to whitelist.
    function addBuyerWhitelistAddresses(uint128 listingId, address[] calldata allowedBuyers) external;

    /// @notice Batch removes buyer addresses from a listing’s whitelist.
    /// @param listingId The ID of the listing.
    /// @param disallowedBuyers The array of buyer addresses to remove.
    function removeBuyerWhitelistAddresses(uint128 listingId, address[] calldata disallowedBuyers) external;
}
