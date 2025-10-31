// part of the sepolia facet upgrade test !!!W delete this

// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.28;

// import {LibAppStorage, AppStorage} from "../libraries/LibAppStorage.sol";
// import {LibDiamond} from "../libraries/LibDiamond.sol";
// import {IVersionFacet} from "../interfaces/IVersionFacet.sol";

// /// @title VersionFacet
// /// @notice Minimal facet that owns a single storage value `marketVersion` under AppStorage.
// /// @dev Mutations are restricted to the diamond owner.
// contract VersionFacet is IVersionFacet {
//     event MarketVersionUpdated(uint256 previousVersion, uint256 newVersion);

//     /// @inheritdoc IVersionFacet
//     function setMarketVersion(uint256 newVersion) external override {
//         LibDiamond.enforceIsContractOwner();
//         AppStorage storage s = LibAppStorage.appStorage();
//         uint256 old = s.marketVersion;
//         s.marketVersion = newVersion;
//         emit MarketVersionUpdated(old, newVersion);
//     }

//     /// @inheritdoc IVersionFacet
//     function getMarketVersion() external view override returns (uint256) {
//         return LibAppStorage.appStorage().marketVersion;
//     }
// }
