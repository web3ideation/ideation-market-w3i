// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Based on Nick Mudge's Diamond reference implementation pattern (MIT).
import {LibDiamond} from "./libraries/LibDiamond.sol";
import {IDiamondUpgradeFacet} from "./interfaces/IDiamondUpgradeFacet.sol";

error Diamond__FunctionDoesNotExist();

/// @title IdeationMarketDiamond (diamond dispatcher)
/// @notice Minimal diamond proxy that owns storage and forwards external calls to facet contracts via `delegatecall`.
/// @dev The constructor sets the initial contract owner and wires the ERC-8109 `upgradeDiamond` function from the
/// provided upgrade facet so further upgrades can be performed. Function dispatch uses the selector→facet mapping in
/// `LibDiamond.DiamondStorage`. Return data and reverts are bubbled exactly as returned by the facet.
/// Security: facets execute in the diamond’s context and share storage; only the diamond owner may perform upgrades.
contract IdeationMarketDiamond {
    /// @notice Constructs the diamond and installs the ERC-8109 `upgradeDiamond` function so future upgrades are possible.
    /// @param _contractOwner Address to be set as the initial diamond owner.
    /// @param _diamondUpgradeFacet Address of a deployed facet that implements `IDiamondUpgradeFacet.upgradeDiamond`.
    constructor(address _contractOwner, address _diamondUpgradeFacet) payable {
        LibDiamond.setContractOwner(_contractOwner);

        bytes4[] memory functionSelectors = new bytes4[](1);
        functionSelectors[0] = IDiamondUpgradeFacet.upgradeDiamond.selector;

        LibDiamond.addFunctions(_diamondUpgradeFacet, functionSelectors);
    }

    /// @notice Forwards unmatched function calls to the facet that implements the selector.
    /// @dev Loads `LibDiamond.DiamondStorage` at the canonical slot, looks up the facet address for `msg.sig`,
    /// and performs `delegatecall` with all calldata and gas. Reverts with `Diamond__FunctionDoesNotExist` if no
    /// facet is registered. Return data is copied back verbatim and revert data is bubbled unchanged.
    fallback() external payable {
        LibDiamond.DiamondStorage storage ds;
        bytes32 position = LibDiamond.DIAMOND_STORAGE_POSITION;
        // get diamond storage
        assembly ("memory-safe") {
            ds.slot := position
        }
        // get facet from function selector
        address facet = ds.selectorToFacetAndPosition[msg.sig].facetAddress;
        if (facet == address(0)) revert Diamond__FunctionDoesNotExist();
        // Execute external function from facet using delegatecall and return any value.
        assembly ("memory-safe") {
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
