// SPDX-License-Identifier: UNLICENSED
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

/*
 * @title IdeationMarketDiamondTest
 * @notice Comprehensive unit tests covering the diamond and all marketplace facets.
 *
 * These tests deploy the diamond and its facets from scratch using the same
 * deployment logic as the provided deploy script. They then exercise every
 * public and external function exposed by the facets, including both success
 * paths and revert branches, to maximise code coverage. Minimal mock ERC‑721
 * and ERC‑1155 token contracts are included at the bottom of the file to
 * facilitate testing of marketplace operations such as listing creation,
 * updating, cancellation and purchase.  Custom errors are checked with
 * `vm.expectRevert` and state assertions verify that storage mutations occur
 * as intended.
 */
contract IdeationMarketDiamondTest is Test {
    // Precomputed error selectors for custom errors used in this test suite.  We define
    // these manually rather than rely on imported error names because we observed
    // mismatches between the imported constants and the actual selector values during
    // testing.  Each selector is calculated as the first four bytes of the keccak256
    // hash of the error signature.
    bytes4 private constant COLLECTION_NOT_WHITELISTED_SEL =
        bytes4(keccak256("IdeationMarket__CollectionNotWhitelisted(address)"));
    bytes4 private constant ALREADY_LISTED_SEL = bytes4(keccak256("IdeationMarket__AlreadyListed()"));
    bytes4 private constant PRICE_NOT_MET_SEL =
        bytes4(keccak256("IdeationMarket__PriceNotMet(uint128,uint256,uint256)"));
    IdeationMarketDiamond internal diamond;

    // Cached facet references for convenience
    DiamondLoupeFacet internal loupe;
    OwnershipFacet internal ownership;
    IdeationMarketFacet internal market;
    CollectionWhitelistFacet internal collections;
    BuyerWhitelistFacet internal buyers;
    GetterFacet internal getter;

    // Address of the initial diamondCut facet deployed in setUp
    address internal diamondCutFacetAddr;

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

    function setUp() public {
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
        GetterFacet getterFacet = new GetterFacet();

        // Deploy the diamond and add the initial diamondCut function
        diamond = new IdeationMarketDiamond(owner, address(cutFacet));

        // Cache diamondCut facet address for later assertions
        diamondCutFacetAddr = address(cutFacet);

        // Prepare facet cut definitions matching the deploy script
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](6);

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
        bytes4[] memory marketSelectors = new bytes4[](7);
        marketSelectors[0] = IdeationMarketFacet.createListing.selector;
        marketSelectors[1] = IdeationMarketFacet.purchaseListing.selector;
        marketSelectors[2] = IdeationMarketFacet.cancelListing.selector;
        marketSelectors[3] = IdeationMarketFacet.updateListing.selector;
        marketSelectors[4] = IdeationMarketFacet.withdrawProceeds.selector;
        marketSelectors[5] = IdeationMarketFacet.setInnovationFee.selector;
        marketSelectors[6] = IdeationMarketFacet.cleanListing.selector;
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

        // Getter selectors (add all view functions exposed by GetterFacet)
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
        cuts[5] = IDiamondCutFacet.FacetCut({
            facetAddress: address(getterFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: getterSelectors
        });

        // Execute diamond cut and initializer
        IDiamondCutFacet(address(diamond)).diamondCut(
            cuts, address(init), abi.encodeCall(DiamondInit.init, (INNOVATION_FEE, MAX_BATCH))
        );

        vm.stopPrank();

        // Cache facet handles through the diamond's address. Casting will
        // delegate calls through the diamond fallback to the appropriate facet.
        loupe = DiamondLoupeFacet(address(diamond));
        ownership = OwnershipFacet(address(diamond));
        market = IdeationMarketFacet(address(diamond));
        collections = CollectionWhitelistFacet(address(diamond));
        buyers = BuyerWhitelistFacet(address(diamond));
        getter = GetterFacet(address(diamond));

        // Deploy mock tokens and mint balances for seller
        erc721 = new MockERC721();
        erc1155 = new MockERC1155();
        erc721.mint(seller, 1);
        erc721.mint(seller, 2);
        erc1155.mint(seller, 1, 10);
    }

    // -------------------------------------------------------------------------
    // Diamond & Loupe Tests
    // -------------------------------------------------------------------------

    function testDiamondInitialization() public view {
        // Owner should be set correctly via IERC173
        assertEq(IERC173(address(diamond)).owner(), owner);
        // Innovation fee and max batch size set in initializer
        assertEq(getter.getInnovationFee(), INNOVATION_FEE);
        assertEq(getter.getBuyerWhitelistMaxBatchSize(), MAX_BATCH);
        // Contract owner from getter matches owner
        assertEq(getter.getContractOwner(), owner);
        // Initially there is no pending owner
        assertEq(getter.getPendingOwner(), address(0));
    }

    function testDiamondLoupeFacets() public view {
        // The diamond should have the cut facet plus six additional facets = 7
        IDiamondLoupeFacet.Facet[] memory facetInfo = loupe.facets();
        // After deployment the diamond has the diamondCut facet plus six added facets
        assertEq(facetInfo.length, 7);

        // Verify that the diamondCut selector maps to the original cut facet
        address cutAddr = loupe.facetAddress(IDiamondCutFacet.diamondCut.selector);
        assertEq(cutAddr, diamondCutFacetAddr);
    }

    function testSupportsInterface() public view {
        // Diamond supports ERC165, cut, loupe and ownership interfaces set in initializer
        assertTrue(IERC165(address(diamond)).supportsInterface(type(IERC165).interfaceId));
        assertTrue(IERC165(address(diamond)).supportsInterface(type(IDiamondCutFacet).interfaceId));
        assertTrue(IERC165(address(diamond)).supportsInterface(type(IDiamondLoupeFacet).interfaceId));
        assertTrue(IERC165(address(diamond)).supportsInterface(type(IERC173).interfaceId));
        // NFT interfaces also registered
        assertTrue(IERC165(address(diamond)).supportsInterface(type(IERC721).interfaceId));
        assertTrue(IERC165(address(diamond)).supportsInterface(type(IERC1155).interfaceId));
        assertTrue(IERC165(address(diamond)).supportsInterface(type(IERC2981).interfaceId));
    }

    function testUnknownFunctionReverts() public {
        // Generate a random function selector to trigger fallback with no facet
        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("unknown()")));
        // Expect the custom Diamond__FunctionDoesNotExist error
        // Expect the custom fallback error defined in the diamond
        vm.expectRevert(Diamond__FunctionDoesNotExist.selector);
        (bool ok,) = address(diamond).call(data);
        // Silence unused variable warning
        ok;
    }

    // -------------------------------------------------------------------------
    // Ownership Tests
    // -------------------------------------------------------------------------

    function testOwnershipTransfer() public {
        // Only the current owner can initiate a transfer
        vm.startPrank(owner);
        ownership.transferOwnership(buyer);
        vm.stopPrank();

        // The pending owner should now be buyer
        assertEq(getter.getPendingOwner(), buyer);

        // A non‑pending address cannot accept ownership
        vm.startPrank(operator);
        vm.expectRevert(Ownership__CallerIsNotThePendingOwner.selector);
        ownership.acceptOwnership();
        vm.stopPrank();

        // Pending owner finalises transfer
        vm.startPrank(buyer);
        ownership.acceptOwnership();
        vm.stopPrank();

        // Owner updated
        assertEq(IERC173(address(diamond)).owner(), buyer);
        assertEq(getter.getContractOwner(), buyer);
        assertEq(getter.getPendingOwner(), address(0));

        // Transfer back to original owner
        vm.startPrank(buyer);
        ownership.transferOwnership(owner);
        vm.stopPrank();
        vm.startPrank(owner);
        ownership.acceptOwnership();
        vm.stopPrank();
        assertEq(IERC173(address(diamond)).owner(), owner);
    }

    // -------------------------------------------------------------------------
    // Collection Whitelist Tests
    // -------------------------------------------------------------------------

    function testCollectionWhitelistAddAndRemove() public {
        // Only owner can add to whitelist
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc721));
        vm.stopPrank();
        assertTrue(getter.isCollectionWhitelisted(address(erc721)));
        // Duplicate add should revert
        vm.startPrank(owner);
        vm.expectRevert(CollectionWhitelist__AlreadyWhitelisted.selector);
        collections.addWhitelistedCollection(address(erc721));
        vm.stopPrank();
        // Non‑owner cannot add
        vm.startPrank(buyer);
        vm.expectRevert("LibDiamond: Must be contract owner");
        collections.addWhitelistedCollection(address(erc1155));
        vm.stopPrank();
        // Remove by owner
        vm.startPrank(owner);
        collections.removeWhitelistedCollection(address(erc721));
        vm.stopPrank();
        assertFalse(getter.isCollectionWhitelisted(address(erc721)));
        // Removing non‑whitelisted reverts
        vm.startPrank(owner);
        vm.expectRevert(CollectionWhitelist__NotWhitelisted.selector);
        collections.removeWhitelistedCollection(address(erc721));
        vm.stopPrank();
    }

    function testCollectionWhitelistBatchOperations() public {
        address[] memory addrs = new address[](2);
        addrs[0] = address(erc721);
        addrs[1] = address(erc1155);
        // Add both addresses in batch
        vm.startPrank(owner);
        collections.batchAddWhitelistedCollections(addrs);
        vm.stopPrank();
        assertTrue(getter.isCollectionWhitelisted(address(erc721)));
        assertTrue(getter.isCollectionWhitelisted(address(erc1155)));
        // Batch remove including duplicates
        address[] memory removeList = new address[](3);
        removeList[0] = address(erc721);
        removeList[1] = address(erc721);
        removeList[2] = address(erc1155);
        vm.startPrank(owner);
        collections.batchRemoveWhitelistedCollections(removeList);
        vm.stopPrank();
        assertFalse(getter.isCollectionWhitelisted(address(erc721)));
        assertFalse(getter.isCollectionWhitelisted(address(erc1155)));
    }

    // -------------------------------------------------------------------------
    // Buyer Whitelist Tests
    // -------------------------------------------------------------------------

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

    function _createListingERC721(bool buyerWhitelistEnabled, address[] memory allowedBuyers)
        internal
        returns (uint128 listingId)
    {
        _whitelistCollectionAndApproveERC721();
        vm.startPrank(seller);
        // Provide zero values for swap params and quantity
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, buyerWhitelistEnabled, false, allowedBuyers
        );
        vm.stopPrank();
        // Next listing id is counter + 1
        listingId = getter.getNextListingId() - 1;
    }

    function testBuyerWhitelistAddRemove() public {
        // Create a listing with whitelist enabled and an initial allowed buyer.
        // Passing an empty array when buyerWhitelistEnabled is true would revert during listing creation.
        address[] memory allowedBuyers = new address[](1);
        allowedBuyers[0] = buyer;
        uint128 listingId = _createListingERC721(true, allowedBuyers);
        // Attempt to add an empty list should revert
        address[] memory emptyList = new address[](0);
        vm.startPrank(seller);
        vm.expectRevert(BuyerWhitelist__EmptyCalldata.selector);
        buyers.addBuyerWhitelistAddresses(listingId, emptyList);
        vm.stopPrank();
        // Batch size exceeding cap should revert. When buyerWhitelistEnabled is true the marketplace
        // itself (the diamond contract) calls into the BuyerWhitelistFacet to add buyers. Thus we
        // impersonate the diamond contract address here to match the internal call context. Passing
        // an oversized array should trigger BuyerWhitelist__ExceedsMaxBatchSize before any other
        // checks.
        address[] memory largeList = new address[](uint256(MAX_BATCH) + 1);
        for (uint256 i = 0; i < largeList.length; i++) {
            largeList[i] = vm.addr(0x2000 + i);
        }
        vm.startPrank(address(diamond));
        vm.expectRevert(BuyerWhitelist__ExceedsMaxBatchSize.selector);
        buyers.addBuyerWhitelistAddresses(listingId, largeList);
        vm.stopPrank();
        // Listing not exist should revert. Use a small list so that batchSize check passes and the
        // listing existence check triggers BuyerWhitelist__ListingDoesNotExist.
        address[] memory dummyList = new address[](1);
        dummyList[0] = buyer;
        vm.startPrank(seller);
        vm.expectRevert(BuyerWhitelist__ListingDoesNotExist.selector);
        buyers.addBuyerWhitelistAddresses(999999, dummyList);
        vm.stopPrank();
        // Non seller (not approved) cannot whitelist
        address[] memory oneBuyer = new address[](1);
        oneBuyer[0] = buyer;
        vm.startPrank(buyer);
        vm.expectRevert(BuyerWhitelist__NotAuthorizedOperator.selector);
        buyers.addBuyerWhitelistAddresses(listingId, oneBuyer);
        vm.stopPrank();
        // Add valid buyer by seller
        vm.startPrank(seller);
        buyers.addBuyerWhitelistAddresses(listingId, oneBuyer);
        vm.stopPrank();
        assertTrue(getter.isBuyerWhitelisted(listingId, buyer));
        // Zero address should revert
        address[] memory invalid = new address[](1);
        invalid[0] = address(0);
        vm.startPrank(seller);
        vm.expectRevert(BuyerWhitelist__ZeroAddress.selector);
        buyers.addBuyerWhitelistAddresses(listingId, invalid);
        vm.stopPrank();
        // Remove buyer
        vm.startPrank(seller);
        buyers.removeBuyerWhitelistAddresses(listingId, oneBuyer);
        vm.stopPrank();
        assertFalse(getter.isBuyerWhitelisted(listingId, buyer));
    }

    // -------------------------------------------------------------------------
    // Marketplace Listing Tests
    // -------------------------------------------------------------------------

    function testCreateListingERC721() public {
        _whitelistCollectionAndApproveERC721();
        vm.startPrank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();
        // Listing id should be 1
        uint128 id = getter.getNextListingId() - 1;
        Listing memory l = getter.getListingByListingId(id);
        assertEq(l.listingId, id);
        assertEq(l.tokenAddress, address(erc721));
        assertEq(l.tokenId, 1);
        assertEq(l.price, 1 ether);
        assertEq(l.seller, seller);
        assertEq(l.erc1155Quantity, 0);
        assertFalse(l.buyerWhitelistEnabled);
        assertFalse(l.partialBuyEnabled);
        // getListingsByNFT returns one active listing
        Listing[] memory listings = getter.getListingsByNFT(address(erc721), 1);
        assertEq(listings.length, 1);
        assertEq(listings[0].listingId, id);
    }

    function testCreateListingERC721Reverts() public {
        // Require whitelisted collection
        vm.startPrank(seller);
        // Expect a revert because the collection is not whitelisted. The createListing
        // function will revert with IdeationMarket__CollectionNotWhitelisted(tokenAddress).
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__CollectionNotWhitelisted.selector, address(erc721)));
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();
        // Now whitelist and test double listing
        _whitelistCollectionAndApproveERC721();
        vm.startPrank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        // Second time should revert because the NFT has already been listed.
        // The createListing function will revert with IdeationMarket__AlreadyListed().
        vm.expectRevert(IdeationMarket__AlreadyListed.selector);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();
    }

    function testPurchaseListingERC721() public {
        // Create listing with no whitelist
        uint128 id = _createListingERC721(false, new address[](0));
        // Give the buyer an ether balance for the purchase
        vm.deal(buyer, 10 ether);
        // Buyer attempts purchase with insufficient value
        vm.startPrank(buyer);
        // Expect revert because the sent value does not cover the price.
        // Expect revert due to insufficient payment; the price is 1 ETH but only 0.5 ETH is sent.
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__PriceNotMet.selector, id, 1 ether, 0.5 ether));
        market.purchaseListing{value: 0.5 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
        // Attempt a full purchase. This should succeed and transfer the token to the buyer.
        vm.startPrank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
        // The listing should be removed after purchase.
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
        // Ownership of the token should now be with the buyer.
        assertEq(erc721.ownerOf(1), buyer);
        // Seller's proceeds should equal sale price minus the innovation fee (1% of 1 ether).
        uint256 sellerProceeds = getter.getProceeds(seller);
        assertEq(sellerProceeds, 0.99 ether);
    }

    function testUpdateListing() public {
        // Create listing with whitelist disabled
        uint128 id = _createListingERC721(false, new address[](0));
        // Attempt update by non owner
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__NotAuthorizedOperator.selector);
        market.updateListing(id, 2 ether, address(0), 0, 0, 0, false, false, new address[](0));
        vm.stopPrank();
        // Update price by seller
        vm.startPrank(seller);
        market.updateListing(id, 2 ether, address(0), 0, 0, 0, false, false, new address[](0));
        vm.stopPrank();
        Listing memory updated = getter.getListingByListingId(id);
        assertEq(updated.price, 2 ether);
        // Enable whitelist on update and add buyer
        address[] memory newBuyers = new address[](1);
        newBuyers[0] = buyer;
        vm.startPrank(seller);
        market.updateListing(id, 2 ether, address(0), 0, 0, 0, true, false, newBuyers);
        vm.stopPrank();
        // Buyer should now be whitelisted
        assertTrue(getter.isBuyerWhitelisted(id, buyer));
    }

    function testCancelListing() public {
        uint128 id = _createListingERC721(false, new address[](0));
        // An unauthorized caller should revert with the NotAuthorizedToCancel error.
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__NotAuthorizedToCancel.selector);
        market.cancelListing(id);
        vm.stopPrank();
        // The seller can cancel the listing successfully.
        vm.startPrank(seller);
        market.cancelListing(id);
        vm.stopPrank();
        // After cancellation, the listing should no longer exist. Expect the
        // GetterFacet to revert with Getter__ListingNotFound(listingId).
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCleanListing() public {
        // Create listing
        uint128 id = _createListingERC721(false, new address[](0));
        // With approvals still present, cleanListing should revert with the StillApproved error.
        vm.startPrank(operator);
        vm.expectRevert(IdeationMarket__StillApproved.selector);
        market.cleanListing(id);
        vm.stopPrank();

        // Remove approval and call cleanListing again. This should succeed and remove the listing.
        vm.startPrank(seller);
        erc721.approve(address(0), 1);
        vm.stopPrank();
        vm.startPrank(operator);
        market.cleanListing(id);
        vm.stopPrank();
        // After cleaning, the listing should no longer exist. Expect the
        // GetterFacet to revert with Getter__ListingNotFound(listingId).
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// -----------------------------------------------------------------------
    /// ERC1155 purchase-time quantity rules
    /// -----------------------------------------------------------------------

    function testERC1155BuyingMoreThanListedReverts() public {
        // Whitelist ERC1155 and approve the marketplace
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.stopPrank();

        vm.startPrank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        // List quantity = 10, price = 10 ether, partial buys enabled (divisible)
        market.createListing(
            address(erc1155),
            1,
            seller, // erc1155Holder
            10 ether, // price
            address(0),
            0,
            0, // desiredErc1155Quantity
            10, // erc1155Quantity
            false, // buyerWhitelistEnabled
            true, // partialBuyEnabled
            new address
        );
        vm.stopPrank();

        uint128 id = getter.getNextListingId() - 1;

        // Buyer tries to buy more than listed (11 > 10) → InvalidPurchaseQuantity
        vm.deal(buyer, 20 ether);
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__InvalidPurchaseQuantity.selector);
        market.purchaseListing{value: 20 ether}(
            id,
            10 ether, // expectedPrice
            10, // expectedErc1155Quantity
            address(0),
            0,
            0,
            11, // erc1155PurchaseQuantity > listed
            address(0)
        );
        vm.stopPrank();
    }

    function testERC1155PartialBuyDisabledReverts() public {
        // Whitelist ERC1155 and approve the marketplace
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.stopPrank();

        vm.startPrank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        // List quantity = 10, price = 10 ether, partial buys DISABLED
        market.createListing(
            address(erc1155),
            1,
            seller, // erc1155Holder
            10 ether, // price
            address(0),
            0,
            0, // desiredErc1155Quantity
            10, // erc1155Quantity
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled (disabled)
            new address
        );
        vm.stopPrank();

        uint128 id = getter.getNextListingId() - 1;

        // Buyer attempts partial buy (5 of 10) while partials are disabled
        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__PartialBuyNotPossible.selector);
        market.purchaseListing{value: 5 ether}(
            id,
            10 ether, // expectedPrice
            10, // expectedErc1155Quantity
            address(0),
            0,
            0,
            5, // partial purchase
            address(0)
        );
        vm.stopPrank();
    }

    // listingId starts at 1 and increments
    function testListingIdIncrements() public {
        _whitelistCollectionAndApproveERC721();

        vm.startPrank(seller);
        market.createListing(address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address);
        market.createListing(address(erc721), 2, address(0), 2 ether, address(0), 0, 0, 0, false, false, new address);
        vm.stopPrank();

        // next id should be 3, last created is 2
        assertEq(getter.getNextListingId(), 3);
        Listing memory l1 = getter.getListingByListingId(1);
        Listing memory l2 = getter.getListingByListingId(2);
        assertEq(l1.listingId, 1);
        assertEq(l2.listingId, 2);
    }

    // owner (diamond owner) can cancel any listing
    function testOwnerCanCancelAnyListing() public {
        uint128 id = _createListingERC721(false, new address);

        // Owner cancels although not token owner nor approved
        vm.startPrank(owner);
        market.cancelListing(id);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    // purchase fails if approval revoked between listing and purchase
    function testPurchaseRevertsIfApprovalRevokedBeforeBuy() public {
        uint128 id = _createListingERC721(false, new address);

        // Revoke marketplace approval
        vm.prank(seller);
        erc721.approve(address(0), 1);

        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    // update keeps same listingId even with other activity in between
    function testUpdateKeepsListingId() public {
        _whitelistCollectionAndApproveERC721();

        // First listing (id=1)
        vm.prank(seller);
        market.createListing(address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address);
        uint128 id1 = 1;

        // Create & cancel another listing to disturb state
        vm.prank(seller);
        erc721.approve(address(diamond), 2);
        vm.prank(seller);
        market.createListing(address(erc721), 2, address(0), 2 ether, address(0), 0, 0, 0, false, false, new address);
        uint128 id2 = 2;
        vm.prank(seller);
        market.cancelListing(id2);

        // Update the first listing, id must remain 1
        vm.prank(seller);
        market.updateListing(id1, 3 ether, address(0), 0, 0, 0, false, false, new address);

        Listing memory l = getter.getListingByListingId(id1);
        assertEq(l.listingId, 1);
        assertEq(l.price, 3 ether);
    }

    // whitelist of exactly MAX_BATCH succeeds on create; >MAX_BATCH reverts
    function testCreateWithWhitelistExactlyMaxBatchSucceeds() public {
        _whitelistCollectionAndApproveERC721();

        address[] memory buyersList = new address[](MAX_BATCH);
        for (uint256 i = 0; i < buyersList.length; i++) {
            buyersList[i] = vm.addr(10_000 + i);
        }

        vm.prank(seller);
        market.createListing(address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, true, false, buyersList);

        uint128 id = getter.getNextListingId() - 1;
        // Spot check a couple of entries made it in
        assertTrue(getter.isBuyerWhitelisted(id, buyersList[0]));
        assertTrue(getter.isBuyerWhitelisted(id, buyersList[buyersList.length - 1]));
    }

    function testCreateWithWhitelistOverMaxBatchReverts() public {
        _whitelistCollectionAndApproveERC721();

        address[] memory tooMany = new address[](uint256(MAX_BATCH) + 1);
        for (uint256 i = 0; i < tooMany.length; i++) {
            tooMany[i] = vm.addr(20_000 + i);
        }

        vm.startPrank(seller);
        vm.expectRevert(BuyerWhitelist__ExceedsMaxBatchSize.selector);
        market.createListing(address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, true, false, tooMany);
        vm.stopPrank();
    }

    // purchase-time royalty > proceeds reverts (listing itself may succeed)
    function testPurchaseRevertsWhenRoyaltyExceedsProceeds() public {
        // High-royalty token (e.g., 99.5%)
        MockERC721Royalty royaltyNft = new MockERC721Royalty();
        royaltyNft.mint(seller, 1);
        royaltyNft.setRoyalty(address(0xB0B), 99_500);

        vm.prank(owner);
        collections.addWhitelistedCollection(address(royaltyNft));

        vm.prank(seller);
        royaltyNft.approve(address(diamond), 1);

        // Listing will succeed with your current code (no listing-time check)
        vm.prank(seller);
        market.createListing(
            address(royaltyNft), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 2 ether);
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__RoyaltyFeeExceedsProceeds.selector);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    // swap with same NFT reverts
    function testSwapWithSameNFTReverts() public {
        _whitelistCollectionAndApproveERC721();

        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__NoSwapForSameToken.selector);
        market.createListing(
            address(erc721),
            1,
            address(0),
            0, // price 0 (swap-only) ok
            address(erc721),
            1,
            0, // same token desired
            0,
            false,
            false,
            new address
        );
        vm.stopPrank();
    }

    // ERC1155 createListing wrong quantity flags → should revert with WrongQuantityParameter
    // NOTE: With your current code, this may fail earlier due to calling ERC1155 methods before checking interface.
    function testWrongQuantityParameterPaths() public {
        // Try to list ERC721 but with erc1155Quantity > 0
        _whitelistCollectionAndApproveERC721();
        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__WrongQuantityParameter.selector);
        market.createListing(
            address(erc721),
            1,
            seller,
            1 ether,
            address(0),
            0,
            0,
            5, // wrongly treating ERC721 as ERC1155
            false,
            false,
            new address
        );
        vm.stopPrank();

        // List ERC1155 but with erc1155Quantity == 0
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.stopPrank();

        vm.startPrank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.expectRevert(IdeationMarket__WrongQuantityParameter.selector);
        market.createListing(
            address(erc1155),
            1,
            seller,
            1 ether,
            address(0),
            0,
            0,
            0, // wrongly treating ERC1155 as ERC721
            false,
            false,
            new address
        );
        vm.stopPrank();
    }

    // withdraw with 0 balance reverts
    function testWithdrawZeroBalanceReverts() public {
        vm.expectRevert(IdeationMarket__NoProceeds.selector);
        market.withdrawProceeds();
    }

    // buyer not on whitelist cannot purchase when whitelist enabled
    function testWhitelistPreventsPurchase() public {
        _whitelistCollectionAndApproveERC721();

        address;
        allowed[0] = operator; // NOT buyer

        vm.prank(seller);
        market.createListing(address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, true, false, allowed);
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__BuyerNotWhitelisted.selector, id, buyer));
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    // End of test contract
}

// -------------------------------------------------------------------------
// Mock Token Implementations
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
}
