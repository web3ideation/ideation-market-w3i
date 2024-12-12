// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

struct Listing {
    uint256 listingId;
    uint256 price;
    address seller;
    address desiredNftAddress;
    uint256 desiredTokenId;
}

struct AppStorage {
    uint256 listingId;
    uint256 ideationMarketFee;
    mapping(address => mapping(uint256 => Listing)) listings; // Listings by NFT contract and token ID
    mapping(address => uint256) proceeds; // Proceeds by seller address
    bool reentrancyLock;
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
