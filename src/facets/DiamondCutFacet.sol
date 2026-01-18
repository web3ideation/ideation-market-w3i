// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Based on Nick Mudge's EIP-2535 Diamond reference implementation (MIT).
import {IDiamondCutFacet} from "../interfaces/IDiamondCutFacet.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";

/// @title DiamondCutFacet (EIP-2535 cut executor)
/// @notice Allows the diamond owner to add/replace/remove selectors and run an initializer.
/// @dev Authorization via `LibDiamond.enforceIsContractOwner()`; initializer (if any) runs by delegatecall
contract DiamondCutFacet is IDiamondCutFacet {
    /// @notice Add/replace/remove any number of functions and optionally execute an initialization
    /// @param _diamondCut The facet and function selectors to add, replace, or remove
    /// @param _init The address of the contract or facet to execute _calldata
    /// @param _calldata A function call, including function selector and arguments, to execute
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }
}
