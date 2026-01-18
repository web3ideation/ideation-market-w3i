// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Based on Nick Mudge's EIP-2535 Diamond reference implementation (MIT).

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IDiamondLoupeFacet} from "../interfaces/IDiamondLoupeFacet.sol";
import {IERC165} from "../interfaces/IERC165.sol";

/// @title DiamondLoupeFacet (EIP-2535 introspection)
/// @notice Read-only queries for facets, selectors, and ERC-165 support, per the Diamonds standard.
/// @dev Reads `LibDiamond.DiamondStorage` (view-only). Returns copies of arrays.
contract DiamondLoupeFacet is IDiamondLoupeFacet, IERC165 {
    /// @notice Gets all facets and their selectors.
    /// @return facets_ Facet
    /// @dev The returned array is allocated in memory and populated from storage.
    function facets() external view override returns (Facet[] memory facets_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 numFacets = ds.facetAddresses.length;
        facets_ = new Facet[](numFacets);
        for (uint256 i = 0; i < numFacets;) {
            address facetAddress_ = ds.facetAddresses[i];
            facets_[i].facetAddress = facetAddress_;
            facets_[i].functionSelectors = ds.facetFunctionSelectors[facetAddress_].functionSelectors;
            unchecked {
                i++;
            }
        }
    }

    /// @notice Gets all the function selectors provided by a facet.
    /// @param _facet The facet address.
    /// @return facetFunctionSelectors_
    /// @dev Returns an in-memory copy of the facet’s selector array.
    function facetFunctionSelectors(address _facet)
        external
        view
        override
        returns (bytes4[] memory facetFunctionSelectors_)
    {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        facetFunctionSelectors_ = ds.facetFunctionSelectors[_facet].functionSelectors;
    }

    /// @notice Get all the facet addresses used by a diamond.
    /// @return facetAddresses_
    /// @dev Returns an in-memory copy of the facet address list.
    function facetAddresses() external view override returns (address[] memory facetAddresses_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        facetAddresses_ = ds.facetAddresses;
    }

    /// @notice Gets the facet that supports the given selector.
    /// @dev If facet is not found return address(0).
    /// @param _functionSelector The function selector.
    /// @return facetAddress_ The facet address.
    function facetAddress(bytes4 _functionSelector) external view override returns (address facetAddress_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        facetAddress_ = ds.selectorToFacetAndPosition[_functionSelector].facetAddress;
    }

    /// @notice Queries ERC-165 support for a given interface ID.
    /// @param _interfaceId The ERC-165 interface identifier.
    /// @return True if the diamond supports this interface, false otherwise.
    function supportsInterface(bytes4 _interfaceId) external view override returns (bool) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return ds.supportedInterfaces[_interfaceId];
    }
}
