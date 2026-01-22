// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IDiamondLoupeFacet} from "../src/interfaces/IDiamondLoupeFacet.sol";
import {IDiamondUpgradeFacet} from "../src/interfaces/IDiamondUpgradeFacet.sol";
import {IERC173} from "../src/interfaces/IERC173.sol";

import {VersionFacet} from "../src/facets/VersionFacet.sol";
import {GetterFacet} from "../src/facets/GetterFacet.sol";

import {DummyUpgradeFacet} from "../src/facets/DummyUpgradeFacet.sol";
import {DummyUpgradeInit} from "../src/upgradeInitializers/DummyUpgradeInit.sol";

/// @title UpgradeDummy
/// @notice Deploys a dummy facet + initializer and adds it to an already-deployed diamond.
/// @dev This script is intended for multisig-owned diamonds:
///      - It deploys the new facet + init contract (requires `--broadcast`).
///      - It prints Safe-ready calldata for a SINGLE multisig proposal using the Safe batch builder:
///        1) diamond.upgradeDiamond(...)
///        2) diamond.setVersion("1.0.1", expectedPostImplementationId)
///      - It does NOT execute the upgrade itself.
///
/// Important assumptions:
/// - This script models an ADD-ONLY upgrade (adding a brand new facet with new selectors).
/// - The printed `expectedPostImplementationId` is only correct if the multisig executes the
///   `upgradeDiamond` call exactly as printed (same facet address and selector set).
///   If you redeploy the facet, change selectors, or perform other upgrades in-between,
///   the correct post-upgrade implementationId will differ.
///
/// Required environment variables:
/// - DEV_PRIVATE_KEY: funded dev EOA key used only to deploy facet/init (does not need to be the diamond owner).
///   Note: this must match the key you use with `--private-key` when broadcasting.
/// - DUMMY_VALUE: uint256 value to set during init
///
/// Example (prints calldata for Safe batch proposal):
///   DEV_PRIVATE_KEY=$DEV_PRIVATE_KEY DUMMY_VALUE=123 \
///     forge script script/UpgradeDummy.s.sol:UpgradeDummy \
///     --rpc-url $RPC_URL --broadcast --private-key $DEV_PRIVATE_KEY -vvvv
///   or
///   source .env && DUMMY_VALUE=123 forge script script/UpgradeDummy.s.sol:UpgradeDummy --rpc-url $SEPOLIA_RPC_URL --broadcast --private-key $DEV_PRIVATE_KEY
contract UpgradeDummy is Script {
    // Target deployment
    address internal constant DIAMOND_ADDRESS = 0x1107Eb26D47A5bF88E9a9F97cbC7EA38c3E1D7EC;
    string internal constant VERSION_STRING = "1.0.1";

    function run() external {
        address diamondAddress = DIAMOND_ADDRESS;
        address diamondOwner = IERC173(diamondAddress).owner();

        console.log("Diamond:", diamondAddress);
        console.log("Diamond owner:", diamondOwner);
        console.log("Chain ID:", block.chainid);

        // We only need a key to deploy facet/init (the multisig will execute the upgrade).
        uint256 pk = vm.envUint("DEV_PRIVATE_KEY");
        address upgrader = vm.addr(pk);
        console.log("Upgrader:", upgrader);

        uint256 value = vm.envUint("DUMMY_VALUE");

        vm.startBroadcast(pk);

        // 1) deploy facet + init
        DummyUpgradeFacet facet = new DummyUpgradeFacet();
        DummyUpgradeInit init = new DummyUpgradeInit();
        console.log("Deployed DummyUpgradeFacet:", address(facet));
        console.log("Deployed DummyUpgradeInit:", address(init));

        // 2) selector list to add
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = DummyUpgradeFacet.getDummyUpgradeValue.selector;
        selectors[1] = DummyUpgradeFacet.setDummyUpgradeValue.selector;

        // 3) preflight: ensure selectors are not already installed
        IDiamondLoupeFacet loupe = IDiamondLoupeFacet(diamondAddress);
        for (uint256 i = 0; i < selectors.length; i++) {
            address currentFacet = loupe.facetAddress(selectors[i]);
            console.log("Existing facet for selector:");
            console.logBytes4(selectors[i]);
            console.log(currentFacet);
            require(currentFacet == address(0), "UpgradeDummy: selector already exists on diamond");
        }

        // 4) add facet + run initializer via ERC-8109 upgradeDiamond
        IDiamondUpgradeFacet.FacetFunctions[] memory addFns = new IDiamondUpgradeFacet.FacetFunctions[](1);
        addFns[0] = IDiamondUpgradeFacet.FacetFunctions({facet: address(facet), selectors: selectors});

        bytes memory initCall = abi.encodeCall(DummyUpgradeInit.initDummyUpgrade, (value));

        // 5) print multisig calldata for a single Safe batch proposal
        console.log("\n=== Safe Batch Proposal (2 calls) ===");

        bytes memory upgradeCalldata = abi.encodeWithSelector(
            IDiamondUpgradeFacet.upgradeDiamond.selector,
            addFns,
            new IDiamondUpgradeFacet.FacetFunctions[](0),
            new bytes4[](0),
            address(init),
            initCall,
            bytes32(0),
            bytes("")
        );

        console.log("\n--- Call #1: upgradeDiamond ---");
        console.log("To (diamond):", diamondAddress);
        console.log("Value:", uint256(0));
        console.log("Data:");
        console.logBytes(upgradeCalldata);

        bytes32 expectedPostImplementationId =
            computeExpectedImplementationIdAfterAdd(diamondAddress, address(facet), selectors);
        bytes memory setVersionCalldata =
            abi.encodeWithSelector(VersionFacet.setVersion.selector, VERSION_STRING, expectedPostImplementationId);

        console.log("\n--- Call #2: setVersion ---");
        console.log("To (diamond):", diamondAddress);
        console.log("Value:", uint256(0));
        console.log("Data:");
        console.logBytes(setVersionCalldata);
        console.log("\nExpected post-upgrade implementationId:");
        console.logBytes32(expectedPostImplementationId);

        vm.stopBroadcast();
    }

    /// @notice Computes the expected post-upgrade implementationId for adding a new facet+selectors.
    /// @dev Deterministic: keccak256(chainId, diamond, sortedFacetAddresses[], sortedSelectorsPerFacet[][]).
    /// This does NOT execute the upgrade; it models the expected diamond state after Call #1.
    function computeExpectedImplementationIdAfterAdd(address diamond, address newFacet, bytes4[] memory newSelectors)
        internal
        view
        returns (bytes32)
    {
        IDiamondLoupeFacet loupe = IDiamondLoupeFacet(diamond);
        IDiamondLoupeFacet.Facet[] memory facets = loupe.facets();
        uint256 facetCount = facets.length;

        address[] memory facetAddresses = new address[](facetCount + 1);
        bytes4[][] memory selectorsPerFacet = new bytes4[][](facetCount + 1);

        for (uint256 i = 0; i < facetCount; i++) {
            facetAddresses[i] = facets[i].facetAddress;
            selectorsPerFacet[i] = facets[i].functionSelectors;
        }

        // Append the new facet and its selectors.
        facetAddresses[facetCount] = newFacet;
        selectorsPerFacet[facetCount] = newSelectors;

        // Sort facets by address (and keep selectors aligned with their facet).
        for (uint256 i = 0; i < facetAddresses.length; i++) {
            for (uint256 j = i + 1; j < facetAddresses.length; j++) {
                if (facetAddresses[i] > facetAddresses[j]) {
                    (facetAddresses[i], facetAddresses[j]) = (facetAddresses[j], facetAddresses[i]);
                    (selectorsPerFacet[i], selectorsPerFacet[j]) = (selectorsPerFacet[j], selectorsPerFacet[i]);
                }
            }
        }

        // Sort selectors within each facet.
        for (uint256 i = 0; i < selectorsPerFacet.length; i++) {
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
