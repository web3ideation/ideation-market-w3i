// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

// Facets and library imports from the marketplace project
import "../src/IdeationMarketDiamond.sol";
import "../src/upgradeInitializers/DiamondInit.sol";
import "../src/facets/DiamondCutFacet.sol";
import "../src/facets/DiamondLoupeFacet.sol";
import "../src/facets/OwnershipFacet.sol";
import "../src/facets/IdeationMarketFacet.sol";
import "../src/facets/CollectionWhitelistFacet.sol";
import "../src/facets/BuyerWhitelistFacet.sol";
import "../src/facets/CurrencyWhitelistFacet.sol";
import "../src/facets/PauseFacet.sol";
import "../src/facets/VersionFacet.sol";
import "../src/facets/GetterFacet.sol";
import "../src/interfaces/IDiamondCutFacet.sol";
import "../src/interfaces/IDiamondLoupeFacet.sol";
import "../src/interfaces/IERC165.sol";
import "../src/interfaces/IERC173.sol";
import "../src/interfaces/IERC721.sol";
import "../src/interfaces/IERC1155.sol";
import "../src/interfaces/IERC2981.sol";
import "../src/libraries/LibAppStorage.sol";
import "../src/libraries/LibDiamond.sol";

// Openzeppelin Mock imports
import {ERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {ERC1155} from "lib/openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";

abstract contract MarketTestBase is Test {
    IdeationMarketDiamond internal diamond;

    // Cached facet references for convenience
    DiamondLoupeFacet internal loupe;
    OwnershipFacet internal ownership;
    IdeationMarketFacet internal market;
    CollectionWhitelistFacet internal collections;
    BuyerWhitelistFacet internal buyers;
    CurrencyWhitelistFacet internal currencies;
    PauseFacet internal pauseFacet;
    VersionFacet internal versionFacet;
    GetterFacet internal getter;

    // Address of the initial diamondCut facet deployed in setUp
    address internal diamondCutFacetAddr;

    // Raw facet implementation addresses (useful for diamondCut edge tests)
    address internal loupeImpl;
    address internal ownershipImpl;
    address internal marketImpl;
    address internal collectionsImpl;
    address internal buyersImpl;
    address internal currenciesImpl;
    address internal pauseImpl;
    address internal versionImpl;
    address internal getterImpl;

    // Test addresses
    address internal owner;
    address internal seller;
    address internal buyer;
    address internal operator;

    // Mock tokens
    MockERC721 internal erc721;
    MockERC1155 internal erc1155;

    // Constants for initial configuration
    uint32 internal constant INNOVATION_FEE = 1000;
    uint16 internal constant MAX_BATCH = 300;

    function setUp() public virtual {
        // Create distinct deterministic addresses for each actor
        owner = vm.addr(0x1000);
        seller = vm.addr(0x1001);
        buyer = vm.addr(0x1002);
        operator = vm.addr(0x1003);

        // Start broadcasting as the owner for deployment
        vm.startPrank(owner);

        // Deploy initializer and facet contracts
        DiamondInit init = new DiamondInit();
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        DiamondLoupeFacet loupeFacet = new DiamondLoupeFacet();
        OwnershipFacet ownershipFacet = new OwnershipFacet();
        IdeationMarketFacet marketFacet = new IdeationMarketFacet();
        CollectionWhitelistFacet collectionFacet = new CollectionWhitelistFacet();
        BuyerWhitelistFacet buyerFacet = new BuyerWhitelistFacet();
        CurrencyWhitelistFacet currencyFacet = new CurrencyWhitelistFacet();
        PauseFacet pauseFacetImpl = new PauseFacet();
        VersionFacet versionFacetImpl = new VersionFacet();
        GetterFacet getterFacet = new GetterFacet();

        // Deploy the diamond and add the initial diamondCut function
        diamond = new IdeationMarketDiamond(owner, address(cutFacet));

        // Cache diamondCut facet address for later assertions
        diamondCutFacetAddr = address(cutFacet);

        // Prepare facet cut definitions matching the deploy script
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](9);

        // Diamond Loupe selectors
        bytes4[] memory loupeSelectors = new bytes4[](5);
        loupeSelectors[0] = IDiamondLoupeFacet.facets.selector;
        loupeSelectors[1] = IDiamondLoupeFacet.facetFunctionSelectors.selector;
        loupeSelectors[2] = IDiamondLoupeFacet.facetAddresses.selector;
        loupeSelectors[3] = IDiamondLoupeFacet.facetAddress.selector;
        loupeSelectors[4] = IERC165.supportsInterface.selector;
        cuts[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(loupeFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: loupeSelectors
        });

        // Ownership selectors, including acceptOwnership from the OwnershipFacet
        bytes4[] memory ownershipSelectors = new bytes4[](3);
        ownershipSelectors[0] = IERC173.owner.selector;
        ownershipSelectors[1] = IERC173.transferOwnership.selector;
        ownershipSelectors[2] = OwnershipFacet.acceptOwnership.selector;
        cuts[1] = IDiamondCutFacet.FacetCut({
            facetAddress: address(ownershipFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: ownershipSelectors
        });

        // Marketplace selectors
        bytes4[] memory marketSelectors = new bytes4[](6);
        marketSelectors[0] = IdeationMarketFacet.createListing.selector;
        marketSelectors[1] = IdeationMarketFacet.purchaseListing.selector;
        marketSelectors[2] = IdeationMarketFacet.cancelListing.selector;
        marketSelectors[3] = IdeationMarketFacet.updateListing.selector;
        marketSelectors[4] = IdeationMarketFacet.setInnovationFee.selector;
        marketSelectors[5] = IdeationMarketFacet.cleanListing.selector;
        cuts[2] = IDiamondCutFacet.FacetCut({
            facetAddress: address(marketFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: marketSelectors
        });

        // Collection whitelist selectors
        bytes4[] memory collectionSelectors = new bytes4[](4);
        collectionSelectors[0] = CollectionWhitelistFacet.addWhitelistedCollection.selector;
        collectionSelectors[1] = CollectionWhitelistFacet.removeWhitelistedCollection.selector;
        collectionSelectors[2] = CollectionWhitelistFacet.batchAddWhitelistedCollections.selector;
        collectionSelectors[3] = CollectionWhitelistFacet.batchRemoveWhitelistedCollections.selector;
        cuts[3] = IDiamondCutFacet.FacetCut({
            facetAddress: address(collectionFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: collectionSelectors
        });

        // Buyer whitelist selectors
        bytes4[] memory buyerSelectors = new bytes4[](2);
        buyerSelectors[0] = BuyerWhitelistFacet.addBuyerWhitelistAddresses.selector;
        buyerSelectors[1] = BuyerWhitelistFacet.removeBuyerWhitelistAddresses.selector;
        cuts[4] = IDiamondCutFacet.FacetCut({
            facetAddress: address(buyerFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: buyerSelectors
        });

        // Currency whitelist selectors
        bytes4[] memory currencySelectors = new bytes4[](2);
        currencySelectors[0] = CurrencyWhitelistFacet.addAllowedCurrency.selector;
        currencySelectors[1] = CurrencyWhitelistFacet.removeAllowedCurrency.selector;
        cuts[5] = IDiamondCutFacet.FacetCut({
            facetAddress: address(currencyFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: currencySelectors
        });

        // Getter selectors (add all view functions exposed by GetterFacet)
        bytes4[] memory getterSelectors = new bytes4[](18);
        getterSelectors[0] = GetterFacet.getListingsByNFT.selector;
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
        getterSelectors[11] = GetterFacet.isPaused.selector;
        getterSelectors[12] = GetterFacet.getVersion.selector;
        getterSelectors[13] = GetterFacet.isCurrencyAllowed.selector;
        getterSelectors[14] = GetterFacet.getAllowedCurrencies.selector;
        getterSelectors[15] = GetterFacet.getPreviousVersion.selector;
        getterSelectors[16] = GetterFacet.getVersionString.selector;
        getterSelectors[17] = GetterFacet.getImplementationId.selector;
        cuts[6] = IDiamondCutFacet.FacetCut({
            facetAddress: address(getterFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: getterSelectors
        });

        // PauseFacet selectors
        bytes4[] memory pauseSelectors = new bytes4[](2);
        pauseSelectors[0] = PauseFacet.pause.selector;
        pauseSelectors[1] = PauseFacet.unpause.selector;
        cuts[7] = IDiamondCutFacet.FacetCut({
            facetAddress: address(pauseFacetImpl),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: pauseSelectors
        });

        // VersionFacet selectors (setVersion only - getters are in GetterFacet)
        bytes4[] memory versionSelectors = new bytes4[](1);
        versionSelectors[0] = VersionFacet.setVersion.selector;
        cuts[8] = IDiamondCutFacet.FacetCut({
            facetAddress: address(versionFacetImpl),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: versionSelectors
        });

        // Execute diamond cut and initializer
        IDiamondCutFacet(address(diamond)).diamondCut(
            cuts, address(init), abi.encodeCall(DiamondInit.init, (INNOVATION_FEE, MAX_BATCH))
        );

        // Note: DiamondInit.init() already initializes 76 allowed currencies including ETH

        vm.stopPrank();

        // Cache facet handles through the diamond's address. Casting will
        // delegate calls through the diamond fallback to the appropriate facet.
        loupe = DiamondLoupeFacet(address(diamond));
        ownership = OwnershipFacet(address(diamond));
        market = IdeationMarketFacet(address(diamond));
        collections = CollectionWhitelistFacet(address(diamond));
        buyers = BuyerWhitelistFacet(address(diamond));
        currencies = CurrencyWhitelistFacet(address(diamond));
        pauseFacet = PauseFacet(address(diamond));
        versionFacet = VersionFacet(address(diamond));
        getter = GetterFacet(address(diamond));

        // cache impl addrs
        loupeImpl = address(loupeFacet);
        ownershipImpl = address(ownershipFacet);
        marketImpl = address(marketFacet);
        collectionsImpl = address(collectionFacet);
        buyersImpl = address(buyerFacet);
        currenciesImpl = address(currencyFacet);
        pauseImpl = address(pauseFacetImpl);
        versionImpl = address(versionFacetImpl);
        getterImpl = address(getterFacet);

        // Deploy mock tokens and mint balances for seller
        erc721 = new MockERC721();
        erc1155 = new MockERC1155();
        erc721.mint(seller, 1);
        erc721.mint(seller, 2);
        erc1155.mint(seller, 1, 10);
    }

    function _whitelist(address c) internal {
        vm.prank(owner);
        collections.addWhitelistedCollection(c);
    }

    function _whitelistDefaultMocks() internal {
        _whitelist(address(erc721));
        _whitelist(address(erc1155));
    }

    function _whitelistCollectionAndApproveERC721() internal {
        // Helper to whitelist ERC721 and approve diamond for token ID 1
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc721));
        vm.stopPrank();
        // Seller approves the marketplace (diamond) to transfer token 1
        vm.startPrank(seller);
        erc721.approve(address(diamond), 1);
        vm.stopPrank();
    }

    function _whitelistCollectionAndApproveERC1155() internal {
        // Whitelist ERC1155 collection
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.stopPrank();

        // Seller grants operator approval to the marketplace (diamond)
        vm.startPrank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.stopPrank();
    }

    function _createListingERC721(bool buyerWhitelistEnabled, address[] memory allowedBuyers)
        internal
        returns (uint128 listingId)
    {
        _whitelistCollectionAndApproveERC721();
        vm.startPrank(seller);
        // Provide zero values for swap params and quantity, use ETH (address(0)) as currency
        market.createListing(
            address(erc721),
            1,
            address(0),
            1 ether,
            address(0),
            address(0),
            0,
            0,
            0,
            buyerWhitelistEnabled,
            false,
            allowedBuyers
        );
        vm.stopPrank();
        // Next listing id is counter + 1
        listingId = getter.getNextListingId() - 1;
    }

    function _createListingERC1155(uint256 quantity, bool buyerWhitelistEnabled, address[] memory allowedBuyers)
        internal
        returns (uint128 listingId)
    {
        require(quantity > 0, "quantity must be > 0");
        _whitelistCollectionAndApproveERC1155(); // must mint to `seller` and setApprovalForAll(market, true)

        vm.startPrank(seller);
        market.createListing(
            address(erc1155), // tokenAddress
            1, // tokenId (align with your ERC721 helper; change if needed)
            seller, // erc1155Holder (must be the holder or authorized operator)
            1 ether, // price
            address(0), // currency (ETH)
            address(0), // desiredTokenAddress (no swap)
            0, // desiredTokenId
            0, // desiredErc1155Quantity (no swap)
            quantity, // erc1155Quantity (>0 for ERC1155)
            buyerWhitelistEnabled, // buyer whitelist flag
            false, // partialBuyEnabled (fixed here; paramize if you plan partial-buy tests)
            allowedBuyers // initial whitelist (must be empty if whitelist disabled)
        );
        vm.stopPrank();

        listingId = getter.getNextListingId() - 1;
    }

    function listERC1155WithOperatorAndWhitelistEnabled(uint256 tokenId, uint256 quantity, uint256 price)
        internal
        returns (uint128 listingId)
    {
        listingId = uint128(getter.getNextListingId());

        vm.startPrank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        erc1155.setApprovalForAll(operator, true);
        vm.stopPrank();

        vm.prank(operator);
        market.createListing(
            address(erc1155),
            tokenId,
            seller,
            price,
            address(0),
            address(0),
            0,
            0,
            quantity,
            true,
            false,
            new address[](0)
        );
    }

    function _contains(address[] memory a, address x) internal pure returns (bool) {
        for (uint256 i = 0; i < a.length; i++) {
            if (a[i] == x) return true;
        }
        return false;
    }

    function _diamondCutSingle(address facet, IDiamondCutFacet.FacetCutAction action, bytes4 selector) internal {
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](1);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;

        cuts[0] = IDiamondCutFacet.FacetCut({facetAddress: facet, action: action, functionSelectors: selectors});

        vm.prank(owner);
        IDiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), "");
    }

    function _diamondCutAddSelector(address facet, bytes4 selector) internal {
        _diamondCutSingle(facet, IDiamondCutFacet.FacetCutAction.Add, selector);
    }

    function _diamondCutReplaceSelector(address facet, bytes4 selector) internal {
        _diamondCutSingle(facet, IDiamondCutFacet.FacetCutAction.Replace, selector);
    }

    function _createERC721ListingWithCurrency(address currency, uint256 price, uint256 tokenId)
        internal
        returns (uint128 listingId)
    {
        if (!getter.isCollectionWhitelisted(address(erc721))) {
            vm.startPrank(owner);
            collections.addWhitelistedCollection(address(erc721));
            vm.stopPrank();
        }

        vm.startPrank(seller);
        erc721.approve(address(diamond), tokenId);
        market.createListing(
            address(erc721), tokenId, address(0), price, currency, address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        listingId = getter.getNextListingId() - 1;
    }

    function _createMaliciousTokenListing(address token, uint256 price, uint256 tokenId)
        internal
        returns (uint128 listingId)
    {
        vm.startPrank(owner);
        currencies.addAllowedCurrency(token);
        collections.addWhitelistedCollection(address(erc721));
        vm.stopPrank();

        vm.startPrank(seller);
        erc721.approve(address(diamond), tokenId);
        market.createListing(
            address(erc721), tokenId, address(0), price, token, address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        listingId = getter.getNextListingId() - 1;
    }

    function _testDecimalToken(MockERC20WithDecimals token, uint256 price, uint256 tokenId) internal {
        erc721.mint(seller, tokenId);

        vm.startPrank(seller);
        erc721.approve(address(diamond), tokenId);
        market.createListing(
            address(erc721),
            tokenId,
            address(0),
            price,
            address(token),
            address(0),
            0,
            0,
            0,
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();

        uint128 listingId = getter.getNextListingId() - 1;

        token.mint(buyer, price);

        uint256 ownerBefore = token.balanceOf(owner);
        uint256 sellerBefore = token.balanceOf(seller);

        vm.startPrank(buyer);
        token.approve(address(diamond), price);
        market.purchaseListing(listingId, price, address(token), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        uint256 expectedFee = (price * uint256(INNOVATION_FEE)) / 100000;
        assertEq(token.balanceOf(owner) - ownerBefore, expectedFee, "Owner fee incorrect");
        assertEq(token.balanceOf(seller) - sellerBefore, price - expectedFee, "Seller proceeds incorrect");
        assertEq(token.balanceOf(address(diamond)), 0, "Diamond holds tokens");
    }

    function _new721() internal returns (MockERC721 m) {
        m = new MockERC721();
    }

    function _new1155() internal returns (MockERC1155 m) {
        m = new MockERC1155();
    }

    function _addCurrency(address token) internal {
        vm.prank(owner);
        currencies.addAllowedCurrency(token);
    }

    function _removeCurrency(address token) internal {
        vm.prank(owner);
        currencies.removeAllowedCurrency(token);
    }

    function _countOccurrences(address[] memory arr, address target) internal pure returns (uint256 count) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == target) {
                count++;
            }
        }
    }

    function _deprecatedSwap_mintAndApproveForBuyer(uint256 tokenId, uint256 amount1155) internal {
        _whitelistDefaultMocks();

        erc1155.mint(buyer, tokenId, amount1155);
        vm.prank(buyer);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        erc721.approve(address(diamond), tokenId);
    }

    function _deprecatedSwap_listBuyerERC1155(uint256 tokenId, uint256 depQty, uint256 priceWei)
        internal
        returns (uint128 depId)
    {
        depId = uint128(getter.getNextListingId());
        vm.prank(buyer);
        market.createListing(
            address(erc1155),
            tokenId,
            buyer,
            priceWei,
            address(0),
            address(0),
            0,
            0,
            depQty,
            false,
            false,
            new address[](0)
        );
    }

    function _deprecatedSwap_listSellerERC721Swap(uint256 tokenId, uint256 desiredQty)
        internal
        returns (uint128 swapId)
    {
        swapId = uint128(getter.getNextListingId());
        vm.prank(seller);
        market.createListing(
            address(erc721),
            tokenId,
            address(0),
            0,
            address(0),
            address(erc1155),
            tokenId,
            desiredQty,
            0,
            false,
            false,
            new address[](0)
        );
    }

    function _deprecatedSwap_purchaseSwap(uint128 swapId, uint256 tokenId, uint256 desiredQty) internal {
        vm.prank(buyer);
        market.purchaseListing(swapId, 0, address(0), 0, address(erc1155), tokenId, desiredQty, 0, buyer);
    }

    function _createERC721ListingInERC20(address currency, uint256 price, uint256 tokenId)
        internal
        returns (uint128 listingId)
    {
        _whitelistCollectionAndApproveERC721();

        vm.startPrank(seller);
        market.createListing(
            address(erc721), tokenId, address(0), price, currency, address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();
        listingId = getter.getNextListingId() - 1;
    }

    function _createERC1155ListingInERC20(address currency, uint256 price, uint256 quantity)
        internal
        returns (uint128 listingId)
    {
        _whitelistCollectionAndApproveERC1155();

        vm.startPrank(seller);
        market.createListing(
            address(erc1155), 1, seller, price, currency, address(0), 0, 0, quantity, false, false, new address[](0)
        );
        vm.stopPrank();
        listingId = getter.getNextListingId() - 1;
    }

    function _createERC721Listing(address currency, uint256 price) internal returns (uint128 listingId) {
        if (!getter.isCollectionWhitelisted(address(erc721))) {
            vm.startPrank(owner);
            collections.addWhitelistedCollection(address(erc721));
            vm.stopPrank();
        }

        vm.startPrank(seller);
        erc721.approve(address(diamond), 1);
        market.createListing(
            address(erc721), 1, address(0), price, currency, address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        listingId = getter.getNextListingId() - 1;
    }

    function _createERC721ListingWithToken(address currency, uint256 price, uint256 tokenId)
        internal
        returns (uint128 listingId)
    {
        if (!getter.isCollectionWhitelisted(address(erc721))) {
            vm.startPrank(owner);
            collections.addWhitelistedCollection(address(erc721));
            vm.stopPrank();
        }

        erc721.mint(seller, tokenId);

        vm.startPrank(seller);
        erc721.approve(address(diamond), tokenId);
        market.createListing(
            address(erc721), tokenId, address(0), price, currency, address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        listingId = getter.getNextListingId() - 1;
    }

    function _createRoyaltyListing(
        MockERC721Royalty royaltyToken,
        address currency,
        uint256 price,
        address royaltyReceiver,
        uint256 royaltyBps
    ) internal returns (uint128 listingId) {
        if (!getter.isCollectionWhitelisted(address(royaltyToken))) {
            vm.startPrank(owner);
            collections.addWhitelistedCollection(address(royaltyToken));
            vm.stopPrank();
        }

        royaltyToken.setRoyalty(royaltyReceiver, royaltyBps);
        royaltyToken.mint(seller, 1);

        vm.startPrank(seller);
        royaltyToken.approve(address(diamond), 1);
        market.createListing(
            address(royaltyToken), 1, address(0), price, currency, address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        listingId = getter.getNextListingId() - 1;
    }

    function _hasSel(bytes4[] memory arr, bytes4 sel) internal pure returns (bool) {
        for (uint256 i; i < arr.length; i++) {
            if (arr[i] == sel) return true;
        }
        return false;
    }

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

// -------------------------------------------------------------------------
// Helper and Mock Token Implementations
// -------------------------------------------------------------------------

// A minimal ERC‑721 that implements owner/approval logic sufficient for the marketplace
contract MockERC721 {
    mapping(uint256 => address) internal _owners;
    mapping(uint256 => address) internal _tokenApprovals;
    mapping(address => mapping(address => bool)) internal _operatorApprovals;
    // Track balances to support balanceOf
    mapping(address => uint256) internal _balances;

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC721).interfaceId;
    }

    function mint(address to, uint256 tokenId) external {
        _owners[tokenId] = to;
        _balances[to] += 1;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        return _owners[tokenId];
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        return _tokenApprovals[tokenId];
    }

    function approve(address to, uint256 tokenId) external {
        require(msg.sender == _owners[tokenId], "not owner");
        _tokenApprovals[tokenId] = to;
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /// @notice Transfer tokenId from `from` to `to`. Caller must be owner or approved.
    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_owners[tokenId] == from, "not owner");
        // caller is from or approved
        require(
            msg.sender == from || msg.sender == _tokenApprovals[tokenId] || _operatorApprovals[from][msg.sender],
            "not approved"
        );
        _owners[tokenId] = to;
        _balances[from] -= 1;
        _balances[to] += 1;
        _tokenApprovals[tokenId] = address(0);
    }

    /// @notice Safe transfer (no ERC721Receiver check for simplicity)
    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        transferFrom(from, to, tokenId);
    }

    /// @notice Safe transfer with data (no ERC721Receiver check)
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external {
        transferFrom(from, to, tokenId);
    }

    /// Trap: someone called the ERC1155 balanceOf on an ERC721 mock.
    function balanceOf(address, /*account*/ uint256 /*id*/ ) external pure returns (uint256) {
        revert("MockERC721: ERC1155.balanceOf(account,id) called on ERC721");
    }

    /// Trap: someone called the 5-arg ERC1155 safeTransferFrom on an ERC721 mock.
    function safeTransferFrom(
        address, /*from*/
        address, /*to*/
        uint256, /*id*/
        uint256, /*amount*/
        bytes calldata /*data*/
    ) external pure {
        revert("MockERC721: ERC1155.safeTransferFrom used on ERC721");
    }

    // Add this helper anywhere in MockERC721
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = _owners[tokenId];
        return (spender == owner || spender == _tokenApprovals[tokenId] || _operatorApprovals[owner][spender]);
    }

    // Replace your current burn with this (no _burn() call needed)
    function burn(uint256 tokenId) external {
        address owner = _owners[tokenId];
        require(owner != address(0), "nonexistent");
        require(_isApprovedOrOwner(msg.sender, tokenId), "not approved");

        _balances[owner] -= 1;
        _owners[tokenId] = address(0);
        _tokenApprovals[tokenId] = address(0);
    }
}

// A minimal ERC‑1155 implementing balance and approval logic
contract MockERC1155 {
    mapping(uint256 => mapping(address => uint256)) internal _balances;
    mapping(address => mapping(address => bool)) internal _operatorApprovals;

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC1155).interfaceId;
    }

    function mint(address to, uint256 id, uint256 amount) external {
        _balances[id][to] += amount;
    }

    function balanceOf(address account, uint256 id) external view returns (uint256) {
        return _balances[id][account];
    }

    function isApprovedForAll(address account, address operator) external view returns (bool) {
        return _operatorApprovals[account][operator];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata) external {
        require(msg.sender == from || _operatorApprovals[from][msg.sender], "not approved");
        require(_balances[id][from] >= amount, "insufficient");
        _balances[id][from] -= amount;
        _balances[id][to] += amount;
    }

    /// Trap: someone called the ERC721 ownerOf on an ERC1155 mock.
    function ownerOf(uint256 /*tokenId*/ ) external pure returns (address) {
        revert("MockERC1155: ERC721.ownerOf called on ERC1155");
    }

    /// Trap: someone called the ERC721 getApproved on an ERC1155 mock.
    function getApproved(uint256 /*tokenId*/ ) external pure returns (address) {
        revert("MockERC1155: ERC721.getApproved called on ERC1155");
    }

    /// Trap: someone called the 3-arg ERC721 safeTransferFrom on an ERC1155 mock.
    function safeTransferFrom(address, /*from*/ address, /*to*/ uint256 /*tokenId*/ ) external pure {
        revert("MockERC1155: ERC721.safeTransferFrom(3) used on ERC1155");
    }

    /// Trap: someone called the 4-arg ERC721 safeTransferFrom on an ERC1155 mock.
    function safeTransferFrom(address, /*from*/ address, /*to*/ uint256, /*tokenId*/ bytes calldata /*data*/ )
        external
        pure
    {
        revert("MockERC1155: ERC721.safeTransferFrom(4) used on ERC1155");
    }

    // assumes these exist in MockERC1155:
    // mapping(address => mapping(uint256 => uint256)) internal _balances;
    // mapping(address => mapping(address => bool)) internal _operatorApprovals;

    function burn(address from, uint256 id, uint256 amount) external {
        require(from == msg.sender || _operatorApprovals[from][msg.sender], "not approved");
        uint256 bal = _balances[id][from];
        require(bal >= amount, "insufficient");
        _balances[id][from] = bal - amount;
    }
}

