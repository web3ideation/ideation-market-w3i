// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

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
    address owner;
    bool reentrancyLock;
}
// IERC721 nft; // Temporarily used for checks in functions // I think this is unnecessary to have as a state variable at all

library LibAppStorage {
    function appStorage() internal pure returns (AppStorage storage s) {
        // this is usually called diamondStorage - but wouldnt that clash with the LibDiamond.sol function diamondStorage()? - and how do i call this function instead of the usual appstorage internal s which wouldnt define the storage slot 0 explicitly?
        assembly {
            s.slot := 0
        }
    }
}
