// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * \
 * Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
 * EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
 *
 * Implementation of a diamond.
 * /*****************************************************************************
 */
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IDiamondLoupeFacet} from "../interfaces/IDiamondLoupeFacet.sol";
import {IDiamondCutFacet} from "../interfaces/IDiamondCutFacet.sol";
import {IERC173} from "../interfaces/IERC173.sol";
import {IERC165} from "../interfaces/IERC165.sol";
import {LibAppStorage, AppStorage} from "../libraries/LibAppStorage.sol";

/// @title DiamondInit (EIP-2535 initializer)
/// @notice Registers ERC-165 interface support and initializes marketplace configuration in shared storage.
/// @dev Must be executed as the `init` call data of `diamondCut` (i.e., via `delegatecall` into the diamond),
/// so that changes persist in the diamond’s storage. Writes to:
/// - `LibDiamond.DiamondStorage.supportedInterfaces` for ERC-165, DiamondCut, DiamondLoupe, and ERC-173.
/// - `LibAppStorage.AppStorage` for `innovationFee` and `buyerWhitelistMaxBatchSize`.
contract DiamondInit {
    /// @notice Initializes ERC-165 flags and marketplace parameters.
    /// @param innovationFee Marketplace fee rate; denominator is **100_000** (e.g., 1_000 = 1%).
    /// @param buyerWhitelistMaxBatchSize Maximum number of addresses accepted per whitelist batch.
    /// @dev Intended to be called once during deployment/upgrade initialization. Idempotent if the same
    /// values are provided again, but repeated calls can overwrite prior configuration.
    function init(uint32 innovationFee, uint16 buyerWhitelistMaxBatchSize) external {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Diamond and ERC165 interfaces
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCutFacet).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupeFacet).interfaceId] = true;
        ds.supportedInterfaces[type(IERC173).interfaceId] = true;

        // Initialize marketplace state variables. / Constructor for IdeationMarketFacet.
        AppStorage storage s = LibAppStorage.appStorage();
        s.innovationFee = innovationFee; // Denominator is 100_000 (e.g., 1_000 = 1%). innovation/Marketplace fee (excluding gascosts) for each sale
        s.buyerWhitelistMaxBatchSize = buyerWhitelistMaxBatchSize;
    }
}
