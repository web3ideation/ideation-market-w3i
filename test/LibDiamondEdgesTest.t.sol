// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

/* ---------- helpers ---------- */

/// Custom error we expect from the reverting initializer
error RevertingInit__Boom();

/// Minimal initializer that always reverts (to test rollback)
contract RevertingInit {
    function init() external pure {
        revert RevertingInit__Boom();
    }
}

/* ---------- tests ---------- */

/// @title LibDiamondEdgesTest
/// @notice Edge-case tests around diamondCut & loupe, built on MarketTestBase
contract LibDiamondEdgesTest is MarketTestBase {
    /* ------------------------------------------------------------------------
       onlyOwner on diamondCut
    ------------------------------------------------------------------------ */
    function testCut_OnlyOwner() public {
        // non-owner tries to cut
        vm.startPrank(buyer);
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](0);

        // don't assert an exact selector to avoid coupling to error strings
        vm.expectRevert("LibDiamond: Must be contract owner");
        IDiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), "");
        vm.stopPrank();
    }

    /* ------------------------------------------------------------------------
       add → replace → remove a custom selector (version())
       uses VersionFacetV1 / VersionFacetV2 already provided by MarketTestBase
    ------------------------------------------------------------------------ */
    function testCut_AddReplaceRemove_Flow() public {
        // deploy our two facet impls
        VersionFacetV1 v1 = new VersionFacetV1();
        VersionFacetV2 v2 = new VersionFacetV2();

        // selector we manage in this test
        bytes4 versionSel = VersionFacetV1.version.selector;

        // --- add ---
        {
            IDiamondCutFacet.FacetCut[] memory addCut = new IDiamondCutFacet.FacetCut[](1);
            bytes4[] memory sels = new bytes4[](1);

            sels[0] = versionSel;

            addCut[0] = IDiamondCutFacet.FacetCut({
                facetAddress: address(v1),
                action: IDiamondCutFacet.FacetCutAction.Add,
                functionSelectors: sels
            });

            uint256 beforeLen = loupe.facets().length;

            vm.prank(owner);
            IDiamondCutFacet(address(diamond)).diamondCut(addCut, address(0), "");

            // loupe should show a new facet entry
            uint256 afterLen = loupe.facets().length;
            assertEq(afterLen, beforeLen + 1);

            // lookup should map selector -> v1
            assertEq(loupe.facetAddress(versionSel), address(v1));

            // call through the diamond and see v1 behavior
            uint256 ver = VersionFacetV1(address(diamond)).version();
            assertEq(ver, 1);
        }

        // --- replace ---
        {
            IDiamondCutFacet.FacetCut[] memory repCut = new IDiamondCutFacet.FacetCut[](1);
            bytes4[] memory sels = new bytes4[](1);

            sels[0] = versionSel;
            repCut[0] = IDiamondCutFacet.FacetCut({
                facetAddress: address(v2),
                action: IDiamondCutFacet.FacetCutAction.Replace,
                functionSelectors: sels
            });

            vm.prank(owner);
            IDiamondCutFacet(address(diamond)).diamondCut(repCut, address(0), "");

            // selector now points at v2
            assertEq(loupe.facetAddress(versionSel), address(v2));
            uint256 ver = VersionFacetV2(address(diamond)).version();
            assertEq(ver, 2);
        }

        // --- remove ---
        {
            IDiamondCutFacet.FacetCut[] memory remCut = new IDiamondCutFacet.FacetCut[](1);
            bytes4[] memory sels = new bytes4[](1);

            sels[0] = versionSel;

            // per EIP-2535, remove uses facetAddress = address(0)
            remCut[0] = IDiamondCutFacet.FacetCut({
                facetAddress: address(0),
                action: IDiamondCutFacet.FacetCutAction.Remove,
                functionSelectors: sels
            });

            vm.prank(owner);
            IDiamondCutFacet(address(diamond)).diamondCut(remCut, address(0), "");

            // selector unmapped
            assertEq(loupe.facetAddress(versionSel), address(0));

            // calling it should hit the diamond fallback and revert with "missing function"
            vm.expectRevert(Diamond__FunctionDoesNotExist.selector);
            VersionFacetV2(address(diamond)).version();
        }
    }

    /* ------------------------------------------------------------------------
       zero-address guards
    ------------------------------------------------------------------------ */
    function testCut_AddZeroAddressReverts() public {
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](1);
        bytes4[] memory sels = new bytes4[](1);

        sels[0] = VersionFacetV1.version.selector;

        cuts[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(0),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: sels
        });

        vm.prank(owner);
        vm.expectRevert("LibDiamondCut: Add facet can't be address(0)");
        IDiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function testCut_ReplaceZeroAddressReverts() public {
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](1);
        bytes4[] memory sels = new bytes4[](1);

        sels[0] = VersionFacetV1.version.selector;

        cuts[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(0),
            action: IDiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: sels
        });

        vm.prank(owner);
        vm.expectRevert("LibDiamondCut: Add facet can't be address(0)");
        IDiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), "");
    }

    /* ------------------------------------------------------------------------
       removing a selector that doesn't exist
    ------------------------------------------------------------------------ */
    function testCut_RemoveNonexistentSelectorReverts() public {
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](1);
        bytes4[] memory sels = new bytes4[](1);

        sels[0] = VersionFacetV1.version.selector; // not added yet

        cuts[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(0),
            action: IDiamondCutFacet.FacetCutAction.Remove,
            functionSelectors: sels
        });

        vm.prank(owner);
        vm.expectRevert("LibDiamondCut: Can't remove function that doesn't exist");
        IDiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), "");
    }

    /* ------------------------------------------------------------------------
       initializer revert -> whole diamondCut reverts (state rolls back)
    ------------------------------------------------------------------------ */
    function testCut_InitializerRevert_RollsBack() public {
        // First add v1 normally so we can prove no change on rollback later
        VersionFacetV1 v1 = new VersionFacetV1();
        bytes4 versionSel = VersionFacetV1.version.selector;

        {
            IDiamondCutFacet.FacetCut[] memory addCut = new IDiamondCutFacet.FacetCut[](1);
            bytes4[] memory sels = new bytes4[](1);
            sels[0] = versionSel;

            addCut[0] = IDiamondCutFacet.FacetCut({
                facetAddress: address(v1),
                action: IDiamondCutFacet.FacetCutAction.Add,
                functionSelectors: sels
            });

            vm.prank(owner);
            IDiamondCutFacet(address(diamond)).diamondCut(addCut, address(0), "");
            assertEq(VersionFacetV1(address(diamond)).version(), 1);
        }

        // Now attempt a no-op cut but with a reverting initializer
        RevertingInit bad = new RevertingInit();
        IDiamondCutFacet.FacetCut[] memory noops = new IDiamondCutFacet.FacetCut[](0);

        vm.prank(owner);
        vm.expectRevert(RevertingInit__Boom.selector);
        IDiamondCutFacet(address(diamond)).diamondCut(noops, address(bad), abi.encodeCall(RevertingInit.init, ()));

        // prove nothing changed
        assertEq(VersionFacetV1(address(diamond)).version(), 1);
    }

    function testCut_AddDuplicateSelectorReverts() public {
        // loupe.facetAddresses.selector already added in setUp()
        IDiamondCutFacet.FacetCut[] memory cut = new IDiamondCutFacet.FacetCut[](1);
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = IDiamondLoupeFacet.facetAddresses.selector;

        cut[0] = IDiamondCutFacet.FacetCut({
            facetAddress: loupeImpl,
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: sels
        });

        vm.prank(owner);
        vm.expectRevert(bytes("LibDiamondCut: Can't add function that already exists"));
        IDiamondCutFacet(address(diamond)).diamondCut(cut, address(0), "");
    }

    function testCut_ReplaceWithSameFacetReverts() public {
        // selector currently mapped to loupeImpl
        IDiamondCutFacet.FacetCut[] memory cut = new IDiamondCutFacet.FacetCut[](1);
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = IDiamondLoupeFacet.facetAddresses.selector;

        cut[0] = IDiamondCutFacet.FacetCut({
            facetAddress: loupeImpl, // same facet -> must revert
            action: IDiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: sels
        });

        vm.prank(owner);
        vm.expectRevert(bytes("LibDiamondCut: Can't replace function with same function"));
        IDiamondCutFacet(address(diamond)).diamondCut(cut, address(0), "");
    }

    function testCut_RemoveFacetAddressNonZeroReverts() public {
        IDiamondCutFacet.FacetCut[] memory cut = new IDiamondCutFacet.FacetCut[](1);
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = IDiamondLoupeFacet.facetAddresses.selector;

        cut[0] = IDiamondCutFacet.FacetCut({
            facetAddress: loupeImpl, // must be zero -> revert
            action: IDiamondCutFacet.FacetCutAction.Remove,
            functionSelectors: sels
        });

        vm.prank(owner);
        vm.expectRevert(bytes("LibDiamondCut: Remove facet address must be address(0)"));
        IDiamondCutFacet(address(diamond)).diamondCut(cut, address(0), "");
    }

    function testCut_AddFacetWithNoCodeReverts() public {
        // EOA / no code
        address eoa = vm.addr(0xBEEF);
        IDiamondCutFacet.FacetCut[] memory cut = new IDiamondCutFacet.FacetCut[](1);
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = VersionFacetV1.version.selector;

        cut[0] = IDiamondCutFacet.FacetCut({
            facetAddress: eoa,
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: sels
        });

        vm.prank(owner);
        vm.expectRevert(bytes("LibDiamondCut: New facet has no code"));
        IDiamondCutFacet(address(diamond)).diamondCut(cut, address(0), "");
    }

    function testCut_InitAddressHasNoCodeReverts() public {
        address eoa = vm.addr(0xCAFE);
        IDiamondCutFacet.FacetCut[] memory empty = new IDiamondCutFacet.FacetCut[](0);

        vm.prank(owner);
        vm.expectRevert(bytes("LibDiamondCut: _init address has no code"));
        IDiamondCutFacet(address(diamond)).diamondCut(empty, eoa, hex"");
    }

    function testCut_RemoveTriggersSwapWithLastFacet() public {
        // deploy two fresh, code-bearing facets with unique selectors
        SwapFacetA fa = new SwapFacetA();
        SwapFacetB fb = new SwapFacetB();

        // add A (selector: a())
        {
            IDiamondCutFacet.FacetCut[] memory addA = new IDiamondCutFacet.FacetCut[](1);
            bytes4[] memory sa = new bytes4[](1);
            sa[0] = SwapFacetA.a.selector;
            addA[0] = IDiamondCutFacet.FacetCut({
                facetAddress: address(fa),
                action: IDiamondCutFacet.FacetCutAction.Add,
                functionSelectors: sa
            });
            vm.prank(owner);
            IDiamondCutFacet(address(diamond)).diamondCut(addA, address(0), "");
            assertEq(loupe.facetAddress(SwapFacetA.a.selector), address(fa));
        }

        // add B (selector: b())
        {
            IDiamondCutFacet.FacetCut[] memory addB = new IDiamondCutFacet.FacetCut[](1);
            bytes4[] memory sb = new bytes4[](1);
            sb[0] = SwapFacetB.b.selector;
            addB[0] = IDiamondCutFacet.FacetCut({
                facetAddress: address(fb),
                action: IDiamondCutFacet.FacetCutAction.Add,
                functionSelectors: sb
            });
            vm.prank(owner);
            IDiamondCutFacet(address(diamond)).diamondCut(addB, address(0), "");
            assertEq(loupe.facetAddress(SwapFacetB.b.selector), address(fb));
        }

        // now remove A’s only selector; since A isn’t the last facet,
        // LibDiamond will swap the last facet (B) into A’s slot and pop the tail.
        {
            IDiamondCutFacet.FacetCut[] memory rem = new IDiamondCutFacet.FacetCut[](1);
            bytes4[] memory sr = new bytes4[](1);
            sr[0] = SwapFacetA.a.selector;
            rem[0] = IDiamondCutFacet.FacetCut({
                facetAddress: address(0),
                action: IDiamondCutFacet.FacetCutAction.Remove,
                functionSelectors: sr
            });
            vm.prank(owner);
            IDiamondCutFacet(address(diamond)).diamondCut(rem, address(0), "");

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
        IDiamondCutFacet.FacetCut[] memory add = new IDiamondCutFacet.FacetCut[](1);
        bytes4[] memory sels = new bytes4[](2);
        sels[0] = MultiSelFacet.f1.selector; // will remove this one
        sels[1] = MultiSelFacet.f2.selector; // will be swapped into position 0
        add[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(mf),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: sels
        });

        vm.prank(owner);
        IDiamondCutFacet(address(diamond)).diamondCut(add, address(0), "");

        // sanity: both map to mf
        assertEq(loupe.facetAddress(MultiSelFacet.f1.selector), address(mf));
        assertEq(loupe.facetAddress(MultiSelFacet.f2.selector), address(mf));

        // now remove f1 only -> triggers selector-array swap in LibDiamond.removeFunction
        IDiamondCutFacet.FacetCut[] memory rem = new IDiamondCutFacet.FacetCut[](1);
        bytes4[] memory rs = new bytes4[](1);
        rs[0] = MultiSelFacet.f1.selector;
        rem[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(0),
            action: IDiamondCutFacet.FacetCutAction.Remove,
            functionSelectors: rs
        });

        vm.prank(owner);
        IDiamondCutFacet(address(diamond)).diamondCut(rem, address(0), "");

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
}

// helper contracts
contract SwapFacetA {
    function a() external pure returns (uint256) {
        return 1;
    }
}

contract SwapFacetB {
    function b() external pure returns (uint256) {
        return 2;
    }
}

contract MultiSelFacet {
    function f1() external pure returns (uint256) {
        return 1;
    }

    function f2() external pure returns (uint256) {
        return 2;
    }
}