// Minimal ERC721 + ERC2981 mock with adjustable royalty (denominator = 100_000)
contract MockERC721Royalty {
    mapping(uint256 => address) internal _owners;
    mapping(uint256 => address) internal _tokenApprovals;
    mapping(address => mapping(address => bool)) internal _operatorApprovals;
    mapping(address => uint256) internal _balances;

    address public royaltyReceiver;
    uint256 public royaltyBps; // out of 100_000

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC721).interfaceId
            || interfaceId == type(IERC2981).interfaceId;
    }

    function mint(address to, uint256 tokenId) external {
        _owners[tokenId] = to;
        _balances[to] += 1;
    }

    function setRoyalty(address receiver, uint256 bps) external {
        royaltyReceiver = receiver;
        royaltyBps = bps; // e.g., 99_500 = 99.5%
    }

    function royaltyInfo(uint256, /*tokenId*/ uint256 salePrice) external view returns (address, uint256) {
        uint256 amount = salePrice * royaltyBps / 100_000;
        return (royaltyReceiver, amount);
    }

    function balanceOf(address owner) external view returns (uint256) {
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        return _owners[tokenId];
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        return _tokenApprovals[tokenId];
    }

    function approve(address to, uint256 tokenId) external {
        require(msg.sender == _owners[tokenId], "not owner");
        _tokenApprovals[tokenId] = to;
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_owners[tokenId] == from, "not owner");
        require(
            msg.sender == from || msg.sender == _tokenApprovals[tokenId] || _operatorApprovals[from][msg.sender],
            "not approved"
        );
        _owners[tokenId] = to;
        _balances[from] -= 1;
        _balances[to] += 1;
        _tokenApprovals[tokenId] = address(0);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external {
        transferFrom(from, to, tokenId);
    }

    function balanceOf(address, /*account*/ uint256 /*id*/ ) external pure returns (uint256) {
        revert("MockERC721Royalty: ERC1155.balanceOf(account,id) called on ERC721");
    }

    function safeTransferFrom(
        address, /*from*/
        address, /*to*/
        uint256, /*id*/
        uint256, /*amount*/
        bytes calldata /*data*/
    ) external pure {
        revert("MockERC721Royalty: ERC1155.safeTransferFrom used on ERC721");
    }
}

