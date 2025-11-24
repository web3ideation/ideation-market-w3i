// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IDiamondCutFacet} from "../src/interfaces/IDiamondCutFacet.sol";
import {IDiamondLoupeFacet} from "../src/interfaces/IDiamondLoupeFacet.sol";
import {VersionFacet} from "../src/facets/VersionFacet.sol";
import {GetterFacet} from "../src/facets/GetterFacet.sol";

/// @title UpgradeDiamond
/// @notice Template script for performing diamond upgrades with automatic versioning.
/// @dev This is a reusable template. Copy and modify the performUpgrade() function for your specific upgrade.
/// Environment variables required:
/// - DIAMOND_ADDRESS: Address of the diamond to upgrade
/// - VERSION_STRING: New version string (e.g., "1.1.0", "2.0.0")
///
/// Example usage:
/// DIAMOND_ADDRESS=0x... VERSION_STRING="1.1.0" forge script scripts/UpgradeDiamond.s.sol:UpgradeDiamond --rpc-url <URL> --broadcast
contract UpgradeDiamond is Script {
    address public diamondAddress;
    string public versionString;

    function run() external {
        // Load configuration from environment
        diamondAddress = vm.envAddress("DIAMOND_ADDRESS");
        versionString = vm.envString("VERSION_STRING");

        console.log("Upgrading diamond at:", diamondAddress);
        console.log("Target version:", versionString);

        vm.startBroadcast();

        // Perform the upgrade (deploy facets and execute diamond cut)
        performUpgrade();

        // Automatically compute and set the new version
        console.log("\nSetting version...");
        bytes32 implementationId = computeImplementationId(diamondAddress);
        VersionFacet(diamondAddress).setVersion(versionString, implementationId);

        console.log("\n=== Version Updated ===");
        console.log("Version:", versionString);
        console.log("Implementation ID:");
        console.logBytes32(implementationId);

        // Show previous version for reference
        (string memory prevVersion, bytes32 prevId,) = GetterFacet(diamondAddress).getPreviousVersion();
        if (bytes(prevVersion).length > 0) {
            console.log("\nPrevious version:", prevVersion);
            console.log("Previous ID:");
            console.logBytes32(prevId);
        }

        vm.stopBroadcast();

        console.log("\n=== Upgrade Complete ===");
    }

    /// @notice Performs the actual upgrade by deploying facets and executing the diamond cut.
    /// @dev Override this function with your specific upgrade logic.
    /// This is a template - uncomment and modify for your actual upgrade.
    function performUpgrade() internal {
        // EXAMPLE: Deploy a new facet
        // YourNewFacet newFacet = new YourNewFacet();
        // console.log("Deployed YourNewFacet:", address(newFacet));

        // EXAMPLE: Prepare the diamond cut
        // IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](1);
        // bytes4[] memory selectors = new bytes4[](2);
        // selectors[0] = YourNewFacet.someFunction.selector;
        // selectors[1] = YourNewFacet.anotherFunction.selector;
        //
        // cuts[0] = IDiamondCutFacet.FacetCut({
        //     facetAddress: address(newFacet),
        //     action: IDiamondCutFacet.FacetCutAction.Add, // or Replace, Remove
        //     functionSelectors: selectors
        // });

        // EXAMPLE: Execute the diamond cut (with optional initializer)
        // IDiamondCutFacet(diamondAddress).diamondCut(cuts, address(0), "");
        // console.log("Diamond cut executed");

        // TODO: Replace this with your actual upgrade logic
        console.log("WARNING: This is a template. Implement performUpgrade() with your upgrade logic.");
    }

    /// @notice Computes the implementationId for a diamond.
    function computeImplementationId(address diamond) internal view returns (bytes32) {
        IDiamondLoupeFacet loupe = IDiamondLoupeFacet(diamond);
        IDiamondLoupeFacet.Facet[] memory facets = loupe.facets();
        uint256 facetCount = facets.length;

        address[] memory facetAddresses = new address[](facetCount);
        bytes4[][] memory selectorsPerFacet = new bytes4[][](facetCount);

        for (uint256 i = 0; i < facetCount; i++) {
            facetAddresses[i] = facets[i].facetAddress;
            selectorsPerFacet[i] = facets[i].functionSelectors;
        }

        // Sort facets by address
        for (uint256 i = 0; i < facetCount; i++) {
            for (uint256 j = i + 1; j < facetCount; j++) {
                if (facetAddresses[i] > facetAddresses[j]) {
                    (facetAddresses[i], facetAddresses[j]) = (facetAddresses[j], facetAddresses[i]);
                    (selectorsPerFacet[i], selectorsPerFacet[j]) = (selectorsPerFacet[j], selectorsPerFacet[i]);
                }
            }
        }

        // Sort selectors within each facet
        for (uint256 i = 0; i < facetCount; i++) {
            selectorsPerFacet[i] = sortSelectors(selectorsPerFacet[i]);
        }

        return keccak256(abi.encode(block.chainid, diamond, facetAddresses, selectorsPerFacet));
    }

    /// @notice Sorts function selectors in ascending order.
    function sortSelectors(bytes4[] memory selectors) internal pure returns (bytes4[] memory) {
        uint256 length = selectors.length;
        bytes4[] memory sorted = new bytes4[](length);
        for (uint256 i = 0; i < length; i++) {
            sorted[i] = selectors[i];
        }

        for (uint256 i = 0; i < length; i++) {
            for (uint256 j = i + 1; j < length; j++) {
                if (uint32(sorted[i]) > uint32(sorted[j])) {
                    (sorted[i], sorted[j]) = (sorted[j], sorted[i]);
                }
            }
        }
        return sorted;
    }
}
