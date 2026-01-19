// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IDiamondLoupeFacet} from "../src/interfaces/IDiamondLoupeFacet.sol";
import {IDiamondUpgradeFacet} from "../src/interfaces/IDiamondUpgradeFacet.sol";
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
/// - PREPARE_MULTISIG: If "true", deploys the new facet and prints Safe-ready `upgradeDiamond` calldata.
/// - PRINT_SETVERSION: If "true", prints Safe-ready `setVersion(VERSION_STRING, implementationId)` calldata.
///
/// Operational gotchas:
/// - PREPARE_MULTISIG requires `--broadcast` to produce a real on-chain facet address. Without broadcast the
///   deployment is only simulated and the printed calldata will not work in the Safe.
/// - PRINT_SETVERSION must be run AFTER the multisig executed `upgradeDiamond`, otherwise the computed
///   `implementationId` will correspond to the pre-upgrade diamond state.
///
/// Commands (3 modes):
/// 1) Direct upgrade (diamond owner is an EOA):
///    VERSION_STRING="1.0.1" DEV_PRIVATE_KEY=$DEV_PRIVATE_KEY \
///      forge script script/UpgradeDiamond.s.sol:UpgradeDiamond \
///      --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $DEV_PRIVATE_KEY -vvvv
///
/// 2) Multisig step 1 (deploy facet + print `upgradeDiamond` calldata for the Safe):
///    VERSION_STRING="1.0.1" PREPARE_MULTISIG=true DEV_PRIVATE_KEY=$DEV_PRIVATE_KEY \
///      forge script script/UpgradeDiamond.s.sol:UpgradeDiamond \
///      --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $DEV_PRIVATE_KEY -vvvv
///
/// 3) Multisig step 2 (print `setVersion` calldata for the Safe; no broadcast):
///    VERSION_STRING="1.0.1" PRINT_SETVERSION=true \
///      forge script script/UpgradeDiamond.s.sol:UpgradeDiamond \
///      --rpc-url $SEPOLIA_RPC_URL -vvvv
contract UpgradeDiamond is Script {
    // Sepolia deployment
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
            "\nNote: run this AFTER the multisig has executed upgradeDiamond, otherwise the implementationId will be for the pre-upgrade state."
        );
    }

    /// @notice Performs the actual upgrade by deploying facets and executing the diamond cut.
    /// @dev Upgrades the core marketplace logic by replacing the selectors that were installed for
    /// `IdeationMarketFacet` and `GetterFacet` at deployment time.
    function performUpgrade() internal {
        // Deploy new facet
        IdeationMarketFacet ideationMarketFacet = new IdeationMarketFacet();
        console.log("Deployed ideationMarketFacet contract at address:", address(ideationMarketFacet));

        GetterFacet getterFacet = new GetterFacet();
        console.log("Deployed getterFacet contract at address:", address(getterFacet));

        // Selectors to replace (must match deployment-time selector list)
        bytes4[] memory marketSelectors = new bytes4[](6);
        marketSelectors[0] = IdeationMarketFacet.createListing.selector;
        marketSelectors[1] = IdeationMarketFacet.purchaseListing.selector;
        marketSelectors[2] = IdeationMarketFacet.cancelListing.selector;
        marketSelectors[3] = IdeationMarketFacet.updateListing.selector;
        marketSelectors[4] = IdeationMarketFacet.setInnovationFee.selector;
        marketSelectors[5] = IdeationMarketFacet.cleanListing.selector;

        bytes4[] memory getterSelectors = new bytes4[](18);
        getterSelectors[0] = GetterFacet.getActiveListingIdByERC721.selector;
        getterSelectors[1] = GetterFacet.getListingByListingId.selector;
        getterSelectors[2] = GetterFacet.getBalance.selector;
        getterSelectors[3] = GetterFacet.getInnovationFee.selector;
        getterSelectors[4] = GetterFacet.getNextListingId.selector;
        getterSelectors[5] = GetterFacet.isCollectionWhitelisted.selector;
        getterSelectors[6] = GetterFacet.getWhitelistedCollections.selector;
        getterSelectors[7] = GetterFacet.getContractOwner.selector;
        getterSelectors[8] = GetterFacet.isBuyerWhitelisted.selector;
        getterSelectors[9] = GetterFacet.getBuyerWhitelistMaxBatchSize.selector;
        getterSelectors[10] = GetterFacet.getPendingOwner.selector;
        getterSelectors[11] = GetterFacet.isCurrencyAllowed.selector;
        getterSelectors[12] = GetterFacet.getAllowedCurrencies.selector;
        getterSelectors[13] = GetterFacet.getVersion.selector;
        getterSelectors[14] = GetterFacet.getPreviousVersion.selector;
        getterSelectors[15] = GetterFacet.getVersionString.selector;
        getterSelectors[16] = GetterFacet.getImplementationId.selector;
        getterSelectors[17] = GetterFacet.isPaused.selector;

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

        for (uint256 i = 0; i < getterSelectors.length; i++) {
            bytes4 selector = getterSelectors[i];
            address currentFacet = loupe.facetAddress(selector);
            console.log("Current facet for selector:");
            console.logBytes4(selector);
            console.log(currentFacet);
            require(currentFacet != address(0), "UpgradeDiamond: selector not found on diamond");
        }

        // Prepare ERC-8109 replace batch
        IDiamondUpgradeFacet.FacetFunctions[] memory replaceFns = new IDiamondUpgradeFacet.FacetFunctions[](2);
        replaceFns[0] =
            IDiamondUpgradeFacet.FacetFunctions({facet: address(ideationMarketFacet), selectors: marketSelectors});
        replaceFns[1] = IDiamondUpgradeFacet.FacetFunctions({facet: address(getterFacet), selectors: getterSelectors});

        // Execute
        IDiamondUpgradeFacet(diamondAddress).upgradeDiamond(
            new IDiamondUpgradeFacet.FacetFunctions[](0),
            replaceFns,
            new bytes4[](0),
            address(0),
            bytes(""),
            bytes32(0),
            bytes("")
        );
        console.log(
            "Diamond upgrade executed via upgradeDiamond (IdeationMarketFacet and GetterFacet selectors updated)"
        );

        // Post-check: ensure routing updated
        for (uint256 i = 0; i < marketSelectors.length; i++) {
            bytes4 selector = marketSelectors[i];
            address routedFacet = loupe.facetAddress(selector);
            require(routedFacet == address(ideationMarketFacet), "UpgradeDiamond: selector not routed to new facet");
        }
    }

    /// @notice Deploys the new facet and prints the calldata for a multisig owner to execute.
    /// @dev This intentionally does not call `upgradeDiamond` or `setVersion`.
    function performUpgradePrepareMultisig() internal {
        // Deploy new facet
        IdeationMarketFacet ideationMarketFacet = new IdeationMarketFacet();
        console.log("Deployed ideationMarketFacet contract at address:", address(ideationMarketFacet));

        GetterFacet getterFacet = new GetterFacet();
        console.log("Deployed getterFacet contract at address:", address(getterFacet));

        bytes4[] memory marketSelectors = new bytes4[](6);
        marketSelectors[0] = IdeationMarketFacet.createListing.selector;
        marketSelectors[1] = IdeationMarketFacet.purchaseListing.selector;
        marketSelectors[2] = IdeationMarketFacet.cancelListing.selector;
        marketSelectors[3] = IdeationMarketFacet.updateListing.selector;
        marketSelectors[4] = IdeationMarketFacet.setInnovationFee.selector;
        marketSelectors[5] = IdeationMarketFacet.cleanListing.selector;

        bytes4[] memory getterSelectors = new bytes4[](18);
        getterSelectors[0] = GetterFacet.getActiveListingIdByERC721.selector;
        getterSelectors[1] = GetterFacet.getListingByListingId.selector;
        getterSelectors[2] = GetterFacet.getBalance.selector;
        getterSelectors[3] = GetterFacet.getInnovationFee.selector;
        getterSelectors[4] = GetterFacet.getNextListingId.selector;
        getterSelectors[5] = GetterFacet.isCollectionWhitelisted.selector;
        getterSelectors[6] = GetterFacet.getWhitelistedCollections.selector;
        getterSelectors[7] = GetterFacet.getContractOwner.selector;
        getterSelectors[8] = GetterFacet.isBuyerWhitelisted.selector;
        getterSelectors[9] = GetterFacet.getBuyerWhitelistMaxBatchSize.selector;
        getterSelectors[10] = GetterFacet.getPendingOwner.selector;
        getterSelectors[11] = GetterFacet.isCurrencyAllowed.selector;
        getterSelectors[12] = GetterFacet.getAllowedCurrencies.selector;
        getterSelectors[13] = GetterFacet.getVersion.selector;
        getterSelectors[14] = GetterFacet.getPreviousVersion.selector;
        getterSelectors[15] = GetterFacet.getVersionString.selector;
        getterSelectors[16] = GetterFacet.getImplementationId.selector;
        getterSelectors[17] = GetterFacet.isPaused.selector;

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

        for (uint256 i = 0; i < getterSelectors.length; i++) {
            bytes4 selector = getterSelectors[i];
            address currentFacet = loupe.facetAddress(selector);
            console.log("Current facet for selector:");
            console.logBytes4(selector);
            console.log(currentFacet);
            require(currentFacet != address(0), "UpgradeDiamond: selector not found on diamond");
        }

        // Build replace batch and encode calldata for ERC-8109 upgradeDiamond
        IDiamondUpgradeFacet.FacetFunctions[] memory replaceFns = new IDiamondUpgradeFacet.FacetFunctions[](2);
        replaceFns[0] =
            IDiamondUpgradeFacet.FacetFunctions({facet: address(ideationMarketFacet), selectors: marketSelectors});
        replaceFns[1] = IDiamondUpgradeFacet.FacetFunctions({facet: address(getterFacet), selectors: getterSelectors});

        bytes memory diamondUpgradeCalldata = abi.encodeWithSelector(
            IDiamondUpgradeFacet.upgradeDiamond.selector,
            new IDiamondUpgradeFacet.FacetFunctions[](0),
            replaceFns,
            new bytes4[](0),
            address(0),
            bytes(""),
            bytes32(0),
            bytes("")
        );

        console.log("\n=== Multisig Transaction ===");
        console.log("To (diamond):", diamondAddress);
        console.log("Value:", uint256(0));
        console.log("Data (upgradeDiamond):");
        console.logBytes(diamondUpgradeCalldata);

        console.log("\nNote: setVersion must be executed separately after the upgrade.");
        console.log(
            "After multisig executes upgradeDiamond, run this script again WITHOUT PREPARE_MULTISIG to compute implementationId and setVersion (or add a separate multisig tx calling VersionFacet.setVersion)."
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