// ERC721 + ERC2981 mock whose royaltyInfo REVERTS
contract MockERC721RoyaltyReverting {
    mapping(uint256 => address) internal _owners;
    mapping(uint256 => address) internal _tokenApprovals;
    mapping(address => mapping(address => bool)) internal _operatorApprovals;
    mapping(address => uint256) internal _balances;

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC721).interfaceId
            || interfaceId == type(IERC2981).interfaceId;
    }

    function mint(address to, uint256 tokenId) external {
        _owners[tokenId] = to;
        _balances[to] += 1;
    }

    // --- ERC2981 ---
    function royaltyInfo(uint256, uint256) external pure returns (address, uint256) {
        revert("MockERC721RoyaltyReverting: royaltyInfo reverts");
    }

    // --- Minimal ERC721 ---
    function ownerOf(uint256 tokenId) external view returns (address) {
        return _owners[tokenId];
    }

    function balanceOf(address owner) external view returns (uint256) {
        return _balances[owner];
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        return _tokenApprovals[tokenId];
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function approve(address to, uint256 tokenId) external {
        require(msg.sender == _owners[tokenId], "not owner");
        _tokenApprovals[tokenId] = to;
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        require(_owners[tokenId] == from, "not owner");
        require(
            msg.sender == from || msg.sender == _tokenApprovals[tokenId] || _operatorApprovals[from][msg.sender],
            "not approved"
        );
        _owners[tokenId] = to;
        _balances[from] -= 1;
        _balances[to] += 1;
        _tokenApprovals[tokenId] = address(0);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external {
        transferFrom(from, to, tokenId);
    }

    // Traps if marketplace accidentally uses ERC1155 functions on an ERC721
    function balanceOf(address, uint256) external pure returns (uint256) {
        revert("ERC1155.balanceOf on ERC721");
    }

    function safeTransferFrom(address, address, uint256, uint256, bytes calldata) external pure {
        revert("ERC1155.safeTransferFrom on ERC721");
    }
}

/// Recipient that reverts on ETH reception.
contract RevertOnReceive {
    receive() external payable {
        revert("RevertOnReceive: cannot receive Ether");
    }
}

contract NotAnNFT {
    function supportsInterface(bytes4) external pure returns (bool) {
        return false;
    }
}

contract SwallowingERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        // attempt something that would normally revert, but swallow it
        try this._doFail() {} catch { /* swallow */ }
        return this.onERC721Received.selector;
    }

    function _doFail() external pure {
        require(false, "internal");
    }
}

