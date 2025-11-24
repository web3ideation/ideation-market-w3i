// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibDiamond} from "../libraries/LibDiamond.sol";

/// @title PauseFacet
/// @notice Allows the diamond owner to pause critical marketplace operations in emergencies.
/// @dev When paused, users cannot create, update, or purchase listings. Users can still cancel
/// their own listings, and owner admin functions remain operational. This provides a circuit-breaker
/// for security incidents without completely locking down the marketplace.
contract PauseFacet {
    /// @notice Emitted when the marketplace is paused.
    /// @param triggeredBy Address that triggered the pause (diamond owner).
    event Paused(address indexed triggeredBy);

    /// @notice Emitted when the marketplace is unpaused.
    /// @param triggeredBy Address that triggered the unpause (diamond owner).
    event Unpaused(address indexed triggeredBy);

    /// @notice Thrown when attempting to pause an already paused marketplace.
    error Pause__AlreadyPaused();

    /// @notice Thrown when attempting to unpause a marketplace that is not paused.
    error Pause__NotPaused();

    /// @notice Pauses critical marketplace operations.
    /// @dev Only callable by the diamond owner (multisig). Prevents createListing, purchaseListing,
    /// and updateListing from executing. Does NOT affect cancelListing, cleanListing, or admin functions.
    function pause() external {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        if (ds.paused) revert Pause__AlreadyPaused();
        ds.paused = true;
        emit Paused(msg.sender);
    }

    /// @notice Unpauses marketplace operations, restoring normal functionality.
    /// @dev Only callable by the diamond owner (multisig).
    function unpause() external {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        if (!ds.paused) revert Pause__NotPaused();
        ds.paused = false;
        emit Unpaused(msg.sender);
    }
}
