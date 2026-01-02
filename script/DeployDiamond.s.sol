// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IdeationMarketDiamond} from "../src/IdeationMarketDiamond.sol";
import {DiamondInit} from "../src/upgradeInitializers/DiamondInit.sol";

import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../src/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "../src/facets/OwnershipFacet.sol";
import {IdeationMarketFacet} from "../src/facets/IdeationMarketFacet.sol";
import {CollectionWhitelistFacet} from "../src/facets/CollectionWhitelistFacet.sol";
import {BuyerWhitelistFacet} from "../src/facets/BuyerWhitelistFacet.sol";
import {GetterFacet} from "../src/facets/GetterFacet.sol";
import {CurrencyWhitelistFacet} from "../src/facets/CurrencyWhitelistFacet.sol";
import {VersionFacet} from "../src/facets/VersionFacet.sol";
import {PauseFacet} from "../src/facets/PauseFacet.sol";

import {IDiamondCutFacet} from "../src/interfaces/IDiamondCutFacet.sol";
import {IDiamondLoupeFacet} from "../src/interfaces/IDiamondLoupeFacet.sol";
import {IERC165} from "../src/interfaces/IERC165.sol";
import {IERC173} from "../src/interfaces/IERC173.sol";

/// @title DeployDiamond (Foundry script)
/// @notice Deploys the IdeationMarket Diamond and all facets, then initializes state via `DiamondInit.init`.
/// @dev Run with Foundry (e.g., `forge script script/DeployDiamond.s.sol:DeployDiamond --rpc-url <URL> --broadcast`).
/// Uses `vm.startBroadcast()`; the tx signer becomes the initial diamond owner.
/// The script performs a diamondCut to add facet groups (Loupe, Ownership, Market, Collection WL, Buyer WL, Getter,
/// Currency WL, Version, Pause) on top of the initially deployed DiamondCut facet, then asserts there are exactly
/// 10 facet addresses.
/// @custom:security The script references `tx.origin` **only** in this off-chain deployment context to set the owner.
/// Do not reuse this pattern inside on-chain contracts.
contract DeployDiamond is Script {
    /// @notice Innovation/marketplace fee rate used during initialization.
    /// @dev Denominator is 100_000 (e.g., 1_000 = 1%). Passed to `DiamondInit.init`.
    uint32 innovationFee = 1000;

    /// @notice Maximum addresses per buyer-whitelist batch.
    /// @dev Enforced by `BuyerWhitelistFacet`; passed to `DiamondInit.init`.
    uint16 buyerWhitelistMaxBatchSize = 300;

    /// @notice Initial version string for the diamond deployment.
    /// @dev Set via environment variable VERSION_STRING, defaults to "1.0.0" if not set.
    string versionString;

    /// @notice Deploys facets, the diamond, performs the diamond cut, and initializes storage.
    /// @dev Reverts if post-cut facet count isn’t 10 (Loupe, Ownership, Market, Collection WL, Buyer WL, Getter,
    /// Currency WL, Version, Pause, Cut).
    /// Emits Foundry `console.log` outputs with deployed addresses for traceability.
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEV_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address deployer = vm.addr(deployerPrivateKey);

        // Deploy Contracts
        DiamondInit diamondInit = new DiamondInit();
        console.log("Deployed diamondInit contract at address:", address(diamondInit));
        DiamondLoupeFacet diamondLoupeFacet = new DiamondLoupeFacet();
        console.log("Deployed diamondLoupeFacet contract at address:", address(diamondLoupeFacet));
        OwnershipFacet ownershipFacet = new OwnershipFacet();
        console.log("Deployed ownershipFacet contract at address:", address(ownershipFacet));
        IdeationMarketFacet ideationMarketFacet = new IdeationMarketFacet();
        console.log("Deployed ideationMarketFacet contract at address:", address(ideationMarketFacet));
        CollectionWhitelistFacet collectionWhitelistFacet = new CollectionWhitelistFacet();
        console.log("Deployed collectionWhitelistFacet contract at address:", address(collectionWhitelistFacet));
        BuyerWhitelistFacet buyerWhitelistFacet = new BuyerWhitelistFacet();
        console.log("Deployed buyerWhitelistFacet contract at address:", address(buyerWhitelistFacet));
        GetterFacet getterFacet = new GetterFacet();
        console.log("Deployed getterFacet contract at address:", address(getterFacet));
        CurrencyWhitelistFacet currencyWhitelistFacet = new CurrencyWhitelistFacet();
        console.log("Deployed currencyWhitelistFacet contract at address:", address(currencyWhitelistFacet));
        VersionFacet versionFacet = new VersionFacet();
        console.log("Deployed versionFacet contract at address:", address(versionFacet));
        PauseFacet pauseFacet = new PauseFacet();
        console.log("Deployed pauseFacet contract at address:", address(pauseFacet));
        DiamondCutFacet diamondCutFacet = new DiamondCutFacet();
        console.log("Deployed diamondCutFacet contract at address:", address(diamondCutFacet));

        // Deploy the diamond with the initial facet cut for DiamondCutFacet
        IdeationMarketDiamond ideationMarketDiamond = new IdeationMarketDiamond(deployer, address(diamondCutFacet));
        console.log("Deployed Diamond contract at address:", address(ideationMarketDiamond));

        // Prepare an array of `cuts` that we want to upgrade our Diamond with.
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](9);

        bytes4[] memory loupeSelectors = new bytes4[](5);
        loupeSelectors[0] = IDiamondLoupeFacet.facets.selector;
        loupeSelectors[1] = IDiamondLoupeFacet.facetFunctionSelectors.selector;
        loupeSelectors[2] = IDiamondLoupeFacet.facetAddresses.selector;
        loupeSelectors[3] = IDiamondLoupeFacet.facetAddress.selector;
        loupeSelectors[4] = IERC165.supportsInterface.selector;

        bytes4[] memory ownershipSelectors = new bytes4[](3);
        ownershipSelectors[0] = IERC173.owner.selector;
        ownershipSelectors[1] = IERC173.transferOwnership.selector;
        ownershipSelectors[2] = OwnershipFacet.acceptOwnership.selector; // finalize handover

        bytes4[] memory marketSelectors = new bytes4[](6);
        marketSelectors[0] = IdeationMarketFacet.createListing.selector;
        marketSelectors[1] = IdeationMarketFacet.purchaseListing.selector;
        marketSelectors[2] = IdeationMarketFacet.cancelListing.selector;
        marketSelectors[3] = IdeationMarketFacet.updateListing.selector;
        marketSelectors[4] = IdeationMarketFacet.setInnovationFee.selector;
        marketSelectors[5] = IdeationMarketFacet.cleanListing.selector;

        bytes4[] memory collectionWhitelistSelectors = new bytes4[](4);
        collectionWhitelistSelectors[0] = CollectionWhitelistFacet.addWhitelistedCollection.selector;
        collectionWhitelistSelectors[1] = CollectionWhitelistFacet.removeWhitelistedCollection.selector;
        collectionWhitelistSelectors[2] = CollectionWhitelistFacet.batchAddWhitelistedCollections.selector;
        collectionWhitelistSelectors[3] = CollectionWhitelistFacet.batchRemoveWhitelistedCollections.selector;

        bytes4[] memory buyerWhitelistSelectors = new bytes4[](2);
        buyerWhitelistSelectors[0] = BuyerWhitelistFacet.addBuyerWhitelistAddresses.selector;
        buyerWhitelistSelectors[1] = BuyerWhitelistFacet.removeBuyerWhitelistAddresses.selector;

        bytes4[] memory currencyWhitelistSelectors = new bytes4[](2);
        currencyWhitelistSelectors[0] = CurrencyWhitelistFacet.addAllowedCurrency.selector;
        currencyWhitelistSelectors[1] = CurrencyWhitelistFacet.removeAllowedCurrency.selector;

        bytes4[] memory versionSelectors = new bytes4[](1);
        versionSelectors[0] = VersionFacet.setVersion.selector;

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

        // Populate the `cuts` array with all data needed for each `FacetCut` struct
        cuts[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(diamondLoupeFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: loupeSelectors
        });

        cuts[1] = IDiamondCutFacet.FacetCut({
            facetAddress: address(ownershipFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: ownershipSelectors
        });

        cuts[2] = IDiamondCutFacet.FacetCut({
            facetAddress: address(ideationMarketFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: marketSelectors
        });

        cuts[3] = IDiamondCutFacet.FacetCut({
            facetAddress: address(collectionWhitelistFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: collectionWhitelistSelectors
        });

        cuts[4] = IDiamondCutFacet.FacetCut({
            facetAddress: address(buyerWhitelistFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: buyerWhitelistSelectors
        });

        cuts[5] = IDiamondCutFacet.FacetCut({
            facetAddress: address(getterFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: getterSelectors
        });

        cuts[6] = IDiamondCutFacet.FacetCut({
            facetAddress: address(currencyWhitelistFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: currencyWhitelistSelectors
        });

        cuts[7] = IDiamondCutFacet.FacetCut({
            facetAddress: address(versionFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: versionSelectors
        });

        bytes4[] memory pauseSelectors = new bytes4[](2);
        pauseSelectors[0] = PauseFacet.pause.selector;
        pauseSelectors[1] = PauseFacet.unpause.selector;

        cuts[8] = IDiamondCutFacet.FacetCut({
            facetAddress: address(pauseFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: pauseSelectors
        });

        // Cut and initialize storage variables
        IDiamondCutFacet(address(ideationMarketDiamond)).diamondCut(
            cuts, address(diamondInit), abi.encodeCall(DiamondInit.init, (innovationFee, buyerWhitelistMaxBatchSize))
        );

        // Post-deployment sanity check for the total of the 10 facets (Loupe, Ownership, Market, Collection WL, Buyer WL, Getter, Currency WL, Version, Pause, Cut)
        require(IDiamondLoupeFacet(address(ideationMarketDiamond)).facetAddresses().length == 10, "Diamond cut failed");

        console.log("Diamond cuts complete");
        console.log("Owner of Diamond:", IERC173(address(ideationMarketDiamond)).owner());

        // Automatically set the version
        versionString = vm.envOr("VERSION_STRING", string("1.0.0"));
        console.log("Setting version:", versionString);

        bytes32 implementationId = computeImplementationId(address(ideationMarketDiamond));
        VersionFacet(address(ideationMarketDiamond)).setVersion(versionString, implementationId);

        console.log("Version set:", versionString);
        console.log("Implementation ID:");
        console.logBytes32(implementationId);

        vm.stopBroadcast();
    }

    /// @notice Computes the implementationId for a diamond.
    /// @dev Queries facets via DiamondLoupe, sorts deterministically, and hashes.
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
