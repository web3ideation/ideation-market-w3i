// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Listing snapshot stored under a unique `listingId`.
/// @dev `feeRate` is captured at listing time (denominator = 100_000). `erc1155Quantity`
/// uses the convention: `0` for ERC-721 listings, `>0` for ERC-1155 (must be ≥1).
struct Listing {
    /// @notice Unique listing identifier.
    uint128 listingId;
    /// @notice Marketplace fee rate at the time of listing.
    /// @dev Denominator is 100_000 (e.g., 1_000 = 1%). Stored to make fees stable across updates.
    uint32 feeRate;
    /// @notice If true, only whitelisted buyers may purchase this listing.
    bool buyerWhitelistEnabled;
    /// @notice If true and ERC-1155, allows partial purchases (per-unit price must divide evenly).
    bool partialBuyEnabled;
    // 38 bytes padding for future tiny vars
    /// @notice NFT contract being sold (ERC-721 or ERC-1155).
    address tokenAddress;
    /// @notice Token id within `tokenAddress`.
    uint256 tokenId;
    /// @notice Quantity listed when selling ERC-1155; must be 0 for ERC-721.
    uint256 erc1155Quantity;
    /// @notice Total listing price in wei (for ERC-1155: total for all `erc1155Quantity` units).
    uint256 price;
    /// @notice Holder address captured at listing time.
    address seller;
    /// @notice Optional desired NFT contract for swap listings (address(0) means no swap).
    address desiredTokenAddress;
    /// @notice Desired token id (swap only).
    uint256 desiredTokenId;
    /// @notice Desired ERC-1155 quantity for swap (0 for ERC-721 swap or non-swap).
    uint256 desiredErc1155Quantity;
}

/// @notice Application-level storage shared by all facets.
/// @dev Lives at `APP_STORAGE_POSITION` and is accessed via `LibAppStorage.appStorage()`.
struct AppStorage {
    /// @notice Monotonic counter for new listing ids.
    uint128 listingIdCounter;
    /// @notice Marketplace fee rate (denominator 100_000; e.g., 1_000 = 1%).
    /// @dev Used as the default/current fee; listings snapshot this into `Listing.feeRate`.
    uint32 innovationFee;
    /// @notice Max number of addresses accepted per buyer whitelist batch (Verified stability at 300).
    uint16 buyerWhitelistMaxBatchSize;
    /// @notice Simple boolean reentrancy lock.
    bool reentrancyLock;
    // 9 bytes padding for future tiny vars
    /// @notice Primary listing registry by id.
    mapping(uint128 listingId => Listing listing) listings;
    /// @notice Reverse index: NFT (contract,id) → active listing ids.
    mapping(address tokenContract => mapping(uint256 tokenId => uint128[] listingIds)) tokenToListingIds;
    /// @notice ETH proceeds available to withdraw by address (sellers, fee collector, royalty receivers, buyers’ change).
    mapping(address seller => uint256 amount) proceeds;
    /// @notice Collection whitelist flags set by the Diamond Owner to curate Utility Token Contracts.
    mapping(address collection => bool isWhitelisted) whitelistedCollections;
    /// @notice Iterable list of whitelisted collections.
    address[] whitelistedCollectionsArray;
    /// @notice Index helper for `whitelistedCollectionsArray`.
    mapping(address collection => uint256 index) whitelistedCollectionsIndex;
    /// @notice Per-listing buyer whitelist set by the listing seller.
    mapping(uint128 listingId => mapping(address buyer => bool isWhitelisted)) whitelistedBuyersByListingId;
}
// part of the sepolia facet upgrade test !!!W delete this
// /// @notice Example upgrade variable to demonstrate adding new storage via a facet upgrade.
// /// @dev Appended at the end to preserve storage layout of existing fields.
// uint256 marketVersion;

/// @title LibAppStorage
/// @notice Canonical application storage for the IdeationMarket diamond (separate from LibDiamond storage).
/// @dev All marketplace facets `delegatecall` into the diamond and must read/write this struct via `appStorage()`.
/// Upgrade rule: append new fields only; never reorder/remove existing fields to avoid storage collisions.
library LibAppStorage {
    /// @notice Canonical storage slot for `AppStorage`.
    /// @dev keccak256("diamond.standard.app.storage").
    bytes32 constant APP_STORAGE_POSITION = keccak256("diamond.standard.app.storage");

    /// @notice Returns a pointer to `AppStorage` at the canonical slot.
    /// @dev Inline assembly assigns the slot to the returned storage reference.
    function appStorage() internal pure returns (AppStorage storage s) {
        bytes32 appStoragePosition = APP_STORAGE_POSITION;
        assembly {
            s.slot := appStoragePosition
        }
    }
}
