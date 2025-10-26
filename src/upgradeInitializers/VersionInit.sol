// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibAppStorage, AppStorage} from "../libraries/LibAppStorage.sol";

/// @title VersionInit
/// @notice Simple initializer used during diamondCut to set the initial `marketVersion`.
/// @dev Executed via `delegatecall` from the diamond, so it writes into the diamond's storage.
contract VersionInit {
    function init(uint256 initialVersion) external {
        AppStorage storage s = LibAppStorage.appStorage();
        s.marketVersion = initialVersion;
    }
}
