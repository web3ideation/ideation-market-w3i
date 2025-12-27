// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IDiamondCutFacet} from "../src/interfaces/IDiamondCutFacet.sol";
import {IDiamondLoupeFacet} from "../src/interfaces/IDiamondLoupeFacet.sol";
import {IERC173} from "../src/interfaces/IERC173.sol";
import {VersionFacet} from "../src/facets/VersionFacet.sol";
import {GetterFacet} from "../src/facets/GetterFacet.sol";
import {IdeationMarketFacet} from "../src/facets/IdeationMarketFacet.sol";

/// @title UpgradeDiamond
/// @notice Template script for performing diamond upgrades with automatic versioning.
/// @dev This is a reusable template. Copy and modify the `performUpgrade()` selector list for your specific upgrade.
///
/// Required environment variables:
/// - VERSION_STRING: New version string (e.g., "1.1.0", "2.0.0")
///
/// Optional environment variables:
/// - DEV_PRIVATE_KEY: EOA key used to deploy the new facet.
///   - For direct upgrades (EOA-owner diamonds), this key must also be the diamond `owner()`.
///   - For multisig-owned diamonds, this key can be any funded dev EOA.
/// - PREPARE_MULTISIG: If "true", deploys the new facet and prints Safe-ready `diamondCut` calldata.
/// - PRINT_SETVERSION: If "true", prints Safe-ready `setVersion(VERSION_STRING, implementationId)` calldata.
///
/// Operational gotchas:
/// - PREPARE_MULTISIG requires `--broadcast` to produce a real on-chain facet address. Without broadcast the
///   deployment is only simulated and the printed calldata will not work in the Safe.
/// - PRINT_SETVERSION must be run AFTER the multisig executed `diamondCut`, otherwise the computed
///   `implementationId` will correspond to the pre-upgrade diamond state.
///
/// Commands (3 modes):
/// 1) Direct upgrade (diamond owner is an EOA):
///    VERSION_STRING="1.0.1" DEV_PRIVATE_KEY=$DEV_PRIVATE_KEY \
///      forge script script/UpgradeDiamond.s.sol:UpgradeDiamond \
///      --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $DEV_PRIVATE_KEY -vvvv
///
/// 2) Multisig step 1 (deploy facet + print `diamondCut` calldata for the Safe):
///    VERSION_STRING="1.0.1" PREPARE_MULTISIG=true DEV_PRIVATE_KEY=$DEV_PRIVATE_KEY \
///      forge script script/UpgradeDiamond.s.sol:UpgradeDiamond \
///      --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $DEV_PRIVATE_KEY -vvvv
///
/// 3) Multisig step 2 (print `setVersion` calldata for the Safe; no broadcast):
///    VERSION_STRING="1.0.1" PRINT_SETVERSION=true \
///      forge script script/UpgradeDiamond.s.sol:UpgradeDiamond \
///      --rpc-url $SEPOLIA_RPC_URL -vvvv
contract UpgradeDiamond is Script {
    // Sepolia deployment (EIP-2535 diamond)
    address internal constant SEPOLIA_DIAMOND_ADDRESS = 0xF422A7779D2feB884CcC1773b88d98494A946604;

    address public diamondAddress;
    string public versionString;

    function run() external {
        bool prepareMultisig = vm.envOr("PREPARE_MULTISIG", false);
        bool printSetVersion = vm.envOr("PRINT_SETVERSION", false);

        require(
            !(prepareMultisig && printSetVersion),
            "UpgradeDiamond: PREPARE_MULTISIG and PRINT_SETVERSION are mutually exclusive"
        );

        // Load configuration
        diamondAddress = SEPOLIA_DIAMOND_ADDRESS;
        versionString = vm.envString("VERSION_STRING");

        address diamondOwner = IERC173(diamondAddress).owner();
        console.log("Diamond owner:", diamondOwner);

        if (printSetVersion) {
            console.log("Printing multisig calldata for setVersion (no broadcast)");
            console.log("Diamond:", diamondAddress);
            console.log("Target version:", versionString);
            console.log("Chain ID:", block.chainid);

            console.log("Diamond owner:", diamondOwner);

            printSetVersionCalldata();
            return;
        }

        // For PREPARE_MULTISIG and the direct-upgrade path we need a key to deploy the new facet.
        uint256 upgraderPrivateKey = vm.envUint("DEV_PRIVATE_KEY");
        address upgrader = vm.addr(upgraderPrivateKey);

        // Fail fast: only the diamond owner can execute the cut in the direct-upgrade path.
        // (In PREPARE_MULTISIG mode we intentionally allow a non-owner to deploy the facet and print calldata.)
        if (!prepareMultisig) {
            require(diamondOwner == upgrader, "UpgradeDiamond: DEV_PRIVATE_KEY is not the diamond owner");
        }

        vm.startBroadcast(upgraderPrivateKey);

        console.log("Upgrading diamond at:", diamondAddress);
        console.log("Target version:", versionString);
        console.log("Chain ID:", block.chainid);
        console.log("Upgrader:", upgrader);

        if (prepareMultisig) {
            console.log(
                "\nPREPARE_MULTISIG=true: deploying facet and printing multisig calldata (no on-chain cut performed by this script)"
            );
            require(diamondOwner != address(0), "UpgradeDiamond: diamond owner is zero address");
            performUpgradePrepareMultisig();
            vm.stopBroadcast();
            console.log("\n=== Prepare Complete ===");
            return;
        }

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

    function printSetVersionCalldata() internal view {
        bytes32 implementationId = computeImplementationId(diamondAddress);
        bytes memory setVersionCalldata =
            abi.encodeWithSelector(VersionFacet.setVersion.selector, versionString, implementationId);

        console.log("\n=== Multisig Transaction ===");
        console.log("To (diamond):", diamondAddress);
        console.log("Value:", uint256(0));
        console.log("Data (setVersion):");
        console.logBytes(setVersionCalldata);
        console.log("\nComputed implementationId:");
        console.logBytes32(implementationId);
        console.log(
            "\nNote: run this AFTER the multisig has executed diamondCut, otherwise the implementationId will be for the pre-upgrade state."
        );
    }

    /// @notice Performs the actual upgrade by deploying facets and executing the diamond cut.
    /// @dev Upgrades the core marketplace logic by replacing the selectors that were installed for
    /// `IdeationMarketFacet` at deployment time.
    function performUpgrade() internal {
        // Deploy new facet
        IdeationMarketFacet ideationMarketFacet = new IdeationMarketFacet();
        console.log("Deployed ideationMarketFacet contract at address:", address(ideationMarketFacet));

        // Selectors to replace (must match deployment-time selector list)
        bytes4[] memory marketSelectors = new bytes4[](6);
        marketSelectors[0] = IdeationMarketFacet.createListing.selector;
        marketSelectors[1] = IdeationMarketFacet.purchaseListing.selector;
        marketSelectors[2] = IdeationMarketFacet.cancelListing.selector;
        marketSelectors[3] = IdeationMarketFacet.updateListing.selector;
        marketSelectors[4] = IdeationMarketFacet.setInnovationFee.selector;
        marketSelectors[5] = IdeationMarketFacet.cleanListing.selector;

        // Preflight: ensure the selectors exist on the target diamond (fail fast)
        IDiamondLoupeFacet loupe = IDiamondLoupeFacet(diamondAddress);
        for (uint256 i = 0; i < marketSelectors.length; i++) {
            bytes4 selector = marketSelectors[i];
            address currentFacet = loupe.facetAddress(selector);
            console.log("Current facet for selector:");
            console.logBytes4(selector);
            console.log(currentFacet);
            require(currentFacet != address(0), "UpgradeDiamond: selector not found on diamond");
        }

        // Prepare the cut
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](1);
        cuts[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(ideationMarketFacet),
            action: IDiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: marketSelectors
        });

        // Execute
        IDiamondCutFacet(diamondAddress).diamondCut(cuts, address(0), "");
        console.log("Diamond cut executed (IdeationMarketFacet selectors replaced)");

        // Post-check: ensure routing updated
        for (uint256 i = 0; i < marketSelectors.length; i++) {
            bytes4 selector = marketSelectors[i];
            address routedFacet = loupe.facetAddress(selector);
            require(routedFacet == address(ideationMarketFacet), "UpgradeDiamond: selector not routed to new facet");
        }
    }

    /// @notice Deploys the new facet and prints the calldata for a multisig owner to execute.
    /// @dev This intentionally does not call `diamondCut` or `setVersion`.
    function performUpgradePrepareMultisig() internal {
        // Deploy new facet
        IdeationMarketFacet ideationMarketFacet = new IdeationMarketFacet();
        console.log("Deployed ideationMarketFacet contract at address:", address(ideationMarketFacet));

        bytes4[] memory marketSelectors = new bytes4[](6);
        marketSelectors[0] = IdeationMarketFacet.createListing.selector;
        marketSelectors[1] = IdeationMarketFacet.purchaseListing.selector;
        marketSelectors[2] = IdeationMarketFacet.cancelListing.selector;
        marketSelectors[3] = IdeationMarketFacet.updateListing.selector;
        marketSelectors[4] = IdeationMarketFacet.setInnovationFee.selector;
        marketSelectors[5] = IdeationMarketFacet.cleanListing.selector;

        // Preflight: ensure selectors exist on diamond
        IDiamondLoupeFacet loupe = IDiamondLoupeFacet(diamondAddress);
        for (uint256 i = 0; i < marketSelectors.length; i++) {
            bytes4 selector = marketSelectors[i];
            address currentFacet = loupe.facetAddress(selector);
            console.log("Current facet for selector:");
            console.logBytes4(selector);
            console.log(currentFacet);
            require(currentFacet != address(0), "UpgradeDiamond: selector not found on diamond");
        }

        // Build the cut and encode calldata
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](1);
        cuts[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(ideationMarketFacet),
            action: IDiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: marketSelectors
        });

        bytes memory diamondCutCalldata =
            abi.encodeWithSelector(IDiamondCutFacet.diamondCut.selector, cuts, address(0), bytes(""));

        console.log("\n=== Multisig Transaction ===");
        console.log("To (diamond):", diamondAddress);
        console.log("Value:", uint256(0));
        console.log("Data (diamondCut):");
        console.logBytes(diamondCutCalldata);

        console.log("\nNote: setVersion must be executed separately after the cut.");
        console.log(
            "After multisig executes diamondCut, run this script again WITHOUT PREPARE_MULTISIG to compute implementationId and setVersion (or add a separate multisig tx calling VersionFacet.setVersion)."
        );
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
