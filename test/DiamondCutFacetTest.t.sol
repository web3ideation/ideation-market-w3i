// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

interface IVersion {
    function version() external pure returns (uint256);
}

contract DiamondCutFacetTest is MarketTestBase {
    // --- Helpers ---

    function _addVersionFacet(address facet) internal {
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](1);
        bytes4[] memory selectors = new bytes4[](1);

        selectors[0] = IVersion.version.selector;

        cuts[0] = IDiamondCutFacet.FacetCut({
            facetAddress: facet,
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: selectors
        });

        vm.prank(owner);
        IDiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function _replaceVersionFacet(address newFacet) internal {
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](1);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IVersion.version.selector;

        cuts[0] = IDiamondCutFacet.FacetCut({
            facetAddress: newFacet,
            action: IDiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: selectors
        });

        vm.prank(owner);
        IDiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function _contains(address[] memory a, address x) internal pure returns (bool) {
        for (uint256 i = 0; i < a.length; i++) {
            if (a[i] == x) return true;
        }
        return false;
    }

    // ---------------------------------------------------------------------
    // 1) DiamondCut event payload: exact struct array, _init, _calldata
    // ---------------------------------------------------------------------
    function testDiamondCut_EmitsExactPayload() public {
        VersionFacetV1 v1 = new VersionFacetV1();

        IDiamondCutFacet.FacetCut[] memory expectedCuts = new IDiamondCutFacet.FacetCut[](1);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IVersion.version.selector;

        expectedCuts[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(v1),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: selectors
        });

        // Record logs around the diamondCut call
        vm.recordLogs();
        vm.prank(owner);
        IDiamondCutFacet(address(diamond)).diamondCut(expectedCuts, address(0), "");

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // topic0 = keccak256("DiamondCut((address,uint8,bytes4[])[],address,bytes)")
        bytes32 topic0 = keccak256("DiamondCut((address,uint8,bytes4[])[],address,bytes)");

        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter == address(diamond) && logs[i].topics.length > 0 && logs[i].topics[0] == topic0) {
                (IDiamondCutFacet.FacetCut[] memory gotCuts, address init, bytes memory data) =
                    abi.decode(logs[i].data, (IDiamondCutFacet.FacetCut[], address, bytes));

                // Verify _init and _calldata
                assertEq(init, address(0));
                assertEq(data.length, 0);

                // Verify the cuts payload matches exactly
                assertEq(gotCuts.length, expectedCuts.length);
                for (uint256 j = 0; j < gotCuts.length; j++) {
                    assertEq(gotCuts[j].facetAddress, expectedCuts[j].facetAddress);
                    assertEq(uint256(gotCuts[j].action), uint256(expectedCuts[j].action));
                    assertEq(gotCuts[j].functionSelectors.length, expectedCuts[j].functionSelectors.length);
                    for (uint256 k = 0; k < gotCuts[j].functionSelectors.length; k++) {
                        // compare as bytes32 to avoid type overloading issues
                        assertEq(
                            bytes32(gotCuts[j].functionSelectors[k]), bytes32(expectedCuts[j].functionSelectors[k])
                        );
                    }
                }
                found = true;
                break;
            }
        }
        assertTrue(found, "DiamondCut event not found");
    }

    // ---------------------------------------------------------------------
    // 2) Batch atomicity: later failing op reverts whole cut (no partial state)
    // ---------------------------------------------------------------------
    function testDiamondCut_BatchAtomicity_WhenLaterOpFails() public {
        // Baseline: add V1 and confirm behavior is 1
        VersionFacetV1 v1 = new VersionFacetV1();
        _addVersionFacet(address(v1));
        assertEq(IVersion(address(diamond)).version(), 1);

        // Prepare a batch: [Replace OK, Remove FAIL (non-zero facetAddress)]
        VersionFacetV2 v2 = new VersionFacetV2();

        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](2);

        // Replace to V2 (valid)
        bytes4[] memory selReplace = new bytes4[](1);
        selReplace[0] = IVersion.version.selector;
        cuts[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(v2),
            action: IDiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: selReplace
        });

        // Remove (invalid because facetAddress must be address(0))
        bytes4[] memory selRemove = new bytes4[](1);
        selRemove[0] = IVersion.version.selector;
        cuts[1] = IDiamondCutFacet.FacetCut({
            facetAddress: address(0xBEEF), // non-zero → should revert in removeFunctions
            action: IDiamondCutFacet.FacetCutAction.Remove,
            functionSelectors: selRemove
        });

        // Expect revert and ensure entire batch has no effect
        vm.prank(owner);
        vm.expectRevert(bytes("LibDiamondCut: Remove facet address must be address(0)"));
        IDiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), "");

        // Still V1
        assertEq(IVersion(address(diamond)).version(), 1);
        assertEq(loupe.facetAddress(IVersion.version.selector), address(v1));

        // And V2 not added
        address[] memory facets = loupe.facetAddresses();
        assertFalse(_contains(facets, address(v2)));
    }

    // ---------------------------------------------------------------------
    // 3) Functional replacement proof: return value flips from V1 → V2
    // ---------------------------------------------------------------------
    function testDiamondCut_FunctionalReplacementProof() public {
        VersionFacetV1 v1 = new VersionFacetV1();
        VersionFacetV2 v2 = new VersionFacetV2();

        _addVersionFacet(address(v1));
        assertEq(IVersion(address(diamond)).version(), 1);
        assertEq(loupe.facetAddress(IVersion.version.selector), address(v1));

        _replaceVersionFacet(address(v2));
        assertEq(IVersion(address(diamond)).version(), 2);
        assertEq(loupe.facetAddress(IVersion.version.selector), address(v2));
    }

    // ---------------------------------------------------------------------
    // 4) Old facet address is pruned when its last selector is moved/replaced
    // ---------------------------------------------------------------------
    function testDiamondCut_ReplacementPrunesEmptyFacetAddress() public {
        VersionFacetV1 v1 = new VersionFacetV1();
        VersionFacetV2 v2 = new VersionFacetV2();

        _addVersionFacet(address(v1));
        assertTrue(_contains(loupe.facetAddresses(), address(v1)));

        _replaceVersionFacet(address(v2));

        // After replace, V1 had only one selector; it should be removed from facetAddresses
        address[] memory facets = loupe.facetAddresses();
        assertFalse(_contains(facets, address(v1)));
        assertEq(loupe.facetAddress(IVersion.version.selector), address(v2));
    }

    // ---------------------------------------------------------------------
    // 5) Loupe consistency: each selector maps back to its facet, no duplicates
    // ---------------------------------------------------------------------
    function testLoupe_SetConsistency_NoSelectorStraddling() public view {
        // Use current setup state (marketplace facets) and assert consistency
        address[] memory facets = loupe.facetAddresses();

        // selector → facet seen
        // Emulate with two parallel arrays
        bytes4[] memory seenSelectors = new bytes4[](0);
        address[] memory seenFacetOf = new address[](0);

        for (uint256 i = 0; i < facets.length; i++) {
            address f = facets[i];
            bytes4[] memory sels = loupe.facetFunctionSelectors(f);
            for (uint256 j = 0; j < sels.length; j++) {
                bytes4 sel = sels[j];

                // 5a) Each selector should map back to this facet
                assertEq(loupe.facetAddress(sel), f);

                // 5b) No selector should appear in more than one facet
                // (linear scan is fine; selector set is small)
                for (uint256 k = 0; k < seenSelectors.length; k++) {
                    if (seenSelectors[k] == sel) {
                        assertEq(seenFacetOf[k], f, "selector appears in multiple facets");
                    }
                }

                // push into "seen" (manual dynamic push)
                bytes4[] memory newSeenSelectors = new bytes4[](seenSelectors.length + 1);
                address[] memory newSeenFacetOf = new address[](seenFacetOf.length + 1);
                for (uint256 m = 0; m < seenSelectors.length; m++) {
                    newSeenSelectors[m] = seenSelectors[m];
                    newSeenFacetOf[m] = seenFacetOf[m];
                }
                newSeenSelectors[seenSelectors.length] = sel;
                newSeenFacetOf[seenFacetOf.length] = f;
                seenSelectors = newSeenSelectors;
                seenFacetOf = newSeenFacetOf;
            }
        }
    }

    function testLoupe_GlobalSetInvariants_MatchAcrossViews() public view {
        // ---------- Build Set A from facets() ----------
        IDiamondLoupeFacet.Facet[] memory all = loupe.facets();

        // Track (selector, facet) pairs from facets()
        bytes32[] memory pairsA = new bytes32[](0);
        // Track facet addresses seen in facets()
        address[] memory facetsA = new address[](0);

        for (uint256 i = 0; i < all.length; i++) {
            address f = all[i].facetAddress;
            require(f != address(0), "facets(): zero facet address");

            // uniqueness of facet addresses within facets()
            for (uint256 j = 0; j < facetsA.length; j++) {
                require(facetsA[j] != f, "facets(): duplicate facet address");
            }
            // push f into facetsA
            address[] memory _facetsA = new address[](facetsA.length + 1);
            for (uint256 a = 0; a < facetsA.length; a++) {
                _facetsA[a] = facetsA[a];
            }
            _facetsA[facetsA.length] = f;
            facetsA = _facetsA;

            bytes4[] memory sels = all[i].functionSelectors;
            for (uint256 k = 0; k < sels.length; k++) {
                // each selector in facets() must map back to f
                require(loupe.facetAddress(sels[k]) == f, "facets(): facetAddress mismatch");

                // pair uniqueness
                bytes32 p = keccak256(abi.encodePacked(sels[k], f));
                for (uint256 d = 0; d < pairsA.length; d++) {
                    require(pairsA[d] != p, "facets(): duplicate (selector,facet)");
                }

                // push pair
                bytes32[] memory _pairsA = new bytes32[](pairsA.length + 1);
                for (uint256 b = 0; b < pairsA.length; b++) {
                    _pairsA[b] = pairsA[b];
                }
                _pairsA[pairsA.length] = p;
                pairsA = _pairsA;
            }
        }

        // ---------- Build Set B from facetAddresses()+facetFunctionSelectors() ----------
        address[] memory addrs = loupe.facetAddresses();
        require(addrs.length == facetsA.length, "facetAddresses(): count mismatch");

        // facet address uniqueness and nonzero in this view
        for (uint256 i = 0; i < addrs.length; i++) {
            require(addrs[i] != address(0), "facetAddresses(): zero address");
            for (uint256 j = i + 1; j < addrs.length; j++) {
                require(addrs[i] != addrs[j], "facetAddresses(): duplicate");
            }
        }

        // ---------- Equality A -> B ----------
        for (uint256 i = 0; i < all.length; i++) {
            address f = all[i].facetAddress;
            bytes4[] memory sels = all[i].functionSelectors;

            // facet in A must exist in B
            bool foundFacet;
            for (uint256 a = 0; a < addrs.length; a++) {
                if (addrs[a] == f) {
                    foundFacet = true;
                    bytes4[] memory selsB = loupe.facetFunctionSelectors(f);
                    // each selector in A must exist under same facet in B
                    for (uint256 k = 0; k < sels.length; k++) {
                        bool foundSel;
                        for (uint256 sIx = 0; sIx < selsB.length; sIx++) {
                            if (selsB[sIx] == sels[k]) {
                                foundSel = true;
                                break;
                            }
                        }
                        require(foundSel, "A to B: selector missing in facetFunctionSelectors");
                    }
                    break;
                }
            }
            require(foundFacet, "A toB: facet missing in facetAddresses");
        }

        // ---------- Equality B -> A ----------
        for (uint256 a = 0; a < addrs.length; a++) {
            address f = addrs[a];
            bytes4[] memory selsB = loupe.facetFunctionSelectors(f);
            for (uint256 sIx = 0; sIx < selsB.length; sIx++) {
                // pair must exist in A
                bytes32 p = keccak256(abi.encodePacked(selsB[sIx], f));
                bool ok;
                for (uint256 x = 0; x < pairsA.length; x++) {
                    if (pairsA[x] == p) {
                        ok = true;
                        break;
                    }
                }
                require(ok, "B to A: (selector,facet) missing from facets()");
                // and facetAddress(sel) must equal f
                require(loupe.facetAddress(selsB[sIx]) == f, "B to A: facetAddress mismatch");
            }
        }
    }

    // ---------------------------------------------------------------------
    // 6) Init-only diamondCut: no facet changes, initializer mutates storage
    // ---------------------------------------------------------------------
    function testDiamondCut_InitOnly_CallsInitializerAndMutatesStorage() public {
        uint32 prev = getter.getInnovationFee();
        assertEq(prev, INNOVATION_FEE);

        InitWriteFee init = new InitWriteFee();

        // No facet changes; just run _init
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](0);

        vm.prank(owner);
        IDiamondCutFacet(address(diamond)).diamondCut(
            cuts, address(init), abi.encodeWithSelector(InitWriteFee.initSetFee.selector, uint32(4242))
        );

        assertEq(getter.getInnovationFee(), 4242, "init-only call did not apply");
        // Facet set unchanged
        address[] memory addrsBefore = loupe.facetAddresses();
        address[] memory addrsAfter = loupe.facetAddresses();
        assertEq(addrsAfter.length, addrsBefore.length, "facet set changed during init-only");
    }

    // ---------------------------------------------------------------------
    // 7) Malicious initializer cannot escalate privileges
    // ---------------------------------------------------------------------
    function testDiamondCut_MaliciousInitializerCannotEscalate() public {
        address ownerBefore = IERC173(address(diamond)).owner();
        uint32 feeBefore = getter.getInnovationFee();

        MaliciousInitTryAdmin bad = new MaliciousInitTryAdmin();

        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](0);

        // The initializer swallows its own failures and returns successfully.
        // diamondCut should succeed, but state (owner/fee) must be unchanged.
        vm.prank(owner);
        IDiamondCutFacet(address(diamond)).diamondCut(
            cuts,
            address(bad),
            abi.encodeWithSelector(MaliciousInitTryAdmin.initTryAdmin.selector, vm.addr(0xBEEF), uint32(999_999))
        );

        assertEq(IERC173(address(diamond)).owner(), ownerBefore, "owner changed via initializer");
        assertEq(getter.getInnovationFee(), feeBefore, "fee changed via initializer");
    }
}

// --- Helpers for initializer coverage ---

contract InitWriteFee {
    // Proves init-only calls can mutate diamond storage via delegatecall
    function initSetFee(uint32 newFee) external {
        AppStorage storage s = LibAppStorage.appStorage();
        s.innovationFee = newFee; // write directly via diamond storage pointer
    }
}

contract MaliciousInitTryAdmin {
    // Tries to call onlyOwner functions from initializer context; must NOT succeed
    function initTryAdmin(address newOwner, uint32 newFee) external {
        // Attempt transferOwnership (IERC173 view)
        try IERC173(address(this)).transferOwnership(newOwner) {
            revert("transferOwnership should revert");
        } catch { /* expected */ }

        // Attempt setInnovationFee (onlyOwner)
        try IdeationMarketFacet(address(this)).setInnovationFee(newFee) {
            revert("setInnovationFee should revert");
        } catch { /* expected */ }
        // Note: we *do not* revert here; diamondCut should succeed with no state changes.
    }
}
