// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IDiamondUpgradeFacet (ERC-8109 optional upgrade function)
/// @notice Standard upgrade entrypoint specified by ERC-8109.
interface IDiamondUpgradeFacet {
    /**
     * @notice The upgradeDiamond function below detects and reverts with the following errors.
     */
    error NoSelectorsProvidedForFacet(address _facet);
    error NoBytecodeAtAddress(address _contractAddress);
    error CannotAddFunctionToDiamondThatAlreadyExists(bytes4 _selector);
    error CannotReplaceFunctionThatDoesNotExist(bytes4 _selector);
    error CannotRemoveFunctionThatDoesNotExist(bytes4 _selector);
    error CannotReplaceFunctionWithTheSameFacet(bytes4 _selector);
    error DelegateCallReverted(address _delegate, bytes _functionCall);

    /// @dev Optional errors for immutable functions.
    error CannotReplaceImmutableFunction(bytes4 _selector);
    error CannotRemoveImmutableFunction(bytes4 _selector);

    struct FacetFunctions {
        address facet;
        bytes4[] selectors;
    }

    /**
     * @notice Emitted when a diamond's constructor function or function from a facet makes a `delegatecall`.
     * @dev MUST NOT be emitted for fallback routing delegatecalls.
     */
    event DiamondDelegateCall(address indexed _delegate, bytes _functionCall);

    /**
     * @notice Emitted to record information about a diamond.
     */
    event DiamondMetadata(bytes32 indexed _tag, bytes _data);

    function upgradeDiamond(
        FacetFunctions[] calldata _addFunctions,
        FacetFunctions[] calldata _replaceFunctions,
        bytes4[] calldata _removeFunctions,
        address _delegate,
        bytes calldata _functionCall,
        bytes32 _tag,
        bytes calldata _metadata
    ) external;
}
