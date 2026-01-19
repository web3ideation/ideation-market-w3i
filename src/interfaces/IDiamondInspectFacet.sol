// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IDiamondInspectFacet (ERC-8109 required introspection)
/// @notice Minimal introspection surface required by ERC-8109.
interface IDiamondInspectFacet {
    /**
     * @notice Gets the facet that handles the given selector.
     *  @dev If facet is not found return address(0).
     *  @param _functionSelector The function selector.
     *  @return The facet address associated with the function selector.
     */
    function facetAddress(bytes4 _functionSelector) external view returns (address);

    struct FunctionFacetPair {
        bytes4 selector;
        address facet;
    }

    /**
     * @notice Returns an array of all function selectors and their corresponding facet addresses.
     * @dev Intended for off-chain use.
     */
    function functionFacetPairs() external view returns (FunctionFacetPair[] memory pairs);
}