interface IERC1155ReceiverLike {
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns (bytes4);
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        returns (bytes4);
}

/// ERC1155 receiver that swallows internal errors but still returns the accept selectors
contract SwallowingERC1155Receiver {
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns (bytes4) {
        try this._noop() {} catch {}
        return IERC1155ReceiverLike.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        returns (bytes4)
    {
        try this._noop() {} catch {}
        return IERC1155ReceiverLike.onERC1155BatchReceived.selector;
    }

    function _noop() external {}
}

/// ===== Minimal burnable ERC721 used only for tests =====
/// NOTE: This is a very small, test-only ERC721 that the marketplace can interact with.
/// It implements approvals, transferFrom/safeTransferFrom, supportsInterface, and burn().
contract BurnableERC721 {
    // ERC165
    function supportsInterface(bytes4 iid) external pure returns (bool) {
        return iid == 0x01ffc9a7 /* ERC165 */ || iid == 0x80ac58cd; /* ERC721 */
    }

    mapping(uint256 => address) private _owner;
    mapping(address => mapping(address => bool)) private _operatorApproval;
    mapping(uint256 => address) private _tokenApproval;

    event Transfer(address indexed from, address indexed to, uint256 indexed id);
    event Approval(address indexed owner, address indexed approved, uint256 indexed id);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function mint(address to, uint256 id) external {
        require(_owner[id] == address(0), "exists");
        _owner[id] = to;
        emit Transfer(address(0), to, id);
    }

    function ownerOf(uint256 id) public view returns (address) {
        address o = _owner[id];
        require(o != address(0), "no owner");
        return o;
    }

    function approve(address to, uint256 id) external {
        address o = ownerOf(id);
        require(msg.sender == o || isApprovedForAll(o, msg.sender), "not auth");
        _tokenApproval[id] = to;
        emit Approval(o, to, id);
    }

    function getApproved(uint256 id) public view returns (address) {
        return _tokenApproval[id];
    }

    function setApprovalForAll(address op, bool ok) external {
        _operatorApproval[msg.sender][op] = ok;
        emit ApprovalForAll(msg.sender, op, ok);
    }

    function isApprovedForAll(address o, address op) public view returns (bool) {
        return _operatorApproval[o][op];
    }

    function transferFrom(address from, address to, uint256 id) public {
        address o = ownerOf(id);
        require(o == from, "wrong from");
        require(msg.sender == o || getApproved(id) == msg.sender || isApprovedForAll(o, msg.sender), "not auth");
        // clear approval
        _tokenApproval[id] = address(0);
        if (to == address(0)) {
            // burn
            _owner[id] = address(0);
            emit Transfer(from, address(0), id);
        } else {
            _owner[id] = to;
            emit Transfer(from, to, id);
        }
    }

    function safeTransferFrom(address from, address to, uint256 id) external {
        transferFrom(from, to, id);
    }

    function safeTransferFrom(address from, address to, uint256 id, bytes calldata) external {
        // Call internal logic directly; don't try to call the external overload.
        transferFrom(from, to, id);
    }

    function burn(uint256 id) external {
        require(ownerOf(id) == msg.sender, "not owner");
        transferFrom(msg.sender, address(0), id);
    }
}

/// ===== Minimal burnable ERC1155 used only for tests =====
contract BurnableERC1155 {
    // ERC165
    function supportsInterface(bytes4 iid) external pure returns (bool) {
        return iid == 0x01ffc9a7 /* ERC165 */ || iid == 0xd9b67a26; /* ERC1155 */
    }

    mapping(address => mapping(uint256 => uint256)) private _bal;
    mapping(address => mapping(address => bool)) private _op;

    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function mint(address to, uint256 id, uint256 qty) external {
        _bal[to][id] += qty;
        emit TransferSingle(msg.sender, address(0), to, id, qty);
    }

    function balanceOf(address a, uint256 id) external view returns (uint256) {
        return _bal[a][id];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _op[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address a, address operator) external view returns (bool) {
        return _op[a][operator];
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 qty, bytes calldata) external {
        require(from == msg.sender || _op[from][msg.sender], "not auth");
        require(_bal[from][id] >= qty, "insufficient");
        _bal[from][id] -= qty;
        if (to != address(0)) {
            _bal[to][id] += qty;
        }
        emit TransferSingle(msg.sender, from, to, id, qty);
        // Receiver acceptance omitted for tests
    }

    function burn(address from, uint256 id, uint256 qty) external {
        require(from == msg.sender || _op[from][msg.sender], "not auth");
        require(_bal[from][id] >= qty, "insufficient");
        _bal[from][id] -= qty;
        emit TransferSingle(msg.sender, from, address(0), id, qty);
    }
}

// This seeds a couple of flows so the contract holds some ETH, then asserts:
// sum of per-address proceeds == getter.getBalance() == address(diamond).balance

contract NonReceiver {
    receive() external payable {}
}

contract StrictERC721 is ERC721 {
    constructor() ERC721("Strict721", "S721") {}

    function mint(address to, uint256 id) external {
        // _safeMint enforces ERC721Receiver on contracts
        _safeMint(to, id);
    }
}

contract StrictERC1155 is ERC1155 {
    constructor() ERC1155("") {}

    function mint(address to, uint256 id, uint256 amt) external {
        // _mint + your later safeTransferFrom will enforce ERC1155Receiver on contracts
        _mint(to, id, amt, "");
    }
}

// mocks for testing against attack vectors

// Reenters purchaseListing from the buyer's ERC721 receiver hook
contract ReenteringReceiver721 {
    IdeationMarketFacet public market;
    uint128 public listingId;
    uint256 public price;
    bool internal attacked;

    constructor(address _market, uint128 _id, uint256 _price) {
        market = IdeationMarketFacet(_market);
        listingId = _id;
        price = _price;
    }

    receive() external payable {}

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        if (!attacked) {
            attacked = true;
            // If this ever succeeds, fail the whole test.
            try market.purchaseListing{value: price}(listingId, price, address(0), 0, address(0), 0, 0, 0, address(0)) {
                revert("reentrant 721 purchase succeeded");
            } catch { /* expected to fail */ }
        }
        return this.onERC721Received.selector;
    }
}

// Reenters purchaseListing from the buyer's ERC1155 receiver hook
contract ReenteringReceiver1155 {
    IdeationMarketFacet public market;
    uint128 public listingId;
    uint256 public price;
    uint256 public qty;
    bool internal attacked;

    constructor(address _market, uint128 _id, uint256 _price, uint256 _qty) {
        market = IdeationMarketFacet(_market);
        listingId = _id;
        price = _price;
        qty = _qty;
    }

    receive() external payable {}

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns (bytes4) {
        if (!attacked) {
            attacked = true;
            // If this ever succeeds, fail the whole test.
            try market.purchaseListing{value: price}(
                listingId, price, address(0), qty, address(0), 0, 0, qty, address(0)
            ) {
                revert("reentrant 1155 purchase succeeded");
            } catch { /* expected to fail */ }
        }
        return IERC1155ReceiverLike.onERC1155Received.selector;
    }
}

// Claims ERC721 but reverts during transfer (behavioral liar)
contract LiarERC721 {
    mapping(uint256 => address) internal _owner;
    mapping(uint256 => address) internal _tokenApproval;
    mapping(address => mapping(address => bool)) internal _op;

    function supportsInterface(bytes4 iid) external pure returns (bool) {
        return iid == 0x01ffc9a7 /* ERC165 */ || iid == 0x80ac58cd; /* ERC721 */
    }

    function mint(address to, uint256 id) external {
        _owner[id] = to;
    }

    function ownerOf(uint256 id) external view returns (address) {
        return _owner[id];
    }

    function balanceOf(address) external pure returns (uint256) {
        return 1;
    } // dummy

    function approve(address to, uint256 id) external {
        require(msg.sender == _owner[id], "not owner");
        _tokenApproval[id] = to;
    }

    function getApproved(uint256 id) external view returns (address) {
        return _tokenApproval[id];
    }

    function setApprovalForAll(address op, bool ok) external {
        _op[msg.sender][op] = ok;
    }

    function isApprovedForAll(address a, address op) external view returns (bool) {
        return _op[a][op];
    }

    function transferFrom(address from, address, /*to*/ uint256 id) public view {
        require(from == _owner[id], "wrong from");
        revert("liar721: transfer breaks");
    }

    function safeTransferFrom(address from, address to, uint256 id) external view {
        transferFrom(from, to, id);
    }

    function safeTransferFrom(address from, address to, uint256 id, bytes calldata) external view {
        transferFrom(from, to, id);
    }
}

// Claims ERC1155 but reverts during transfer (behavioral liar)
contract LiarERC1155 {
    mapping(uint256 => mapping(address => uint256)) internal _bal;
    mapping(address => mapping(address => bool)) internal _op;

    function supportsInterface(bytes4 iid) external pure returns (bool) {
        return iid == 0x01ffc9a7 /* ERC165 */ || iid == 0xd9b67a26; /* ERC1155 */
    }

    function mint(address to, uint256 id, uint256 qty) external {
        _bal[id][to] += qty;
    }

    function balanceOf(address a, uint256 id) external view returns (uint256) {
        return _bal[id][a];
    }

    function setApprovalForAll(address op, bool ok) external {
        _op[msg.sender][op] = ok;
    }

    function isApprovedForAll(address a, address op) external view returns (bool) {
        return _op[a][op];
    }

    function safeTransferFrom(address from, address, /*to*/ uint256 id, uint256 qty, bytes calldata) external view {
        require(from == msg.sender || _op[from][msg.sender], "not auth");
        require(_bal[id][from] >= qty, "insufficient");
        revert("liar1155: transfer breaks");
    }
}

// During transfer, attempts to call admin setter on the market
contract MaliciousAdminERC721 {
    mapping(uint256 => address) internal _owner;
    mapping(uint256 => address) internal _tokenApproval;
    mapping(address => mapping(address => bool)) internal _op;
    IdeationMarketFacet public market;
    bool internal attacked;

    constructor(address _market) {
        market = IdeationMarketFacet(_market);
    }

    function supportsInterface(bytes4 iid) external pure returns (bool) {
        return iid == 0x01ffc9a7 /* ERC165 */ || iid == 0x80ac58cd; /* ERC721 */
    }

    function mint(address to, uint256 id) external {
        _owner[id] = to;
    }

    function ownerOf(uint256 id) external view returns (address) {
        return _owner[id];
    }

    function balanceOf(address) external pure returns (uint256) {
        return 1;
    } // dummy

    function approve(address to, uint256 id) external {
        require(msg.sender == _owner[id], "not owner");
        _tokenApproval[id] = to;
    }

    function getApproved(uint256 id) external view returns (address) {
        return _tokenApproval[id];
    }

    function setApprovalForAll(address op, bool ok) external {
        _op[msg.sender][op] = ok;
    }

    function isApprovedForAll(address a, address op) external view returns (bool) {
        return _op[a][op];
    }

    function transferFrom(address from, address to, uint256 id) public {
        require(from == _owner[id], "wrong from");
        require(msg.sender == from || msg.sender == _tokenApproval[id] || _op[from][msg.sender], "not auth");

        if (!attacked) {
            attacked = true;
            // Must revert; if it ever succeeds the test should fail.
            try market.setInnovationFee(777) {
                revert("setInnovationFee succeeded from token");
            } catch { /* expected */ }
        }

        _tokenApproval[id] = address(0);
        _owner[id] = to;
    }

    function safeTransferFrom(address from, address to, uint256 id) external {
        transferFrom(from, to, id);
    }

    function safeTransferFrom(address from, address to, uint256 id, bytes calldata) external {
        transferFrom(from, to, id);
    }
}

// Malicious ERC1155 that attempts reentrancy during safeTransferFrom
contract MaliciousERC1155 {
    mapping(uint256 => mapping(address => uint256)) internal _bal;
    mapping(address => mapping(address => bool)) internal _op;
    IdeationMarketFacet public market;
    bool internal attacked;

    constructor(address _market) {
        market = IdeationMarketFacet(_market);
    }

    function supportsInterface(bytes4 iid) external pure returns (bool) {
        return iid == 0x01ffc9a7 /* ERC165 */ || iid == 0xd9b67a26; /* ERC1155 */
    }

    function mint(address to, uint256 id, uint256 qty) external {
        _bal[id][to] += qty;
    }

    function balanceOf(address a, uint256 id) external view returns (uint256) {
        return _bal[id][a];
    }

    function setApprovalForAll(address op, bool ok) external {
        _op[msg.sender][op] = ok;
    }

    function isApprovedForAll(address a, address op) external view returns (bool) {
        return _op[a][op];
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 qty, bytes calldata) external {
        require(from == msg.sender || _op[from][msg.sender], "not auth");
        require(_bal[id][from] >= qty, "insufficient");

        // Attempt reentrancy during transfer
        if (!attacked) {
            attacked = true;
            // Try to purchase the same listing again during the transfer
            // This should fail due to reentrancy guard
            try market.purchaseListing{value: 0}(
                0, // will fail anyway, but tests reentrancy protection
                0,
                address(0),
                0,
                address(0),
                0,
                0,
                0,
                address(0)
            ) {
                revert("malicious1155: reentrancy succeeded");
            } catch { /* expected to fail */ }
        }

        // Complete the transfer
        _bal[id][from] -= qty;
        _bal[id][to] += qty;

        // Call receiver hook if `to` is a contract
        if (to.code.length > 0) {
            try IERC1155ReceiverLike(to).onERC1155Received(msg.sender, from, id, qty, "") returns (bytes4 response) {
                require(response == IERC1155ReceiverLike.onERC1155Received.selector, "malicious1155: rejected");
            } catch {
                revert("malicious1155: receiver reverted");
            }
        }
    }
}

// --- Dummy upgrade facets for testing diamond cut operations ---
contract DummyUpgradeFacetV1 {
    function dummyFunction() external pure returns (uint256) {
        return 100;
    }
}

contract DummyUpgradeFacetV2 {
    function dummyFunction() external pure returns (uint256) {
        return 200;
    }
}

// -------------------------------------------------------------------------
// Additional test helper contracts
// -------------------------------------------------------------------------

interface IDummyUpgrade {
    function dummyFunction() external pure returns (uint256);
}

contract InitWriteFee {
    function initSetFee(uint32 newFee) external {
        AppStorage storage s = LibAppStorage.appStorage();
        s.innovationFee = newFee;
    }
}

contract LayoutGuardInitGood {
    error LayoutMismatch();

    function initCheckLayout(uint32 marker) external {
        AppStorage storage s = LibAppStorage.appStorage();

        uint32 prev = s.innovationFee;
        s.innovationFee = marker;

        uint32 got = GetterFacet(address(this)).getInnovationFee();
        if (got != marker) revert LayoutMismatch();

        s.innovationFee = prev;
    }
}

library LibAppStorage_Bad {
    bytes32 constant APP_STORAGE_POSITION = keccak256("diamond.standard.app.storage");

    struct BadAppStorage {
        uint256 __gap0;
        uint32 innovationFee;
    }

    function appStorage() internal pure returns (BadAppStorage storage s) {
        bytes32 p = APP_STORAGE_POSITION;
        assembly {
            s.slot := p
        }
    }
}

contract LayoutGuardInitBad {
    error LayoutMismatch();

    function initCheckLayout(uint32 marker) external {
        LibAppStorage_Bad.BadAppStorage storage s = LibAppStorage_Bad.appStorage();

        uint32 prev = s.innovationFee;
        s.innovationFee = marker;

        uint32 got = GetterFacet(address(this)).getInnovationFee();
        if (got != marker) revert LayoutMismatch();

        s.innovationFee = prev;
    }
}

contract DualFacet {
    function a() external pure returns (uint256) {
        return 11;
    }

    function b() external pure returns (uint256) {
        return 22;
    }
}

// Used by multiple tests to validate storage collision / drift detection.
library LibBadAppSlot {
    bytes32 constant APP_SLOT = keccak256("diamond.standard.app.storage");

    function appS() internal pure returns (AppStorage storage s) {
        bytes32 p = APP_SLOT;
        assembly {
            s.slot := p
        }
    }
}

contract BadFacetAppSmash {
    function smash(uint32 newFee, uint16 newMax) external {
        AppStorage storage s = LibBadAppSlot.appS();
        s.innovationFee = newFee;
        s.buyerWhitelistMaxBatchSize = newMax;
    }
}

contract MaliciousInitTryAdmin {
    function initTryAdmin(address newOwner, uint32 newFee) external {
        try IERC173(address(this)).transferOwnership(newOwner) {} catch {}
        try IdeationMarketFacet(address(this)).setInnovationFee(newFee) {} catch {}
    }
}

contract SellerReenterOnReceive {
    IdeationMarketFacet public market;
    bool public attempted;
    bool public reentryFailed;
    uint128 public targetListingId;
    uint256 public targetPrice;

    constructor(address _market) {
        market = IdeationMarketFacet(_market);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {
        if (attempted) return;
        attempted = true;

        try market.purchaseListing{value: targetPrice}(
            targetListingId, targetPrice, address(0), 0, address(0), 0, 0, 0, address(0)
        ) {
            revert("seller receive reentrancy succeeded");
        } catch {
            reentryFailed = true;
        }
    }

    function setReentryTarget(uint128 _listingId, uint256 _price) external {
        targetListingId = _listingId;
        targetPrice = _price;
    }

    function approveAndListERC721(address diamondAddr, address token, uint256 tokenId, uint256 price)
        external
        returns (uint128 listingId)
    {
        StrictERC721(token).approve(diamondAddr, tokenId);
        market.createListing(
            token, tokenId, address(0), price, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        listingId = GetterFacet(diamondAddr).getNextListingId() - 1;
    }
}

contract SellerRevertOnReceive {
    IdeationMarketFacet public market;

    constructor(address _market) {
        market = IdeationMarketFacet(_market);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {
        revert("seller cannot receive ETH");
    }

    function approveAndListERC721(address diamondAddr, address token, uint256 tokenId, uint256 price)
        external
        returns (uint128 listingId)
    {
        StrictERC721(token).approve(diamondAddr, tokenId);
        market.createListing(
            token, tokenId, address(0), price, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        listingId = GetterFacet(diamondAddr).getNextListingId() - 1;
    }
}

error RevertingInit__Boom();

contract RevertingInit {
    function init() external pure {
        revert RevertingInit__Boom();
    }
}

// --- ERC20 helpers/mocks ---

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "allowance");
        allowance[from][msg.sender] = allowed - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

contract MockERC20Ext {
    string public name;
    string public symbol;
    uint8 public decimals;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "allowance");
        allowance[from][msg.sender] = allowed - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

contract MockERC20NoReturn {
    string public name;
    string public symbol;
    uint8 public decimals;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "insufficient allowance");
        require(balanceOf[from] >= amount, "insufficient balance");
        allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

contract MaliciousERC20Reverting {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        revert("MaliciousERC20: transfer failed");
    }
}

contract MaliciousERC20ReturnsFalse {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        require(balanceOf[from] >= amount, "insufficient balance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return false;
    }
}

contract FeeOnTransferERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        require(balanceOf[from] >= amount, "insufficient balance");

        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;

        uint256 actualAmount = amount / 2;
        balanceOf[to] += actualAmount;

        return true;
    }
}

contract ReentrantERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public marketplace;
    uint128 public targetListingId;
    bool public hasReentered;

    constructor(address _marketplace) {
        marketplace = _marketplace;
    }

    function setTarget(uint128 listingId) external {
        targetListingId = listingId;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        require(balanceOf[from] >= amount, "insufficient balance");

        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        if (!hasReentered && targetListingId != 0 && to != from) {
            hasReentered = true;
            IdeationMarketFacet(marketplace).purchaseListing(
                targetListingId, 1 ether, address(this), 0, address(0), 0, 0, 0, address(0)
            );
        }

        return true;
    }
}

