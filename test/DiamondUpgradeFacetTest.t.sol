// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

contract DiamondUpgradeFacetTest is MarketTestBase {
    // ---------------------------------------------------------------------
    // 1) ERC-8109 per-selector events emitted on upgrade
    // ---------------------------------------------------------------------
    function testUpgradeDiamond_EmitsPerSelectorAddedEvent() public {
        DummyUpgradeFacetV1 v1 = new DummyUpgradeFacetV1();

        // Record logs around the upgradeDiamond call
        vm.recordLogs();
        _upgradeAddSelector(address(v1), IDummyUpgrade.dummyFunction.selector);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // topic0 = keccak256("DiamondFunctionAdded(bytes4,address)")
        bytes32 topic0 = keccak256("DiamondFunctionAdded(bytes4,address)");

        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(diamond) && logs[i].topics.length == 3 && logs[i].topics[0] == topic0
                    && logs[i].topics[1] == bytes32(IDummyUpgrade.dummyFunction.selector)
                    && logs[i].topics[2] == bytes32(uint256(uint160(address(v1))))
            ) {
                // Indexed topics fully describe the event; no data payload.
                assertEq(logs[i].data.length, 0);
                found = true;
                break;
            }
        }
        assertTrue(found, "DiamondFunctionAdded event not found");
    }

    function testUpgradeDiamond_EmitsPerSelectorReplacedEvent() public {
        DummyUpgradeFacetV1 v1 = new DummyUpgradeFacetV1();
        DummyUpgradeFacetV2 v2 = new DummyUpgradeFacetV2();

        // First add selector to v1
        _upgradeAddSelector(address(v1), IDummyUpgrade.dummyFunction.selector);

        // Record logs around the replace upgrade
        vm.recordLogs();
        _upgradeReplaceSelector(address(v2), IDummyUpgrade.dummyFunction.selector);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // topic0 = keccak256("DiamondFunctionReplaced(bytes4,address,address)")
        bytes32 topic0 = keccak256("DiamondFunctionReplaced(bytes4,address,address)");

        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(diamond) && logs[i].topics.length == 4 && logs[i].topics[0] == topic0
                    && logs[i].topics[1] == bytes32(IDummyUpgrade.dummyFunction.selector)
                    && logs[i].topics[2] == bytes32(uint256(uint160(address(v1))))
                    && logs[i].topics[3] == bytes32(uint256(uint160(address(v2))))
            ) {
                // Indexed topics fully describe the event; no data payload.
                assertEq(logs[i].data.length, 0);
                found = true;
                break;
            }
        }
        assertTrue(found, "DiamondFunctionReplaced event not found");
    }

    function testUpgradeDiamond_EmitsPerSelectorRemovedEvent() public {
        DummyUpgradeFacetV1 v1 = new DummyUpgradeFacetV1();

        _upgradeAddSelector(address(v1), IDummyUpgrade.dummyFunction.selector);

        vm.recordLogs();
        _upgradeRemoveSelector(IDummyUpgrade.dummyFunction.selector);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // topic0 = keccak256("DiamondFunctionRemoved(bytes4,address)")
        bytes32 topic0 = keccak256("DiamondFunctionRemoved(bytes4,address)");

        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].emitter == address(diamond) && logs[i].topics.length == 3 && logs[i].topics[0] == topic0
                    && logs[i].topics[1] == bytes32(IDummyUpgrade.dummyFunction.selector)
                    && logs[i].topics[2] == bytes32(uint256(uint160(address(v1))))
            ) {
                // Indexed topics fully describe the event; no data payload.
                assertEq(logs[i].data.length, 0);
                found = true;
                break;
            }
        }
        assertTrue(found, "DiamondFunctionRemoved event not found");
    }

    // ---------------------------------------------------------------------
    // 2) Batch atomicity: later failing op reverts whole cut (no partial state)
    // ---------------------------------------------------------------------
    function testUpgradeDiamond_IsAtomic_WhenRemovePhaseFails() public {
        // Baseline: add V1 and confirm behavior is 100
        DummyUpgradeFacetV1 v1 = new DummyUpgradeFacetV1();
        _upgradeAddSelector(address(v1), IDummyUpgrade.dummyFunction.selector);
        assertEq(IDummyUpgrade(address(diamond)).dummyFunction(), 100);

        // Prepare a batch: [Replace OK, Remove FAIL (non-existent selector)]
        DummyUpgradeFacetV2 v2 = new DummyUpgradeFacetV2();

        // Replace to V2 (valid)
        IDiamondUpgradeFacet.FacetFunctions[] memory replaceFns = new IDiamondUpgradeFacet.FacetFunctions[](1);
        bytes4[] memory selReplace = new bytes4[](1);
        selReplace[0] = IDummyUpgrade.dummyFunction.selector;
        replaceFns[0] = IDiamondUpgradeFacet.FacetFunctions({facet: address(v2), selectors: selReplace});

        // Remove non-existent selector (must revert)
        bytes4[] memory selRemove = new bytes4[](1);
        selRemove[0] = bytes4(0xDEADBEEF);

        // Expect revert and ensure entire batch has no effect
        vm.expectRevert(
            abi.encodeWithSelector(IDiamondUpgradeFacet.CannotRemoveFunctionThatDoesNotExist.selector, selRemove[0])
        );
        _upgradeDiamond(new IDiamondUpgradeFacet.FacetFunctions[](0), replaceFns, selRemove, address(0), "");

        // Still V1
        assertEq(IDummyUpgrade(address(diamond)).dummyFunction(), 100);
        assertEq(loupe.facetAddress(IDummyUpgrade.dummyFunction.selector), address(v1));

        // And V2 not added
        address[] memory facets = loupe.facetAddresses();
        assertFalse(_contains(facets, address(v2)));
    }

    // ---------------------------------------------------------------------
    // 3) Functional replacement proof: return value flips from V1 → V2
    // ---------------------------------------------------------------------
    function testDiamondCut_FunctionalReplacementProof() public {
        DummyUpgradeFacetV1 v1 = new DummyUpgradeFacetV1();
        DummyUpgradeFacetV2 v2 = new DummyUpgradeFacetV2();

        _upgradeAddSelector(address(v1), IDummyUpgrade.dummyFunction.selector);
        assertEq(IDummyUpgrade(address(diamond)).dummyFunction(), 100);
        assertEq(loupe.facetAddress(IDummyUpgrade.dummyFunction.selector), address(v1));

        _upgradeReplaceSelector(address(v2), IDummyUpgrade.dummyFunction.selector);
        assertEq(IDummyUpgrade(address(diamond)).dummyFunction(), 200);
        assertEq(loupe.facetAddress(IDummyUpgrade.dummyFunction.selector), address(v2));
    }

    // ---------------------------------------------------------------------
    // 4) Old facet address is pruned when its last selector is moved/replaced
    // ---------------------------------------------------------------------
    function testDiamondCut_ReplacementPrunesEmptyFacetAddress() public {
        DummyUpgradeFacetV1 v1 = new DummyUpgradeFacetV1();
        DummyUpgradeFacetV2 v2 = new DummyUpgradeFacetV2();

        _upgradeAddSelector(address(v1), IDummyUpgrade.dummyFunction.selector);
        assertTrue(_contains(loupe.facetAddresses(), address(v1)));

        _upgradeReplaceSelector(address(v2), IDummyUpgrade.dummyFunction.selector);

        // After replace, V1 had only one selector; it should be removed from facetAddresses
        address[] memory facets = loupe.facetAddresses();
        assertFalse(_contains(facets, address(v1)));
        assertEq(loupe.facetAddress(IDummyUpgrade.dummyFunction.selector), address(v2));
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
    // 5c) ERC-8109 inspect: functionFacetPairs() matches loupe views
    // ---------------------------------------------------------------------
    function testInspect_FunctionFacetPairs_MatchLoupe() public view {
        IDiamondInspectFacet.FunctionFacetPair[] memory pairs =
            IDiamondInspectFacet(address(diamond)).functionFacetPairs();

        // Count selectors from loupe views
        address[] memory facets = loupe.facetAddresses();
        uint256 expected;
        for (uint256 i = 0; i < facets.length; i++) {
            expected += loupe.facetFunctionSelectors(facets[i]).length;
        }
        assertEq(pairs.length, expected, "functionFacetPairs length mismatch");

        bool foundUpgrade;

        for (uint256 i = 0; i < pairs.length; i++) {
            bytes4 sel = pairs[i].selector;
            address fac = pairs[i].facet;

            assertTrue(fac != address(0), "functionFacetPairs: zero facet");
            assertEq(loupe.facetAddress(sel), fac, "functionFacetPairs: facetAddress mismatch");

            // selector must appear in that facet's selector list
            bytes4[] memory sels = loupe.facetFunctionSelectors(fac);
            bool inFacet;
            for (uint256 j = 0; j < sels.length; j++) {
                if (sels[j] == sel) {
                    inFacet = true;
                    break;
                }
            }
            assertTrue(inFacet, "functionFacetPairs: selector not listed under facet");

            // selectors should be unique across all pairs
            for (uint256 k = i + 1; k < pairs.length; k++) {
                assertTrue(pairs[k].selector != sel, "functionFacetPairs: duplicate selector");
            }

            if (sel == IDiamondUpgradeFacet.upgradeDiamond.selector) {
                foundUpgrade = true;
                assertEq(fac, diamondUpgradeFacetAddr, "upgradeDiamond mapped to unexpected facet");
            }
        }

        assertTrue(foundUpgrade, "upgradeDiamond selector missing from functionFacetPairs");
    }

    // ---------------------------------------------------------------------
    // 6) Init-only upgrade: no facet changes, initializer mutates storage
    // ---------------------------------------------------------------------
    function testDiamondCut_InitOnly_CallsInitializerAndMutatesStorage() public {
        uint32 prev = getter.getInnovationFee();
        assertEq(prev, INNOVATION_FEE);

        address[] memory addrsBefore = loupe.facetAddresses();

        InitWriteFee init = new InitWriteFee();

        // No facet changes; just run _init
        _upgradeNoopWithInit(address(init), abi.encodeWithSelector(InitWriteFee.initSetFee.selector, uint32(4242)));

        assertEq(getter.getInnovationFee(), 4242, "init-only call did not apply");
        // Facet set unchanged
        address[] memory addrsAfter = loupe.facetAddresses();
        assertEq(addrsAfter.length, addrsBefore.length, "facet set changed during init-only");
        for (uint256 i = 0; i < addrsBefore.length; i++) {
            assertEq(addrsAfter[i], addrsBefore[i], "facet order/contents changed during init-only");
        }
    }

    function testDiamondCut_InitGuard_AllowsCorrectLayout() public {
        LayoutGuardInitGood good = new LayoutGuardInitGood();

        _upgradeNoopWithInit(
            address(good), abi.encodeWithSelector(LayoutGuardInitGood.initCheckLayout.selector, uint32(42_42))
        );
        assertEq(getter.getInnovationFee(), INNOVATION_FEE);
    }

    function testDiamondCut_InitGuard_BlocksBadLayout() public {
        LayoutGuardInitBad bad = new LayoutGuardInitBad();

        // choose a marker that MUST differ from the current fee
        uint32 prev = getter.getInnovationFee();
        uint32 marker = prev ^ 0xBEEF; // guaranteed != prev

        vm.expectRevert(LayoutGuardInitBad.LayoutMismatch.selector);
        _upgradeNoopWithInit(address(bad), abi.encodeWithSelector(LayoutGuardInitBad.initCheckLayout.selector, marker));
    }

    // ---------------------------------------------------------------------
    // 7) ERC-8109 upgrade-level events: DiamondDelegateCall & DiamondMetadata
    // ---------------------------------------------------------------------
    function testUpgradeDiamond_EmitsDelegateCallAndMetadata() public {
        // Snapshot current fee to prove delegatecall actually executed
        uint32 prev = getter.getInnovationFee();
        assertEq(prev, INNOVATION_FEE);

        InitWriteFee init = new InitWriteFee();
        bytes memory functionCall = abi.encodeWithSelector(InitWriteFee.initSetFee.selector, uint32(4242));
        bytes32 tag = keccak256("test-tag");
        bytes memory meta = hex"010203";

        vm.recordLogs();

        vm.prank(owner);
        IDiamondUpgradeFacet(address(diamond)).upgradeDiamond(
            new IDiamondUpgradeFacet.FacetFunctions[](0),
            new IDiamondUpgradeFacet.FacetFunctions[](0),
            new bytes4[](0),
            address(init),
            functionCall,
            tag,
            meta
        );

        // Delegatecall must have executed and updated storage
        assertEq(getter.getInnovationFee(), 4242, "delegatecall did not mutate state");

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // topic0 = keccak256("DiamondDelegateCall(address,bytes)")
        bytes32 delegateTopic0 = keccak256("DiamondDelegateCall(address,bytes)");
        // topic0 = keccak256("DiamondMetadata(bytes32,bytes)")
        bytes32 metaTopic0 = keccak256("DiamondMetadata(bytes32,bytes)");

        bool foundDelegate;
        bool foundMetadata;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != address(diamond)) continue;

            if (logs[i].topics.length == 2 && logs[i].topics[0] == delegateTopic0) {
                // indexed delegate
                if (logs[i].topics[1] == bytes32(uint256(uint160(address(init))))) {
                    assertEq(logs[i].data, abi.encode(functionCall));
                    foundDelegate = true;
                }
            }

            if (logs[i].topics.length == 2 && logs[i].topics[0] == metaTopic0) {
                // indexed tag
                if (logs[i].topics[1] == tag) {
                    assertEq(logs[i].data, abi.encode(meta));
                    foundMetadata = true;
                }
            }
        }

        assertTrue(foundDelegate, "DiamondDelegateCall event not found");
        assertTrue(foundMetadata, "DiamondMetadata event not found");
    }

    // ---------------------------------------------------------------------
    // 8) Owner authorization: only contract owner can call upgrade
    // ---------------------------------------------------------------------
    function testDiamondCut_OnlyOwnerCanCall() public {
        DummyUpgradeFacetV1 v1 = new DummyUpgradeFacetV1();
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = DummyUpgradeFacetV1.dummyFunction.selector;

        IDiamondUpgradeFacet.FacetFunctions[] memory addFns = new IDiamondUpgradeFacet.FacetFunctions[](1);
        addFns[0] = IDiamondUpgradeFacet.FacetFunctions({facet: address(v1), selectors: sels});

        // Non-owner cannot call upgrade
        vm.prank(buyer);
        vm.expectRevert("LibDiamond: Must be contract owner");
        IDiamondUpgradeFacet(address(diamond)).upgradeDiamond(
            addFns, new IDiamondUpgradeFacet.FacetFunctions[](0), new bytes4[](0), address(0), "", bytes32(0), bytes("")
        );

        // Owner can successfully call upgrade
        _upgradeAddSelectors(address(v1), sels);

        // Verify the facet was added
        (bool ok, bytes memory ret) =
            address(diamond).call(abi.encodeWithSelector(DummyUpgradeFacetV1.dummyFunction.selector));
        assertTrue(ok);
        assertEq(abi.decode(ret, (uint256)), 100);
    }

    function testDiamondCut_RemoveFacet_MakesSelectorUncallable() public {
        // 1) Add V1 and prove callable
        DummyUpgradeFacetV1 v1 = new DummyUpgradeFacetV1();
        _upgradeAddSelector(address(v1), IDummyUpgrade.dummyFunction.selector);
        assertEq(IDummyUpgrade(address(diamond)).dummyFunction(), 100);
        assertEq(loupe.facetAddress(IDummyUpgrade.dummyFunction.selector), address(v1));

        // 2) Remove the selector properly
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IDummyUpgrade.dummyFunction.selector;

        _upgradeRemoveSelectors(selectors);

        // 3) Loupe now returns zero for this selector
        assertEq(loupe.facetAddress(IDummyUpgrade.dummyFunction.selector), address(0));

        // 4) Calling removed function reverts via diamond fallback
        vm.expectRevert(Diamond__FunctionDoesNotExist.selector);
        IDummyUpgrade(address(diamond)).dummyFunction();

        // 4b) Raw call also fails
        (bool ok,) = address(diamond).call(abi.encodeWithSelector(IDummyUpgrade.dummyFunction.selector));
        assertFalse(ok, "raw call to removed selector unexpectedly succeeded");

        // 5) Since V1 had only this selector, its address should be pruned
        address[] memory facets = loupe.facetAddresses();
        assertFalse(_contains(facets, address(v1)));

        // 6) Ensure selector not present in any facetFunctionSelectors()
        for (uint256 i = 0; i < facets.length; i++) {
            bytes4[] memory sels = loupe.facetFunctionSelectors(facets[i]);
            for (uint256 j = 0; j < sels.length; j++) {
                assertTrue(sels[j] != IDummyUpgrade.dummyFunction.selector, "removed selector still listed");
            }
        }
    }

    function testDiamondCut_RemoveOneOfMany_DoesNotPruneFacet() public {
        DualFacet dual = new DualFacet();

        // Add both selectors
        bytes4[] memory sels = new bytes4[](2);
        sels[0] = DualFacet.a.selector;
        sels[1] = DualFacet.b.selector;
        _upgradeAddSelectors(address(dual), sels);

        // Prove both callable
        (bool okA, bytes memory ra) = address(diamond).call(abi.encodeWithSelector(DualFacet.a.selector));
        (bool okB, bytes memory rb) = address(diamond).call(abi.encodeWithSelector(DualFacet.b.selector));
        assertTrue(okA && okB);
        assertEq(abi.decode(ra, (uint256)), 11);
        assertEq(abi.decode(rb, (uint256)), 22);

        // Remove only 'a'
        bytes4[] memory one = new bytes4[](1);
        one[0] = DualFacet.a.selector;
        _upgradeRemoveSelectors(one);

        // 'a' gone, 'b' remains and facet not pruned
        assertEq(loupe.facetAddress(DualFacet.a.selector), address(0));
        vm.expectRevert(Diamond__FunctionDoesNotExist.selector);
        DualFacet(address(diamond)).a();

        address facB = loupe.facetAddress(DualFacet.b.selector);
        assertEq(facB, address(dual), "remaining selector moved unexpectedly");

        bool stillListed;
        address[] memory fas = loupe.facetAddresses();
        for (uint256 i = 0; i < fas.length; i++) {
            if (fas[i] == address(dual)) stillListed = true;
        }
        assertTrue(stillListed, "facet wrongly pruned after partial removal");
    }
}
