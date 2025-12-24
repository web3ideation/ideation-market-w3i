// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import "forge-std/console.sol";

/// @title VersionFacetTest
/// @notice Tests for the diamond versioning functionality in full marketplace context
contract VersionFacetTest is MarketTestBase {
    address user;

    function setUp() public override {
        super.setUp();

        user = vm.addr(0x5678);

        // Set initial version
        vm.prank(owner);
        bytes32 initialId = keccak256("initial-test-id");
        versionFacet.setVersion("1.0.0", initialId);
    }

    // ============================================
    // Diamond Routing Verification
    // ============================================

    /// @notice Verify version-related selectors route correctly through diamond
    function testVersionSelectorsRoutedCorrectly() public view {
        // Verify setVersion() routes to VersionFacet
        address setVersionAddr = loupe.facetAddress(VersionFacet.setVersion.selector);
        assertEq(setVersionAddr, versionImpl, "setVersion() must route to VersionFacet implementation");

        // Verify version getter selectors route to GetterFacet
        address getVersionAddr = loupe.facetAddress(GetterFacet.getVersion.selector);
        assertEq(getVersionAddr, getterImpl, "getVersion() must route to GetterFacet implementation");

        address getPrevVersionAddr = loupe.facetAddress(GetterFacet.getPreviousVersion.selector);
        assertEq(getPrevVersionAddr, getterImpl, "getPreviousVersion() must route to GetterFacet implementation");

        address getVersionStringAddr = loupe.facetAddress(GetterFacet.getVersionString.selector);
        assertEq(getVersionStringAddr, getterImpl, "getVersionString() must route to GetterFacet implementation");

        address getImplIdAddr = loupe.facetAddress(GetterFacet.getImplementationId.selector);
        assertEq(getImplIdAddr, getterImpl, "getImplementationId() must route to GetterFacet implementation");
    }

    // ============================================
    // Version Functionality Tests
    // ============================================

    function testInitialVersion() public view {
        (string memory versionStr, bytes32 implId, uint256 timestamp) = getter.getVersion();

        assertEq(versionStr, "1.0.0", "Initial version should be 1.0.0");
        assertEq(implId, keccak256("initial-test-id"), "Implementation ID should match");
        assertGt(timestamp, 0, "Timestamp should be set");
    }

    function testGetVersionString() public view {
        assertEq(getter.getVersionString(), "1.0.0", "Version string should be 1.0.0");
    }

    function testGetImplementationId() public view {
        assertEq(getter.getImplementationId(), keccak256("initial-test-id"), "Implementation ID should match");
    }

    function testSetVersionAsOwner() public {
        vm.prank(owner);

        bytes32 newId = keccak256("new-version-id");

        // Set new version
        versionFacet.setVersion("1.1.0", newId);

        // Check current version
        (string memory versionStr, bytes32 implId, uint256 timestamp) = getter.getVersion();
        assertEq(versionStr, "1.1.0", "Version should be updated to 1.1.0");
        assertEq(implId, newId, "Implementation ID should be updated");
        assertGt(timestamp, 0, "Current version timestamp should be set");

        // Check previous version
        (string memory prevVersion, bytes32 prevId, uint256 prevTimestamp) = getter.getPreviousVersion();
        assertEq(prevVersion, "1.0.0", "Previous version should be 1.0.0");
        assertEq(prevId, keccak256("initial-test-id"), "Previous ID should match initial");
        assertGt(prevTimestamp, 0, "Previous version timestamp should be set");
        assertGe(timestamp, prevTimestamp, "Current timestamp should be >= previous timestamp");
    }

    function testSetVersionRevertsForNonOwner() public {
        vm.prank(user);

        bytes32 newId = keccak256("new-version-id");

        vm.expectRevert("LibDiamond: Must be contract owner");
        versionFacet.setVersion("1.1.0", newId);
    }

    function testVersionUpdatedEvent() public {
        vm.prank(owner);

        bytes32 newId = keccak256("new-version-id");

        vm.expectEmit(true, true, true, true);
        emit VersionFacet.VersionUpdated("1.1.0", newId, block.timestamp);

        versionFacet.setVersion("1.1.0", newId);
    }

    function testMultipleVersionUpdates() public {
        vm.startPrank(owner);

        // Update to 1.1.0
        bytes32 id110 = keccak256("1.1.0");
        versionFacet.setVersion("1.1.0", id110);

        // Update to 1.2.0
        bytes32 id120 = keccak256("1.2.0");
        versionFacet.setVersion("1.2.0", id120);

        // Current should be 1.2.0
        assertEq(getter.getVersionString(), "1.2.0", "Current version should be 1.2.0");

        // Previous should be 1.1.0 (not 1.0.0, as we only keep the last one)
        (string memory prevVersion, bytes32 prevId,) = getter.getPreviousVersion();
        assertEq(prevVersion, "1.1.0", "Previous version should be 1.1.0");
        assertEq(prevId, id110, "Previous ID should match 1.1.0");

        vm.stopPrank();
    }

    function testComputeImplementationIdDeterministic() public view {
        // Get the facets from the diamond
        IDiamondLoupeFacet.Facet[] memory facets = loupe.facets();

        // Compute ID twice with same data - should be identical
        bytes32 id1 = computeImplementationId(address(diamond), facets);
        bytes32 id2 = computeImplementationId(address(diamond), facets);

        assertEq(id1, id2, "Implementation ID should be deterministic");
    }

    /// @notice Test that version persists across marketplace operations
    function testVersionPersistsThroughMarketplaceOps() public {
        // Verify initial version
        assertEq(getter.getVersionString(), "1.0.0");

        // Perform marketplace operations
        _whitelistDefaultMocks();
        vm.startPrank(seller);
        erc721.approve(address(diamond), 1);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        // Verify version unchanged
        assertEq(getter.getVersionString(), "1.0.0");

        // Get the listing ID and purchase
        uint128 listingId = getter.getNextListingId() - 1;
        vm.prank(buyer);
        vm.deal(buyer, 1 ether);
        market.purchaseListing{value: 1 ether}(listingId, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        // Verify version still unchanged
        assertEq(getter.getVersionString(), "1.0.0");
    }

    /// @notice Test version update in context of diamond upgrade
    function testVersionUpdateWithDiamondUpgrade() public {
        vm.startPrank(owner);

        // Simulate upgrade by adding a dummy facet
        DummyUpgradeFacetV2 dummyFacet = new DummyUpgradeFacetV2();
        bytes4[] memory dummySelectors = new bytes4[](1);
        dummySelectors[0] = DummyUpgradeFacetV2.dummyFunction.selector;

        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](1);
        cuts[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(dummyFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: dummySelectors
        });

        IDiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), "");

        // Now update version to reflect the upgrade
        bytes32 newId = computeImplementationId(address(diamond), loupe.facets());
        versionFacet.setVersion("1.1.0", newId);

        // Verify new version is set
        assertEq(getter.getVersionString(), "1.1.0");
        assertEq(getter.getImplementationId(), newId);

        // Verify previous version is preserved
        (string memory prevVersion, bytes32 prevId, uint256 prevTimestamp) = getter.getPreviousVersion();
        assertEq(prevVersion, "1.0.0", "Previous version should be 1.0.0");
        assertEq(prevId, keccak256("initial-test-id"), "Previous ID should match initial");
        assertGt(prevTimestamp, 0, "Previous version timestamp should be set");

        vm.stopPrank();
    }
}
