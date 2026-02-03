// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Based on Nick Mudge's Diamond reference implementation pattern (MIT).

error InitializationFunctionReverted(address _initializationContractAddress, bytes _calldata);

/// @title LibDiamond (core storage & selector upgrade helpers)
/// @notice Provides the shared diamond storage layout and internal helpers to add/replace/remove selectors.
/// @dev All functions here must be called via facets executing in the diamond context (delegatecall).
library LibDiamond {
    // 32 bytes keccak hash of a string to use as a diamond storage location.
    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

    /// @notice Selector→facet address mapping payload.
    /// @dev `functionSelectorPosition` indexes into the facet’s selectors array.
    struct FacetAddressAndPosition {
        address facetAddress;
        uint96 functionSelectorPosition;
    }

    /// @notice Per-facet selector set and its position in `facetAddresses`.
    struct FacetFunctionSelectors {
        bytes4[] functionSelectors;
        uint256 facetAddressPosition;
    }

    /// @notice Full diamond storage layout.
    /// @dev All facets share this storage via delegatecall.
    struct DiamondStorage {
        /// selector → (facet, pos in that facet's selector array)
        mapping(bytes4 selector => FacetAddressAndPosition facetInfo) selectorToFacetAndPosition;
        /// facet address → its selectors + its index in `facetAddresses`
        mapping(address facetAddress => FacetFunctionSelectors selectors) facetFunctionSelectors;
        /// list of facet addresses
        address[] facetAddresses;
        /// ERC-165 support flags (incl. Loupe, ERC-173, etc.)
        mapping(bytes4 interfaceId => bool isSupported) supportedInterfaces;
        /// ownership (two-step transfer supported via `pendingContractOwner`)
        address contractOwner;
        address pendingContractOwner;
        /// emergency pause: when true, critical marketplace functions are disabled
        bool paused;
        // 7 bytes padding for future small variables
        /// versioning: current diamond version string (e.g., "1.0.0", "1.1.0")
        string currentVersion;
        /// versioning: cryptographic hash of current diamond configuration (facets + selectors)
        bytes32 currentImplementationId;
        /// versioning: timestamp when current version was set
        uint256 currentVersionTimestamp;
        /// versioning: previous diamond version string (before last upgrade)
        string previousVersion;
        /// versioning: previous implementation ID (before last upgrade)
        bytes32 previousImplementationId;
        /// versioning: timestamp when previous version was set
        uint256 previousVersionTimestamp;
    }

    /// @notice Returns a pointer to diamond storage at the canonical slot.
    /// @dev Inline assembly assigns the slot to the returned storage reference.
    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly ("memory-safe") {
            ds.slot := position
        }
    }

    /// @notice Emitted when ownership changes.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @notice Emitted when a function is added to a diamond.
     * @param _selector The function selector being added.
     * @param _facet    The facet address that will handle calls to `_selector`.
     */
    event DiamondFunctionAdded(bytes4 indexed _selector, address indexed _facet);

    /**
     * @notice Emitted when changing the facet that will handle calls to a function.
     * @param _selector The function selector being affected.
     * @param _oldFacet The facet address previously responsible for `_selector`.
     * @param _newFacet The facet address that will now handle calls to `_selector`.
     */
    event DiamondFunctionReplaced(bytes4 indexed _selector, address indexed _oldFacet, address indexed _newFacet);

    /**
     * @notice Emitted when a function is removed from a diamond.
     * @param _selector The function selector being removed.
     * @param _oldFacet The facet address that previously handled `_selector`.
     */
    event DiamondFunctionRemoved(bytes4 indexed _selector, address indexed _oldFacet);

    /// @notice Sets a new contract owner and emits `OwnershipTransferred`.
    /// @dev No authorization check here; callers should gate with `enforceIsContractOwner`.
    function setContractOwner(address _newOwner) internal {
        DiamondStorage storage ds = diamondStorage();
        address previousOwner = ds.contractOwner;
        ds.contractOwner = _newOwner;
        emit OwnershipTransferred(previousOwner, _newOwner);
    }

    /// @notice Returns the current contract owner.
    function contractOwner() internal view returns (address contractOwner_) {
        contractOwner_ = diamondStorage().contractOwner;
    }

    /// @notice Reverts unless `msg.sender` is the diamond owner.
    function enforceIsContractOwner() internal view {
        require(msg.sender == diamondStorage().contractOwner, "LibDiamond: Must be contract owner");
    }

    /// @notice Adds selectors to a facet (adding the facet if first selector).
    /// @dev Reverts if any selector already exists or facet is zero address.
    function addFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");
        DiamondStorage storage ds = diamondStorage();
        require(_facetAddress != address(0), "LibDiamondCut: Add facet can't be address(0)");
        uint96 selectorPosition = uint96(ds.facetFunctionSelectors[_facetAddress].functionSelectors.length);
        // add new facet address if it does not exist
        if (selectorPosition == 0) {
            addFacet(ds, _facetAddress);
        }

        uint256 selLen = _functionSelectors.length;

        for (uint256 selectorIndex = 0; selectorIndex < selLen;) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            require(oldFacetAddress == address(0), "LibDiamondCut: Can't add function that already exists");
            addFunction(ds, selector, selectorPosition, _facetAddress);
            emit DiamondFunctionAdded(selector, _facetAddress);
            selectorPosition++;
            unchecked {
                selectorIndex++;
            }
        }
    }

    /// @notice Replaces existing selectors with implementations from a facet.
    /// @dev Reverts if facet is zero or attempting to replace with same facet.
    function replaceFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");
        DiamondStorage storage ds = diamondStorage();
        require(_facetAddress != address(0), "LibDiamondCut: Replace facet can't be address(0)");
        uint96 selectorPosition = uint96(ds.facetFunctionSelectors[_facetAddress].functionSelectors.length);
        // add new facet address if it does not exist
        if (selectorPosition == 0) {
            addFacet(ds, _facetAddress);
        }

        uint256 selLen = _functionSelectors.length;

        for (uint256 selectorIndex; selectorIndex < selLen;) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            require(oldFacetAddress != _facetAddress, "LibDiamondCut: Can't replace function with same function");
            removeFunction(ds, oldFacetAddress, selector);
            addFunction(ds, selector, selectorPosition, _facetAddress);
            emit DiamondFunctionReplaced(selector, oldFacetAddress, _facetAddress);
            selectorPosition++;
            unchecked {
                selectorIndex++;
            }
        }
    }

    /// @notice Removes selectors from the diamond.
    /// @dev ERC-8109 upgradeDiamond uses a selector-only removal list. Callers must validate
    ///      existence/immutability constraints before calling to ensure standardized errors.
    function removeSelectors(bytes4[] memory _functionSelectors) internal {
        require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");
        DiamondStorage storage ds = diamondStorage();

        uint256 selLen = _functionSelectors.length;
        for (uint256 selectorIndex; selectorIndex < selLen;) {
            bytes4 selector = _functionSelectors[selectorIndex];
            address oldFacetAddress = ds.selectorToFacetAndPosition[selector].facetAddress;
            removeFunction(ds, oldFacetAddress, selector);
            emit DiamondFunctionRemoved(selector, oldFacetAddress);
            unchecked {
                selectorIndex++;
            }
        }
    }

    /// @notice Registers a new facet address in storage.
    /// @dev Verifies bytecode presence via `extcodesize`.
    function addFacet(DiamondStorage storage ds, address _facetAddress) internal {
        enforceHasContractCode(_facetAddress, "LibDiamondCut: New facet has no code");
        ds.facetFunctionSelectors[_facetAddress].facetAddressPosition = ds.facetAddresses.length;
        ds.facetAddresses.push(_facetAddress);
    }

    /// @notice Adds a single selector mapping to a facet.
    /// @dev Appends selector to the facet’s selector array and records its index.
    function addFunction(DiamondStorage storage ds, bytes4 _selector, uint96 _selectorPosition, address _facetAddress)
        internal
    {
        ds.selectorToFacetAndPosition[_selector].functionSelectorPosition = _selectorPosition;
        ds.facetFunctionSelectors[_facetAddress].functionSelectors.push(_selector);
        ds.selectorToFacetAndPosition[_selector].facetAddress = _facetAddress;
    }

    /// @notice Removes a selector mapping; compacts arrays and prunes empty facets.
    /// @dev Cannot remove immutable (in-diamond) functions; bubbles last item swap-and-pop.
    function removeFunction(DiamondStorage storage ds, address _facetAddress, bytes4 _selector) internal {
        require(_facetAddress != address(0), "LibDiamondCut: Can't remove function that doesn't exist");
        // an immutable function is a function defined directly in a diamond
        require(_facetAddress != address(this), "LibDiamondCut: Can't remove immutable function");
        // replace selector with last selector, then delete last selector
        uint256 selectorPosition = ds.selectorToFacetAndPosition[_selector].functionSelectorPosition;
        uint256 lastSelectorPosition = ds.facetFunctionSelectors[_facetAddress].functionSelectors.length - 1;
        // if not the same then replace _selector with lastSelector
        if (selectorPosition != lastSelectorPosition) {
            bytes4 lastSelector = ds.facetFunctionSelectors[_facetAddress].functionSelectors[lastSelectorPosition];
            ds.facetFunctionSelectors[_facetAddress].functionSelectors[selectorPosition] = lastSelector;
            ds.selectorToFacetAndPosition[lastSelector].functionSelectorPosition = uint96(selectorPosition);
        }
        // delete the last selector
        ds.facetFunctionSelectors[_facetAddress].functionSelectors.pop();
        delete ds.selectorToFacetAndPosition[_selector];

        // if no more selectors for facet address then delete the facet address
        if (lastSelectorPosition == 0) {
            // replace facet address with last facet address and delete last facet address
            uint256 lastFacetAddressPosition = ds.facetAddresses.length - 1;
            uint256 facetAddressPosition = ds.facetFunctionSelectors[_facetAddress].facetAddressPosition;
            if (facetAddressPosition != lastFacetAddressPosition) {
                address lastFacetAddress = ds.facetAddresses[lastFacetAddressPosition];
                ds.facetAddresses[facetAddressPosition] = lastFacetAddress;
                ds.facetFunctionSelectors[lastFacetAddress].facetAddressPosition = facetAddressPosition;
            }
            ds.facetAddresses.pop();
            delete ds.facetFunctionSelectors[_facetAddress].facetAddressPosition;
        }
    }

    /// @notice Executes an optional initializer after a cut.
    /// @dev Requires `_init` to contain code and delegates `_calldata`. Bubbles revert data if any.
    function initializeDiamondCut(address _init, bytes memory _calldata) internal {
        if (_init == address(0)) {
            return;
        }
        enforceHasContractCode(_init, "LibDiamondCut: _init address has no code");
        (bool success, bytes memory error) = _init.delegatecall(_calldata);
        if (!success) {
            if (error.length > 0) {
                assembly ("memory-safe") {
                    let returndata_size := mload(error)
                    revert(add(32, error), returndata_size)
                }
            } else {
                revert InitializationFunctionReverted(_init, _calldata);
            }
        }
    }

    /// @notice Ensures `_contract` has bytecode.
    /// @dev Uses `extcodesize` to guard against EOAs or undeployed addresses.
    function enforceHasContractCode(address _contract, string memory _errorMessage) internal view {
        uint256 contractSize;
        assembly ("memory-safe") {
            contractSize := extcodesize(_contract)
        }
        require(contractSize > 0, _errorMessage);
    }
}
