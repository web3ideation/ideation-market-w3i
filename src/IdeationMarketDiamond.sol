// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * \
 * Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
 * EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
 *
 * Implementation of a diamond.
 * --- adapted by wolf3i
 * /*****************************************************************************
 */
import {LibDiamond} from "./libraries/LibDiamond.sol";
import {IDiamondCutFacet} from "./interfaces/IDiamondCutFacet.sol";

error Diamond__FunctionDoesNotExist();

/// @title IdeationMarketDiamond (EIP-2535 dispatcher)
/// @notice Minimal diamond proxy that owns storage and forwards external calls to facet contracts via `delegatecall`.
/// @dev The constructor sets the initial contract owner and wires the `diamondCut` function from the provided
/// DiamondCut facet so further cuts can be performed. Function dispatch uses the selector→facet mapping in
/// `LibDiamond.DiamondStorage`. Return data and reverts are bubbled exactly as returned by the facet.
/// Security: facets execute in the diamond’s context and share storage; only the diamond owner may perform cuts.
contract IdeationMarketDiamond {
    /// @notice Constructs the diamond and installs the `diamondCut` function so future upgrades are possible.
    /// @param _contractOwner Address to be set as the initial diamond owner.
    /// @param _diamondCutFacet Address of a deployed facet that implements `IDiamondCutFacet.diamondCut`.
    /// @dev Performs an initial cut that adds only the `diamondCut` selector. No initializer is executed at deploy.
    constructor(address _contractOwner, address _diamondCutFacet) payable {
        LibDiamond.setContractOwner(_contractOwner);

        // Add the diamondCut external function from the diamondCutFacet
        IDiamondCutFacet.FacetCut[] memory cut = new IDiamondCutFacet.FacetCut[](1);
        bytes4[] memory functionSelectors = new bytes4[](1);
        functionSelectors[0] = IDiamondCutFacet.diamondCut.selector;
        cut[0] = IDiamondCutFacet.FacetCut({
            facetAddress: _diamondCutFacet,
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: functionSelectors
        });
        LibDiamond.diamondCut(cut, address(0), "");
    }

    /// @notice Forwards unmatched function calls to the facet that implements the selector.
    /// @dev Loads `LibDiamond.DiamondStorage` at the canonical slot, looks up the facet address for `msg.sig`,
    /// and performs `delegatecall` with all calldata and gas. Reverts with `Diamond__FunctionDoesNotExist` if no
    /// facet is registered. Return data is copied back verbatim and revert data is bubbled unchanged.
    fallback() external payable {
        LibDiamond.DiamondStorage storage ds;
        bytes32 position = LibDiamond.DIAMOND_STORAGE_POSITION;
        // get diamond storage
        assembly {
            ds.slot := position
        }
        // get facet from function selector
        address facet = ds.selectorToFacetAndPosition[msg.sig].facetAddress;
        if (facet == address(0)) revert Diamond__FunctionDoesNotExist();
        // Execute external function from facet using delegatecall and return any value.
        assembly {
            // copy function selector and any arguments
            calldatacopy(0, 0, calldatasize())
            // execute function call using the facet
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            // get any return value
            returndatacopy(0, 0, returndatasize())
            // return any return value or error back to the caller
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
