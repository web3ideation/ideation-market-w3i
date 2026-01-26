// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibAppStorage, AppStorage} from "../libraries/LibAppStorage.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";

/// @title DummyUpgradeInit
/// @notice Upgrade initializer that writes the new dummy state variable into AppStorage.
/// @dev Must be executed via `delegatecall` into the diamond so writes persist.
contract DummyUpgradeInit {
    event DummyUpgradeInitialized(uint256 value);
    event DummyUpgradeVersionInitialized(string version, bytes32 implementationId, uint256 timestamp);

    function initDummyUpgrade(uint256 value) external {
        AppStorage storage s = LibAppStorage.appStorage();
        s.dummyUpgradeValue = value;
        emit DummyUpgradeInitialized(value);
    }

    /// @notice Atomic init: sets the dummy value AND updates LibDiamond versioning in the same upgrade tx.
    /// @dev Intended to be called via ERC-8109 `upgradeDiamond` as the initializer delegatecall.
    /// Computes the post-cut implementationId on-chain from LibDiamond storage.
    function initDummyUpgradeAndVersion(uint256 value, string calldata newVersion) external {
        {
            AppStorage storage s = LibAppStorage.appStorage();
            s.dummyUpgradeValue = value;
        }

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Move current to previous
        ds.previousVersion = ds.currentVersion;
        ds.previousImplementationId = ds.currentImplementationId;
        ds.previousVersionTimestamp = ds.currentVersionTimestamp;

        // Set new current version
        ds.currentVersion = newVersion;
        ds.currentImplementationId = _computeImplementationIdFromDiamondStorage(ds);
        ds.currentVersionTimestamp = block.timestamp;

        emit DummyUpgradeInitialized(value);
        emit DummyUpgradeVersionInitialized(newVersion, ds.currentImplementationId, block.timestamp);
    }

    /// @dev Computes implementationId from the CURRENT diamond storage (post-cut).
    /// Uses the same definition as README/VersionFacet: keccak256(chainId, diamondAddress, sortedFacetAddresses[], sortedSelectorsPerFacet[][]).
    function _computeImplementationIdFromDiamondStorage(LibDiamond.DiamondStorage storage ds)
        internal
        view
        returns (bytes32)
    {
        address[] memory facetAddresses = ds.facetAddresses;
        _sortAddresses(facetAddresses);

        bytes4[][] memory selectorsPerFacet = new bytes4[][](facetAddresses.length);
        for (uint256 i = 0; i < facetAddresses.length; i++) {
            bytes4[] memory selectors = ds.facetFunctionSelectors[facetAddresses[i]].functionSelectors;
            selectorsPerFacet[i] = _sortSelectors(selectors);
        }

        // Under delegatecall, address(this) is the diamond.
        return keccak256(abi.encode(block.chainid, address(this), facetAddresses, selectorsPerFacet));
    }

    function _sortAddresses(address[] memory arr) internal pure {
        uint256 length = arr.length;
        for (uint256 i = 0; i < length; i++) {
            for (uint256 j = i + 1; j < length; j++) {
                if (arr[i] > arr[j]) {
                    (arr[i], arr[j]) = (arr[j], arr[i]);
                }
            }
        }
    }

    function _sortSelectors(bytes4[] memory selectors) internal pure returns (bytes4[] memory) {
        uint256 length = selectors.length;
        bytes4[] memory sorted = new bytes4[](length);
        for (uint256 i = 0; i < length; i++) {
            sorted[i] = selectors[i];
        }

        for (uint256 i = 0; i < length; i++) {
            for (uint256 j = i + 1; j < length; j++) {
                if (uint32(sorted[i]) > uint32(sorted[j])) {
                    (sorted[i], sorted[j]) = (sorted[j], sorted[i]);
                }
            }
        }
        return sorted;
    }
}
