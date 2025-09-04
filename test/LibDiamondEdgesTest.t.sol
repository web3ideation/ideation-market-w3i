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
}
