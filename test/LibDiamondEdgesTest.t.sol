// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

/**
 * @title LibDiamondEdgesTest
 * @notice Scope/category: diamond-cut and loupe edge semantics for ERC-8109
 * upgrade flows and LibDiamond selector/facet bookkeeping behavior.
 *
 * Covered categories:
 * - Add/replace/remove selector lifecycle via `upgradeDiamond`
 * - Guard rails for invalid inputs (zero facet, no code, empty selectors, duplicate selectors)
 * - Removal mechanics (nonexistent selector, swap-and-pop across facets, swap within same facet)
 * - Loupe consistency for unknown selectors and post-cut facet visibility
 */
contract LibDiamondEdgesTest is MarketTestBase {
    /* ------------------------------------------------------------------------
         add → replace → remove a custom selector (dummyFunction())
       uses VersionFacetV1 / VersionFacetV2 already provided by MarketTestBase
    ------------------------------------------------------------------------ */
    function testCut_AddReplaceRemove_Flow() public {
        // deploy our two facet impls
        DummyUpgradeFacetV1 v1 = new DummyUpgradeFacetV1();
        DummyUpgradeFacetV2 v2 = new DummyUpgradeFacetV2();

        // selector we manage in this test
        bytes4 versionSel = DummyUpgradeFacetV1.dummyFunction.selector;

        // --- add ---
        {
            uint256 beforeLen = loupe.facets().length;

            _upgradeAddSelector(address(v1), versionSel);

            // loupe should show a new facet entry
            uint256 afterLen = loupe.facets().length;
            assertEq(afterLen, beforeLen + 1);

            // lookup should map selector -> v1
            assertEq(loupe.facetAddress(versionSel), address(v1));

            // call through the diamond and see v1 behavior
            uint256 ver = DummyUpgradeFacetV1(address(diamond)).dummyFunction();
            assertEq(ver, 100);
        }

        // --- replace ---
        {
            _upgradeReplaceSelector(address(v2), versionSel);

            // selector now points at v2
            assertEq(loupe.facetAddress(versionSel), address(v2));
            uint256 ver = DummyUpgradeFacetV2(address(diamond)).dummyFunction();
            assertEq(ver, 200);
        }

        // --- remove ---
        {
            _upgradeRemoveSelector(versionSel);

            // selector unmapped
            assertEq(loupe.facetAddress(versionSel), address(0));

            // calling it should hit the diamond fallback and revert with "missing function"
            vm.expectRevert(Diamond__FunctionDoesNotExist.selector);
            DummyUpgradeFacetV2(address(diamond)).dummyFunction();
        }
    }

    /* ------------------------------------------------------------------------
       zero-address guards
    ------------------------------------------------------------------------ */
    function testCut_AddZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IDiamondUpgradeFacet.NoBytecodeAtAddress.selector, address(0)));
        _upgradeAddSelector(address(0), DummyUpgradeFacetV1.dummyFunction.selector);
    }

    function testCut_ReplaceZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IDiamondUpgradeFacet.NoBytecodeAtAddress.selector, address(0)));
        _upgradeReplaceSelector(address(0), DummyUpgradeFacetV1.dummyFunction.selector);
    }

    function testCut_AddEmptySelectorsReverts() public {
        DummyUpgradeFacetV1 v1 = new DummyUpgradeFacetV1();

        IDiamondUpgradeFacet.FacetFunctions[] memory addFns = new IDiamondUpgradeFacet.FacetFunctions[](1);
        addFns[0] = IDiamondUpgradeFacet.FacetFunctions({facet: address(v1), selectors: new bytes4[](0)});

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IDiamondUpgradeFacet.NoSelectorsProvidedForFacet.selector, address(v1)));
        IDiamondUpgradeFacet(address(diamond)).upgradeDiamond(
            addFns,
            new IDiamondUpgradeFacet.FacetFunctions[](0),
            new bytes4[](0),
            address(0),
            bytes(""),
            bytes32(0),
            bytes("")
        );
    }

    function testCut_ReplaceEmptySelectorsReverts() public {
        DummyUpgradeFacetV1 v1 = new DummyUpgradeFacetV1();

        IDiamondUpgradeFacet.FacetFunctions[] memory replaceFns = new IDiamondUpgradeFacet.FacetFunctions[](1);
        replaceFns[0] = IDiamondUpgradeFacet.FacetFunctions({facet: address(v1), selectors: new bytes4[](0)});

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IDiamondUpgradeFacet.NoSelectorsProvidedForFacet.selector, address(v1)));
        IDiamondUpgradeFacet(address(diamond)).upgradeDiamond(
            new IDiamondUpgradeFacet.FacetFunctions[](0),
            replaceFns,
            new bytes4[](0),
            address(0),
            bytes(""),
            bytes32(0),
            bytes("")
        );
    }

    /* ------------------------------------------------------------------------
       removing a selector that doesn't exist
    ------------------------------------------------------------------------ */
    function testCut_RemoveNonexistentSelectorReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDiamondUpgradeFacet.CannotRemoveFunctionThatDoesNotExist.selector,
                DummyUpgradeFacetV1.dummyFunction.selector
            )
        );
        _upgradeRemoveSelector(DummyUpgradeFacetV1.dummyFunction.selector);
    }

    /* ------------------------------------------------------------------------
    initializer revert -> whole upgrade reverts (state rolls back)
    ------------------------------------------------------------------------ */
    function testCut_InitializerRevert_RollsBack() public {
        // First add v1 normally so we can prove no change on rollback later
        DummyUpgradeFacetV1 v1 = new DummyUpgradeFacetV1();
        bytes4 versionSel = DummyUpgradeFacetV1.dummyFunction.selector;

        {
            _upgradeAddSelector(address(v1), versionSel);
            assertEq(DummyUpgradeFacetV1(address(diamond)).dummyFunction(), 100);
        }

        // Now attempt a no-op cut but with a reverting initializer
        RevertingInit bad = new RevertingInit();
        vm.expectRevert(RevertingInit__Boom.selector);
        _upgradeNoopWithInit(address(bad), abi.encodeCall(RevertingInit.init, ()));

        // prove nothing changed
        assertEq(DummyUpgradeFacetV1(address(diamond)).dummyFunction(), 100);
    }

    function testCut_AddDuplicateSelectorReverts() public {
        // loupe.facetAddresses.selector already added in setUp()
        vm.expectRevert(
            abi.encodeWithSelector(
                IDiamondUpgradeFacet.CannotAddFunctionToDiamondThatAlreadyExists.selector,
                IDiamondLoupeFacet.facetAddresses.selector
            )
        );
        _upgradeAddSelector(loupeImpl, IDiamondLoupeFacet.facetAddresses.selector);
    }

    function testCut_ReplaceWithSameFacetReverts() public {
        // selector currently mapped to loupeImpl
        vm.expectRevert(
            abi.encodeWithSelector(
                IDiamondUpgradeFacet.CannotReplaceFunctionWithTheSameFacet.selector,
                IDiamondLoupeFacet.facetAddresses.selector
            )
        );
        _upgradeReplaceSelector(loupeImpl, IDiamondLoupeFacet.facetAddresses.selector);
    }

    function testCut_AddFacetWithNoCodeReverts() public {
        // EOA / no code
        address eoa = vm.addr(0xBEEF);
        vm.expectRevert(abi.encodeWithSelector(IDiamondUpgradeFacet.NoBytecodeAtAddress.selector, eoa));
        _upgradeAddSelector(eoa, DummyUpgradeFacetV1.dummyFunction.selector);
    }

    function testCut_InitAddressHasNoCodeReverts() public {
        address eoa = vm.addr(0xCAFE);
        vm.expectRevert(abi.encodeWithSelector(IDiamondUpgradeFacet.NoBytecodeAtAddress.selector, eoa));
        _upgradeNoopWithInit(eoa, hex"");
    }

    function testCut_RemoveTriggersSwapWithLastFacet() public {
        // deploy two fresh, code-bearing facets with unique selectors
        SwapFacetA fa = new SwapFacetA();
        SwapFacetB fb = new SwapFacetB();

        // add A (selector: a())
        {
            _upgradeAddSelector(address(fa), SwapFacetA.a.selector);
            assertEq(loupe.facetAddress(SwapFacetA.a.selector), address(fa));
        }

        // add B (selector: b())
        {
            _upgradeAddSelector(address(fb), SwapFacetB.b.selector);
            assertEq(loupe.facetAddress(SwapFacetB.b.selector), address(fb));
        }

        // now remove A’s only selector; since A isn’t the last facet,
        // LibDiamond will swap the last facet (B) into A’s slot and pop the tail.
        {
            _upgradeRemoveSelector(SwapFacetA.a.selector);

            // selector unmapped and facet A gone from addresses
            assertEq(loupe.facetAddress(SwapFacetA.a.selector), address(0));
            address[] memory addrs = loupe.facetAddresses();
            for (uint256 i = 0; i < addrs.length; i++) {
                assert(addrs[i] != address(fa));
            }
            // B still present (may have moved index due to swap)
            bool foundB;
            for (uint256 i = 0; i < addrs.length; i++) {
                if (addrs[i] == address(fb)) {
                    foundB = true;
                    break;
                }
            }
            assertTrue(foundB);
        }
    }

    function testCut_RemoveSelector_SwapsWithinFacet() public {
        MultiSelFacet mf = new MultiSelFacet();

        // add both selectors from the SAME facet
        bytes4[] memory sels = new bytes4[](2);
        sels[0] = MultiSelFacet.f1.selector; // will remove this one
        sels[1] = MultiSelFacet.f2.selector; // will be swapped into position 0
        _upgradeAddSelectors(address(mf), sels);

        // sanity: both map to mf
        assertEq(loupe.facetAddress(MultiSelFacet.f1.selector), address(mf));
        assertEq(loupe.facetAddress(MultiSelFacet.f2.selector), address(mf));

        // now remove f1 only -> triggers selector-array swap in LibDiamond.removeFunction
        bytes4[] memory rs = new bytes4[](1);
        rs[0] = MultiSelFacet.f1.selector;
        _upgradeRemoveSelectors(rs);

        // f1 unmapped, f2 still present on the same facet
        assertEq(loupe.facetAddress(MultiSelFacet.f1.selector), address(0));
        assertEq(loupe.facetAddress(MultiSelFacet.f2.selector), address(mf));

        // optional: loupe shows only one selector left for mf
        bytes4[] memory remaining = loupe.facetFunctionSelectors(address(mf));
        assertEq(remaining.length, 1);
        assertEq(remaining[0], MultiSelFacet.f2.selector);
    }

    function testLoupe_FacetAddressUnknownSelectorIsZero() public view {
        assertEq(loupe.facetAddress(bytes4(0xDEADBEEF)), address(0));
    }

    /**
     * @notice Deployment-time initialization invariants for the base diamond.
     * @dev Verifies that constructor + `DiamondInit` wiring is reflected through
     * IERC173 ownership, GetterFacet views, and loupe selector routing.
     */
    function testDiamondInitialization() public view {
        // IERC173 owner must be the deploy-time owner configured by MarketTestBase.
        assertEq(IERC173(address(diamond)).owner(), owner);

        // Initial protocol constants are persisted by initializer storage writes.
        assertEq(getter.getInnovationFee(), INNOVATION_FEE);
        assertEq(getter.getBuyerWhitelistMaxBatchSize(), MAX_BATCH);

        // Getter ownership mirrors IERC173 and no transfer is pending at deploy.
        assertEq(getter.getContractOwner(), owner);
        assertEq(getter.getPendingOwner(), address(0));

        // Core upgrade selector must resolve to the configured upgrade facet.
        address upgradeAddr = loupe.facetAddress(IDiamondUpgradeFacet.upgradeDiamond.selector);
        assertEq(upgradeAddr, diamondUpgradeFacetAddr);
    }
}
