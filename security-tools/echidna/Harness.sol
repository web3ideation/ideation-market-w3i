// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./src/IdeationMarketDiamond.sol";
import "./src/upgradeInitializers/DiamondInit.sol";

import "./src/facets/BuyerWhitelistFacet.sol";
import "./src/facets/CollectionWhitelistFacet.sol";
import "./src/facets/CurrencyWhitelistFacet.sol";
import "./src/facets/DiamondLoupeFacet.sol";
import "./src/facets/DiamondUpgradeFacet.sol";
import "./src/facets/GetterFacet.sol";
import "./src/facets/IdeationMarketFacet.sol";
import "./src/facets/OwnershipFacet.sol";
import "./src/facets/PauseFacet.sol";
import "./src/facets/VersionFacet.sol";

import "./src/interfaces/IDiamondInspectFacet.sol";
import "./src/interfaces/IDiamondLoupeFacet.sol";
import "./src/interfaces/IDiamondUpgradeFacet.sol";
import "./src/interfaces/IERC165.sol";
import "./src/interfaces/IERC173.sol";

/// @title EchidnaIdeationMarketHarness
/// @notice Minimal Echidna harness compatible with the current diamond design (ERC-8109 `upgradeDiamond`).
contract EchidnaIdeationMarketHarness {
    IdeationMarketDiamond public diamond;

    uint32 internal constant INNOVATION_FEE = 1_000;
    uint16 internal constant BUYER_WL_MAX_BATCH = 300;

    constructor() {
        DiamondInit diamondInit = new DiamondInit();

        DiamondLoupeFacet diamondLoupeFacet = new DiamondLoupeFacet();
        OwnershipFacet ownershipFacet = new OwnershipFacet();
        IdeationMarketFacet ideationMarketFacet = new IdeationMarketFacet();
        CollectionWhitelistFacet collectionWhitelistFacet = new CollectionWhitelistFacet();
        BuyerWhitelistFacet buyerWhitelistFacet = new BuyerWhitelistFacet();
        GetterFacet getterFacet = new GetterFacet();
        CurrencyWhitelistFacet currencyWhitelistFacet = new CurrencyWhitelistFacet();
        VersionFacet versionFacet = new VersionFacet();
        PauseFacet pauseFacet = new PauseFacet();
        DiamondUpgradeFacet diamondUpgradeFacet = new DiamondUpgradeFacet();

        // Deploy the diamond with the initial upgrade facet (ERC-8109 `upgradeDiamond`).
        diamond = new IdeationMarketDiamond(address(this), address(diamondUpgradeFacet));

        // Prepare add functions grouped by facet (ERC-8109)
        IDiamondUpgradeFacet.FacetFunctions[] memory addFns = new IDiamondUpgradeFacet.FacetFunctions[](9);

        bytes4[] memory loupeSelectors = new bytes4[](6);
        loupeSelectors[0] = IDiamondLoupeFacet.facets.selector;
        loupeSelectors[1] = IDiamondLoupeFacet.facetFunctionSelectors.selector;
        loupeSelectors[2] = IDiamondLoupeFacet.facetAddresses.selector;
        loupeSelectors[3] = IDiamondLoupeFacet.facetAddress.selector;
        loupeSelectors[4] = IERC165.supportsInterface.selector;
        loupeSelectors[5] = IDiamondInspectFacet.functionFacetPairs.selector;

        bytes4[] memory ownershipSelectors = new bytes4[](3);
        ownershipSelectors[0] = IERC173.owner.selector;
        ownershipSelectors[1] = IERC173.transferOwnership.selector;
        ownershipSelectors[2] = OwnershipFacet.acceptOwnership.selector;

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

        bytes4[] memory pauseSelectors = new bytes4[](2);
        pauseSelectors[0] = PauseFacet.pause.selector;
        pauseSelectors[1] = PauseFacet.unpause.selector;

        addFns[0] = IDiamondUpgradeFacet.FacetFunctions({facet: address(diamondLoupeFacet), selectors: loupeSelectors});
        addFns[1] = IDiamondUpgradeFacet.FacetFunctions({facet: address(ownershipFacet), selectors: ownershipSelectors});
        addFns[2] =
            IDiamondUpgradeFacet.FacetFunctions({facet: address(ideationMarketFacet), selectors: marketSelectors});
        addFns[3] = IDiamondUpgradeFacet.FacetFunctions({
            facet: address(collectionWhitelistFacet),
            selectors: collectionWhitelistSelectors
        });
        addFns[4] = IDiamondUpgradeFacet.FacetFunctions({
            facet: address(buyerWhitelistFacet),
            selectors: buyerWhitelistSelectors
        });
        addFns[5] = IDiamondUpgradeFacet.FacetFunctions({facet: address(getterFacet), selectors: getterSelectors});
        addFns[6] = IDiamondUpgradeFacet.FacetFunctions({
            facet: address(currencyWhitelistFacet),
            selectors: currencyWhitelistSelectors
        });
        addFns[7] = IDiamondUpgradeFacet.FacetFunctions({facet: address(versionFacet), selectors: versionSelectors});

        addFns[8] = IDiamondUpgradeFacet.FacetFunctions({facet: address(pauseFacet), selectors: pauseSelectors});

        IDiamondUpgradeFacet(address(diamond)).upgradeDiamond(
            addFns,
            new IDiamondUpgradeFacet.FacetFunctions[](0),
            new bytes4[](0),
            address(diamondInit),
            abi.encodeCall(DiamondInit.init, (INNOVATION_FEE, BUYER_WL_MAX_BATCH)),
            bytes32(0),
            bytes("")
        );
    }

    function echidna_facet_count_is_10() external view returns (bool) {
        return IDiamondLoupeFacet(address(diamond)).facetAddresses().length == 10;
    }

    function echidna_supports_expected_interfaces() external view returns (bool) {
        bool ok165 = IERC165(address(diamond)).supportsInterface(type(IERC165).interfaceId);
        bool okLoupe = IERC165(address(diamond)).supportsInterface(type(IDiamondLoupeFacet).interfaceId);
        bool okInspect = IERC165(address(diamond)).supportsInterface(type(IDiamondInspectFacet).interfaceId);
        bool okUpgrade = IERC165(address(diamond)).supportsInterface(type(IDiamondUpgradeFacet).interfaceId);
        bool okOwn = IERC165(address(diamond)).supportsInterface(type(IERC173).interfaceId);
        return ok165 && okLoupe && okInspect && okUpgrade && okOwn;
    }

    function echidna_owner_is_set() external view returns (bool) {
        return IERC173(address(diamond)).owner() != address(0);
    }
}
