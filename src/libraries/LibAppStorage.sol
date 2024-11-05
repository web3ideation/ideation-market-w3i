// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

struct AppStorage {
    uint256 firstVar;
}

library LibAppStorage {
    function appStorage() internal pure returns (AppStorage storage s) {
        // this is usually called diamondStorage - but wouldnt that clash with the LibDiamond.sol function diamondStorage()? - and how do i call this function instead of the usual appstorage internal s which wouldnt define the storage slot 0 explicitly?
        assembly {
            s.slot := 0
        }
    }
}
