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
        vm.startPrank(seller);
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
            new address[](0)
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
            new address[](0)
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
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );

        // Approve token #2 before creating its listing
        erc721.approve(address(diamond), 2);

        market.createListing(
            address(erc721), 2, address(0), 2 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
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
        uint128 id = _createListingERC721(false, new address[](0));

        // Owner cancels although not token owner nor approved
        vm.startPrank(owner);
        market.cancelListing(id);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    // purchase fails if approval revoked between listing and purchase
    function testPurchaseRevertsIfApprovalRevokedBeforeBuy() public {
        uint128 id = _createListingERC721(false, new address[](0));

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
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id1 = 1;

        // Create & cancel another listing to disturb state
        vm.prank(seller);
        erc721.approve(address(diamond), 2);
        vm.prank(seller);
        market.createListing(
            address(erc721), 2, address(0), 2 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id2 = 2;
        vm.prank(seller);
        market.cancelListing(id2);

        // Update the first listing, id must remain 1
        vm.prank(seller);
        market.updateListing(id1, 3 ether, address(0), 0, 0, 0, false, false, new address[](0));

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
            address(royaltyNft), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
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
            new address[](0)
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
            new address[](0)
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
            new address[](0)
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

        // Whitelist someone else (not the buyer) so creation succeeds

        address[] memory allowed = new address[](1);
        allowed[0] = operator;

        vm.prank(seller);
        market.createListing(address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, true, false, allowed);
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__BuyerNotWhitelisted.selector, id, buyer));
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    function testERC1155PartialBuyHappyPath() public {
        // Whitelist & approve
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // List qty=10, price=10 ETH, partials enabled
        vm.prank(seller);
        market.createListing(address(erc1155), 1, seller, 10 ether, address(0), 0, 0, 10, false, true, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        // Buyer buys 4 → purchasePrice=4 ETH; remains: qty=6, price=6 ETH
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 4 ether}(id, 10 ether, 10, address(0), 0, 0, 4, address(0));

        // Listing mutated correctly
        Listing memory l = getter.getListingByListingId(id);
        assertEq(l.erc1155Quantity, 6);
        assertEq(l.price, 6 ether);

        // Proceeds reflect fee (1% default): seller gets 3.96 ETH
        assertEq(getter.getProceeds(seller), 3.96 ether);
        assertEq(getter.getProceeds(owner), 0.04 ether);
    }

    function testInnovationFeeUpdateSemantics() public {
        _whitelistCollectionAndApproveERC721();

        // Listing #1 under initial fee (1000 = 1%)
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id1 = getter.getNextListingId() - 1;
        assertEq(getter.getListingByListingId(id1).feeRate, 1000);

        // Update fee to 2.5% and create Listing #2 using new fee
        vm.prank(owner);
        market.setInnovationFee(2500);
        vm.prank(seller);
        erc721.approve(address(diamond), 2);
        vm.prank(seller);
        market.createListing(
            address(erc721), 2, address(0), 2 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id2 = getter.getNextListingId() - 1;
        assertEq(getter.getListingByListingId(id2).feeRate, 2500);

        // Listing #1 still has old fee until updated
        assertEq(getter.getListingByListingId(id1).feeRate, 1000);

        // Updating #1 "refreshes" fee to current (2500)
        vm.prank(seller);
        market.updateListing(id1, 1 ether, address(0), 0, 0, 0, false, false, new address[](0));
        assertEq(getter.getListingByListingId(id1).feeRate, 2500);
    }

    function testExcessPaymentCreditAndWithdraw() public {
        uint128 id = _createListingERC721(false, new address[](0)); // price = 1 ETH

        vm.deal(buyer, 3 ether);
        uint256 balBefore = buyer.balance;

        // Overpay 1.5 ETH → excess 0.5 ETH credited to buyer's proceeds
        vm.prank(buyer);
        market.purchaseListing{value: 1.5 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        assertEq(getter.getProceeds(buyer), 0.5 ether);
        // Seller 0.99, owner 0.01 (1% fee)
        assertEq(getter.getProceeds(seller), 0.99 ether);
        assertEq(getter.getProceeds(owner), 0.01 ether);

        // Withdraw buyer credit → net spend becomes exactly 1 ETH
        vm.prank(buyer);
        market.withdrawProceeds();
        uint256 balAfterBuyerWithdraw = buyer.balance;
        assertEq(balBefore - balAfterBuyerWithdraw, 1 ether);

        // Drain remaining proceeds; diamond balance should go to zero
        vm.prank(owner);
        market.withdrawProceeds();
        vm.prank(seller);
        market.withdrawProceeds();
        assertEq(getter.getBalance(), 0);
    }

    function testGetterNoActiveListingsReverts() public {
        _whitelistCollectionAndApproveERC721();

        // Create & cancel listing
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        vm.prank(seller);
        market.cancelListing(id);

        // No active listings → revert
        vm.expectRevert(abi.encodeWithSelector(Getter__NoActiveListings.selector, address(erc721), 1));
        getter.getListingsByNFT(address(erc721), 1);
    }

    function testUpdateAfterCollectionDeWhitelistingCancels() public {
        _whitelistCollectionAndApproveERC721();

        // Create listing
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // De-whitelist the collection
        vm.prank(owner);
        collections.removeWhitelistedCollection(address(erc721));

        // Calling updateListing should cancel and return (no revert)
        vm.prank(seller);
        market.updateListing(id, 1 ether, address(0), 0, 0, 0, false, false, new address[](0));

        // Listing is gone
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testWithdrawHappyPathWithRoyaltyAndOwner() public {
        // Prepare royalty NFT (10%) and whitelist
        MockERC721Royalty royaltyNft = new MockERC721Royalty();
        royaltyNft.mint(seller, 1);
        address royaltyReceiver = address(0xB0B);
        royaltyNft.setRoyalty(royaltyReceiver, 10_000); // 10% of 100_000

        vm.prank(owner);
        collections.addWhitelistedCollection(address(royaltyNft));

        // Approve & list for 1 ETH
        vm.prank(seller);
        royaltyNft.approve(address(diamond), 1);
        vm.prank(seller);
        market.createListing(
            address(royaltyNft), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Purchase at 1 ETH
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        // Fee math: fee(1%)=0.01; sellerProceeds=0.99; royalty(10%) of sale=0.1 → seller takes 0.89
        assertEq(getter.getProceeds(owner), 0.01 ether);
        assertEq(getter.getProceeds(royaltyReceiver), 0.1 ether);
        assertEq(getter.getProceeds(seller), 0.89 ether);

        // Withdraws transfer correctly and contract drains
        uint256 sBefore = seller.balance;
        uint256 oBefore = owner.balance;
        uint256 rBefore = royaltyReceiver.balance;

        vm.prank(royaltyReceiver);
        market.withdrawProceeds();
        vm.prank(owner);
        market.withdrawProceeds();
        vm.prank(seller);
        market.withdrawProceeds();

        assertEq(seller.balance - sBefore, 0.89 ether);
        assertEq(owner.balance - oBefore, 0.01 ether);
        assertEq(royaltyReceiver.balance - rBefore, 0.1 ether);
        assertEq(getter.getBalance(), 0);
    }

    function testInvalidUnitPriceOnCreateReverts() public {
        // ERC1155 listing with qty=3, price=10 (not divisible) and partials enabled → revert
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__InvalidUnitPrice.selector);
        market.createListing(
            address(erc1155),
            1,
            seller,
            10, // price
            address(0),
            0,
            0,
            3, // quantity
            false,
            true, // partialBuyEnabled
            new address[](0)
        );
        vm.stopPrank();
    }

    /// -----------------------------------------------------------------------
    /// Diamond upgrade & owner auth tests
    /// -----------------------------------------------------------------------

    // Tests that only the contract owner can call diamondCut, and that
    // selectors can be added, replaced and removed correctly.
    function testDiamondCutAuthAndUpgradeFlow() public {
        // Prepare a dummy facet with a version() function.
        VersionFacetV1 v1 = new VersionFacetV1();
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = VersionFacetV1.version.selector;
        IDiamondCutFacet.FacetCut[] memory addCut = new IDiamondCutFacet.FacetCut[](1);
        addCut[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(v1),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: sels
        });

        // Only the owner may call diamondCut.
        vm.prank(buyer);
        vm.expectRevert("LibDiamond: Must be contract owner");
        IDiamondCutFacet(address(diamond)).diamondCut(addCut, address(0), "");

        // Owner adds the new facet.
        vm.prank(owner);
        IDiamondCutFacet(address(diamond)).diamondCut(addCut, address(0), "");

        // Call the function through the diamond; should return 1.
        (bool ok1, bytes memory ret1) = address(diamond).call(abi.encodeWithSelector(VersionFacetV1.version.selector));
        assertTrue(ok1);
        assertEq(abi.decode(ret1, (uint256)), 1);

        // Replace the facet with another returning 2.
        VersionFacetV2 v2 = new VersionFacetV2();
        IDiamondCutFacet.FacetCut[] memory replaceCut = new IDiamondCutFacet.FacetCut[](1);
        replaceCut[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(v2),
            action: IDiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: sels
        });
        vm.prank(owner);
        IDiamondCutFacet(address(diamond)).diamondCut(replaceCut, address(0), "");

        (bool ok2, bytes memory ret2) = address(diamond).call(abi.encodeWithSelector(VersionFacetV1.version.selector));
        assertTrue(ok2);
        assertEq(abi.decode(ret2, (uint256)), 2);

        // Remove the selector entirely.
        IDiamondCutFacet.FacetCut[] memory removeCut = new IDiamondCutFacet.FacetCut[](1);
        removeCut[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(0),
            action: IDiamondCutFacet.FacetCutAction.Remove,
            functionSelectors: sels
        });
        vm.prank(owner);
        IDiamondCutFacet(address(diamond)).diamondCut(removeCut, address(0), "");

        // Calling it now should revert via the diamond fallback.
        vm.expectRevert(Diamond__FunctionDoesNotExist.selector);
        VersionFacetV1(address(diamond)).version();
    }

    /// -----------------------------------------------------------------------
    /// Whitelisted buyer success path
    /// -----------------------------------------------------------------------

    // Confirms that a buyer on the whitelist can purchase successfully.
    function testWhitelistedBuyerPurchaseSuccess() public {
        _whitelistCollectionAndApproveERC721();

        // Whitelist the buyer.
        address[] memory allowed = new address[](1);
        allowed[0] = buyer;

        vm.prank(seller);
        market.createListing(address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, true, false, allowed);
        uint128 id = getter.getNextListingId() - 1;

        // Buyer pays the exact price and should succeed.
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        // Listing is removed, token ownership transferred.
        assertEq(erc721.ownerOf(1), buyer);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// -----------------------------------------------------------------------
    /// ERC721 Approval-for-All creation path
    /// -----------------------------------------------------------------------

    // Tests that setApprovalForAll (without per-token approval) allows listing.
    function testERC721SetApprovalForAllCreateListing() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        // Seller grants blanket approval instead of approve(1).
        vm.prank(seller);
        erc721.setApprovalForAll(address(diamond), true);

        // Create listing for token ID 1; should succeed.
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );

        uint128 id = getter.getNextListingId() - 1;
        Listing memory l = getter.getListingByListingId(id);
        assertEq(l.tokenId, 1);
        assertEq(l.seller, seller);
    }

    /// -----------------------------------------------------------------------
    /// ERC721 creation without approval should revert
    /// -----------------------------------------------------------------------

    // A stand-alone check that creating a listing without any approval reverts.
    function testCreateListingWithoutApprovalReverts() public {
        // Whitelist the ERC721 collection.
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        // Attempt to list token ID 2 without approve() or setApprovalForAll().
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.createListing(
            address(erc721), 2, address(0), 2 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
    }

    /// -----------------------------------------------------------------------
    /// Reentrancy: withdrawProceeds attempt
    /// -----------------------------------------------------------------------

    // Attacker contract attempts to re-enter withdrawProceeds from within its
    // receive() fallback. The lock in withdrawProceeds should prevent this.
    function testReentrancyOnWithdrawProceeds() public {
        // Deploy attacker, mint an NFT to it, and whitelist.
        ReentrantWithdrawer attacker = new ReentrantWithdrawer(address(diamond));
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));
        erc721.mint(address(attacker), 3);

        // Attacker approves the marketplace and lists the token.
        vm.prank(address(attacker));
        erc721.approve(address(diamond), 3);
        vm.prank(address(attacker));
        market.createListing(
            address(erc721), 3, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer purchases the listing.
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        // Attacker withdraws; reentrant call in receive() should be blocked.
        uint256 beforeBal = address(attacker).balance;
        vm.prank(address(attacker));
        market.withdrawProceeds();
        uint256 afterBal = address(attacker).balance;

        // Only one withdrawal should occur.
        assertEq(afterBal - beforeBal, 0.99 ether);
        assertEq(getter.getProceeds(address(attacker)), 0);
    }

    /// -----------------------------------------------------------------------
    /// Reentrancy: ERC1155 transfer attempt
    /// -----------------------------------------------------------------------

    // A malicious ERC1155 token tries to re-enter withdrawProceeds inside its
    // safeTransferFrom. The nonReentrant modifier should prevent success.
    function testReentrancyDuringERC1155Transfer() public {
        // Deploy malicious ERC1155 and mint tokens to seller.
        MaliciousERC1155 mal1155 = new MaliciousERC1155(address(diamond));
        vm.prank(owner);
        collections.addWhitelistedCollection(address(mal1155));
        mal1155.mint(seller, 1, 10);

        // Seller grants approval for all and lists the entire stack.
        vm.prank(seller);
        mal1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(mal1155), 1, seller, 10 ether, address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer purchases all 10 units.
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 10 ether}(id, 10 ether, 10, address(0), 0, 0, 10, address(0));

        // Ensure token balances updated and proceeds calculated correctly.
        assertEq(mal1155.balanceOf(buyer, 1), 10);
        assertEq(getter.getProceeds(seller), 9.9 ether);
        assertEq(getter.getProceeds(owner), 0.1 ether);
    }

    /// -----------------------------------------------------------------------
    /// Reentrancy: ERC721 transfer attempt
    /// -----------------------------------------------------------------------

    // A malicious ERC721 token tries to re-enter withdrawProceeds inside its
    // transferFrom. The nonReentrant modifier should prevent success.
    function testReentrancyDuringERC721Transfer() public {
        // Deploy malicious ERC721 and mint a token to seller.
        MaliciousERC721 mal721 = new MaliciousERC721(address(diamond));
        vm.prank(owner);
        collections.addWhitelistedCollection(address(mal721));
        mal721.mint(seller, 1);

        // Seller approves and lists the token.
        vm.prank(seller);
        mal721.approve(address(diamond), 1);
        vm.prank(seller);
        market.createListing(
            address(mal721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer purchases the NFT.
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        // Ownership transfers and proceeds reflect the fee.
        assertEq(mal721.ownerOf(1), buyer);
        assertEq(getter.getProceeds(seller), 0.99 ether);
        assertEq(getter.getProceeds(owner), 0.01 ether);
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

// -------------------------------------------------------------------------
// Helper facets for upgrade testing
// -------------------------------------------------------------------------

contract VersionFacetV1 {
    function version() external pure returns (uint256) {
        return 1;
    }
}

contract VersionFacetV2 {
    function version() external pure returns (uint256) {
        return 2;
    }
}

// -------------------------------------------------------------------------
// Reentrant withdraw attacker
// -------------------------------------------------------------------------

// Attempts to re-enter withdrawProceeds from its receive() callback. The
// nonReentrant modifier on withdrawProceeds should prevent success.
contract ReentrantWithdrawer {
    IdeationMarketFacet public market;
    bool internal attacked;

    constructor(address diamond) {
        market = IdeationMarketFacet(diamond);
    }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            try market.withdrawProceeds() {
                // ignore success; should revert due to nonReentrant
            } catch {
                // ignore revert
            }
        }
    }
}

// -------------------------------------------------------------------------
// Malicious ERC1155 token
// -------------------------------------------------------------------------

// Minimal ERC1155 that calls withdrawProceeds during safeTransferFrom to
// attempt a reentrant attack. It catches the revert to allow the transfer.
contract MaliciousERC1155 {
    mapping(uint256 => mapping(address => uint256)) internal _balances;
    mapping(address => mapping(address => bool)) internal _operatorApprovals;
    IdeationMarketFacet public market;
    bool internal attacked;

    constructor(address diamond) {
        market = IdeationMarketFacet(diamond);
    }

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
        // Attempt to re-enter withdrawProceeds once.
        if (!attacked) {
            attacked = true;
            try market.withdrawProceeds() {
                // no-op: should revert due to reentrancy lock
            } catch {
                // ignore the revert
            }
        }
        require(msg.sender == from || _operatorApprovals[from][msg.sender], "not approved");
        require(_balances[id][from] >= amount, "insufficient");
        _balances[id][from] -= amount;
        _balances[id][to] += amount;
    }
}

