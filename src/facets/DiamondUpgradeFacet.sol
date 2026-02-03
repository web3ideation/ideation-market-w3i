// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IDiamondUpgradeFacet} from "../interfaces/IDiamondUpgradeFacet.sol";

/// @title DiamondUpgradeFacet (ERC-8109 upgradeDiamond)
/// @notice Implements the standard ERC-8109 upgrade function.
contract DiamondUpgradeFacet is IDiamondUpgradeFacet {
    function upgradeDiamond(
        FacetFunctions[] calldata _addFunctions,
        FacetFunctions[] calldata _replaceFunctions,
        bytes4[] calldata _removeFunctions,
        address _delegate,
        bytes calldata _functionCall,
        bytes32 _tag,
        bytes calldata _metadata
    ) external {
        LibDiamond.enforceIsContractOwner();

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // --- Add ---
        for (uint256 i = 0; i < _addFunctions.length; i++) {
            address facet = _addFunctions[i].facet;
            bytes4[] calldata selectors = _addFunctions[i].selectors;

            if (selectors.length == 0) revert NoSelectorsProvidedForFacet(facet);
            if (!_hasCode(facet)) revert NoBytecodeAtAddress(facet);

            for (uint256 j = 0; j < selectors.length; j++) {
                bytes4 selector = selectors[j];
                if (ds.selectorToFacetAndPosition[selector].facetAddress != address(0)) {
                    revert CannotAddFunctionToDiamondThatAlreadyExists(selector);
                }
            }

            // Emits DiamondFunctionAdded per selector (ERC-8109 required events).
            LibDiamond.addFunctions(facet, _toMemory(selectors));
        }

        // --- Replace ---
        for (uint256 i = 0; i < _replaceFunctions.length; i++) {
            address facet = _replaceFunctions[i].facet;
            bytes4[] calldata selectors = _replaceFunctions[i].selectors;

            if (selectors.length == 0) revert NoSelectorsProvidedForFacet(facet);
            if (!_hasCode(facet)) revert NoBytecodeAtAddress(facet);

            for (uint256 j = 0; j < selectors.length; j++) {
                bytes4 selector = selectors[j];
                address oldFacet = ds.selectorToFacetAndPosition[selector].facetAddress;
                if (oldFacet == address(0)) revert CannotReplaceFunctionThatDoesNotExist(selector);
                if (oldFacet == address(this)) revert CannotReplaceImmutableFunction(selector);
                if (oldFacet == facet) revert CannotReplaceFunctionWithTheSameFacet(selector);
            }

            // Emits DiamondFunctionReplaced per selector (ERC-8109 required events).
            LibDiamond.replaceFunctions(facet, _toMemory(selectors));
        }

        // --- Remove ---
        if (_removeFunctions.length > 0) {
            for (uint256 i = 0; i < _removeFunctions.length; i++) {
                bytes4 selector = _removeFunctions[i];
                address oldFacet = ds.selectorToFacetAndPosition[selector].facetAddress;
                if (oldFacet == address(0)) revert CannotRemoveFunctionThatDoesNotExist(selector);
                if (oldFacet == address(this)) revert CannotRemoveImmutableFunction(selector);
            }

            // Emits DiamondFunctionRemoved per selector (ERC-8109 required events).
            LibDiamond.removeSelectors(_toMemory(_removeFunctions));
        }

        // --- delegatecall (optional) ---
        if (_delegate != address(0)) {
            if (!_hasCode(_delegate)) revert NoBytecodeAtAddress(_delegate);

            (bool success, bytes memory returndata) = _delegate.delegatecall(_functionCall);
            if (!success) {
                if (returndata.length > 0) {
                    _revertWith(returndata);
                }
                revert DelegateCallReverted(_delegate, _functionCall);
            }

            emit DiamondDelegateCall(_delegate, _functionCall);
        }

        // --- metadata (optional) ---
        if (_tag != bytes32(0) || _metadata.length > 0) {
            emit DiamondMetadata(_tag, _metadata);
        }
    }

    function _hasCode(address _addr) internal view returns (bool) {
        uint256 size;
        assembly ("memory-safe") {
            size := extcodesize(_addr)
        }
        return size > 0;
    }

    function _revertWith(bytes memory revertData) internal pure {
        assembly ("memory-safe") {
            revert(add(revertData, 32), mload(revertData))
        }
    }

    function _toMemory(bytes4[] calldata arr) internal pure returns (bytes4[] memory out) {
        out = new bytes4[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            out[i] = arr[i];
        }
    }
}
