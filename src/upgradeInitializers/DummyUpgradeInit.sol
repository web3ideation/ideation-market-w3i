// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibAppStorage, AppStorage} from "../libraries/LibAppStorage.sol";

/// @title DummyUpgradeInit
/// @notice Upgrade initializer that writes the new dummy state variable into AppStorage.
/// @dev Must be executed via `delegatecall` into the diamond so writes persist.
contract DummyUpgradeInit {
    event DummyUpgradeInitialized(uint256 value);

    function initDummyUpgrade(uint256 value) external {
        AppStorage storage s = LibAppStorage.appStorage();
        s.dummyUpgradeValue = value;
        emit DummyUpgradeInitialized(value);
    }
}