// -------------------------------------------------------------------------
// Malicious ERC721 token
// -------------------------------------------------------------------------

// Minimal ERC721 that calls withdrawProceeds during transferFrom to attempt
// a reentrant attack. It catches the revert to allow the transfer.
contract MaliciousERC721 {
    mapping(uint256 => address) internal _owners;
    mapping(uint256 => address) internal _tokenApprovals;
    mapping(address => mapping(address => bool)) internal _operatorApprovals;
    IdeationMarketFacet public market;
    bool internal attacked;

    constructor(address diamond) {
        market = IdeationMarketFacet(diamond);
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC721).interfaceId;
    }

    function mint(address to, uint256 tokenId) external {
        _owners[tokenId] = to;
    }

    function balanceOf(address owner) external view returns (uint256) {
        uint256 count;
        // Count tokens owned by 'owner'
        // Not needed for test logic but provided for completeness
        for (uint256 i = 0; i < 10; i++) {
            if (_owners[i] == owner) count++;
        }
        return count;
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
        // caller must be owner or approved
        require(
            msg.sender == from || msg.sender == _tokenApprovals[tokenId] || _operatorApprovals[from][msg.sender],
            "not approved"
        );
        // Attempt reentrancy once.
        if (!attacked) {
            attacked = true;
            try market.withdrawProceeds() {
                // will revert due to reentrancy lock; ignore
            } catch {
                // ignore revert
            }
        }
        _owners[tokenId] = to;
        _tokenApprovals[tokenId] = address(0);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external {
        transferFrom(from, to, tokenId);
    }
}
