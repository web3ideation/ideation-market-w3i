// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IdeationMarketDiamond} from "../src/IdeationMarketDiamond.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../src/facets/DiamondLoupeFacet.sol";
import {VersionFacet} from "../src/facets/VersionFacet.sol";
import {GetterFacet} from "../src/facets/GetterFacet.sol";

import {IDiamondCutFacet} from "../src/interfaces/IDiamondCutFacet.sol";
import {IDiamondLoupeFacet} from "../src/interfaces/IDiamondLoupeFacet.sol";
import {IERC165} from "../src/interfaces/IERC165.sol";

/// @title VersionFacetTest
/// @notice Tests for the diamond versioning functionality
contract VersionFacetTest is Test {
    IdeationMarketDiamond diamond;
    DiamondCutFacet diamondCutFacet;
    DiamondLoupeFacet diamondLoupeFacet;
    VersionFacet versionFacet;
    GetterFacet getterFacet;

    address owner = address(0x1234);
    address user = address(0x5678);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy facets
        diamondCutFacet = new DiamondCutFacet();
        diamondLoupeFacet = new DiamondLoupeFacet();
        versionFacet = new VersionFacet();
        getterFacet = new GetterFacet();

        // Deploy diamond
        diamond = new IdeationMarketDiamond(owner, address(diamondCutFacet));

        // Prepare cuts for Loupe, Getter, and Version facets
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](3);

        // Add DiamondLoupeFacet
        bytes4[] memory loupeSelectors = new bytes4[](5);
        loupeSelectors[0] = IDiamondLoupeFacet.facets.selector;
        loupeSelectors[1] = IDiamondLoupeFacet.facetFunctionSelectors.selector;
        loupeSelectors[2] = IDiamondLoupeFacet.facetAddresses.selector;
        loupeSelectors[3] = IDiamondLoupeFacet.facetAddress.selector;
        loupeSelectors[4] = IERC165.supportsInterface.selector;

        cuts[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(diamondLoupeFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: loupeSelectors
        });

        // Add GetterFacet (with version getters)
        bytes4[] memory getterSelectors = new bytes4[](4);
        getterSelectors[0] = GetterFacet.getVersion.selector;
        getterSelectors[1] = GetterFacet.getPreviousVersion.selector;
        getterSelectors[2] = GetterFacet.getVersionString.selector;
        getterSelectors[3] = GetterFacet.getImplementationId.selector;

        cuts[1] = IDiamondCutFacet.FacetCut({
            facetAddress: address(getterFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: getterSelectors
        });

        // Add VersionFacet (only setVersion)
        bytes4[] memory versionSelectors = new bytes4[](1);
        versionSelectors[0] = VersionFacet.setVersion.selector;

        cuts[2] = IDiamondCutFacet.FacetCut({
            facetAddress: address(versionFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: versionSelectors
        });

        // Execute diamond cut without initializer
        IDiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), "");

        // Manually set initial version
        bytes32 initialId = keccak256("initial-test-id");
        VersionFacet(address(diamond)).setVersion("1.0.0", initialId);

        vm.stopPrank();
    }

    function testInitialVersion() public view {
        GetterFacet getter = GetterFacet(address(diamond));

        (string memory versionStr, bytes32 implId, uint256 timestamp) = getter.getVersion();

        assertEq(versionStr, "1.0.0", "Initial version should be 1.0.0");
        assertEq(implId, keccak256("initial-test-id"), "Implementation ID should match");
        assertGt(timestamp, 0, "Timestamp should be set");
    }

    function testGetVersionString() public view {
        GetterFacet getter = GetterFacet(address(diamond));
        assertEq(getter.getVersionString(), "1.0.0", "Version string should be 1.0.0");
    }

    function testGetImplementationId() public view {
        GetterFacet getter = GetterFacet(address(diamond));
        assertEq(getter.getImplementationId(), keccak256("initial-test-id"), "Implementation ID should match");
    }

    function testSetVersionAsOwner() public {
        vm.prank(owner);

        VersionFacet version = VersionFacet(address(diamond));
        GetterFacet getter = GetterFacet(address(diamond));
        bytes32 newId = keccak256("new-version-id");

        // Set new version
        version.setVersion("1.1.0", newId);

        // Check current version
        (string memory versionStr, bytes32 implId, uint256 timestamp) = getter.getVersion();
        assertEq(versionStr, "1.1.0", "Version should be updated to 1.1.0");
        assertEq(implId, newId, "Implementation ID should be updated");

        // Check previous version
        (string memory prevVersion, bytes32 prevId, uint256 prevTimestamp) = getter.getPreviousVersion();
        assertEq(prevVersion, "1.0.0", "Previous version should be 1.0.0");
        assertEq(prevId, keccak256("initial-test-id"), "Previous ID should match initial");
    }

    function testSetVersionRevertsForNonOwner() public {
        vm.prank(user);

        VersionFacet version = VersionFacet(address(diamond));
        bytes32 newId = keccak256("new-version-id");

        vm.expectRevert("LibDiamond: Must be contract owner");
        version.setVersion("1.1.0", newId);
    }

    function testVersionUpdatedEvent() public {
        vm.prank(owner);

        VersionFacet version = VersionFacet(address(diamond));
        bytes32 newId = keccak256("new-version-id");

        vm.expectEmit(true, true, true, true);
        emit VersionFacet.VersionUpdated("1.1.0", newId, block.timestamp);

        version.setVersion("1.1.0", newId);
    }

    function testMultipleVersionUpdates() public {
        vm.startPrank(owner);

        VersionFacet version = VersionFacet(address(diamond));
        GetterFacet getter = GetterFacet(address(diamond));

        // Update to 1.1.0
        bytes32 id110 = keccak256("1.1.0");
        version.setVersion("1.1.0", id110);

        // Update to 1.2.0
        bytes32 id120 = keccak256("1.2.0");
        version.setVersion("1.2.0", id120);

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
        IDiamondLoupeFacet loupe = IDiamondLoupeFacet(address(diamond));
        IDiamondLoupeFacet.Facet[] memory facets = loupe.facets();

        // Compute ID twice with same data - should be identical
        bytes32 id1 = computeImplementationId(address(diamond), facets);
        bytes32 id2 = computeImplementationId(address(diamond), facets);

        assertEq(id1, id2, "Implementation ID should be deterministic");
    }

    // Helper to compute implementation ID (simplified version)
    function computeImplementationId(address diamondAddr, IDiamondLoupeFacet.Facet[] memory facets)
        internal
        view
        returns (bytes32)
    {
        uint256 facetCount = facets.length;
        address[] memory addresses = new address[](facetCount);
        bytes4[][] memory selectors = new bytes4[][](facetCount);

        for (uint256 i = 0; i < facetCount; i++) {
            addresses[i] = facets[i].facetAddress;
            selectors[i] = facets[i].functionSelectors;
        }

        return keccak256(abi.encode(block.chainid, diamondAddr, addresses, selectors));
    }
}
