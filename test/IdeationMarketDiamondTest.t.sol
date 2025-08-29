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
        assertFalse(IERC165(address(diamond)).supportsInterface(type(IERC721).interfaceId));
        assertFalse(IERC165(address(diamond)).supportsInterface(type(IERC1155).interfaceId));
        assertFalse(IERC165(address(diamond)).supportsInterface(type(IERC2981).interfaceId));
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
        /// Batch size exceeding cap should revert.
        /// We call the BuyerWhitelistFacet through the diamond **as the seller** (an authorized operator)
        /// against an existing listing, then pass an oversized array (MAX_BATCH+1).
        /// Because the caller is authorized and the listing exists, the only failing condition is the
        /// batch-size guard, so the call must revert with BuyerWhitelist__ExceedsMaxBatchSize.
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

    function testCleanListing721() public {
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

    function testCleanListing_WhileStillApproved_ERC721_Reverts() public {
        // Whitelist + approve + create a valid ERC721 listing
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Anyone can call cleanListing, but since the listing is still valid, it must revert
        address rando = vm.addr(0xC1EA11);
        vm.startPrank(rando);
        vm.expectRevert(IdeationMarket__StillApproved.selector);
        market.cleanListing(id);
        vm.stopPrank();
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

    // -----------------------------------------------------------------------
    // Extra edge-case tests
    // -----------------------------------------------------------------------

    function testLoupeReflectsAddReplaceRemove() public {
        // Add v1
        VersionFacetV1 v1 = new VersionFacetV1();
        bytes4 sel = VersionFacetV1.version.selector;
        IDiamondCutFacet.FacetCut[] memory addCut = new IDiamondCutFacet.FacetCut[](1);
        bytes4[] memory sels = new bytes4[](1);

        sels[0] = sel;
        addCut[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(v1),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: sels
        });

        vm.prank(owner);
        IDiamondCutFacet(address(diamond)).diamondCut(addCut, address(0), "");

        // Loupe should point selector -> v1
        assertEq(loupe.facetAddress(sel), address(v1));

        // Replace with v2
        VersionFacetV2 v2 = new VersionFacetV2();
        IDiamondCutFacet.FacetCut[] memory repCut = new IDiamondCutFacet.FacetCut[](1);
        repCut[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(v2),
            action: IDiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: sels
        });

        vm.prank(owner);
        IDiamondCutFacet(address(diamond)).diamondCut(repCut, address(0), "");

        // Loupe should now point selector -> v2
        assertEq(loupe.facetAddress(sel), address(v2));

        // Remove selector
        IDiamondCutFacet.FacetCut[] memory remCut = new IDiamondCutFacet.FacetCut[](1);
        remCut[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(0),
            action: IDiamondCutFacet.FacetCutAction.Remove,
            functionSelectors: sels
        });

        vm.prank(owner);
        IDiamondCutFacet(address(diamond)).diamondCut(remCut, address(0), "");

        // Loupe should return zero for removed selector
        assertEq(loupe.facetAddress(sel), address(0));
    }

    function testDiamondCutAddZeroAddressReverts() public {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = VersionFacetV1.version.selector;

        IDiamondCutFacet.FacetCut[] memory cut = new IDiamondCutFacet.FacetCut[](1);
        cut[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(0),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: sels
        });

        vm.prank(owner);
        vm.expectRevert("LibDiamondCut: Add facet can't be address(0)");
        IDiamondCutFacet(address(diamond)).diamondCut(cut, address(0), "");
    }

    function testDiamondCutReplaceZeroAddressReverts() public {
        // First add v1 so there is something to replace
        VersionFacetV1 v1 = new VersionFacetV1();
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = VersionFacetV1.version.selector;

        IDiamondCutFacet.FacetCut[] memory addCut = new IDiamondCutFacet.FacetCut[](1);
        addCut[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(v1),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: sels
        });
        vm.prank(owner);
        IDiamondCutFacet(address(diamond)).diamondCut(addCut, address(0), "");

        // Now attempt to replace with zero facet address -> revert
        IDiamondCutFacet.FacetCut[] memory repCut = new IDiamondCutFacet.FacetCut[](1);
        repCut[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(0),
            action: IDiamondCutFacet.FacetCutAction.Replace,
            functionSelectors: sels
        });

        vm.prank(owner);
        vm.expectRevert("LibDiamondCut: Add facet can't be address(0)");
        IDiamondCutFacet(address(diamond)).diamondCut(repCut, address(0), "");
    }

    function testCollectionWhitelistZeroAddressReverts() public {
        vm.prank(owner);
        vm.expectRevert(CollectionWhitelist__ZeroAddress.selector);
        collections.addWhitelistedCollection(address(0));
    }

    function testSellerCancelAfterApprovalRevoked() public {
        uint128 id = _createListingERC721(false, new address[](0));
        // Revoke approval then cancel as seller
        vm.prank(seller);
        erc721.approve(address(0), 1);

        vm.prank(seller);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCreateWithWhitelistEnabledEmptyArrayOK() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, true, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        Listing memory ls = getter.getListingByListingId(id);
        assertEq(ls.buyerWhitelistEnabled, true);

        // Sanity: no addresses are whitelisted yet
        assertEq(getter.isBuyerWhitelisted(id, buyer), false);
        assertEq(getter.isBuyerWhitelisted(id, seller), false);
    }

    function testUpdateEnableWhitelistWithEmptyArrayOK() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.prank(seller);
        market.updateListing(id, 1 ether, address(0), 0, 0, 0, true, false, new address[](0));

        Listing memory ls = getter.getListingByListingId(id);
        assertEq(ls.buyerWhitelistEnabled, true);

        // Sanity: no addresses are whitelisted yet
        assertEq(getter.isBuyerWhitelisted(id, buyer), false);
        assertEq(getter.isBuyerWhitelisted(id, seller), false);
    }

    function testUpdateDisableWhitelistThenOpenPurchase() public {
        _whitelistCollectionAndApproveERC721();

        address[] memory allowed = new address[](1);
        allowed[0] = operator;

        vm.prank(seller);
        market.createListing(address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, true, false, allowed);
        uint128 id = getter.getNextListingId() - 1;

        // Disable whitelist on update
        vm.prank(seller);
        market.updateListing(id, 1 ether, address(0), 0, 0, 0, false, false, new address[](0));

        // Now anyone can buy
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));
        assertEq(erc721.ownerOf(1), buyer);
    }

    function testCreateWithWhitelistDisabledNonEmptyListReverts() public {
        _whitelistCollectionAndApproveERC721();

        address[] memory bogus = new address[](1);
        bogus[0] = buyer;

        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__WhitelistDisabled.selector);
        market.createListing(
            address(erc721),
            1,
            address(0),
            1 ether,
            address(0),
            0,
            0,
            0,
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            bogus // non-empty -> must revert per facet
        );
        vm.stopPrank();
    }

    function testCreateWithZeroTokenAddressReverts() public {
        // No whitelist entry can exist for address(0), expect revert
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__CollectionNotWhitelisted.selector, address(0)));
        market.createListing(address(0), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0));
    }

    function testCreatePriceZeroWithoutSwapReverts() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__FreeListingsNotSupported.selector);
        market.createListing(address(erc721), 1, address(0), 0, address(0), 0, 0, 0, false, false, new address[](0));
    }

    function testBuyNonexistentListingIdReverts() public {
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotListed.selector);
        market.purchaseListing{value: 1 ether}(999_999, 1 ether, 0, address(0), 0, 0, 0, address(0));
    }

    function testExpectedPriceMismatchReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        // Seller changes price to 2 ether
        vm.prank(seller);
        market.updateListing(id, 2 ether, address(0), 0, 0, 0, false, false, new address[](0));

        // Buyer sends enough ETH but insists expectedPrice=1 ether -> should revert
        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__ListingTermsChanged.selector);
        market.purchaseListing{value: 2 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));
    }

    function testExpectedErc1155QuantityMismatchReverts() public {
        // ERC1155 listing: qty=10
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__ListingTermsChanged.selector);
        market.purchaseListing{value: 10 ether}(id, 10 ether, 9, address(0), 0, 0, 10, address(0));
    }

    function testERC1155BuyExactRemainingRemovesListing() public {
        // List 10, partials enabled
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(address(erc1155), 1, seller, 10 ether, address(0), 0, 0, 10, false, true, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        // Buy 4, then buy remaining 6
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 4 ether}(id, 10 ether, 10, address(0), 0, 0, 4, address(0));

        vm.deal(operator, 6 ether);
        vm.prank(operator);
        market.purchaseListing{value: 6 ether}(id, 6 ether, 6, address(0), 0, 0, 6, address(0));

        // Listing removed
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testERC721PurchaseWithNonZero1155QuantityReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__InvalidPurchaseQuantity.selector);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 1, address(0));
    }

    function testRepurchaseAfterBuyReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        // Second attempt should revert since listing is gone
        vm.deal(operator, 1 ether);
        vm.prank(operator);
        vm.expectRevert(IdeationMarket__NotListed.selector);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));
    }

    function testUpdateNonexistentListingReverts() public {
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotListed.selector);
        market.updateListing(999_999, 1 ether, address(0), 0, 0, 0, false, false, new address[](0));
    }

    function testNoOpUpdateKeepsValues() public {
        uint128 id = _createListingERC721(false, new address[](0));
        Listing memory beforeL = getter.getListingByListingId(id);

        vm.prank(seller);
        market.updateListing(
            id,
            beforeL.price,
            beforeL.desiredTokenAddress,
            beforeL.desiredTokenId,
            beforeL.desiredErc1155Quantity,
            beforeL.erc1155Quantity,
            beforeL.buyerWhitelistEnabled,
            beforeL.partialBuyEnabled,
            new address[](0)
        );

        Listing memory afterL = getter.getListingByListingId(id);
        assertEq(afterL.listingId, beforeL.listingId);
        assertEq(afterL.price, beforeL.price);
        assertEq(afterL.erc1155Quantity, beforeL.erc1155Quantity);
    }

    function testERC1155UpdateInvalidUnitPriceReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(address(erc1155), 1, seller, 10 ether, address(0), 0, 0, 10, false, true, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        // 7 ether % 3 != 0 in wei -> MUST revert
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__InvalidUnitPrice.selector);
        market.updateListing(id, 7 ether, address(0), 0, 0, 3, false, true, new address[](0));
    }

    function testCancelNonexistentListingReverts() public {
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotListed.selector);
        market.cancelListing(999_999);
    }

    function testDoubleCleanReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));

        // Revoke approval, clean once
        vm.prank(seller);
        erc721.approve(address(0), 1);

        vm.prank(operator);
        market.cleanListing(id);

        // Second clean should revert (listing gone)
        vm.prank(operator);
        vm.expectRevert(IdeationMarket__NotListed.selector);
        market.cleanListing(id);
    }

    function testWithdrawTwiceRevertsNoProceeds() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        // Seller withdraws once
        vm.prank(seller);
        market.withdrawProceeds();

        // Second withdraw must revert with NoProceeds
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NoProceeds.selector);
        market.withdrawProceeds();
    }

    function testGetProceedsNeverInteractedIsZero() public view {
        address ghost = address(0xBEEF);
        assertEq(getter.getProceeds(ghost), 0);
    }

    function testRoyaltyReceiverEqualsSeller() public {
        MockERC721Royalty r = new MockERC721Royalty();
        r.mint(seller, 1);
        r.setRoyalty(seller, 10_000); // 10%

        vm.prank(owner);
        collections.addWhitelistedCollection(address(r));

        vm.prank(seller);
        r.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(address(r), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        // Seller receives sale - fee (0.99), since royalty loops back to seller
        assertEq(getter.getProceeds(seller), 0.99 ether);
        assertEq(getter.getProceeds(owner), 0.01 ether);
    }

    function testRoyaltyEqualsPostFeeProceedsBoundary() public {
        // fee = 1% (0.01 ETH), royalty = 99% (0.99 ETH) → seller net 0
        MockERC721Royalty r = new MockERC721Royalty();
        r.mint(seller, 1);
        r.setRoyalty(address(0xB0B), 99_000);

        vm.prank(owner);
        collections.addWhitelistedCollection(address(r));

        vm.prank(seller);
        r.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(address(r), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        assertEq(getter.getProceeds(owner), 0.01 ether);
        assertEq(getter.getProceeds(address(0xB0B)), 0.99 ether);
        assertEq(getter.getProceeds(seller), 0);
    }

    // Whitelist: enabling on update with exactly MAX_BATCH should succeed
    function testUpdateWhitelistExactlyMaxBatchSucceeds() public {
        _whitelistCollectionAndApproveERC721();

        // Create listing with whitelist disabled
        vm.prank(seller);
        market.createListing(
            address(erc721),
            1,
            address(0),
            1 ether,
            address(0),
            0,
            0,
            0,
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Enable whitelist with exactly MAX_BATCH addresses
        address[] memory buyersList = new address[](MAX_BATCH);
        for (uint256 i = 0; i < buyersList.length; i++) {
            buyersList[i] = vm.addr(30_000 + i);
        }

        vm.prank(seller);
        market.updateListing(id, 1 ether, address(0), 0, 0, 0, true, false, buyersList);

        // Spot check entries made it in
        assertTrue(getter.isBuyerWhitelisted(id, buyersList[0]));
        assertTrue(getter.isBuyerWhitelisted(id, buyersList[buyersList.length - 1]));
    }

    // Whitelist: enabling on update with >MAX_BATCH should revert
    function testUpdateWhitelistOverMaxBatchReverts() public {
        _whitelistCollectionAndApproveERC721();

        // Create listing with whitelist disabled
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        address[] memory tooMany = new address[](uint256(MAX_BATCH) + 1);
        for (uint256 i = 0; i < tooMany.length; i++) {
            tooMany[i] = vm.addr(31_000 + i);
        }

        vm.startPrank(seller);
        vm.expectRevert(BuyerWhitelist__ExceedsMaxBatchSize.selector);
        market.updateListing(id, 1 ether, address(0), 0, 0, 0, true, false, tooMany);
        vm.stopPrank();
    }

    // Whitelist: adding duplicates should be idempotent (no revert, end state true)
    function testBuyerWhitelistAddDuplicatesIdempotent() public {
        // Create listing with whitelist enabled and one buyer
        address[] memory allowed = new address[](1);
        allowed[0] = buyer;
        uint128 id = _createListingERC721(true, allowed);

        // Add [buyer, buyer] again; should not revert and still be whitelisted
        address[] memory dups = new address[](2);
        dups[0] = buyer;
        dups[1] = buyer;

        vm.prank(seller);
        buyers.addBuyerWhitelistAddresses(id, dups);

        assertTrue(getter.isBuyerWhitelisted(id, buyer));
    }

    // Whitelist: removing with empty calldata should revert
    function testBuyerWhitelistRemoveEmptyCalldataReverts() public {
        address[] memory allowed = new address[](1);
        allowed[0] = buyer;
        uint128 id = _createListingERC721(true, allowed);

        address[] memory empty = new address[](0);
        vm.startPrank(seller);
        vm.expectRevert(BuyerWhitelist__EmptyCalldata.selector);
        buyers.removeBuyerWhitelistAddresses(id, empty);
        vm.stopPrank();
    }

    // Whitelist: removing by unauthorized address should revert
    function testBuyerWhitelistRemoveUnauthorizedReverts() public {
        address[] memory allowed = new address[](1);
        allowed[0] = buyer;
        uint128 id = _createListingERC721(true, allowed);

        address[] memory one = new address[](1);
        one[0] = buyer;

        vm.startPrank(buyer);
        vm.expectRevert(BuyerWhitelist__NotAuthorizedOperator.selector);
        buyers.removeBuyerWhitelistAddresses(id, one);
        vm.stopPrank();
    }

    // Whitelist: after removal, purchase should fail for that buyer
    function testPurchaseRevertsAfterWhitelistRemoval() public {
        address[] memory allowed = new address[](1);
        allowed[0] = buyer;
        uint128 id = _createListingERC721(true, allowed);

        // Remove buyer from whitelist
        address[] memory one = new address[](1);
        one[0] = buyer;
        vm.prank(seller);
        buyers.removeBuyerWhitelistAddresses(id, one);
        assertFalse(getter.isBuyerWhitelisted(id, buyer));

        // Attempt purchase → revert BuyerNotWhitelisted
        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__BuyerNotWhitelisted.selector, id, buyer));
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    // Innovation fee: only owner can set
    function testSetInnovationFeeOnlyOwner() public {
        vm.startPrank(buyer);
        vm.expectRevert("LibDiamond: Must be contract owner");
        market.setInnovationFee(1234);
        vm.stopPrank();
    }

    // ERC1155: zero-quantity purchase should revert
    function testERC1155ZeroQuantityPurchaseReverts() public {
        // Whitelist & approve; list qty=10, partials enabled
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(address(erc1155), 1, seller, 10 ether, address(0), 0, 0, 10, false, true, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        // Buy 0 units → InvalidPurchaseQuantity
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__InvalidPurchaseQuantity.selector);
        market.purchaseListing{value: 0}(
            id,
            10 ether, // expectedPrice (total listing price)
            10, // expectedErc1155Quantity (total listed qty)
            address(0),
            0,
            0,
            0, // erc1155PurchaseQuantity
            address(0)
        );
        vm.stopPrank();
    }

    // ERC1155: after a partial fill, buying more than remaining should revert
    function testERC1155OverRemainingAfterPartialReverts() public {
        // List qty=10, partials enabled
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(address(erc1155), 1, seller, 10 ether, address(0), 0, 0, 10, false, true, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        // First partial: buy 7
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 7 ether}(id, 10 ether, 10, address(0), 0, 0, 7, address(0));

        // Remaining = 3; attempt to buy 4 → revert
        address secondBuyer = vm.addr(0xABCD);
        vm.deal(secondBuyer, 10 ether);
        vm.startPrank(secondBuyer);
        vm.expectRevert(IdeationMarket__InvalidPurchaseQuantity.selector);
        market.purchaseListing{value: 4 ether}(id, 3 ether, 3, address(0), 0, 0, 4, address(0));
        vm.stopPrank();
    }

    // ERC1155 create: msg.sender is neither holder nor holder's operator ⇒ revert NotAuthorizedOperator
    function testERC1155CreateUnauthorizedListerReverts() public {
        // Whitelist the collection
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Holder owns the tokens and approves the marketplace, but NOT the would-be lister.
        // This ensures we fail on auth (msg.sender not holder nor operator), not on marketplace approval.
        vm.prank(operator);
        erc1155.mint(operator, 1, 10);
        vm.prank(operator);
        erc1155.setApprovalForAll(address(diamond), true); // marketplace approval intact

        // Seller is NOT an operator for `operator` (the holder). Creating should revert on auth.
        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__NotAuthorizedOperator.selector);
        market.createListing(
            address(erc1155), // token
            1, // tokenId
            operator, // erc1155Holder (the actual balance holder)
            10 ether, // price (no swap)
            address(0), // desiredTokenAddress (no swap)
            0, // desiredTokenId
            0, // desiredErc1155Quantity
            10, // erc1155Quantity (=> 1155 branch)
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            new address[](0) // allowedBuyers
        );
        vm.stopPrank();
    }

    function testERC1155HolderDifferentFromSellerHappyPath() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        erc1155.mint(operator, 1, 10);

        // Holder approvals
        vm.prank(operator);
        erc1155.setApprovalForAll(seller, true); // seller may act for holder
        vm.prank(operator);
        erc1155.setApprovalForAll(address(diamond), true); // marketplace may transfer

        // Seller creates the listing on behalf of holder
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, operator, 10 ether, address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        Listing memory beforeBuy = getter.getListingByListingId(id);
        assertEq(beforeBuy.seller, operator);

        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 10 ether}(id, 10 ether, 10, address(0), 0, 0, 10, address(0));

        // Tokens left holder → buyer
        assertEq(erc1155.balanceOf(operator, 1), 0);
        assertEq(erc1155.balanceOf(buyer, 1), 10);

        // Proceeds go to the holder (the Listing.seller), not msg.sender(seller)
        assertEq(getter.getProceeds(operator), 9.9 ether);
        assertEq(getter.getProceeds(owner), 0.1 ether);
        assertEq(getter.getProceeds(seller), 0);
    }

    // Whitelist: passing address(0) in create should revert
    function testCreateListingWhitelistWithZeroAddressReverts() public {
        _whitelistCollectionAndApproveERC721();

        address[] memory allowed = new address[](1);
        allowed[0] = address(0);

        vm.startPrank(seller);
        vm.expectRevert(BuyerWhitelist__ZeroAddress.selector);
        market.createListing(
            address(erc721),
            1,
            address(0),
            1 ether,
            address(0),
            0,
            0,
            0,
            true, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            allowed
        );
        vm.stopPrank();
    }

    // Whitelist: passing address(0) in update while enabling should revert
    function testUpdateListingWhitelistWithZeroAddressReverts() public {
        _whitelistCollectionAndApproveERC721();

        // Create listing with whitelist disabled
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        address[] memory invalid = new address[](1);
        invalid[0] = address(0);

        vm.startPrank(seller);
        vm.expectRevert(BuyerWhitelist__ZeroAddress.selector);
        market.updateListing(
            id,
            1 ether,
            address(0),
            0,
            0,
            0,
            true, // enable whitelist
            false,
            invalid
        );
        vm.stopPrank();
    }

    function testTogglePartialBuyEnabledWithoutPriceChange() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(address(erc1155), 1, seller, 10 ether, address(0), 0, 0, 10, false, true, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        // Flip partials to disabled; keep qty the same (ERC1155 stays ERC1155)
        vm.prank(seller);
        market.updateListing(id, 10 ether, address(0), 0, 0, 10, false, false, new address[](0));

        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__PartialBuyNotPossible.selector);
        market.purchaseListing{value: 4 ether}(id, 10 ether, 10, address(0), 0, 0, 4, address(0));
        vm.stopPrank();

        Listing memory l = getter.getListingByListingId(id);
        assertEq(l.price, 10 ether);
        assertFalse(l.partialBuyEnabled);
        assertEq(l.erc1155Quantity, 10);
    }

    // Lister is NOT approved by the ERC1155 holder -> NotAuthorizedOperator
    function testERC1155OperatorNotApprovedReverts_thenSucceedsAfterApproval() public {
        // Whitelist ERC1155 and mint balance to the HOLDER (operator).
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        erc1155.mint(operator, 1, 10);

        // Seller tries to list tokens held by 'operator' without being approved by operator.
        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__NotAuthorizedOperator.selector);
        market.createListing(
            address(erc1155),
            1,
            operator, // erc1155Holder
            1 ether,
            address(0),
            0,
            0,
            10, // quantity
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();

        // Grant seller operator rights and marketplace transfer rights; then it should work
        vm.prank(operator);
        erc1155.setApprovalForAll(seller, true);
        vm.prank(operator);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, operator, 1 ether, address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        Listing memory l = getter.getListingByListingId(id);
        assertEq(l.erc1155Quantity, 10);
    }

    // Listing-time guard: erc1155Holder has ZERO balance for the token id -> WrongErc1155HolderParameter
    function testERC1155HolderZeroBalanceAtCreateRevertsWrongHolder() public {
        // Use a fresh tokenId that no one owns (e.g., 42).
        uint256 freshTokenId = 42;

        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Seller claims to be the erc1155Holder but has zero balance for freshTokenId.
        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__WrongErc1155HolderParameter.selector);
        market.createListing(
            address(erc1155),
            freshTokenId,
            seller, // claimed erc1155Holder
            1 ether,
            address(0),
            0,
            0,
            10, // quantity
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();
    }

    // Update while whitelist is DISABLED but a non-empty address list is provided -> WhitelistDisabled
    function testUpdateWhitelistDisabledWithAddressesReverts() public {
        // Create a simple ERC721 listing with whitelist disabled.
        uint128 id = _createListingERC721(false, new address[](0));

        // Attempt to update while keeping whitelist disabled but passing addresses.
        address[] memory bogus = new address[](1);
        bogus[0] = buyer;

        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__WhitelistDisabled.selector);
        market.updateListing(
            id,
            1 ether, // keep same price
            address(0), // no swap
            0,
            0,
            0, // still ERC721
            false, // whitelist remains disabled
            false, // partialBuy irrelevant for ERC721
            bogus // <-- non-empty list should trigger revert
        );
        vm.stopPrank();
    }

    function testLoupeSelectorsPerFacet() public view {
        // ===== Market facet =====
        address marketAddr = loupe.facetAddress(IdeationMarketFacet.createListing.selector);
        assertTrue(marketAddr != address(0));

        // All market selectors should live on the same facet
        assertEq(loupe.facetAddress(IdeationMarketFacet.purchaseListing.selector), marketAddr);
        assertEq(loupe.facetAddress(IdeationMarketFacet.cancelListing.selector), marketAddr);
        assertEq(loupe.facetAddress(IdeationMarketFacet.updateListing.selector), marketAddr);
        assertEq(loupe.facetAddress(IdeationMarketFacet.withdrawProceeds.selector), marketAddr);
        assertEq(loupe.facetAddress(IdeationMarketFacet.setInnovationFee.selector), marketAddr);
        assertEq(loupe.facetAddress(IdeationMarketFacet.cleanListing.selector), marketAddr);

        // Spot-check the facet’s selector list actually includes them
        bytes4[] memory m = loupe.facetFunctionSelectors(marketAddr);
        assertTrue(_hasSel(m, IdeationMarketFacet.createListing.selector));
        assertTrue(_hasSel(m, IdeationMarketFacet.purchaseListing.selector));
        assertTrue(_hasSel(m, IdeationMarketFacet.cancelListing.selector));
        assertTrue(_hasSel(m, IdeationMarketFacet.updateListing.selector));
        assertTrue(_hasSel(m, IdeationMarketFacet.withdrawProceeds.selector));
        assertTrue(_hasSel(m, IdeationMarketFacet.setInnovationFee.selector));
        assertTrue(_hasSel(m, IdeationMarketFacet.cleanListing.selector));

        // ===== Ownership facet =====
        address ownershipAddr = loupe.facetAddress(IERC173.owner.selector);
        assertTrue(ownershipAddr != address(0));
        assertEq(loupe.facetAddress(IERC173.transferOwnership.selector), ownershipAddr);
        assertEq(loupe.facetAddress(OwnershipFacet.acceptOwnership.selector), ownershipAddr);
        bytes4[] memory o = loupe.facetFunctionSelectors(ownershipAddr);
        assertTrue(_hasSel(o, IERC173.owner.selector));
        assertTrue(_hasSel(o, IERC173.transferOwnership.selector));
        assertTrue(_hasSel(o, OwnershipFacet.acceptOwnership.selector));

        // ===== Loupe facet =====
        address loupeAddr = loupe.facetAddress(IDiamondLoupeFacet.facets.selector);
        assertTrue(loupeAddr != address(0));
        assertEq(loupe.facetAddress(IDiamondLoupeFacet.facetFunctionSelectors.selector), loupeAddr);
        assertEq(loupe.facetAddress(IDiamondLoupeFacet.facetAddresses.selector), loupeAddr);
        assertEq(loupe.facetAddress(IDiamondLoupeFacet.facetAddress.selector), loupeAddr);
        assertEq(loupe.facetAddress(IERC165.supportsInterface.selector), loupeAddr);
        bytes4[] memory l = loupe.facetFunctionSelectors(loupeAddr);
        assertTrue(_hasSel(l, IDiamondLoupeFacet.facets.selector));
        assertTrue(_hasSel(l, IDiamondLoupeFacet.facetFunctionSelectors.selector));
        assertTrue(_hasSel(l, IDiamondLoupeFacet.facetAddresses.selector));
        assertTrue(_hasSel(l, IDiamondLoupeFacet.facetAddress.selector));
        assertTrue(_hasSel(l, IERC165.supportsInterface.selector));

        // ===== Collection whitelist facet =====
        address colAddr = loupe.facetAddress(CollectionWhitelistFacet.addWhitelistedCollection.selector);
        assertTrue(colAddr != address(0));
        assertEq(loupe.facetAddress(CollectionWhitelistFacet.removeWhitelistedCollection.selector), colAddr);
        assertEq(loupe.facetAddress(CollectionWhitelistFacet.batchAddWhitelistedCollections.selector), colAddr);
        assertEq(loupe.facetAddress(CollectionWhitelistFacet.batchRemoveWhitelistedCollections.selector), colAddr);

        // ===== Buyer whitelist facet =====
        address bwAddr = loupe.facetAddress(BuyerWhitelistFacet.addBuyerWhitelistAddresses.selector);
        assertTrue(bwAddr != address(0));
        assertEq(loupe.facetAddress(BuyerWhitelistFacet.removeBuyerWhitelistAddresses.selector), bwAddr);

        // ===== Getter facet =====
        address getterAddr = loupe.facetAddress(GetterFacet.getNextListingId.selector);
        assertTrue(getterAddr != address(0));
        assertEq(loupe.facetAddress(GetterFacet.getListingsByNFT.selector), getterAddr);
        assertEq(loupe.facetAddress(GetterFacet.getListingByListingId.selector), getterAddr);
        assertEq(loupe.facetAddress(GetterFacet.getProceeds.selector), getterAddr);
        assertEq(loupe.facetAddress(GetterFacet.getBalance.selector), getterAddr);
        assertEq(loupe.facetAddress(GetterFacet.getInnovationFee.selector), getterAddr);
        assertEq(loupe.facetAddress(GetterFacet.isCollectionWhitelisted.selector), getterAddr);
        assertEq(loupe.facetAddress(GetterFacet.getWhitelistedCollections.selector), getterAddr);
        assertEq(loupe.facetAddress(GetterFacet.getContractOwner.selector), getterAddr);
        assertEq(loupe.facetAddress(GetterFacet.isBuyerWhitelisted.selector), getterAddr);
        assertEq(loupe.facetAddress(GetterFacet.getBuyerWhitelistMaxBatchSize.selector), getterAddr);
        assertEq(loupe.facetAddress(GetterFacet.getPendingOwner.selector), getterAddr);
    }

    function _hasSel(bytes4[] memory arr, bytes4 sel) internal pure returns (bool) {
        for (uint256 i; i < arr.length; i++) {
            if (arr[i] == sel) return true;
        }
        return false;
    }

    function testSupportsInterfaceNegative() public view {
        assertFalse(IERC165(address(diamond)).supportsInterface(0x12345678));
    }

    function testCleanListingERC1155() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Revoke marketplace approval so cleanListing is allowed
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), false);

        vm.prank(operator);
        market.cleanListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCleanListing_WhileStillApproved_ERC1155_Reverts() public {
        // Whitelist + operator approval + create a valid ERC1155 listing
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155),
            1,
            seller, // erc1155Holder
            10 ether, // fixed price, no swap
            address(0),
            0,
            0,
            10, // quantity
            false, // whitelist disabled
            false, // partialBuy disabled
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Still fully approved & whitelisted → cleanListing should revert with StillApproved
        address rando = vm.addr(0xC1EA12);
        vm.startPrank(rando);
        vm.expectRevert(IdeationMarket__StillApproved.selector);
        market.cleanListing(id);
        vm.stopPrank();
    }

    /// Ensures ListingTermsChanged also trips on expectedDesired* mismatches.
    function testExpectedDesiredFieldsMismatchReverts() public {
        uint128 id = _createListingERC721(false, new address[](0)); // price = 1 ether

        vm.deal(buyer, 2 ether);

        // 1) Mismatch expectedDesiredTokenAddress (non-swap listing has address(0))
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__ListingTermsChanged.selector);
        market.purchaseListing{value: 1 ether}(
            id,
            1 ether, // expectedPrice OK
            0, // expectedErc1155Quantity OK (ERC721)
            address(0xBEEF), // <-- mismatch
            0, // OK
            0, // OK
            0, // ERC721
            address(0)
        );
        vm.stopPrank();

        // 2) Mismatch expectedDesiredTokenId (non-swap listing has 0)
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__ListingTermsChanged.selector);
        market.purchaseListing{value: 1 ether}(
            id,
            1 ether,
            0,
            address(0), // OK
            123, // <-- mismatch
            0, // OK
            0,
            address(0)
        );
        vm.stopPrank();

        // 3) Mismatch expectedDesiredErc1155Quantity (non-swap listing has 0)
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__ListingTermsChanged.selector);
        market.purchaseListing{value: 1 ether}(
            id,
            1 ether,
            0,
            address(0),
            0,
            1, // <-- mismatch
            0,
            address(0)
        );
        vm.stopPrank();
    }

    /// Assert ListingCanceledDueToInvalidListing is emitted by cleanListing.
    function testCleanListingEmitsCancellationEvent() public {
        uint128 id = _createListingERC721(false, new address[](0));

        // Revoke approval so cleanListing may cancel the listing.
        vm.prank(seller);
        erc721.approve(address(0), 1);

        // Expect the event from the diamond.
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(id, address(erc721), 1, seller, operator);

        // Trigger as any caller (operator in this test).
        vm.prank(operator);
        market.cleanListing(id);

        // Listing gone.
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    // ERC-1155 partials: 10 units at 1e18 each; buy 3, then 2; check exact residual price/qty and proceeds/fees.
    function testERC1155MultiStepPartialsMaintainPriceProportions() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // List 10 units for total 10 ETH; partials enabled (unit price = 1 ETH).
        vm.prank(seller);
        market.createListing(address(erc1155), 1, seller, 10 ether, address(0), 0, 0, 10, false, true, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        // Buy 3 units -> pay 3 ETH ; remaining: qty=7, price=7 ETH
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 3 ether}(id, 10 ether, 10, address(0), 0, 0, 3, address(0));

        Listing memory after3 = getter.getListingByListingId(id);
        assertEq(after3.erc1155Quantity, 7);
        assertEq(after3.price, 7 ether);
        // Proceeds so far: seller 2.97, owner 0.03
        assertEq(getter.getProceeds(seller), 2.97 ether);
        assertEq(getter.getProceeds(owner), 0.03 ether);

        // Buy 2 more -> pay 2 ETH ; remaining: qty=5, price=5 ETH
        address buyer2 = vm.addr(0x4242);
        vm.deal(buyer2, 10 ether);
        vm.prank(buyer2);
        market.purchaseListing{value: 2 ether}(id, 7 ether, 7, address(0), 0, 0, 2, address(0));

        Listing memory after5 = getter.getListingByListingId(id);
        assertEq(after5.erc1155Quantity, 5);
        assertEq(after5.price, 5 ether);

        // Totals: seller 2.97 + 1.98 = 4.95 ; owner 0.03 + 0.02 = 0.05
        assertEq(getter.getProceeds(seller), 4.95 ether);
        assertEq(getter.getProceeds(owner), 0.05 ether);
    }

    /// Swap (ERC-721 <-> ERC-721): happy path, requires buyer's token approval to marketplace + cleanup of buyer's pre-existing listing.
    function testSwapERC721ToERC721_WithCleanupOfObsoleteListing() public {
        // Fresh ERC721 collections
        MockERC721 a = new MockERC721();
        MockERC721 b = new MockERC721();

        // Whitelist both
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(a));
        collections.addWhitelistedCollection(address(b));
        vm.stopPrank();

        // Mint A#100 to seller; B#200 to buyer
        a.mint(seller, 100);
        b.mint(buyer, 200);

        // Approvals: marketplace for A#100 (by seller), marketplace for B#200 (by buyer)
        vm.prank(seller);
        a.approve(address(diamond), 100);
        vm.prank(buyer);
        b.approve(address(diamond), 200);

        // Buyer pre-lists B#200 (to verify cleanup)
        vm.prank(buyer);
        market.createListing(address(b), 200, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0));
        uint128 buyersBListingId = getter.getNextListingId() - 1;

        // Seller lists A#100 wanting B#200 (swap only, price=0)
        vm.prank(seller);
        market.createListing(address(a), 100, address(0), 0, address(b), 200, 0, 0, false, false, new address[](0));
        uint128 swapId = getter.getNextListingId() - 1;

        // Buyer executes swap; pays 0; expected fields must match.
        vm.prank(buyer);
        market.purchaseListing{value: 0}(
            swapId,
            0, // expectedPrice
            0, // expectedErc1155Quantity (ERC721)
            address(b), // expectedDesiredTokenAddress
            200, // expectedDesiredTokenId
            0, // expectedDesiredErc1155Quantity
            0, // erc1155PurchaseQuantity
            address(0) // desiredErc1155Holder N/A for 721
        );

        // Ownership swapped
        assertEq(a.ownerOf(100), buyer);
        assertEq(b.ownerOf(200), seller);

        // Buyer's obsolete listing for B#200 must be removed
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, buyersBListingId));
        getter.getListingByListingId(buyersBListingId);
    }

    function testSwapERC721ToERC1155_OperatorNoMarketApprovalReverts_ThenSucceeds() public {
        // Whitelist collections
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc721)); // unused but harmless
        collections.addWhitelistedCollection(address(erc1155));
        vm.stopPrank();

        // Mint ERC721 to seller (will be swapped away)
        erc721.mint(seller, 111);
        vm.prank(seller);
        erc721.approve(address(diamond), 111);

        // Use a fresh ERC1155 id so seller has zero starting balance for this id
        uint256 desiredId = 2;
        erc1155.mint(operator, desiredId, 10);

        // Buyer is operator of 'operator', but marketplace NOT approved yet
        vm.prank(operator);
        erc1155.setApprovalForAll(buyer, true);

        // Seller lists ERC721 wanting 6 units of ERC1155 desiredId
        vm.prank(seller);
        market.createListing(
            address(erc721), 111, address(0), 0, address(erc1155), desiredId, 6, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Attempt purchase -> revert: holder hasn't approved marketplace
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.purchaseListing{value: 0}(id, 0, 0, address(erc1155), desiredId, 6, 0, operator);

        // Grant marketplace approval by holder; try again -> succeeds
        vm.prank(operator);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(buyer);
        market.purchaseListing{value: 0}(id, 0, 0, address(erc1155), desiredId, 6, 0, operator);

        // Post-conditions
        assertEq(erc721.ownerOf(111), buyer);
        assertEq(erc1155.balanceOf(operator, desiredId), 4);
        assertEq(erc1155.balanceOf(seller, desiredId), 6);
    }

    /// Royalty edge: bump fee high and royalty so fee+royalty>price -> reverts with RoyaltyFeeExceedsProceeds.
    function testRoyaltyEdge_HighFeePlusRoyaltyExceedsProceeds() public {
        // Royalty NFT: 50% royalty
        MockERC721Royalty r = new MockERC721Royalty();
        r.mint(seller, 1);
        r.setRoyalty(address(0xB0B), 50_000); // 50% of 100_000

        // Whitelist and approve
        vm.prank(owner);
        collections.addWhitelistedCollection(address(r));
        vm.prank(seller);
        r.approve(address(diamond), 1);

        // Set innovation fee to 60%
        vm.prank(owner);
        market.setInnovationFee(60_000);

        // List for 1 ETH (non-swap)
        vm.prank(seller);
        market.createListing(address(r), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        // Purchase must revert: sellerProceeds = 0.4 ETH, royalty = 0.5 ETH -> exceeds proceeds.
        vm.deal(buyer, 2 ether);
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__RoyaltyFeeExceedsProceeds.selector);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    /// ERC-721 by operator: operator creates listing; purchase succeeds.
    function testERC721OperatorListsAndPurchaseSucceeds_AfterFix() public {
        MockERC721 x = new MockERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(x));

        // holder owns token; operator is approved-for-all
        address holder = vm.addr(0xAAAA);
        x.mint(holder, 9);
        vm.prank(holder);
        x.setApprovalForAll(operator, true);

        // Marketplace approval by holder
        vm.prank(holder);
        x.approve(address(diamond), 9);

        // Operator creates listing on behalf of holder
        vm.prank(operator);
        market.createListing(address(x), 9, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        // Confirm listing seller is the holder (post-fix behavior)
        Listing memory L = getter.getListingByListingId(id);
        assertEq(L.seller, holder);

        // Buyer purchases successfully
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        // Token moved to buyer; proceeds to holder
        assertEq(x.ownerOf(9), buyer);
        assertEq(getter.getProceeds(holder), 0.99 ether);
    }

    function testPurchaseRevertsWhenBuyerIsSeller() public {
        // seller lists ERC721 (price = 1 ETH)
        uint128 id = _createListingERC721(false, new address[](0));

        // seller tries to buy own listing -> must revert
        vm.deal(seller, 1 ether);
        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__SameBuyerAsSeller.selector);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    function testSwap1155MissingHolderParamReverts() public {
        // Whitelist listed collection (ERC721). Desired (ERC1155) need not be whitelisted, only must pass interface check.
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        // Seller approval for the listed ERC721
        vm.prank(seller);
        erc721.approve(address(diamond), 1);

        // Create swap listing: want ERC1155 id=1, quantity=2; price=0 (pure swap)
        vm.prank(seller);
        market.createListing(
            address(erc721),
            1,
            address(0),
            0, // price
            address(erc1155), // desiredTokenAddress (ERC1155)
            1, // desiredTokenId
            2, // desiredErc1155Quantity > 0
            0, // erc1155Quantity (listed is ERC721)
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer attempts purchase but omits desiredErc1155Holder -> must revert early
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__WrongErc1155HolderParameter.selector);
        market.purchaseListing{value: 0}(
            id,
            0, // expectedPrice
            0, // expectedErc1155Quantity (listed is ERC721)
            address(erc1155), // expectedDesiredTokenAddress
            1, // expectedDesiredTokenId
            2, // expectedDesiredErc1155Quantity
            0, // erc1155PurchaseQuantity (ERC721 path)
            address(0) // desiredErc1155Holder MISSING -> revert
        );
        vm.stopPrank();
    }

    function testCancelListingByERC721ApprovedOperator() public {
        // Whitelist ERC721 collection
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        // Seller: grant blanket approval to marketplace (so createListing passes)
        vm.prank(seller);
        erc721.setApprovalForAll(address(diamond), true);

        // Seller: set per-token approval to 'operator' (this is the authority we want to test)
        vm.prank(seller);
        erc721.approve(operator, 1);

        // Create listing for token 1
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Operator cancels via getApproved(tokenId) path
        vm.prank(operator);
        market.cancelListing(id);

        // Listing is removed
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCancelListing_UnauthorizedThirdParty_ERC721_Reverts() public {
        // Setup: whitelist + approve + create a live ERC721 listing
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // A random third party (not owner, not token-approved, not operator) cannot cancel
        address rando = vm.addr(0xCAFE);
        vm.startPrank(rando);
        vm.expectRevert(IdeationMarket__NotAuthorizedToCancel.selector);
        market.cancelListing(id);
        vm.stopPrank();
    }

    function testCancelListing_UnauthorizedThirdParty_ERC1155_Reverts() public {
        // Setup: whitelist + operator approval + create a live ERC1155 listing
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155),
            1,
            seller, // erc1155Holder
            10 ether, // price (no swap)
            address(0),
            0,
            0,
            10, // erc1155Quantity
            false, // whitelist disabled
            false, // partialBuy disabled
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // A random third party (not seller, not operator) cannot cancel
        address rando = vm.addr(0xBEEF);
        vm.startPrank(rando);
        vm.expectRevert(IdeationMarket__NotAuthorizedToCancel.selector);
        market.cancelListing(id);
        vm.stopPrank();
    }

    function testSetInnovationFeeEmitsEvent() public {
        uint32 previous = getter.getInnovationFee();
        uint32 next = previous + 123; // any value; you keep fee unbounded by design

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.InnovationFeeUpdated(previous, next);

        vm.prank(owner);
        market.setInnovationFee(next);

        assertEq(getter.getInnovationFee(), next);
    }

    function testPurchaseRevertsIfOwnerChangedOffMarket() public {
        // Create a normal ERC721 listing (price = 1 ETH)
        uint128 id = _createListingERC721(false, new address[](0));

        // Off-market transfer: seller moves token #1 to operator
        vm.prank(seller);
        erc721.transferFrom(seller, operator, 1);

        // Buyer has enough ETH but purchase must revert because stored seller no longer owns the token
        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__SellerNotTokenOwner.selector, id));
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    function testSwapWithEth_ERC721toERC721_HappyPath() public {
        // Fresh collections to avoid interference with other tests
        MockERC721 a = new MockERC721();
        MockERC721 b = new MockERC721();

        // Only the listed collection must be whitelisted, but whitelisting both is harmless
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(a));
        collections.addWhitelistedCollection(address(b));
        vm.stopPrank();

        // Seller owns A#100, buyer owns B#200
        a.mint(seller, 100);
        b.mint(buyer, 200);

        // Approvals for marketplace transfers
        vm.prank(seller);
        a.approve(address(diamond), 100);
        vm.prank(buyer);
        b.approve(address(diamond), 200);

        // Seller lists A#100 wanting B#200 *and* 0.4 ETH
        vm.prank(seller);
        market.createListing(
            address(a),
            100,
            address(0),
            0.4 ether, // price > 0: buyer must pay ETH in addition to providing desired token
            address(b), // desired ERC721
            200,
            0, // desiredErc1155Quantity = 0 (since desired is ERC721)
            0, // erc1155Quantity = 0 (listed is ERC721)
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer executes swap + ETH
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 0.4 ether}(
            id,
            0.4 ether, // expectedPrice
            0, // expectedErc1155Quantity (listed is ERC721)
            address(b), // expectedDesiredTokenAddress
            200, // expectedDesiredTokenId
            0, // expectedDesiredErc1155Quantity
            0, // erc1155PurchaseQuantity (ERC721 path)
            address(0) // desiredErc1155Holder N/A for ERC721
        );

        // Ownership swapped and proceeds credited (fee 1% of 0.4 = 0.004)
        assertEq(a.ownerOf(100), buyer);
        assertEq(b.ownerOf(200), seller);
        assertEq(getter.getProceeds(seller), 0.396 ether);
        assertEq(getter.getProceeds(owner), 0.004 ether);
    }

    function testSwapWithEth_ERC721toERC1155_HappyPath() public {
        // Listed collection must be whitelisted; desired ERC1155 only needs to pass interface checks.
        MockERC721 a = new MockERC721();
        MockERC1155 m1155 = new MockERC1155();

        vm.prank(owner);
        collections.addWhitelistedCollection(address(a));

        // Seller owns A#101
        a.mint(seller, 101);
        vm.prank(seller);
        a.approve(address(diamond), 101);

        // Buyer holds 5 units of desired ERC1155 id=77 and approves marketplace
        uint256 desiredId = 77;
        m1155.mint(buyer, desiredId, 5);
        vm.prank(buyer);
        m1155.setApprovalForAll(address(diamond), true);

        // Seller lists A#101 wanting 3x (ERC1155 id=77) *and* 0.3 ETH
        vm.prank(seller);
        market.createListing(
            address(a),
            101,
            address(0),
            0.3 ether, // ETH component
            address(m1155), // desired ERC1155
            desiredId,
            3, // desiredErc1155Quantity > 0
            0, // erc1155Quantity = 0 (listed is ERC721)
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer executes swap + ETH (must pass desiredErc1155Holder)
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 0.3 ether}(
            id,
            0.3 ether, // expectedPrice
            0, // expectedErc1155Quantity (listed is ERC721)
            address(m1155), // expectedDesiredTokenAddress
            desiredId, // expectedDesiredTokenId
            3, // expectedDesiredErc1155Quantity
            0, // erc1155PurchaseQuantity (ERC721 path)
            buyer // desiredErc1155Holder (buyer is the holder)
        );

        // Token and balance changes; proceeds reflect fee 1% of 0.3 = 0.003
        assertEq(a.ownerOf(101), buyer);
        assertEq(m1155.balanceOf(buyer, desiredId), 2);
        assertEq(m1155.balanceOf(seller, desiredId), 3);
        assertEq(getter.getProceeds(seller), 0.297 ether);
        assertEq(getter.getProceeds(owner), 0.003 ether);
    }

    /// Listing ERC1155 more than holder’s balance should revert with SellerInsufficientTokenBalance.
    function testERC1155CreateInsufficientBalanceReverts() public {
        // Mint only 5 units of a fresh tokenId
        uint256 tokenId = 99;
        erc1155.mint(seller, tokenId, 5);

        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IdeationMarket__SellerInsufficientTokenBalance.selector,
                10, // required
                5 // available
            )
        );
        market.createListing(
            address(erc1155),
            tokenId,
            seller,
            1 ether,
            address(0),
            0,
            0,
            10, // quantity > balance
            false,
            false,
            new address[](0)
        );
    }

    /// ERC1155 listing without marketplace approval must revert NotApprovedForMarketplace.
    function testERC1155CreateWithoutMarketplaceApprovalReverts() public {
        uint256 tokenId = 100;
        erc1155.mint(seller, tokenId, 5);

        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Seller intentionally does not call setApprovalForAll(address(diamond), true)

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.createListing(
            address(erc1155), tokenId, seller, 1 ether, address(0), 0, 0, 5, false, false, new address[](0)
        );
    }

    /// Unauthorised ERC721 lister (not owner/approved) must revert NotAuthorizedOperator.
    function testERC721CreateUnauthorizedListerReverts() public {
        // whitelist and approve the ERC721 for the seller
        _whitelistCollectionAndApproveERC721();
        // buyer attempts to list seller’s token
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotAuthorizedOperator.selector);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
    }

    /// Partial buys cannot be enabled when quantity <= 1 (ERC1155).
    function testPartialBuyWithQuantityOneReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 101;
        erc1155.mint(seller, tokenId, 1);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__PartialBuyNotPossible.selector);
        market.createListing(
            address(erc1155),
            tokenId,
            seller,
            1 ether,
            address(0),
            0,
            0,
            1,
            false,
            true, // partialBuyEnabled on single unit
            new address[](0)
        );
    }

    /// Partial buys cannot be enabled on swap listings (desiredTokenAddress != 0).
    function testPartialBuyWithSwapReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 102;
        erc1155.mint(seller, tokenId, 4);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // listing wants an ERC721 in exchange and partials are enabled → must revert
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__PartialBuyNotPossible.selector);
        market.createListing(
            address(erc1155),
            tokenId,
            seller,
            4 ether,
            address(erc721), // swap (non-zero) desiredTokenAddress
            1,
            0,
            4,
            false,
            true, // partialBuyEnabled
            new address[](0)
        );
    }

    /// No‑swap listings must not specify a non‑zero desiredTokenId.
    function testInvalidNoSwapDesiredTokenIdReverts() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__InvalidNoSwapParameters.selector);
        market.createListing(
            address(erc721),
            1,
            address(0),
            1 ether,
            address(0),
            1, // invalid nonzero desiredTokenId
            0,
            0,
            false,
            false,
            new address[](0)
        );
    }

    /// No‑swap listings must not specify a non‑zero desiredErc1155Quantity.
    function testInvalidNoSwapDesiredErc1155QuantityReverts() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__InvalidNoSwapParameters.selector);
        market.createListing(
            address(erc721),
            1,
            address(0),
            1 ether,
            address(0),
            0,
            1, // invalid nonzero desiredErc1155Quantity
            0,
            false,
            false,
            new address[](0)
        );
    }

    /// Swap listings requiring ERC1155 (quantity > 0) must specify an ERC1155 contract.
    function testSwapDesiredTypeMismatchERC1155Reverts() public {
        _whitelistCollectionAndApproveERC721();
        // seller attempts to create an ERC721 listing wanting ERC721 (erc721) but with desiredErc1155Quantity > 0
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotSupportedTokenStandard.selector);
        market.createListing(
            address(erc721),
            1,
            address(0),
            0,
            address(erc721), // wrong type: this is ERC721 not ERC1155
            2,
            1, // desiredErc1155Quantity > 0 indicates ERC1155
            0,
            false,
            false,
            new address[](0)
        );
    }

    /// Swap listings requiring ERC721 (quantity == 0) must specify an ERC721 contract.
    function testSwapDesiredTypeMismatchERC721Reverts() public {
        _whitelistCollectionAndApproveERC721();
        // seller attempts to create an ERC721 listing wanting an ERC1155 (erc1155) with desiredErc1155Quantity == 0
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotSupportedTokenStandard.selector);
        market.createListing(
            address(erc721),
            1,
            address(0),
            0,
            address(erc1155), // wrong type: this is ERC1155 not ERC721
            1,
            0, // desiredErc1155Quantity == 0 implies ERC721
            0,
            false,
            false,
            new address[](0)
        );
    }

    /// Duplicates in the buyer whitelist on creation should be idempotent (no revert).
    function testWhitelistDuplicatesOnCreateIdempotent() public {
        _whitelistCollectionAndApproveERC721();
        address[] memory allowed = new address[](3);
        allowed[0] = buyer;
        allowed[1] = buyer; // duplicate
        allowed[2] = operator;

        vm.prank(seller);
        market.createListing(address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, true, false, allowed);
        uint128 id = getter.getNextListingId() - 1;
        assertTrue(getter.isBuyerWhitelisted(id, buyer));
        assertTrue(getter.isBuyerWhitelisted(id, operator));
    }

    /// Updating from ERC721 to ERC1155 (changing quantity from 0 to >0) must revert.
    function testUpdateFlipERC721ToERC1155Reverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__WrongQuantityParameter.selector);
        market.updateListing(
            id,
            1 ether,
            address(0),
            0,
            0,
            5, // newErc1155Quantity > 0 (trying to flip to ERC1155)
            false,
            false,
            new address[](0)
        );
    }

    /// Updating from ERC1155 to ERC721 (setting new quantity to 0) must revert.
    function testUpdateFlipERC1155ToERC721Reverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 200;
        erc1155.mint(seller, tokenId, 5);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), tokenId, seller, 5 ether, address(0), 0, 0, 5, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__WrongQuantityParameter.selector);
        market.updateListing(
            id,
            5 ether,
            address(0),
            0,
            0,
            0, // setting quantity to 0 (trying to flip to ERC721)
            false,
            false,
            new address[](0)
        );
    }

    /// Only seller or its authorised operator may update an ERC1155 listing.
    function testERC1155UpdateUnauthorizedOperatorReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 201;
        erc1155.mint(seller, tokenId, 5);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), tokenId, seller, 5 ether, address(0), 0, 0, 5, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // buyer has no rights → NotAuthorizedOperator
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotAuthorizedOperator.selector);
        market.updateListing(id, 5 ether, address(0), 0, 0, 5, false, false, new address[](0));
    }

    //
    function testERC1155UpdateApprovalRevokedReverts() public {
        // Whitelist & approve; create ERC1155 listing (qty>0 keeps standard)
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Revoke marketplace approval, then attempt update → must revert
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), false);

        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.updateListing(id, 10 ether, address(0), 0, 0, 10, false, false, new address[](0));
        vm.stopPrank();
    }

    /// Updating quantity greater than seller’s ERC1155 balance must revert.
    function testERC1155UpdateBalanceTooLowReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 202;
        erc1155.mint(seller, tokenId, 5);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), tokenId, seller, 5 ether, address(0), 0, 0, 5, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        // seller transfers away 3 units (leaving 2)
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, buyer, tokenId, 3, "");
        // update to quantity 5 (available 2) → revert with SellerInsufficientTokenBalance
        vm.prank(seller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IdeationMarket__SellerInsufficientTokenBalance.selector,
                5, // new requested
                2 // remaining
            )
        );
        market.updateListing(id, 5 ether, address(0), 0, 0, 5, false, false, new address[](0));
    }

    /// Updating ERC721 listing with revoked approval must revert.
    function testERC721UpdateApprovalRevokedReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        // revoke approval
        vm.prank(seller);
        erc721.approve(address(0), 1);
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.updateListing(id, 1 ether, address(0), 0, 0, 0, false, false, new address[](0));
    }

    /// Updating partial buy on a too‑small ERC1155 quantity must revert.
    function testUpdatePartialBuyWithSmallQuantityReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 203;
        erc1155.mint(seller, tokenId, 1);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), tokenId, seller, 1 ether, address(0), 0, 0, 1, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__PartialBuyNotPossible.selector);
        market.updateListing(
            id,
            1 ether,
            address(0),
            0,
            0,
            1,
            false,
            true, // attempt to enable partial buys
            new address[](0)
        );
    }

    /// Updating partial buy while introducing a swap must revert.
    function testUpdatePartialBuyWithSwapReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 204;
        erc1155.mint(seller, tokenId, 5);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), tokenId, seller, 5 ether, address(0), 0, 0, 5, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        // update with partialBuyEnabled true AND desiredTokenAddress non-zero → revert
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__PartialBuyNotPossible.selector);
        market.updateListing(id, 5 ether, address(erc721), 1, 0, 5, false, true, new address[](0));
    }

    /// No‑swap update cannot set a non‑zero desiredTokenId.
    function testUpdateInvalidNoSwapDesiredTokenIdReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__InvalidNoSwapParameters.selector);
        market.updateListing(
            id,
            1 ether,
            address(0),
            1, // invalid non-zero desiredTokenId
            0,
            0,
            false,
            false,
            new address[](0)
        );
    }

    /// No‑swap update cannot set a non‑zero desiredErc1155Quantity.
    function testUpdateInvalidNoSwapDesiredErc1155QuantityReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__InvalidNoSwapParameters.selector);
        market.updateListing(
            id,
            1 ether,
            address(0),
            0,
            1, // invalid non-zero desiredErc1155Quantity
            0,
            false,
            false,
            new address[](0)
        );
    }

    /// Swap update requiring ERC1155 must specify an ERC1155 contract.
    function testUpdateSwapDesiredTypeMismatchERC1155Reverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotSupportedTokenStandard.selector);
        market.updateListing(
            id,
            0,
            address(erc721), // wrong type: ERC721 not ERC1155
            2,
            1, // desiredErc1155Quantity > 0
            0,
            false,
            false,
            new address[](0)
        );
    }

    /// Swap update requiring ERC721 must specify an ERC721 contract.
    function testUpdateSwapDesiredTypeMismatchERC721Reverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotSupportedTokenStandard.selector);
        market.updateListing(
            id,
            0,
            address(erc1155), // wrong type: ERC1155 not ERC721
            1,
            0, // desiredErc1155Quantity == 0 implies ERC721
            0,
            false,
            false,
            new address[](0)
        );
    }

    function testSwapExpectedDesiredFieldsMismatchReverts() public {
        // create 721->721 swap listing (price 0)
        _whitelistCollectionAndApproveERC721();
        MockERC721 other = new MockERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(other));
        other.mint(buyer, 42);
        vm.prank(buyer);
        other.approve(address(diamond), 42);
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 0, address(other), 42, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // wrong expectedDesiredTokenId
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__ListingTermsChanged.selector);
        market.purchaseListing{value: 0}(id, 0, 0, address(other), 999, 0, 0, address(0));
    }

    /// Duplicates in the buyer whitelist on update are idempotent.
    function testWhitelistDuplicatesOnUpdateIdempotent() public {
        uint128 id = _createListingERC721(false, new address[](0));
        address[] memory allowed = new address[](3);
        allowed[0] = buyer;
        allowed[1] = buyer;
        allowed[2] = operator;
        vm.prank(seller);
        market.updateListing(
            id,
            1 ether,
            address(0),
            0,
            0,
            0,
            true, // enabling whitelist
            false,
            allowed
        );
        assertTrue(getter.isBuyerWhitelisted(id, buyer));
        assertTrue(getter.isBuyerWhitelisted(id, operator));
    }

    /// After listing an ERC1155, if seller’s balance drops below listed quantity, purchase reverts.
    function testERC1155PurchaseSellerBalanceDroppedReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 400;
        erc1155.mint(seller, tokenId, 10);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), tokenId, seller, 10 ether, address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // seller transfers away 5 units leaving 5 (less than listed 10)
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, buyer, tokenId, 5, "");

        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IdeationMarket__SellerInsufficientTokenBalance.selector,
                10, // required
                5 // available
            )
        );
        market.purchaseListing{value: 10 ether}(id, 10 ether, 10, address(0), 0, 0, 10, address(0));
    }

    /// If marketplace approval is revoked for an ERC1155 listing, purchase reverts.
    function testERC1155PurchaseMarketplaceApprovalRevokedReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 401;
        erc1155.mint(seller, tokenId, 10);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(seller);
        market.createListing(
            address(erc1155), tokenId, seller, 10 ether, address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // seller revokes approval
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), false);

        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.purchaseListing{value: 10 ether}(id, 10 ether, 10, address(0), 0, 0, 10, address(0));
    }

    /// Purchase uses the fee rate frozen at listing time, not the current innovationFee.
    function testPurchaseFeeSnapshotOldFee() public {
        _whitelistCollectionAndApproveERC721();
        // Create listing with initial fee of 1% (1000)
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Owner raises fee to 2.5%
        vm.prank(owner);
        market.setInnovationFee(2500);

        // Purchase: seller must still receive 0.99, owner 0.01
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        assertEq(getter.getProceeds(seller), 0.99 ether);
        assertEq(getter.getProceeds(owner), 0.01 ether);
    }

    // Misconfigured fee (>100%) should make purchase impossible.
    // Underflow in `sellerProceeds = purchasePrice - innovationProceeds` triggers
    // Solidity 0.8 arithmetic revert.
    function testPathologicalFeeCausesRevert() public {
        _whitelistCollectionAndApproveERC721();

        vm.prank(owner);
        market.setInnovationFee(200_000); // 200% with denominator 100_000

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(stdError.arithmeticError); // forge-std
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));
    }

    function testFeeExactly100Percent_SucceedsSellerGetsZero() public {
        _whitelistCollectionAndApproveERC721();

        vm.prank(owner);
        market.setInnovationFee(100_000); // exactly 100%

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        // Seller gets 0, owner gets full 1 ETH (no royalty in this test)
        assertEq(getter.getProceeds(seller), 0);
        assertEq(getter.getProceeds(owner), 1 ether);

        // Listing is gone and ownership transferred
        assertEq(erc721.ownerOf(1), buyer);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// ERC2981 token returning zero royalty should succeed and pay only fee.
    function testERC2981ZeroRoyalty() public {
        MockERC721Royalty token = new MockERC721Royalty();
        token.mint(seller, 1);
        token.setRoyalty(address(0xBEEF), 0); // 0%

        vm.prank(owner);
        collections.addWhitelistedCollection(address(token));
        vm.prank(seller);
        token.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(token), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        // Seller 0.99, owner 0.01, royaltyReceiver 0
        assertEq(getter.getProceeds(seller), 0.99 ether);
        assertEq(getter.getProceeds(owner), 0.01 ether);
        assertEq(getter.getProceeds(address(0xBEEF)), 0);
    }

    /// ERC2981 royaltyReceiver = address(0) should credit zero address.
    function testRoyaltyReceiverZeroAddress() public {
        MockERC721Royalty r = new MockERC721Royalty();
        r.mint(seller, 1);
        r.setRoyalty(address(0), 10_000); // 10%
        vm.prank(owner);
        collections.addWhitelistedCollection(address(r));
        vm.prank(seller);
        r.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(address(r), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        // Proceeds: seller 0.89, owner 0.01, zero address 0.10
        assertEq(getter.getProceeds(seller), 0.89 ether);
        assertEq(getter.getProceeds(owner), 0.01 ether);
        assertEq(getter.getProceeds(address(0)), 0.1 ether);
    }

    /// ERC2981 token that reverts royaltyInfo must cause purchase to revert.
    function testERC2981RevertingRoyaltyRevertsPurchase() public {
        MockERC721RoyaltyReverting r = new MockERC721RoyaltyReverting();
        r.mint(seller, 1);
        vm.prank(owner);
        collections.addWhitelistedCollection(address(r));
        vm.prank(seller);
        r.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(address(r), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(); // royaltyInfo reverts inside purchase
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));
    }

    /// Swap (ERC721→ERC1155) purchase must revert if buyer has insufficient ERC1155 balance.
    function testSwapERC1155DesiredBalanceInsufficientReverts() public {
        // fresh ERC721 collection
        MockERC721 a = new MockERC721();
        a.mint(seller, 1);
        vm.prank(owner);
        collections.addWhitelistedCollection(address(a));
        vm.prank(seller);
        a.approve(address(diamond), 1);

        // Seller lists token #1 wanting 5 units of ERC1155 id=1
        vm.prank(seller);
        market.createListing(address(a), 1, address(0), 0, address(erc1155), 1, 5, 0, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        // Buyer only holds 2 units of that ERC1155 and approves
        erc1155.mint(buyer, 1, 2);
        vm.prank(buyer);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IdeationMarket__InsufficientSwapTokenBalance.selector,
                5, // required
                2 // available
            )
        );
        market.purchaseListing{value: 0}(id, 0, 0, address(erc1155), 1, 5, 0, buyer);
    }

    /// Swap (ERC721→ERC721) purchase must revert if buyer did not approve desired token.
    function testSwapERC721DesiredNotApprovedReverts() public {
        MockERC721 a = new MockERC721();
        MockERC721 b = new MockERC721();
        a.mint(seller, 10);
        b.mint(buyer, 20);

        vm.prank(owner);
        collections.addWhitelistedCollection(address(a));
        vm.prank(seller);
        a.approve(address(diamond), 10);

        vm.prank(seller);
        market.createListing(address(a), 10, address(0), 0, address(b), 20, 0, 0, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        // Buyer did not approve b#20 to marketplace
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.purchaseListing{value: 0}(id, 0, 0, address(b), 20, 0, 0, address(0));
    }

    /// Swap (ERC721→ERC721) must revert if buyer neither owns nor is approved for desired token.
    function testSwapERC721BuyerNotOwnerOrOperatorReverts() public {
        MockERC721 a = new MockERC721();
        MockERC721 b = new MockERC721();
        a.mint(seller, 1);
        b.mint(operator, 2); // desired token held by operator

        vm.prank(owner);
        collections.addWhitelistedCollection(address(a));
        vm.prank(seller);
        a.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(address(a), 1, address(0), 0, address(b), 2, 0, 0, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        // buyer attempts purchase but has no rights over b#2
        vm.prank(buyer);
        vm.expectRevert(IdeationMarket__NotAuthorizedOperator.selector);
        market.purchaseListing{value: 0}(id, 0, 0, address(b), 2, 0, 0, address(0));
    }

    /// ERC1155 listings can be cancelled by any operator approved for the seller.
    function testCancelERC1155ListingByOperator() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        uint256 tokenId = 500;
        erc1155.mint(seller, tokenId, 10);
        // seller grants operator blanket approval
        vm.prank(seller);
        erc1155.setApprovalForAll(operator, true);
        // also approve marketplace
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), tokenId, seller, 10 ether, address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // operator cancels
        vm.prank(operator);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// cleanListing should cancel if collection has been removed from whitelist.
    function testCleanListingAfterDeWhitelistingCancels() public {
        uint128 id = _createListingERC721(false, new address[](0));
        // Remove collection
        vm.prank(owner);
        collections.removeWhitelistedCollection(address(erc721));
        // cleanListing should delete the listing
        vm.prank(operator);
        market.cleanListing(id);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// Removing whitelist entries on a non‑existent listing reverts.
    function testBuyerWhitelistRemoveNonexistentListingReverts() public {
        address[] memory list = new address[](1);
        list[0] = buyer;
        vm.prank(seller);
        vm.expectRevert(BuyerWhitelist__ListingDoesNotExist.selector);
        buyers.removeBuyerWhitelistAddresses(123456, list);
    }

    /// Removing an address that isn’t in the whitelist should not revert.
    function testBuyerWhitelistRemoveNonWhitelistedNoRevert() public {
        address[] memory allowed = new address[](1);
        allowed[0] = buyer;
        uint128 id = _createListingERC721(true, allowed);

        // operator is not on the list
        address[] memory toRemove = new address[](1);
        toRemove[0] = operator;

        vm.prank(seller);
        buyers.removeBuyerWhitelistAddresses(id, toRemove);
        assertFalse(getter.isBuyerWhitelisted(id, operator));
    }

    /// Adding/removing whitelist entries while whitelist is disabled must not revert.
    function testBuyerWhitelistAddRemoveWhenDisabledAllowed() public {
        uint128 id = _createListingERC721(false, new address[](0));
        address[] memory arr = new address[](1);
        arr[0] = buyer;
        // Add a buyer even though whitelist is disabled
        vm.prank(seller);
        buyers.addBuyerWhitelistAddresses(id, arr);
        // Remove the same buyer
        vm.prank(seller);
        buyers.removeBuyerWhitelistAddresses(id, arr);
        // Buyer should remain not whitelisted
        assertFalse(getter.isBuyerWhitelisted(id, buyer));
    }

    /// batchAddWhitelistedCollections must revert if any entry is zero address.
    function testBatchAddWhitelistedCollectionWithZeroReverts() public {
        address[] memory arr = new address[](2);
        arr[0] = address(erc721);
        arr[1] = address(0);
        vm.prank(owner);
        vm.expectRevert(CollectionWhitelist__ZeroAddress.selector);
        collections.batchAddWhitelistedCollections(arr);
    }

    /// isBuyerWhitelisted should revert on invalid listing id.
    function testIsBuyerWhitelistedInvalidListingIdReverts() public {
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, 999999));
        getter.isBuyerWhitelisted(999999, buyer);
    }

    function testWithdrawProceedsReceiverReverts() public {
        // Contract that reverts on receiving ETH
        RevertOnReceive rc = new RevertOnReceive();

        // Whitelist ERC721 and mint a token to rc
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));
        erc721.mint(address(rc), 777);

        // rc approves marketplace and creates a listing
        vm.prank(address(rc));
        erc721.approve(address(diamond), 777);
        vm.prank(address(rc));
        market.createListing(
            address(erc721), 777, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer purchases, crediting proceeds to rc
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        // rc attempts to withdraw; transfer must fail and revert with TransferFailed
        vm.prank(address(rc));
        vm.expectRevert(IdeationMarket__TransferFailed.selector);
        market.withdrawProceeds();

        // Proceeds remain intact for rc
        assertEq(getter.getProceeds(address(rc)), 0.99 ether);
    }

    /// After collection is removed from whitelist, purchases should still succeed.
    function testPurchaseAfterCollectionDeWhitelistingStillSucceeds() public {
        uint128 id = _createListingERC721(false, new address[](0));
        // remove collection
        vm.prank(owner);
        collections.removeWhitelistedCollection(address(erc721));

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));
        assertEq(erc721.ownerOf(1), buyer);
    }

    function testCreateListingWithNonNFTContracQt0tReverts() public {
        NotAnNFT bad = new NotAnNFT();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(bad));

        // Note: the whitelist does NOT enforce interfaces—you can whitelist any address.
        // The revert happens inside createListing’s interface check:
        // with erc1155Quantity == 0 it requires ERC721 via IERC165; a non-NFT reverts with NotSupportedTokenStandard.

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotSupportedTokenStandard.selector);
        market.createListing(address(bad), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0));
    }

    function testCreateListingWithNonNFTContractQ9Reverts() public {
        NotAnNFT bad = new NotAnNFT();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(bad));

        // Note: the whitelist does NOT enforce interfaces—you can whitelist any address.
        // The revert happens inside createListing’s interface check:
        // with erc1155Quantity == 9 it requires ERC1155 via IERC165; a non-NFT reverts with NotSupportedTokenStandard.

        vm.prank(seller);
        vm.expectRevert(IdeationMarket__NotSupportedTokenStandard.selector);
        market.createListing(address(bad), 1, address(0), 1 ether, address(0), 0, 0, 9, false, false, new address[](0));
    }

    function testUpdatePriceZeroWithoutSwapReverts() public {
        uint128 id = _createListingERC721(false, new address[](0));
        vm.prank(seller);
        vm.expectRevert(IdeationMarket__FreeListingsNotSupported.selector);
        market.updateListing(id, 0, address(0), 0, 0, 0, false, false, new address[](0));
    }

    function testCancelERC721ByOperatorForAll() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        erc721.setApprovalForAll(operator, true);
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        vm.prank(operator);
        market.cancelListing(id);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// ListingCreated fires with exact parameters for ERC721 listing
    function testEmitListingCreated() public {
        _whitelistCollectionAndApproveERC721();
        uint128 expectedId = getter.getNextListingId();

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCreated(
            expectedId,
            address(erc721),
            1,
            0, // erc1155Quantity (ERC721 -> 0)
            1 ether,
            getter.getInnovationFee(),
            seller,
            false,
            false,
            address(0),
            0,
            0
        );

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
    }

    /// ListingUpdated fires with exact parameters on price change
    function testEmitListingUpdated() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingUpdated(
            id, address(erc721), 1, 0, 2 ether, getter.getInnovationFee(), seller, false, false, address(0), 0, 0
        );

        vm.prank(seller);
        market.updateListing(id, 2 ether, address(0), 0, 0, 0, false, false, new address[](0));
    }

    /// ListingPurchased fires with exact parameters on ERC721 full purchase
    function testEmitListingPurchased() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingPurchased(
            id, address(erc721), 1, 0, false, 1 ether, INNOVATION_FEE, seller, buyer, address(0), 0, 0
        );

        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));
    }

    /// RoyaltyPaid fires with exact parameters
    function testEmitRoyaltyPaid() public {
        // Prepare royalty NFT (10%) and whitelist
        MockERC721Royalty royaltyNft = new MockERC721Royalty();
        address royaltyReceiver = address(0xB0B);
        royaltyNft.setRoyalty(royaltyReceiver, 10_000); // 10% of 100_000

        vm.prank(owner);
        collections.addWhitelistedCollection(address(royaltyNft));
        royaltyNft.mint(seller, 1);

        vm.prank(seller);
        royaltyNft.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(royaltyNft), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.RoyaltyPaid(id, royaltyReceiver, address(royaltyNft), 1, 0.1 ether);

        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));
    }

    /// ListingCanceled fires with exact parameters
    function testEmitListingCanceled() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceled(id, address(erc721), 1, seller, seller);

        vm.prank(seller);
        market.cancelListing(id);
    }

    /// ListingCanceledDueToInvalidListing fires with exact parameters
    function testEmitListingCanceledDueToInvalidListing() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        erc721.approve(address(0), 1);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(id, address(erc721), 1, seller, operator);

        vm.prank(operator);
        market.cleanListing(id);
    }

    /// InnovationFeeUpdated fires with exact parameters
    function testEmitInnovationFeeUpdated() public {
        uint32 prev = getter.getInnovationFee();
        uint32 next = 777;

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.InnovationFeeUpdated(prev, next);

        // prank applies to the NEXT call only — apply it to the setter
        vm.prank(owner);
        market.setInnovationFee(next);

        // sanity check
        assertEq(getter.getInnovationFee(), next);
    }

    /// ProceedsWithdrawn fires with exact parameters
    function testEmitProceedsWithdrawn() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        uint256 proceedsBefore = getter.getProceeds(seller);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ProceedsWithdrawn(seller, proceedsBefore);

        vm.prank(seller);
        market.withdrawProceeds();
    }

    /* ================================
       ERC1155 reverse index coverage
       ================================ */

    function testERC1155_MultiListings_SameAndDifferentSellers_AppearInReverseIndex() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Same (token,id), different holders → two listings
        erc1155.mint(seller, 9, 5);
        erc1155.mint(operator, 9, 7);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(operator);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(address(erc1155), 9, seller, 5 ether, address(0), 0, 0, 5, false, false, new address[](0));
        uint128 id1 = getter.getNextListingId() - 1;

        vm.prank(operator);
        market.createListing(
            address(erc1155), 9, operator, 7 ether, address(0), 0, 0, 7, false, false, new address[](0)
        );
        uint128 id2 = getter.getNextListingId() - 1;

        Listing[] memory arr = getter.getListingsByNFT(address(erc1155), 9);
        assertEq(arr.length, 2);
        bool seen1;
        bool seen2;
        for (uint256 i; i < arr.length; i++) {
            if (arr[i].listingId == id1) seen1 = true;
            if (arr[i].listingId == id2) seen2 = true;
        }
        assertTrue(seen1 && seen2);
    }

    function testERC1155_ReverseIndex_MiddleDelete_Compaction() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        erc1155.mint(seller, 10, 3);
        erc1155.mint(buyer, 10, 4);
        erc1155.mint(operator, 10, 5);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(buyer);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(operator);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(address(erc1155), 10, seller, 3 ether, address(0), 0, 0, 3, false, false, new address[](0));
        uint128 id1 = getter.getNextListingId() - 1;

        vm.prank(buyer);
        market.createListing(address(erc1155), 10, buyer, 4 ether, address(0), 0, 0, 4, false, false, new address[](0));
        uint128 id2 = getter.getNextListingId() - 1;

        vm.prank(operator);
        market.createListing(
            address(erc1155), 10, operator, 5 ether, address(0), 0, 0, 5, false, false, new address[](0)
        );
        uint128 id3 = getter.getNextListingId() - 1;

        // Delete the middle listing and ensure the others remain returned
        vm.prank(buyer);
        market.cancelListing(id2);

        Listing[] memory arr = getter.getListingsByNFT(address(erc1155), 10);
        assertEq(arr.length, 2);
        bool seen1;
        bool seen3;
        for (uint256 i; i < arr.length; i++) {
            if (arr[i].listingId == id1) seen1 = true;
            if (arr[i].listingId == id3) seen3 = true;
        }
        assertTrue(seen1 && seen3);
    }

    /* ======================================
       ERC1155 partial-buy payment edge cases
       ====================================== */

    function testERC1155_PartialBuy_UnderpayReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        erc1155.mint(seller, 11, 10);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // qty=10, price=10 ETH → unit=1 ETH; partials enabled
        vm.prank(seller);
        market.createListing(
            address(erc1155), 11, seller, 10 ether, address(0), 0, 0, 10, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);
        // Buy 4 units but send 3.9 ETH → PriceNotMet(listingId, 4, 3.9)
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__PriceNotMet.selector, id, 4 ether, 3.9 ether));
        market.purchaseListing{value: 3.9 ether}(id, 10 ether, 10, address(0), 0, 0, 4, address(0));
        vm.stopPrank();
    }

    function testERC1155_PartialBuy_OverpayCreditsBuyer() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        erc1155.mint(seller, 12, 10);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // qty=10, price=10 ETH; partials enabled
        vm.prank(seller);
        market.createListing(
            address(erc1155), 12, seller, 10 ether, address(0), 0, 0, 10, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buy 4 units; send 4.5 ETH → 0.5 ETH credited to buyer
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 4.5 ether}(id, 10 ether, 10, address(0), 0, 0, 4, address(0));

        assertEq(getter.getProceeds(buyer), 0.5 ether); // credit
        assertEq(getter.getProceeds(seller), 3.96 ether); // 4 - 1% fee
        assertEq(getter.getProceeds(owner), 0.04 ether);

        // Listing mutated 10→6 qty and 10→6 price
        Listing memory L = getter.getListingByListingId(id);
        assertEq(L.erc1155Quantity, 6);
        assertEq(L.price, 6 ether);
    }

    /* =========================================
       Overpay behaviour on swap (with and zero-ETH)
       ========================================= */

    function testSwapWithEth_OverpayCreditsBuyer() public {
        // Fresh 721s
        MockERC721 A = new MockERC721();
        MockERC721 B = new MockERC721();

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(A));
        collections.addWhitelistedCollection(address(B));
        vm.stopPrank();

        // Seller owns A#1, buyer owns B#2
        A.mint(seller, 1);
        B.mint(buyer, 2);

        vm.prank(seller);
        A.approve(address(diamond), 1);
        vm.prank(buyer);
        B.approve(address(diamond), 2);

        // List A#1 wanting B#2 + 0.4 ETH
        vm.prank(seller);
        market.createListing(address(A), 1, address(0), 0.4 ether, address(B), 2, 0, 0, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        // Buyer sends 0.5 ETH → 0.1 ETH excess credited back to buyer
        vm.prank(buyer);
        market.purchaseListing{value: 0.5 ether}(id, 0.4 ether, 0, address(B), 2, 0, 0, address(0));

        assertEq(getter.getProceeds(buyer), 0.1 ether);
        assertEq(getter.getProceeds(seller), 0.396 ether);
        assertEq(getter.getProceeds(owner), 0.004 ether);
        assertEq(A.ownerOf(1), buyer);
        assertEq(B.ownerOf(2), seller);
    }

    function testPureSwap_AccidentalEthCreditedToBuyer() public {
        MockERC721 A = new MockERC721();
        MockERC721 B = new MockERC721();

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(A));
        collections.addWhitelistedCollection(address(B));
        vm.stopPrank();

        A.mint(seller, 10);
        B.mint(buyer, 20);

        vm.prank(seller);
        A.approve(address(diamond), 10);
        vm.prank(buyer);
        B.approve(address(diamond), 20);

        // price=0 (pure swap)
        vm.prank(seller);
        market.createListing(address(A), 10, address(0), 0, address(B), 20, 0, 0, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        // Accidentally sends ETH; all should be credited back to buyer proceeds (no fee)
        market.purchaseListing{value: 0.25 ether}(id, 0, 0, address(B), 20, 0, 0, address(0));

        assertEq(getter.getProceeds(buyer), 0.25 ether);
        assertEq(getter.getProceeds(owner), 0);
        assertEq(A.ownerOf(10), buyer);
        assertEq(B.ownerOf(20), seller);
    }

    /* ==================================
       Whitelist enforcement on swaps
       ================================== */

    function testWhitelist_BlocksSwap_ERC721toERC721() public {
        MockERC721 A = new MockERC721();
        MockERC721 B = new MockERC721();

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(A));
        collections.addWhitelistedCollection(address(B));
        vm.stopPrank();

        A.mint(seller, 100);
        B.mint(operator, 200); // operator will be the allowed swapper

        vm.prank(seller);
        A.approve(address(diamond), 100);
        vm.prank(operator);
        B.approve(address(diamond), 200);

        address[] memory allow = new address[](1);
        allow[0] = operator;

        vm.prank(seller);
        market.createListing(address(A), 100, address(0), 0, address(B), 200, 0, 0, true, false, allow);
        uint128 id = getter.getNextListingId() - 1;

        // Non-whitelisted buyer is blocked
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__BuyerNotWhitelisted.selector, id, buyer));
        market.purchaseListing{value: 0}(id, 0, 0, address(B), 200, 0, 0, address(0));

        // Whitelisted operator succeeds
        vm.prank(operator);
        market.purchaseListing{value: 0}(id, 0, 0, address(B), 200, 0, 0, address(0));
        assertEq(A.ownerOf(100), operator);
        assertEq(B.ownerOf(200), seller);
    }

    function testWhitelist_BlocksSwap_ERC721toERC1155() public {
        MockERC721 A = new MockERC721();

        vm.prank(owner);
        collections.addWhitelistedCollection(address(A)); // listed collection

        // Seller has A#1; operator has desired 1155
        A.mint(seller, 1);
        vm.prank(seller);
        A.approve(address(diamond), 1);

        erc1155.mint(operator, 77, 5);
        vm.prank(operator);
        erc1155.setApprovalForAll(address(diamond), true);

        address[] memory allow = new address[](1);
        allow[0] = operator;

        // Want 3 units of id=77
        vm.prank(seller);
        market.createListing(address(A), 1, address(0), 0, address(erc1155), 77, 3, 0, true, false, allow);
        uint128 id = getter.getNextListingId() - 1;

        // Non-whitelisted buyer blocked
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__BuyerNotWhitelisted.selector, id, buyer));
        market.purchaseListing{value: 0}(id, 0, 0, address(erc1155), 77, 3, 0, operator);

        // Whitelisted operator succeeds
        vm.prank(operator);
        market.purchaseListing{value: 0}(id, 0, 0, address(erc1155), 77, 3, 0, operator);
        assertEq(A.ownerOf(1), operator);
        assertEq(erc1155.balanceOf(operator, 77), 2);
        assertEq(erc1155.balanceOf(seller, 77), 3);
    }

    /* =======================================================
       Whitelist mutations by token-approved & operator-for-all
       ======================================================= */

    function testBuyerWhitelist_AddRemove_ByERC721TokenApprovedOperator() public {
        _whitelistCollectionAndApproveERC721();

        // Create whitelist-enabled listing (seed with buyer)
        address[] memory allow = new address[](1);
        allow[0] = buyer;
        vm.prank(seller);
        market.createListing(address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, true, false, allow);
        uint128 id = getter.getNextListingId() - 1;

        // Approve 'operator' for that ERC721 token
        vm.prank(seller);
        erc721.approve(operator, 1);

        // operator can add/remove entries
        address who = vm.addr(123);
        address[] memory arr = new address[](1);
        arr[0] = who;

        vm.prank(operator);
        buyers.addBuyerWhitelistAddresses(id, arr);
        assertTrue(getter.isBuyerWhitelisted(id, who));

        vm.prank(operator);
        buyers.removeBuyerWhitelistAddresses(id, arr);
        assertFalse(getter.isBuyerWhitelisted(id, who));
    }

    function testBuyerWhitelist_AddRemove_ByERC721OperatorForAll() public {
        _whitelistCollectionAndApproveERC721();

        address[] memory allow = new address[](1);
        allow[0] = buyer;
        vm.prank(seller);
        market.createListing(address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, true, false, allow);
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        erc721.setApprovalForAll(operator, true);

        address who = vm.addr(456);
        address[] memory arr = new address[](1);
        arr[0] = who;

        vm.prank(operator);
        buyers.addBuyerWhitelistAddresses(id, arr);
        assertTrue(getter.isBuyerWhitelisted(id, who));

        vm.prank(operator);
        buyers.removeBuyerWhitelistAddresses(id, arr);
        assertFalse(getter.isBuyerWhitelisted(id, who));
    }

    /* ===========================
       Swaps with listed ERC1155
       =========================== */

    function testSwap_ERC1155toERC721_HappyPath() public {
        // Listed collection must be whitelisted
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Seller lists 6 of id=500 wanting B#9
        MockERC721 B = new MockERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(B)); // optional but fine

        erc1155.mint(seller, 500, 6);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        B.mint(buyer, 9);
        vm.prank(buyer);
        B.approve(address(diamond), 9);

        vm.prank(seller);
        market.createListing(address(erc1155), 500, seller, 0, address(B), 9, 0, 6, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        // Buy full quantity (partials disabled): erc1155PurchaseQuantity=6
        vm.prank(buyer);
        market.purchaseListing{value: 0}(id, 0, 6, address(B), 9, 0, 6, address(0));

        assertEq(erc1155.balanceOf(buyer, 500), 6);
        assertEq(erc1155.balanceOf(seller, 500), 0);
        assertEq(B.ownerOf(9), seller);
        // price=0 → no fee/proceeds
        assertEq(getter.getProceeds(owner), 0);
        assertEq(getter.getProceeds(seller), 0);
    }

    function testSwap_ERC1155toERC1155_HappyPath() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155)); // listed collection

        // Seller lists 5 of idA wanting 3 of idB (same contract is fine)
        uint256 idA = 600;
        uint256 idB = 601;

        erc1155.mint(seller, idA, 5);
        erc1155.mint(buyer, idB, 4);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(buyer);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), idA, seller, 0, address(erc1155), idB, 3, 5, false, false, new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        // Buyer pays with 3 units of idB; receives 5 of idA
        vm.prank(buyer);
        market.purchaseListing{value: 0}(listingId, 0, 5, address(erc1155), idB, 3, 5, buyer);

        assertEq(erc1155.balanceOf(buyer, idA), 5);
        assertEq(erc1155.balanceOf(seller, idA), 0);
        assertEq(erc1155.balanceOf(buyer, idB), 1);
        assertEq(erc1155.balanceOf(seller, idB), 3);
    }

    function testSwap_ERC1155toERC1155_DesiredHolderNoMarketApprovalReverts_ThenSucceeds() public {
        // Whitelist the 1155 collection
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Balances:
        // - seller has tokenId=1 (listed)
        // - buyer  has tokenId=2 (desired)
        erc1155.mint(seller, 111, 10);
        erc1155.mint(buyer, 222, 10);

        // Seller approves marketplace; buyer (desired holder) does NOT yet.
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // Seller lists 10x id=1, pure swap for 10x id=2 (price=0)
        vm.prank(seller);
        market.createListing(
            address(erc1155),
            111,
            seller, // erc1155Holder
            0, // price (pure swap)
            address(erc1155), // desiredTokenAddress
            222, // desiredTokenId
            10, // desiredErc1155Quantity
            10, // erc1155Quantity (listed)
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Attempt swap while desired holder (buyer) has NOT approved the marketplace → revert
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__NotApprovedForMarketplace.selector);
        market.purchaseListing{value: 0}(
            id,
            0, // expectedPrice
            10, // expected listed erc1155Quantity
            address(erc1155), // expected desired token addr
            222, // expected desired tokenId
            10, // expected desired erc1155 qty
            10, // erc1155PurchaseQuantity
            buyer // desiredErc1155Holder
        );
        vm.stopPrank();

        // Now desired holder approves marketplace and swap succeeds
        vm.prank(buyer);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(buyer);
        market.purchaseListing{value: 0}(id, 0, 10, address(erc1155), 222, 10, 10, buyer);

        // Post-swap balances
        assertEq(erc1155.balanceOf(seller, 111), 0);
        assertEq(erc1155.balanceOf(seller, 222), 10);
        assertEq(erc1155.balanceOf(buyer, 111), 10);
        assertEq(erc1155.balanceOf(buyer, 222), 0);
    }

    /* ==================================================
       Terms changed after a partial fill (freshness guard)
       ================================================== */

    function testERC1155_PartialBuy_SecondBuyerWithStaleExpectedTermsReverts() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        erc1155.mint(seller, 700, 10);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // qty=10, price=10 ETH; partials enabled
        vm.prank(seller);
        market.createListing(
            address(erc1155), 700, seller, 10 ether, address(0), 0, 0, 10, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // First partial: buy 4
        vm.deal(buyer, 10 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 4 ether}(id, 10 ether, 10, address(0), 0, 0, 4, address(0));

        // Second buyer uses stale expected terms (10/10) → ListingTermsChanged
        address buyer2 = vm.addr(0xDEAD);
        vm.deal(buyer2, 10 ether);
        vm.startPrank(buyer2);
        vm.expectRevert(IdeationMarket__ListingTermsChanged.selector);
        market.purchaseListing{value: 6 ether}(id, 10 ether, 10, address(0), 0, 0, 6, address(0));
        vm.stopPrank();
    }

    /* ===========================================
       Accounting invariant: sum(proceeds) == cash
       =========================================== */

    function testInvariant_ContractBalanceEqualsSumOfProceeds_AfterOps() public {
        // 1) Simple ERC721 sale with overpay → proceeds: seller, owner, buyer
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id1 = getter.getNextListingId() - 1;

        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1.2 ether}(id1, 1 ether, 0, address(0), 0, 0, 0, address(0));
        // At this point:
        // buyer: 0.2, seller: 0.99, owner: 0.01

        // 2) Royalty sale at 1.5 ETH, 10% royalty to R
        MockERC721Royalty r = new MockERC721Royalty();
        address R = vm.addr(0xB0B0);
        r.mint(seller, 88);
        r.setRoyalty(R, 10_000); // 10%

        vm.prank(owner);
        collections.addWhitelistedCollection(address(r));
        vm.prank(seller);
        r.approve(address(diamond), 88);

        vm.prank(seller);
        market.createListing(address(r), 88, address(0), 1.5 ether, address(0), 0, 0, 0, false, false, new address[](0));
        uint128 id2 = getter.getNextListingId() - 1;

        address richBuyer = vm.addr(0xCAFE);
        vm.deal(richBuyer, 2 ether);
        vm.prank(richBuyer);
        market.purchaseListing{value: 1.5 ether}(id2, 1.5 ether, 0, address(0), 0, 0, 0, address(0));
        // Adds: owner +0.015, seller +1.335, R +0.15

        // Sum proceeds we expect are the only balances held by the diamond:
        uint256 sum =
            getter.getProceeds(buyer) + getter.getProceeds(seller) + getter.getProceeds(owner) + getter.getProceeds(R);

        assertEq(sum, getter.getBalance());
    }

    function testCleanListingAfterERC721BurnByThirdUser() public {
        // Create simple ERC721 listing for token #1 (price = 1 ETH)
        uint128 id = _createListingERC721(false, new address[](0));

        // "Burn" by transferring to address(0) — clears per-token approval in the mock
        vm.prank(seller);
        erc721.transferFrom(seller, address(0), 1);

        // Any third party may clean an invalid listing
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(
            id,
            address(erc721),
            1,
            seller,
            operator // cleaner
        );

        vm.prank(operator);
        market.cleanListing(id);

        // Listing removed
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCancelListingAfterERC721BurnByOwner() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.prank(seller);
        erc721.transferFrom(seller, address(0), 1); // burn

        // Diamond owner can cancel any listing, even after burn
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceled(id, address(erc721), 1, seller, owner);

        vm.prank(owner);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCancelListingAfterERC721BurnBySeller() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.prank(seller);
        erc721.transferFrom(seller, address(0), 1); // burn

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceled(id, address(erc721), 1, seller, seller);

        vm.prank(seller);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCancelListingAfterERC721BurnByOperatorForAll() public {
        uint128 id = _createListingERC721(false, new address[](0));

        // Grant blanket operator rights (NOT the marketplace; a real operator)
        vm.prank(seller);
        erc721.setApprovalForAll(operator, true);

        // Burn after listing
        vm.prank(seller);
        erc721.transferFrom(seller, address(0), 1);

        // Operator-for-all may cancel on behalf of the (former) seller
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceled(id, address(erc721), 1, seller, operator);

        vm.prank(operator);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCleanListingAfterERC1155BurnAllByThirdUser() public {
        // Whitelist & approve marketplace for ERC1155
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // IMPORTANT: seller has 10 units from setUp(); list all 10 so a full burn invalidates the listing
        vm.prank(seller);
        market.createListing(
            address(erc1155),
            1,
            seller,
            10 ether, // total price
            address(0),
            0,
            0,
            10, // list the full 10
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Burn all 10 units by sending to the zero address -> seller balance becomes 0 (< listed 10)
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, address(0), 1, 10, "");

        // Revoke marketplace approval; cleanListing requires the listing to be invalid AND not approved
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), false);

        // Third party can now clean the invalid listing
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(id, address(erc1155), 1, seller, operator);

        vm.prank(operator);
        market.cleanListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /* ============================================================
    Additional tests: burns, operator-for-all cancels, 1155 partial
    burn cleanup, and ERC1155 swap cleanup boundary behavior.
    Copy/paste into IdeationMarketDiamondTest.
    ============================================================ */

    /// Purchase after ERC721 burn should revert (distinct from off-market transfer).
    function testPurchaseRevertsAfterERC721Burn() public {
        _whitelistCollectionAndApproveERC721();

        // Create listing: ERC721 #1, price = 1 ETH
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // "Burn" token by sending to the zero address (owner becomes address(0))
        vm.prank(seller);
        erc721.transferFrom(seller, address(0), 1);

        // Buyer attempts purchase → must revert with SellerNotTokenOwner(listingId)
        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__SellerNotTokenOwner.selector, id));
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    /// Diamond owner can cancel an ERC721 listing after the token is burned.
    function testCancelAfterERC721BurnByOwner() public {
        _whitelistCollectionAndApproveERC721();

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Burn it
        vm.prank(seller);
        erc721.transferFrom(seller, address(0), 1);

        // Diamond owner cancels
        vm.prank(owner);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// Operator-for-all (without per-token approval) can cancel after ERC721 burn.
    function testCancelAfterERC721BurnByOperatorForAll() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));

        // Seller grants operator-for-all; approve marketplace for creation
        vm.prank(seller);
        erc721.setApprovalForAll(operator, true);
        vm.prank(seller);
        erc721.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Burn token
        vm.prank(seller);
        erc721.transferFrom(seller, address(0), 1);

        // Operator-for-all cancels
        vm.prank(operator);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// ERC-1155 partial burn leaving less than listed quantity → purchase reverts, then clean().
    function testERC1155PartialBurnBelowListed_PurchaseRevertsThenClean() public {
        // Whitelist & approve
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // Seller has 10 of id=1 from setUp. List qty=10, price=10 ETH.
        vm.prank(seller);
        market.createListing(
            address(erc1155),
            1,
            seller,
            10 ether,
            address(0),
            0,
            0,
            10, // listed quantity
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Burn 7 → seller balance becomes 3 (< 10 listed)
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, address(0), 1, 7, "");

        // Purchase (attempt to buy all 10) → must revert with SellerInsufficientTokenBalance(10, 3)
        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__SellerInsufficientTokenBalance.selector, 10, 3));
        market.purchaseListing{value: 10 ether}(id, 10 ether, 10, address(0), 0, 0, 10, address(0));
        vm.stopPrank();

        // Revoke marketplace approval or cleanListing will revert with StillApproved
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), false);

        // Third party can clean the invalid listing
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(id, address(erc1155), 1, seller, operator);

        vm.prank(operator);
        market.cleanListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /* ============================================================
    ERC1155 swap cleanup boundary behavior
    - If buyer’s post-swap remaining balance == their own listed qty → not deleted
    - If remaining balance < their listed qty → listing is deleted
    ============================================================ */

    /// Buyer has a pre-existing ERC1155 listing with qty = QL.
    /// After swapping away QS units, remaining == QL → should NOT delete.
    function testSwapCleanupERC1155_RemainingEqualsListed_NotDeleted() public {
        // Fresh ERC721 for the listed side
        MockERC721 A = new MockERC721();
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(A)); // listed collection must be whitelisted
        collections.addWhitelistedCollection(address(erc1155)); // needed so buyer can list ERC1155
        vm.stopPrank();

        // Mint A#100 to seller and approve marketplace
        A.mint(seller, 100);
        vm.prank(seller);
        A.approve(address(diamond), 100);

        uint256 id1155 = 777;
        uint256 QL = 5; // buyer's own ERC1155 listing quantity
        uint256 QS = 3; // units required by the swap
        // Mint buyer QL + QS so remaining == QL after swap
        erc1155.mint(buyer, id1155, QL + QS);
        vm.prank(buyer);
        erc1155.setApprovalForAll(address(diamond), true);

        // Buyer pre-lists ERC1155(id=777) qty=QL
        vm.prank(buyer);
        market.createListing(
            address(erc1155),
            id1155,
            buyer,
            5 ether,
            address(0),
            0,
            0,
            uint16(QL), // erc1155Quantity
            false,
            false,
            new address[](0)
        );
        uint128 buyerListingId = getter.getNextListingId() - 1;

        // Seller lists A#100 wanting QS units of that ERC1155; price=0 (pure swap)
        vm.prank(seller);
        market.createListing(
            address(A),
            100,
            address(0),
            0,
            address(erc1155),
            id1155,
            uint16(QS), // desire ERC1155
            0,
            false,
            false,
            new address[](0)
        );
        uint128 swapListingId = getter.getNextListingId() - 1;

        // Buyer performs the swap; must pass desiredErc1155Holder=buyer
        vm.prank(buyer);
        market.purchaseListing{value: 0}(
            swapListingId,
            0, // expectedPrice
            0, // expectedErc1155Quantity (listed is ERC721)
            address(erc1155),
            id1155,
            uint16(QS),
            0, // erc1155PurchaseQuantity (ERC721 path)
            buyer // desiredErc1155Holder
        );

        // Buyer’s ERC1155 listing should still exist (remaining == QL)
        Listing memory L = getter.getListingByListingId(buyerListingId);
        assertEq(L.erc1155Quantity, QL);
        // Spot-check balances: buyer kept exactly QL
        assertEq(erc1155.balanceOf(buyer, id1155), QL);
    }

    /// Buyer’s remaining balance falls BELOW their listed qty → marketplace should delete that listing.
    function testSwapCleanupERC1155_RemainingBelowListed_Deleted() public {
        // Fresh ERC721
        MockERC721 A = new MockERC721();
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(A));
        collections.addWhitelistedCollection(address(erc1155));
        vm.stopPrank();

        // Mint/approve A#101 to seller
        A.mint(seller, 101);
        vm.prank(seller);
        A.approve(address(diamond), 101);

        uint256 id1155 = 888;
        uint256 QL = 5; // buyer's listing quantity
        uint256 QS = 3; // required by swap
        // Mint buyer QL + QS - 1 so post-swap remaining = QL - 1 (insufficient)
        erc1155.mint(buyer, id1155, QL + QS - 1);
        vm.prank(buyer);
        erc1155.setApprovalForAll(address(diamond), true);

        // Buyer pre-lists ERC1155(id=888) qty=QL
        vm.prank(buyer);
        market.createListing(
            address(erc1155), id1155, buyer, 5 ether, address(0), 0, 0, uint16(QL), false, false, new address[](0)
        );
        uint128 buyerListingId = getter.getNextListingId() - 1;

        // Seller lists ERC721 wanting QS of that ERC1155 (pure swap)
        vm.prank(seller);
        market.createListing(
            address(A), 101, address(0), 0, address(erc1155), id1155, uint16(QS), 0, false, false, new address[](0)
        );
        uint128 swapListingId = getter.getNextListingId() - 1;

        // Execute swap
        vm.prank(buyer);
        market.purchaseListing{value: 0}(swapListingId, 0, 0, address(erc1155), id1155, uint16(QS), 0, buyer);

        // The buyer's ERC1155 listing should have been deleted by the swap cleanup
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, buyerListingId));
        getter.getListingByListingId(buyerListingId);

        // Remaining balance is QL-1 as constructed
        assertEq(erc1155.balanceOf(buyer, id1155), QL - 1);
    }

    /* ========== 1155 ↔ 1155 swaps ========== */

    /// Pure 1155(A) ↔ 1155(B) swap (price = 0).
    function testERC1155toERC1155Swap_Pure() public {
        // Token A is the shared fixture erc1155; deploy token B.
        MockERC1155 tokenB = new MockERC1155();

        // Whitelist both 1155 collections.
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        collections.addWhitelistedCollection(address(tokenB));
        vm.stopPrank();

        // Mint balances.
        uint256 idA = 11;
        uint256 idB = 22;
        uint16 qtyA = 5;
        uint16 qtyB = 3;

        erc1155.mint(seller, idA, 10);
        tokenB.mint(buyer, idB, 10);

        // Approvals.
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(buyer);
        tokenB.setApprovalForAll(address(diamond), true);

        // Seller lists A:idA qtyA desiring B:idB qtyB, price = 0 (pure swap).
        vm.prank(seller);
        market.createListing(
            address(erc1155), idA, seller, 0, address(tokenB), idB, qtyB, qtyA, false, false, new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        // Execute swap by buyer (supplying tokenB from buyer).
        vm.prank(buyer);
        market.purchaseListing{value: 0}(
            listingId,
            0, // expectedPrice
            qtyA, // expectedErc1155Quantity (listed is 1155)
            address(tokenB),
            idB,
            qtyB, // desired 1155 qty to deliver
            qtyA, // purchase qty of listed 1155
            buyer // desiredErc1155Holder = buyer
        );

        // Post conditions: A moved seller->buyer, B moved buyer->seller, no ETH moved.
        assertEq(erc1155.balanceOf(seller, idA), 10 - qtyA);
        assertEq(erc1155.balanceOf(buyer, idA), qtyA);
        assertEq(tokenB.balanceOf(buyer, idB), 10 - qtyB);
        assertEq(tokenB.balanceOf(seller, idB), qtyB);
        assertEq(address(diamond).balance, 0);
    }

    /// 1155(A) ↔ 1155(B) + ETH (seller charges ETH in addition to ERC1155 consideration).
    function testERC1155toERC1155Swap_WithEth() public {
        MockERC1155 tokenB = new MockERC1155();

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        collections.addWhitelistedCollection(address(tokenB));
        vm.stopPrank();

        uint256 idA = 33;
        uint256 idB = 44;
        uint16 qtyA = 6;
        uint16 qtyB = 2;
        uint256 price = 1 ether;

        erc1155.mint(seller, idA, 20);
        tokenB.mint(buyer, idB, 10);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(buyer);
        tokenB.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), idA, seller, price, address(tokenB), idB, qtyB, qtyA, false, false, new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        vm.deal(buyer, price);
        vm.prank(buyer);
        market.purchaseListing{value: price}(listingId, price, qtyA, address(tokenB), idB, qtyB, qtyA, buyer);

        assertEq(erc1155.balanceOf(seller, idA), 20 - qtyA);
        assertEq(erc1155.balanceOf(buyer, idA), qtyA);
        assertEq(tokenB.balanceOf(buyer, idB), 10 - qtyB);
        assertEq(tokenB.balanceOf(seller, idB), qtyB);

        // Contract should now hold the price until proceeds withdrawal.
        assertEq(address(diamond).balance, price);
    }

    /// Buyer is ONLY an authorized operator for the desired 1155(B) holder (not the holder).
    /// Your contract checks isApprovedForAll(holder, buyer), so grant that, and also approve the diamond to move tokens.
    function testERC1155toERC1155Swap_BuyerIsOperatorForDesired() public {
        MockERC1155 tokenB = new MockERC1155();

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        collections.addWhitelistedCollection(address(tokenB));
        vm.stopPrank();

        address holder = makeAddr("holder"); // third-party holder of tokenB

        uint256 idA = 55;
        uint256 idB = 66;
        uint16 qtyA = 4;
        uint16 qtyB = 3;

        erc1155.mint(seller, idA, 10);
        tokenB.mint(holder, idB, 10);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // Holder authorizes the DIAMOND (for the actual transfer) and the BUYER (authZ check your market performs)
        vm.startPrank(holder);
        tokenB.setApprovalForAll(address(diamond), true);
        tokenB.setApprovalForAll(buyer, true); // <<< important: satisfies IdeationMarket__NotAuthorizedOperator guard
        vm.stopPrank();

        vm.prank(seller);
        market.createListing(
            address(erc1155), idA, seller, 0, address(tokenB), idB, qtyB, qtyA, false, false, new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        // Buyer executes swap, supplying B from `holder` via marketplace pull.
        vm.prank(buyer);
        market.purchaseListing{value: 0}(
            listingId,
            0,
            qtyA,
            address(tokenB),
            idB,
            qtyB,
            qtyA,
            holder // desiredErc1155Holder is the third-party holder
        );

        // Effects: holder lost B, seller gained B, buyer received A.
        assertEq(tokenB.balanceOf(holder, idB), 10 - qtyB);
        assertEq(tokenB.balanceOf(seller, idB), qtyB);
        assertEq(erc1155.balanceOf(buyer, idA), qtyA);
        assertEq(erc1155.balanceOf(seller, idA), 10 - qtyA);
    }

    /* ========== Clean-listing on ERC1155 balance drift while approval INTACT ========== */

    /// Canonical: balance drifts via normal transfer (approval remains true) → cleanListing cancels.
    function testCleanListingERC1155_BalanceDrift_ApprovalIntact_Cancels() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Seller lists qty=10 of id=77; approval to marketplace is TRUE.
        uint256 id1155 = 77;
        uint256 listedQty = 10;
        erc1155.mint(seller, id1155, listedQty);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // Non-zero price to avoid FreeListingsNotSupported
        vm.prank(seller);
        market.createListing(
            address(erc1155), id1155, seller, 10 ether, address(0), 0, 0, listedQty, false, false, new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        // Drift: seller moves 6 away → remaining 4 (< 10); approval STILL true.
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, buyer, id1155, 6, "");

        // Expect cancellation event, then anyone can clean.
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(
            listingId, address(erc1155), id1155, seller, operator
        );

        vm.prank(operator);
        market.cleanListing(listingId);

        // Listing is gone.
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingId));
        getter.getListingByListingId(listingId);
    }

    /// balance drifts because units are burned (approval remains true) → cancel.
    /// If your MockERC1155 exposes a burn(address,uint256,uint256) method, prefer that. Otherwise
    /// keep the safeTransferFrom(..., address(0), ...) line below (if your mock treats that as burn).
    function testCleanListingERC1155_BalanceDrift_ApprovalIntact_Cancels_BurnVariant() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        uint256 tid = 600;
        uint256 listedQty = 8;
        erc1155.mint(seller, tid, 10);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), tid, seller, 1 wei, address(0), 0, 0, listedQty, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Burn 5 units so remaining = 5 (< 8).
        // If you have erc1155.burn(seller, tid, 5); use that instead of the next line.
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, address(0), tid, 5, "");

        vm.prank(operator);
        market.cleanListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// Same as above but demonstrate it also cancels after approval is revoked.
    function testCleanListingERC1155_BalanceDrift_AfterApprovalRevoked_Cleans() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        uint256 id = 88;
        erc1155.mint(seller, id, 10);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // Non-zero price
        vm.prank(seller);
        market.createListing(
            address(erc1155),
            id,
            seller,
            1, // 1 wei
            address(0),
            0,
            0,
            9,
            false,
            false,
            new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        // Drift down to 7 (< 9).
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, address(0), id, 3, "");

        // Revoke approval; listing is invalid regardless in your implementation.
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), false);

        // Clean succeeds and deletes the listing.
        vm.prank(operator);
        market.cleanListing(listingId);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingId));
        getter.getListingByListingId(listingId);
    }

    /* ========== Invariant: sum of recorded proceeds == contract balance ========== */

    address[] internal __trackedProceedsAddrs;

    /// Optional helper to register addresses once.
    function __ensureTrackedInit() internal {
        if (__trackedProceedsAddrs.length == 0) {
            __trackedProceedsAddrs.push(owner);
            __trackedProceedsAddrs.push(seller);
            __trackedProceedsAddrs.push(buyer);
            __trackedProceedsAddrs.push(operator);
            // Add more if your suite mints/credits different actors:
            // __trackedProceedsAddrs.push(makeAddr("royaltyReceiver"));
        }
    }

    /// Foundry will run any function prefixed with `invariant_` during invariant tests.
    /// This asserts the escrowed ETH in the diamond equals the sum of per-user proceeds.
    function invariant_RecordedProceedsEqualsDiamondBalance() public {
        __ensureTrackedInit();

        uint256 sum;
        for (uint256 i = 0; i < __trackedProceedsAddrs.length; i++) {
            sum += getter.getProceeds(__trackedProceedsAddrs[i]);
        }
        assertEq(sum, address(diamond).balance, "sum(proceeds) must equal contract balance");
    }

    /* ========== Receiver hooks that swallow reverts (malicious tokens) ========== */

    /// Listed token is MaliciousERC1155 which tries (and catches) reentrant withdrawProceeds.
    /// Purchase must succeed and not break accounting.
    function testPurchaseWithMaliciousERC1155Listed_Succeeds_NoReentrancy() public {
        // Deploy malicious 1155 bound to this diamond.
        MaliciousERC1155 m1155 = new MaliciousERC1155(address(diamond));

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(m1155));
        vm.stopPrank();

        uint256 id = 909;
        m1155.mint(seller, id, 5);

        vm.prank(seller);
        m1155.setApprovalForAll(address(diamond), true);

        // List qty=5 for 1 ETH.
        vm.prank(seller);
        market.createListing(address(m1155), id, seller, 1 ether, address(0), 0, 0, 5, false, false, new address[](0));
        uint128 listingId = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(listingId, 1 ether, 5, address(0), 0, 0, 5, address(0));

        // Buyer received all 5; diamond holds ETH; reentrancy attempt was swallowed by the token.
        assertEq(m1155.balanceOf(buyer, id), 5);
        assertEq(address(diamond).balance, 1 ether);
    }

    /// Desired token is MaliciousERC1155; its transfer hook tries (and catches) reentrant withdrawProceeds.
    /// Swap+ETH purchase must succeed.
    function testPurchaseWithMaliciousERC1155Desired_Succeeds_NoReentrancy() public {
        // Listed side uses regular erc1155; desired side is malicious.
        MaliciousERC1155 m1155 = new MaliciousERC1155(address(diamond));

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        collections.addWhitelistedCollection(address(m1155));
        vm.stopPrank();

        uint256 idListed = 1001;
        uint256 idDesired = 2002;
        uint16 qtyListed = 2;
        uint16 qtyDesired = 1;
        uint256 price = 0.25 ether;

        erc1155.mint(seller, idListed, 10);
        m1155.mint(buyer, idDesired, 5);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(buyer);
        m1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155),
            idListed,
            seller,
            price,
            address(m1155),
            idDesired,
            qtyDesired,
            qtyListed,
            false,
            false,
            new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        vm.deal(buyer, price);
        vm.prank(buyer);
        market.purchaseListing{value: price}(
            listingId, price, qtyListed, address(m1155), idDesired, qtyDesired, qtyListed, buyer
        );

        // Transfer should have succeeded despite malicious hook swallowing the internal revert.
        assertEq(erc1155.balanceOf(buyer, idListed), qtyListed);
        assertEq(m1155.balanceOf(seller, idDesired), qtyDesired);
        assertEq(address(diamond).balance, price);
    }

    function testSwapERC1155toERC1155_PureSwap_HappyPath() public {
        // Listed 1155 (A) must be whitelisted; desired 1155 (B) only needs to pass interface checks.
        MockERC1155 A = new MockERC1155();
        MockERC1155 B = new MockERC1155();

        vm.prank(owner);
        collections.addWhitelistedCollection(address(A));

        // Seller lists 10x A#1
        A.mint(seller, 1, 10);
        vm.prank(seller);
        A.setApprovalForAll(address(diamond), true);

        // Buyer holds 6x B#7 and approves marketplace
        B.mint(buyer, 7, 6);
        vm.prank(buyer);
        B.setApprovalForAll(address(diamond), true);

        // Create pure swap: want 6x B#7 for 10x A#1 (price=0, partials disabled)
        vm.prank(seller);
        market.createListing(address(A), 1, seller, 0, address(B), 7, 6, 10, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        // Execute swap
        vm.prank(buyer);
        market.purchaseListing{value: 0}(id, 0, 10, address(B), 7, 6, 10, buyer);

        // Balances swapped
        assertEq(A.balanceOf(buyer, 1), 10);
        assertEq(B.balanceOf(seller, 7), 6);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testSwapERC1155toERC1155_WithEth_AndBuyerIsOperatorForDesired() public {
        MockERC1155 A = new MockERC1155();
        MockERC1155 B = new MockERC1155();

        vm.prank(owner);
        collections.addWhitelistedCollection(address(A));

        // Seller lists 8x A#2
        A.mint(seller, 2, 8);
        vm.prank(seller);
        A.setApprovalForAll(address(diamond), true);

        // Desired B#9 is held by 'operatorHolder'; buyer is its operator (NOT holder)
        address operatorHolder = vm.addr(0x5155);
        B.mint(operatorHolder, 9, 5);
        vm.prank(operatorHolder);
        B.setApprovalForAll(buyer, true); // buyer can move holder's B
        vm.prank(operatorHolder);
        B.setApprovalForAll(address(diamond), true); // marketplace can pull B from holder

        // Create swap+ETH: want 5x B#9 + 0.25 ETH for 8x A#2
        vm.prank(seller);
        market.createListing(address(A), 2, seller, 0.25 ether, address(B), 9, 5, 8, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 0.25 ether}(id, 0.25 ether, 8, address(B), 9, 5, 8, operatorHolder);

        // Results: A goes to buyer, B to seller, proceeds to seller (minus fee)
        assertEq(A.balanceOf(buyer, 2), 8);
        assertEq(B.balanceOf(seller, 9), 5);
        assertEq(getter.getProceeds(seller), 0.2475 ether); // 0.25 * 99%
        assertEq(getter.getProceeds(owner), 0.0025 ether);
    }

    function testCleanListingERC721_OwnerChangedButApprovalIntact_Cancels() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Off-market transfer to operator; marketplace approval on token 1 is still the diamond
        vm.prank(seller);
        erc721.transferFrom(seller, operator, 1);
        // (no approval changes)

        // Anyone should be able to clean this stale listing
        vm.prank(buyer);
        market.cleanListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCleanListing_BurnedERC721_Cancels() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        erc721.burn(1);

        vm.prank(operator);
        market.cleanListing(id);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCancelListing_BurnedERC1155_BySeller() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        erc1155.mint(seller, 42, 5);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(address(erc1155), 42, seller, 5 ether, address(0), 0, 0, 5, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        erc1155.burn(seller, 42, 5);

        vm.prank(seller);
        market.cancelListing(id);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testERC721ReceiverSwallowsRevert_DoesNotMaskMarketplaceChecks() public {
        _whitelistCollectionAndApproveERC721();
        SwallowingERC721Receiver recv = new SwallowingERC721Receiver();

        // list and sell to receiver
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        // Then send to receiver via normal transfer to assert hook didn’t break semantics
        vm.prank(buyer);
        erc721.safeTransferFrom(buyer, address(recv), 1);

        assertEq(erc721.ownerOf(1), address(recv));
    }

    /// 1155 <-> 1155 swap paths

    function testSwap_ERC1155toERC1155_PureSwap_BuyerIsOperatorForDesired() public {
        // Fresh ERC1155 collections
        MockERC1155 A = new MockERC1155();
        MockERC1155 B = new MockERC1155();

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(A));
        collections.addWhitelistedCollection(address(B));
        vm.stopPrank();

        // Seller holds A#1 x10; Holder owns B#2 x7 and makes buyer an operator
        address holder = vm.addr(0xA11CE);
        A.mint(seller, 1, 10);
        B.mint(holder, 2, 7);

        // Approvals
        vm.prank(seller);
        A.setApprovalForAll(address(diamond), true);
        vm.prank(holder);
        B.setApprovalForAll(buyer, true); // buyer can act for holder
        vm.prank(holder);
        B.setApprovalForAll(address(diamond), true); // marketplace can move holder's tokens

        // Seller lists 6x A#1, desires 5x B#2 (price=0 -> pure swap)
        vm.prank(seller);
        market.createListing(address(A), 1, seller, 0, address(B), 2, 5, 6, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        // Buyer executes swap on behalf of holder
        vm.prank(buyer);
        market.purchaseListing{value: 0}(id, 0, 6, address(B), 2, 5, 6, holder);

        // Post conditions
        assertEq(A.balanceOf(buyer, 1), 6);
        assertEq(B.balanceOf(seller, 2), 5);
    }

    function testSwap_ERC1155toERC1155_WithEth() public {
        MockERC1155 A = new MockERC1155();
        MockERC1155 B = new MockERC1155();

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(A));
        collections.addWhitelistedCollection(address(B));
        vm.stopPrank();

        A.mint(seller, 10, 8);
        B.mint(buyer, 20, 6);

        vm.prank(seller);
        A.setApprovalForAll(address(diamond), true);
        vm.prank(buyer);
        B.setApprovalForAll(address(diamond), true);

        // Seller wants 4x B#20 + 0.25 ETH for 5x A#10
        vm.prank(seller);
        market.createListing(address(A), 10, seller, 0.25 ether, address(B), 20, 4, 5, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 0.25 ether}(id, 0.25 ether, 5, address(B), 20, 4, 5, buyer);

        assertEq(A.balanceOf(buyer, 10), 5);
        assertEq(B.balanceOf(seller, 20), 4);
        // 1% fee on 0.25 ETH = 0.0025
        assertEq(getter.getProceeds(seller), 0.2475 ether);
        assertEq(getter.getProceeds(owner), 0.0025 ether);
    }

    /// -----------------------------------------------------------------------
    /// Clean/cancel after burn (uses tiny burnable mocks added below)
    /// -----------------------------------------------------------------------

    function testCleanListingCancelsAfterERC721Burn() public {
        BurnableERC721 x = new BurnableERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(x));

        x.mint(seller, 1);
        vm.prank(seller);
        x.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(address(x), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        // Burn off-market
        vm.prank(seller);
        x.burn(1);

        // Anyone can clean
        vm.prank(operator);
        market.cleanListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCancelListingAfterERC721Burn_ByContractOwner() public {
        BurnableERC721 x = new BurnableERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(x));

        x.mint(seller, 2);
        vm.prank(seller);
        x.approve(address(diamond), 2);
        vm.prank(seller);
        market.createListing(address(x), 2, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        x.burn(2);

        // Contract owner can cancel any listing
        vm.prank(owner);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCleanListingCancelsAfterERC1155Burn() public {
        BurnableERC1155 y = new BurnableERC1155();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(y));

        y.mint(seller, 5, 10);
        vm.prank(seller);
        y.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(address(y), 5, seller, 10 ether, address(0), 0, 0, 10, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        // Burn some so balance < listed
        vm.prank(seller);
        y.burn(seller, 5, 7); // leaves 3 < 10

        vm.prank(operator);
        market.cleanListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    function testCancelListingAfterERC1155Burn_ByContractOwner() public {
        BurnableERC1155 y = new BurnableERC1155();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(y));

        y.mint(seller, 9, 6);
        vm.prank(seller);
        y.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(address(y), 9, seller, 6 ether, address(0), 0, 0, 6, false, false, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        vm.prank(seller);
        y.burn(seller, 9, 6); // full burn

        vm.prank(owner);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// -----------------------------------------------------------------------
    /// Old approval exists but owner changed off-market → clean cancels
    /// -----------------------------------------------------------------------

    function testCleanListingCancelsAfterOwnerChangedOffMarket() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Off-market transfer to some other address; marketplace approval on seller is now meaningless
        vm.prank(seller);
        erc721.transferFrom(seller, operator, 1);

        // Anyone can clean invalid listing
        vm.prank(buyer);
        market.cleanListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// -----------------------------------------------------------------------
    /// Receiver hooks that swallow reverts
    /// -----------------------------------------------------------------------

    function testReceiverHooksThatSwallowReverts_ERC721() public {
        _whitelistCollectionAndApproveERC721();
        // Mint + approve a fresh token
        erc721.mint(seller, 99);
        vm.prank(seller);
        erc721.approve(address(diamond), 99);

        vm.prank(seller);
        market.createListing(
            address(erc721), 99, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        SwallowingERC721Receiver rcvr = new SwallowingERC721Receiver();
        vm.deal(address(rcvr), 1 ether);

        vm.prank(address(rcvr));
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        assertEq(erc721.ownerOf(99), address(rcvr));
    }

    function testERC721BuyerContractWithoutReceiverInterfaceReverts_Strict() public {
        // Deploy strict token that enforces ERC721Receiver check
        StrictERC721 strict721 = new StrictERC721();

        // Whitelist the strict token
        vm.prank(owner);
        collections.addWhitelistedCollection(address(strict721));

        // Mint token #1 to seller and approve marketplace
        strict721.mint(seller, 1);
        vm.prank(seller);
        strict721.approve(address(diamond), 1);

        // Create a fixed-price listing
        vm.prank(seller);
        market.createListing(
            address(strict721),
            1,
            address(0), // erc1155Holder (unused for 721)
            1 ether, // price
            address(0),
            0,
            0, // no swap
            0, // erc1155Quantity
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer is a contract with NO ERC721Receiver
        NonReceiver non = new NonReceiver();
        vm.deal(address(non), 2 ether);

        // Purchase must revert due to missing onERC721Received
        vm.startPrank(address(non));
        vm.expectRevert(); // any revert is fine
        market.purchaseListing{value: 1 ether}(
            id,
            1 ether, // expectedPrice
            0, // expectedErc1155Quantity
            address(0),
            0,
            0,
            0, // erc1155PurchaseQuantity
            address(0)
        );
        vm.stopPrank();
    }

    function testReceiverHooksThatSwallowReverts_ERC1155() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        erc1155.mint(seller, 55, 5);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(address(erc1155), 55, seller, 5 ether, address(0), 0, 0, 5, false, true, new address[](0));
        uint128 id = getter.getNextListingId() - 1;

        SwallowingERC1155Receiver rcvr = new SwallowingERC1155Receiver();
        vm.deal(address(rcvr), 10 ether);

        // Buy all 5 to receiver; its hook swallows internal errors but returns selector
        vm.prank(address(rcvr));
        market.purchaseListing{value: 5 ether}(id, 5 ether, 5, address(0), 0, 0, 5, address(0));

        assertEq(erc1155.balanceOf(address(rcvr), 55), 5);
    }

    function testERC1155BuyerContractWithoutReceiverInterfaceReverts_Strict() public {
        // Deploy strict token that enforces ERC1155Receiver check
        StrictERC1155 strict1155 = new StrictERC1155();

        // Whitelist the strict token
        vm.prank(owner);
        collections.addWhitelistedCollection(address(strict1155));

        // Mint id=1 qty=10 to seller and approve marketplace
        strict1155.mint(seller, 1, 10);
        vm.prank(seller);
        strict1155.setApprovalForAll(address(diamond), true);

        // Create a fixed-price 1155 listing (no partials)
        vm.prank(seller);
        market.createListing(
            address(strict1155),
            1,
            seller, // erc1155Holder (seller is the holder)
            10 ether, // total price for qty 10
            address(0),
            0,
            0, // no swap
            10, // erc1155Quantity
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Buyer is a contract with NO ERC1155Receiver
        NonReceiver non = new NonReceiver();
        vm.deal(address(non), 20 ether);

        // Purchase must revert due to missing onERC1155Received
        vm.startPrank(address(non));
        vm.expectRevert(); // any revert is fine
        market.purchaseListing{value: 10 ether}(
            id,
            10 ether, // expectedPrice
            10, // expectedErc1155Quantity
            address(0),
            0,
            0,
            10, // erc1155PurchaseQuantity (full buy)
            address(0)
        );
        vm.stopPrank();
    }

    // End of test contract
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

// Helper facets for upgrade testing
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

contract IdeationMarketInvariantTest is Test {
    IdeationMarketDiamond internal diamond;
    GetterFacet internal getter;
    IdeationMarketFacet internal market;
    CollectionWhitelistFacet internal collections;

    address internal owner;
    address internal seller;
    address internal buyer;

    MockERC721 internal erc721;

    address[] internal actors;

    uint32 constant INNOVATION_FEE = 1000;
    uint16 constant MAX_BATCH = 300;

    function setUp() public {
        owner = vm.addr(0x9001);
        seller = vm.addr(0x9002);
        buyer = vm.addr(0x9003);

        vm.startPrank(owner);
        DiamondInit init = new DiamondInit();
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        DiamondLoupeFacet loupeFacet = new DiamondLoupeFacet();
        OwnershipFacet ownershipFacet = new OwnershipFacet();
        IdeationMarketFacet marketFacet = new IdeationMarketFacet();
        CollectionWhitelistFacet collectionFacet = new CollectionWhitelistFacet();
        BuyerWhitelistFacet buyerFacet = new BuyerWhitelistFacet();
        GetterFacet getterFacet = new GetterFacet();

        diamond = new IdeationMarketDiamond(owner, address(cutFacet));

        // loupe
        bytes4[] memory loupeSelectors = new bytes4[](5);
        loupeSelectors[0] = IDiamondLoupeFacet.facets.selector;
        loupeSelectors[1] = IDiamondLoupeFacet.facetFunctionSelectors.selector;
        loupeSelectors[2] = IDiamondLoupeFacet.facetAddresses.selector;
        loupeSelectors[3] = IDiamondLoupeFacet.facetAddress.selector;
        loupeSelectors[4] = IERC165.supportsInterface.selector;
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](6);
        cuts[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(loupeFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: loupeSelectors
        });
        // ownership
        bytes4[] memory ownershipSelectors = new bytes4[](3);
        ownershipSelectors[0] = IERC173.owner.selector;
        ownershipSelectors[1] = IERC173.transferOwnership.selector;
        ownershipSelectors[2] = OwnershipFacet.acceptOwnership.selector;
        cuts[1] = IDiamondCutFacet.FacetCut({
            facetAddress: address(ownershipFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: ownershipSelectors
        });
        // market
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
        // collections
        bytes4[] memory colSelectors = new bytes4[](4);
        colSelectors[0] = CollectionWhitelistFacet.addWhitelistedCollection.selector;
        colSelectors[1] = CollectionWhitelistFacet.removeWhitelistedCollection.selector;
        colSelectors[2] = CollectionWhitelistFacet.batchAddWhitelistedCollections.selector;
        colSelectors[3] = CollectionWhitelistFacet.batchRemoveWhitelistedCollections.selector;
        cuts[3] = IDiamondCutFacet.FacetCut({
            facetAddress: address(collectionFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: colSelectors
        });
        // buyers
        bytes4[] memory buyerSelectors = new bytes4[](2);
        buyerSelectors[0] = BuyerWhitelistFacet.addBuyerWhitelistAddresses.selector;
        buyerSelectors[1] = BuyerWhitelistFacet.removeBuyerWhitelistAddresses.selector;
        cuts[4] = IDiamondCutFacet.FacetCut({
            facetAddress: address(buyerFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: buyerSelectors
        });
        // getter
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

        IDiamondCutFacet(address(diamond)).diamondCut(
            cuts, address(init), abi.encodeCall(DiamondInit.init, (INNOVATION_FEE, MAX_BATCH))
        );
        vm.stopPrank();

        // cache handles
        getter = GetterFacet(address(diamond));
        market = IdeationMarketFacet(address(diamond));
        collections = CollectionWhitelistFacet(address(diamond));

        // set up one flow so contract holds ETH
        erc721 = new MockERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));
        erc721.mint(seller, 1);
        vm.prank(seller);
        erc721.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        // track a few plausible recipients (extend as needed)
        actors.push(owner);
        actors.push(seller);
        actors.push(buyer);
        actors.push(address(0)); // zero-address royalties, if any
    }

    function invariant_ProceedsSumEqualsDiamondBalance() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; i++) {
            sum += getter.getProceeds(actors[i]);
        }
        assertEq(sum, getter.getBalance());
        assertEq(getter.getBalance(), address(diamond).balance);
    }
}

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
