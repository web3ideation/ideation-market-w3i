// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {LibAppStorage, AppStorage} from "../libraries/LibAppStorage.sol";

/// @title DummyUpgradeFacet
/// @notice Minimal facet used to verify upgrade flows and AppStorage append-only upgrades.
contract DummyUpgradeFacet {
    event DummyUpgradeValueSet(uint256 value);

    /// @notice Returns the dummy upgrade value stored in AppStorage.
    function getDummyUpgradeValue() external view returns (uint256) {
        AppStorage storage s = LibAppStorage.appStorage();
        return s.dummyUpgradeValue;
    }

    /// @notice Sets the dummy upgrade value stored in AppStorage.
    /// @dev Owner-gated so random users can’t scribble on storage during testing.
    function setDummyUpgradeValue(uint256 value) external {
        LibDiamond.enforceIsContractOwner();
        AppStorage storage s = LibAppStorage.appStorage();
        s.dummyUpgradeValue = value;
        emit DummyUpgradeValueSet(value);
    }
}
