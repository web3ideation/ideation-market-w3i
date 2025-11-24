// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibDiamond} from "../libraries/LibDiamond.sol";

/// @title VersionFacet
/// @notice Implements diamond version management (owner-only write operations).
/// @dev The implementationId is computed off-chain to keep this facet simple and gas-efficient.
/// Version data is stored in LibDiamond.DiamondStorage since versioning is a diamond structure concern.
/// Read operations are available in GetterFacet for consistency with other diamond queries.
contract VersionFacet {
    /// @notice Emitted when a new version is set.
    event VersionUpdated(string version, bytes32 indexed implementationId, uint256 timestamp);

    /// @notice Sets a new version for the diamond (owner only).
    /// @dev Moves current version to previous, sets new current version with block.timestamp.
    /// The implementationId should be computed off-chain using the diamond loupe data:
    /// keccak256(abi.encode(chainId, diamondAddress, sortedFacetAddresses[], sortedSelectorsPerFacet[][])).
    /// @param newVersion Semantic version string (e.g., "1.0.0", "1.1.0", "2.0.0").
    /// @param newImplementationId Hash of diamond configuration computed off-chain.
    function setVersion(string calldata newVersion, bytes32 newImplementationId) external {
        LibDiamond.enforceIsContractOwner();

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Move current to previous
        ds.previousVersion = ds.currentVersion;
        ds.previousImplementationId = ds.currentImplementationId;
        ds.previousVersionTimestamp = ds.currentVersionTimestamp;

        // Set new current version
        ds.currentVersion = newVersion;
        ds.currentImplementationId = newImplementationId;
        ds.currentVersionTimestamp = block.timestamp;

        emit VersionUpdated(newVersion, newImplementationId, block.timestamp);
    }
}
