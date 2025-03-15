// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

struct Listing {
    uint128 listingId;
    uint96 price;
    uint32 feeRate; // storing the fee at the time of listing
    address seller;
    address desiredNftAddress; // For swap Listing !=address(0)
    uint256 desiredTokenId;
    uint256 desiredQuantity; // For swap ERC1155 >1 and for swap ERC721 ==0 or non swap
    uint256 quantity; // For ERC1155 >1 and for ERC721 ==0
    bool buyerWhitelistEnabled; // true means only whitelisted buyers can purchase.
}

struct AppStorage {
    uint128 listingId;
    uint32 ideationMarketFee; // e.g., 2000 = 2% // this is the total fee (excluding gascosts) for each sale, including founderFee and innovationFee
    mapping(address => mapping(uint256 => Listing)) listings; // Listings by NFT contract and token ID
    mapping(address => uint256) proceeds; // Proceeds by seller address
    bool reentrancyLock;
    address founder1;
    address founder2;
    address founder3;
    uint32 founder1Ratio; // e.g., 25500 for 25,5% of the total ideationMarketFee
    uint32 founder2Ratio; // e.g., 17000 for 17% of the total ideationMarketFee
    uint32 founder3Ratio; // e.g., 7500 for 7,5% of the total ideationMarketFee
    mapping(address => bool) whitelistedCollections; // whitelisted collection (NFT) Address => true (or false if this collection has not been whitelisted)
    address[] whitelistedCollectionsArray; // for lookups
    mapping(address => uint256) whitelistedCollectionsIndex; // to make lookups and deletions more efficient
    mapping(address => mapping(uint256 => mapping(address => bool))) whitelistedBuyersByNFT; // nftAddress => tokenId => whitelistedBuyer => true (or false if the buyers adress is not on the whitelist)
    uint256 buyerWhitelistMaxBatchSize; // should be
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