contract HighGasERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(uint256 => uint256) public gasWaster;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        require(balanceOf[from] >= amount, "insufficient balance");

        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        for (uint256 i = 0; i < 50; i++) {
            gasWaster[i] = i;
        }

        return true;
    }
}

contract ConditionalFailureERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    address public failOnTransferTo;

    function setFailOnTransferTo(address target) external {
        failOnTransferTo = target;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        require(balanceOf[from] >= amount, "insufficient balance");

        if (to == failOnTransferTo) {
            revert("ConditionalFailure: transfer to target blocked");
        }

        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        return true;
    }
}

contract MockERC20WithDecimals {
    string public name;
    string public symbol;
    uint8 public decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        require(balanceOf[from] >= amount, "insufficient balance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

// --- Helpers for loupe edge tests ---

contract SwapFacetA {
    function a() external pure returns (uint256) {
        return 1;
    }
}

contract SwapFacetB {
    function b() external pure returns (uint256) {
        return 2;
    }
}

contract MultiSelFacet {
    function f1() external pure returns (uint256) {
        return 1;
    }

    function f2() external pure returns (uint256) {
        return 2;
    }
}

// --- Handlers used by StorageCollisionTest invariant ---

interface ISellerHandlerView {
    function lastListingId721() external view returns (uint128);
}

contract SellerHandler {
    IdeationMarketFacet public market;
    GetterFacet public getter;
    BuyerWhitelistFacet public buyers;
    MockERC721 public erc721;
    MockERC1155 public erc1155;

    address public diamond;
    address public buyerAddr;

    uint128 public lastListingId721;
    bool public hasListing721;

    constructor(address _diamond, address _buyers, address _erc721, address _erc1155) {
        diamond = _diamond;
        market = IdeationMarketFacet(_diamond);
        getter = GetterFacet(_diamond);
        buyers = BuyerWhitelistFacet(_buyers);
        erc721 = MockERC721(_erc721);
        erc1155 = MockERC1155(_erc1155);
    }

    function setBuyer(address _buyer) external {
        buyerAddr = _buyer;
    }

    function setupApprovals() external {
        erc721.approve(diamond, 100);
        erc1155.setApprovalForAll(diamond, true);
    }

    function create721Listing() external {
        if (hasListing721) return;

        market.createListing(
            address(erc721), 100, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        lastListingId721 = getter.getNextListingId() - 1;
        hasListing721 = true;
    }

    function enableWhitelist() external {
        if (!hasListing721) return;
        Listing memory listing = getter.getListingByListingId(lastListingId721);
        market.updateListing(
            lastListingId721,
            listing.price,
            listing.currency,
            listing.desiredTokenAddress,
            listing.desiredTokenId,
            listing.desiredErc1155Quantity,
            listing.erc1155Quantity,
            true,
            listing.partialBuyEnabled,
            new address[](0)
        );
    }

    function addBuyerToWhitelist() external {
        if (!hasListing721 || buyerAddr == address(0)) return;
        address[] memory a = new address[](1);
        a[0] = buyerAddr;
        buyers.addBuyerWhitelistAddresses(lastListingId721, a);
    }

    function removeBuyerFromWhitelist() external {
        if (!hasListing721 || buyerAddr == address(0)) return;
        address[] memory a = new address[](1);
        a[0] = buyerAddr;
        buyers.removeBuyerWhitelistAddresses(lastListingId721, a);
    }

    function cancel721() external {
        if (!hasListing721) return;
        market.cancelListing(lastListingId721);
        hasListing721 = false;
        lastListingId721 = 0;
    }

    function create1155Listing() external {
        market.createListing(
            address(erc1155), 5, address(this), 2 ether, address(0), address(0), 0, 0, 2, false, false, new address[](0)
        );
    }
}

contract BuyerHandler {
    IdeationMarketFacet public market;
    GetterFacet public getter;
    ISellerHandlerView public sellerH;

    constructor(address _diamond, address _getter, address _sellerH) {
        market = IdeationMarketFacet(_diamond);
        getter = GetterFacet(_getter);
        sellerH = ISellerHandlerView(_sellerH);
    }

    receive() external payable {}

    function buySeller721() external {
        uint128 id = sellerH.lastListingId721();
        if (id == 0) return;

        Listing memory listing = getter.getListingByListingId(id);
        if (listing.erc1155Quantity != 0) return;

        market.purchaseListing{value: listing.price}(
            id,
            listing.price,
            listing.currency,
            listing.erc1155Quantity,
            listing.desiredTokenAddress,
            listing.desiredTokenId,
            listing.desiredErc1155Quantity,
            0,
            address(0)
        );
    }

    function setSeller(address _sellerH) external {
        sellerH = ISellerHandlerView(_sellerH);
    }
}

// --- Invariant handler used by InvariantTest ---

contract InvariantHandler {
    using stdStorage for StdStorage;

    Vm internal constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    IdeationMarketFacet public immutable market;
    GetterFacet public immutable getter;
    CollectionWhitelistFacet public immutable collections;

    MockERC721Royalty public immutable erc721Roy;
    MockERC1155 public immutable erc1155;

    address public immutable owner;
    address public immutable seller;

    address[] public buyers;
    address public royaltyReceiver;

    uint128[] internal _listingIds;

    mapping(address => bool) internal _seen;
    address[] internal _actors;

    uint256 internal _next721Id = 100;
    uint256 internal _next1155Id = 200;
    uint256 internal _nextSwap721Wanted = 10_000;
    uint256 internal _nextSwap1155Wanted = 20_000;

    constructor(
        address _market,
        address _getter,
        address _collections,
        address _erc721Roy,
        address _erc1155,
        address _owner,
        address _seller,
        address[] memory _buyers
    ) {
        market = IdeationMarketFacet(_market);
        getter = GetterFacet(_getter);
        collections = CollectionWhitelistFacet(_collections);
        erc721Roy = MockERC721Royalty(_erc721Roy);
        erc1155 = MockERC1155(_erc1155);
        owner = _owner;
        seller = _seller;
        buyers = _buyers;

        royaltyReceiver = vm.addr(0x7777);

        _addActor(owner);
        _addActor(seller);
        _addActor(royaltyReceiver);
        for (uint256 i; i < buyers.length; i++) {
            _addActor(buyers[i]);
        }
    }

    function _addActor(address a) internal {
        if (!_seen[a]) {
            _seen[a] = true;
            _actors.push(a);
        }
    }

    function _pushListing(uint128 id) internal {
        _listingIds.push(id);
    }

    function _randomListing(uint256 seed) internal view returns (uint128 id) {
        if (_listingIds.length == 0) return 0;
        return _listingIds[seed % _listingIds.length];
    }

    function list721(uint256 priceSeed, uint256 royaltyBpsSeed) external {
        uint256 tokenId = ++_next721Id;

        vm.prank(seller);
        erc721Roy.mint(seller, tokenId);
        vm.prank(seller);
        erc721Roy.approve(address(market), tokenId);

        uint256 bps = royaltyBpsSeed % 20_000;
        erc721Roy.setRoyalty(royaltyReceiver, bps);
        _addActor(royaltyReceiver);

        uint256 price = 0.01 ether + (priceSeed % 1 ether);

        vm.prank(seller);
        market.createListing(
            address(erc721Roy),
            tokenId,
            address(0),
            price,
            address(0),
            address(0),
            0,
            0,
            0,
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        _pushListing(id);
    }

    function list1155(uint256 unitSeed, uint256 qtySeed, bool _partial) external {
        uint256 id = ++_next1155Id;
        uint256 qty = 1 + (qtySeed % 8);
        uint256 unit = 0.005 ether + (unitSeed % 5e15);
        bool allowPartial = _partial && qty > 1;

        uint256 price = unit * qty;

        vm.prank(seller);
        erc1155.mint(seller, id, qty);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(market), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155),
            id,
            seller,
            price,
            address(0),
            address(0),
            0,
            0,
            qty,
            false,
            allowPartial,
            new address[](0)
        );
        uint128 lid = getter.getNextListingId() - 1;
        _pushListing(lid);
    }

    function listSwap721For721(uint256) external {
        uint256 offeredId = ++_next721Id;
        uint256 wantedId = ++_nextSwap721Wanted;

        vm.prank(seller);
        erc721Roy.mint(seller, offeredId);
        vm.prank(seller);
        erc721Roy.approve(address(market), offeredId);

        vm.prank(seller);
        market.createListing(
            address(erc721Roy),
            offeredId,
            address(0),
            0,
            address(0),
            address(erc721Roy),
            wantedId,
            0,
            0,
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        _pushListing(id);
    }

    function listSwap721For1155(uint256 qtySeed) external {
        uint256 offeredId = ++_next721Id;
        uint256 wantedId = ++_nextSwap1155Wanted;
        uint256 wantedQty = 1 + (qtySeed % 5);

        vm.prank(seller);
        erc721Roy.mint(seller, offeredId);
        vm.prank(seller);
        erc721Roy.approve(address(market), offeredId);

        vm.prank(seller);
        market.createListing(
            address(erc721Roy),
            offeredId,
            address(0),
            0,
            address(0),
            address(erc1155),
            wantedId,
            wantedQty,
            0,
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        _pushListing(id);
    }

    function purchase(uint256 pickSeed, uint256 qtySeed, uint256 buyerSeed) external {
        uint128 id = _randomListing(pickSeed);
        if (id == 0) return;

        Listing memory listing = getter.getListingByListingId(id);
        if (listing.seller == address(0) || listing.desiredTokenAddress != address(0)) return;

        address buyer = buyers[buyerSeed % buyers.length];

        uint256 buyQty = (listing.erc1155Quantity == 0) ? 0 : (1 + (qtySeed % listing.erc1155Quantity));
        if (!listing.partialBuyEnabled && listing.erc1155Quantity > 0) buyQty = listing.erc1155Quantity;

        uint256 purchasePrice = listing.price;
        if (buyQty > 0 && buyQty != listing.erc1155Quantity) {
            purchasePrice = listing.price * buyQty / listing.erc1155Quantity;
        }

        vm.deal(buyer, buyer.balance + purchasePrice);

        vm.prank(buyer);
        market.purchaseListing{value: purchasePrice}(
            id,
            listing.price,
            address(0),
            listing.erc1155Quantity,
            listing.desiredTokenAddress,
            listing.desiredTokenId,
            listing.desiredErc1155Quantity,
            buyQty,
            address(0)
        );
    }
}
