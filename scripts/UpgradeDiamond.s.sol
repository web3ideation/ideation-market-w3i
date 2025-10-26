// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IDiamondCutFacet} from "../src/interfaces/IDiamondCutFacet.sol";
import {IVersionFacet} from "../src/interfaces/IVersionFacet.sol";
import {VersionFacet} from "../src/facets/VersionFacet.sol";
import {VersionInit} from "../src/upgradeInitializers/VersionInit.sol";

/// @title UpgradeDiamond
/// @notice Reusable Foundry script to perform a diamond upgrade by deploying a new facet and executing a cut.
/// @dev Example adds the `VersionFacet` with two selectors and initializes an `uint256 marketVersion`.
/// Set  vars before running: DIAMOND_ADDRESS, INITIAL_VERSION.
contract UpgradeDiamond is Script {
    /// @dev Address of the target diamond on the current network.
    address public DIAMONDADDRESS = 0x8cE90712463c87a6d62941D67C3507D090Ea9d79;

    /// @dev Initial version to set in the initializer.
    uint256 public initialVersion = 1;

    function run() external {
        vm.startBroadcast();

        // 1) Deploy new facet and initializer
        VersionFacet versionFacet = new VersionFacet();
        console.log("Deployed VersionFacet:", address(versionFacet));
        VersionInit versionInit = new VersionInit();
        console.log("Deployed VersionInit:", address(versionInit));

        // 2) Prepare cut for adding the new facet
        IDiamondCutFacet.FacetCut[] memory cut = new IDiamondCutFacet.FacetCut[](1);
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = IVersionFacet.setMarketVersion.selector;
        selectors[1] = IVersionFacet.getMarketVersion.selector;
        cut[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(versionFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: selectors
        });

        // 3) Execute the diamond cut with initializer call (atomic)
        IDiamondCutFacet(DIAMONDADDRESS).diamondCut(
            cut, address(versionInit), abi.encodeCall(VersionInit.init, (initialVersion))
        );
        console.log("Diamond upgraded. VersionFacet added.");

        // Optional post-check: read value back
        uint256 version = IVersionFacet(DIAMONDADDRESS).getMarketVersion();
        console.log("marketVersion after upgrade:", version);

        vm.stopBroadcast();
    }
}
