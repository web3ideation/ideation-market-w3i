// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

struct Listing {
    uint128 listingId;
    uint256 price;
    uint32 feeRate; // storing the fee at the time of listing
    address tokenAddress;
    // 12 bytes padding reserved for future flags
    uint256 tokenId;
    address seller;
    bool buyerWhitelistEnabled; // true means only whitelisted buyers can purchase.
    bool partialBuyEnabled; // true means that the ERC1155 Listing can be bought in multiple parts
    // 10 bytes padding reserved for future flags
    address desiredTokenAddress; // For swap Listing !=address(0)
    // 12 bytes padding reserved for future flags
    uint256 desiredTokenId;
    uint256 desiredErc1155Quantity; // For swap ERC1155 >1 and for swap ERC721 ==0 or non swap
    uint256 erc1155Quantity; // For ERC1155 >1 and for ERC721 ==0
}

struct AppStorage {
    uint128 listingIdCounter;
    uint32 innovationFee; // e.g., 1000 = 1% // this is the innovation/Marketplace fee (excluding gascosts) for each sale
    uint16 buyerWhitelistMaxBatchSize; // should be 300
    bool reentrancyLock;
    // 9 bytes padding for future tiny vars
    mapping(uint128 => Listing) listings; // Listings by listinngId
    mapping(address => mapping(uint256 => uint128[])) tokenToListingIds; // reverse index from token to ListingIds
    mapping(address => uint256) proceeds; // Proceeds by seller address
    mapping(address => bool) whitelistedCollections; // whitelisted collection (NFT) Address => true (or false if this collection has not been whitelisted)
    address[] whitelistedCollectionsArray; // for lookups
    mapping(address => uint256) whitelistedCollectionsIndex; // to make lookups and deletions more efficient
    mapping(uint128 => mapping(address => bool)) whitelistedBuyersByListingId; // listingId => whitelistedBuyer => true (or false if the buyers adress is not on the whitelist)
}

library LibAppStorage {
    // The unique storage position for the app storage struct.
    bytes32 constant APP_STORAGE_POSITION = keccak256("diamond.standard.app.storage");

    function appStorage() internal pure returns (AppStorage storage s) {
        bytes32 appStoragePosition = APP_STORAGE_POSITION;
        assembly {
            s.slot := appStoragePosition
        }
    }
}
