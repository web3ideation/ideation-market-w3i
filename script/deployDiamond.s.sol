// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

import {IdeationMarketDiamond} from "../src/IdeationMarketDiamond.sol";
import {DiamondInit} from "../src/upgradeInitializers/DiamondInit.sol";

import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../src/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "../src/facets/OwnershipFacet.sol";
import {IdeationMarketFacet} from "../src/facets/IdeationMarketFacet.sol";
import {CollectionWhitelistFacet} from "../src/facets/CollectionWhitelistFacet.sol";
import {BuyerWhitelistFacet} from "../src/facets/BuyerWhitelistFacet.sol";
import {GetterFacet} from "../src/facets/GetterFacet.sol";

import {IDiamondCutFacet} from "../src/interfaces/IDiamondCutFacet.sol";
import {IDiamondLoupeFacet} from "../src/interfaces/IDiamondLoupeFacet.sol";
import {IERC165} from "../src/interfaces/IERC165.sol";
import {IERC173} from "../src/interfaces/IERC173.sol";

contract DeployDiamond is Script {
    // Constructor arguments
    address owner = 0x64890a1ddD3Cea0A14D62E14fE76C4a1b34A4328; // !!!W Use appropriate address for testing
    uint32 innovationFee = 1000; // Example fee, e.g., 1000 means 1%
    uint16 buyerWhitelistMaxBatchSize = 300;

    function run() external {
        vm.startBroadcast();

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
        DiamondCutFacet diamondCutFacet = new DiamondCutFacet();
        console.log("Deployed diamondCutFacet contract at address:", address(diamondCutFacet));

        // Deploy the diamond with the initial facet cut for DiamondCutFacet
        IdeationMarketDiamond ideationMarketDiamond = new IdeationMarketDiamond(owner, address(diamondCutFacet));
        console.log("Deployed Diamond contract at address:", address(ideationMarketDiamond));
        console.log("Owner of Diamond:", IERC173(address(ideationMarketDiamond)).owner());

        // Prepare an array of `cuts` that we want to upgrade our Diamond with.
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](6);

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

        bytes4[] memory marketSelectors = new bytes4[](7);
        marketSelectors[0] = IdeationMarketFacet.createListing.selector;
        marketSelectors[1] = IdeationMarketFacet.purchaseListing.selector;
        marketSelectors[2] = IdeationMarketFacet.cancelListing.selector;
        marketSelectors[3] = IdeationMarketFacet.updateListing.selector;
        marketSelectors[4] = IdeationMarketFacet.withdrawProceeds.selector;
        marketSelectors[5] = IdeationMarketFacet.setInnovationFee.selector;
        marketSelectors[6] = IdeationMarketFacet.cleanListing.selector;

        bytes4[] memory collectionWhitelistSelectors = new bytes4[](4);
        collectionWhitelistSelectors[0] = CollectionWhitelistFacet.addWhitelistedCollection.selector;
        collectionWhitelistSelectors[1] = CollectionWhitelistFacet.removeWhitelistedCollection.selector;
        collectionWhitelistSelectors[2] = CollectionWhitelistFacet.batchAddWhitelistedCollections.selector;
        collectionWhitelistSelectors[3] = CollectionWhitelistFacet.batchRemoveWhitelistedCollections.selector;

        bytes4[] memory buyerWhitelistSelectors = new bytes4[](2);
        buyerWhitelistSelectors[0] = BuyerWhitelistFacet.addBuyerWhitelistAddresses.selector;
        buyerWhitelistSelectors[1] = BuyerWhitelistFacet.removeBuyerWhitelistAddresses.selector;

        bytes4[] memory getterSelectors = new bytes4[](12);
        getterSelectors[0] = GetterFacet.getListingsByNFT.selector;
        getterSelectors[1] = GetterFacet.getListingByListingId.selector;
        getterSelectors[2] = GetterFacet.getProceeds.selector;
        getterSelectors[3] = GetterFacet.getBalance.selector;
        getterSelectors[4] = GetterFacet.getInnovationFee.selector;
        getterSelectors[5] = GetterFacet.getNextListingId.selector;
        getterSelectors[6] = GetterFacet.isCollectionWhitelisted.selector;
        getterSelectors[7] = GetterFacet.getWhitelistedCollections.selector;
        getterSelectors[8] = GetterFacet.getContractOwner.selector;
        getterSelectors[9] = GetterFacet.isBuyerWhitelisted.selector;
        getterSelectors[10] = GetterFacet.getBuyerWhitelistMaxBatchSize.selector;
        getterSelectors[11] = GetterFacet.getPendingOwner.selector;

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

        // Upgrade and initialize the diamond to include these facets
        IDiamondCutFacet(address(ideationMarketDiamond)).diamondCut(
            cuts, address(diamondInit), abi.encodeCall(DiamondInit.init, (innovationFee, buyerWhitelistMaxBatchSize))
        );

        // Post-deployment sanity check for the total of the 7 facets
        require(IDiamondLoupeFacet(address(ideationMarketDiamond)).facetAddresses().length == 7, "Diamond cut failed");

        console.log("Diamond cuts complete");

        vm.stopBroadcast();
    }
}
