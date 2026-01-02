// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

/// ==========================================================================
///  Storage-collision safety tests + malicious-facet simulation + invariants
/// ==========================================================================

contract StorageCollisionTest is MarketTestBase {
    /// -----------------------------------------------------------------------
    /// 1) Slots must be distinct (quick compile-time sanity guard)
    /// -----------------------------------------------------------------------
    function testStorageSlots_AreDistinct() public pure {
        bytes32 ds = keccak256("diamond.standard.diamond.storage");
        bytes32 as_ = keccak256("diamond.standard.app.storage");
        assertTrue(ds != as_, "Diamond/App storage slots must differ");
    }

    /// -----------------------------------------------------------------------
    /// 2) Cross-facet activity does not drift unrelated canary state
    /// -----------------------------------------------------------------------
    function testStorage_NoCrossFacetDrift() public {
        _whitelistDefaultMocks();

        // Snapshot canaries
        uint32 fee0 = getter.getInnovationFee();
        uint16 maxBatch0 = getter.getBuyerWhitelistMaxBatchSize();
        uint256 wlLen0 = getter.getWhitelistedCollections().length;

        // --- Seed: ERC721 listing with whitelist -> cross-facet add during create ---
        vm.startPrank(seller);
        erc721.approve(address(diamond), 1);
        vm.stopPrank();

        address[] memory allow1 = new address[](1);
        allow1[0] = buyer;

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, true, false, allow1
        );

        uint128 listingId = getter.getNextListingId() - 1;

        // --- Cross-facet add again via updateListing ---
        address altBuyer = vm.addr(0xBEEF);
        address[] memory allow2 = new address[](1);
        allow2[0] = altBuyer;

        vm.prank(seller);
        market.updateListing(listingId, 1 ether, address(0), address(0), 0, 0, 0, true, false, allow2);

        // assert ERC-721 active listing guard unchanged before purchase
        uint128 activeId = getter.getActiveListingIdByERC721(address(erc721), 1);
        assertEq(activeId, listingId, "active listing id drifted");

        // --- Purchase by whitelisted buyer; should not touch canaries ---
        address diamondOwner = getter.getContractOwner();
        uint256 pricePaid = 1 ether;
        uint256 expectedFee = (pricePaid * fee0) / 100_000;

        // Capture balances before purchase (non-custodial: atomic payment)
        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = diamondOwner.balance;

        vm.deal(buyer, 2 ether); // give buyer enough ETH for the purchase
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(listingId, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        // Verify atomic payments (non-custodial: no proceeds accumulation)
        uint256 ownerGot = diamondOwner.balance - ownerBalBefore;
        uint256 sellerGot = seller.balance - sellerBalBefore;

        assertEq(ownerGot, expectedFee, "owner did not receive fee atomically");
        assertEq(sellerGot + ownerGot, pricePaid, "seller+owner payments must equal price");

        // Canaries unchanged
        assertEq(getter.getInnovationFee(), fee0, "innovationFee drifted");
        assertEq(getter.getBuyerWhitelistMaxBatchSize(), maxBatch0, "buyerWhitelistMaxBatchSize drifted");
        assertEq(getter.getWhitelistedCollections().length, wlLen0, "whitelistedCollections length drifted");
    }

    /// -----------------------------------------------------------------------
    /// 3) Cross-facet round-trip (write in BuyerWhitelistFacet, read in Getter)
    /// -----------------------------------------------------------------------
    function testStorage_CrossFacetWhitelistWrite_ExactAndNoDriftOnListing() public {
        _whitelistDefaultMocks();

        vm.startPrank(seller);
        erc721.approve(address(diamond), 2);
        vm.stopPrank();

        address[] memory allow = new address[](1);
        allow[0] = buyer;

        uint256 price = 2 ether;

        vm.prank(seller);
        market.createListing(address(erc721), 2, address(0), price, address(0), address(0), 0, 0, 0, true, false, allow);

        uint128 id = getter.getNextListingId() - 1;

        // Positive + negative checks
        assertTrue(getter.isBuyerWhitelisted(id, buyer), "buyer should be whitelisted");
        address stranger = vm.addr(0xCAFE);
        assertFalse(getter.isBuyerWhitelisted(id, stranger), "stranger must not be whitelisted");

        // Unrelated listing fields unchanged
        Listing memory listing = getter.getListingByListingId(id);
        assertEq(listing.listingId, id);
        assertEq(listing.tokenAddress, address(erc721));
        assertEq(listing.tokenId, 2);
        assertEq(listing.erc1155Quantity, 0);
        assertEq(listing.price, price, "price drifted");
        assertEq(listing.seller, seller, "seller drifted");
        assertTrue(listing.buyerWhitelistEnabled, "whitelist flag drifted");
        assertFalse(listing.partialBuyEnabled, "partialBuy flag drifted");
    }

    /// -----------------------------------------------------------------------
    /// 4) Direct BuyerWhitelistFacet usage also does not drift canaries
    /// -----------------------------------------------------------------------
    function testStorage_NoDrift_WhenBuyerFacetUsedDirectly() public {
        _whitelistDefaultMocks();

        vm.startPrank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.stopPrank();

        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 6, true, false, new address[](0)
        );

        uint128 id = getter.getNextListingId() - 1;

        // Snapshot canaries
        uint32 fee0 = getter.getInnovationFee();
        uint16 maxBatch0 = getter.getBuyerWhitelistMaxBatchSize();
        uint256 wlLen0 = getter.getWhitelistedCollections().length;

        // Add and remove
        address[] memory addrs = new address[](1);
        addrs[0] = buyer;

        vm.prank(seller);
        buyers.addBuyerWhitelistAddresses(id, addrs);
        assertTrue(getter.isBuyerWhitelisted(id, buyer));

        vm.prank(seller);
        buyers.removeBuyerWhitelistAddresses(id, addrs);
        assertFalse(getter.isBuyerWhitelisted(id, buyer));

        // Canaries unchanged
        assertEq(getter.getInnovationFee(), fee0, "innovationFee drifted");
        assertEq(getter.getBuyerWhitelistMaxBatchSize(), maxBatch0, "buyerWhitelistMaxBatchSize drifted");
        assertEq(getter.getWhitelistedCollections().length, wlLen0, "whitelistedCollections length drifted");
    }

    /// -----------------------------------------------------------------------
    /// 5) Malicious facet "smash": simulate a bad upgrade writing AppStorage.
    ///    This is NOT a collision; it demonstrates your guards would catch a
    ///    refactor accident by observing drift in canaries.
    /// -----------------------------------------------------------------------
    function testStorage_MaliciousFacetCorruptsCanaries() public {
        // Snapshot canaries
        uint32 fee0 = getter.getInnovationFee();
        uint16 maxBatch0 = getter.getBuyerWhitelistMaxBatchSize();

        // Deploy malicious facet that directly writes to AppStorage
        BadFacetAppSmash bad = new BadFacetAppSmash();

        // Prepare diamondCut to add malicious facet
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = BadFacetAppSmash.smash.selector;

        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](1);
        cuts[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(bad),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: selectors
        });

        // Execute cut (as owner)
        vm.prank(owner);
        IDiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), "");

        // Call malicious smash function through diamond
        (bool ok,) =
            address(diamond).call(abi.encodeWithSelector(BadFacetAppSmash.smash.selector, uint32(99999), uint16(9999)));
        assertTrue(ok, "smash call should succeed");

        // Verify canaries WERE corrupted (proving guards would detect drift)
        assertNotEq(getter.getInnovationFee(), fee0, "smash should have corrupted innovationFee");
        assertNotEq(getter.getBuyerWhitelistMaxBatchSize(), maxBatch0, "smash should have corrupted maxBatch");
        assertEq(getter.getInnovationFee(), 99999, "innovationFee should be 99999 after smash");
        assertEq(getter.getBuyerWhitelistMaxBatchSize(), 9999, "maxBatch should be 9999 after smash");
    }
}

/// ==========================================================================
///  Invariant: No drift on foreign (admin) state during normal flows
/// ==========================================================================

contract StorageCollisionInvariant is StdInvariant, MarketTestBase {
    uint32 internal initialFee;
    uint16 internal initialMax;
    uint256 internal initialWlLen;

    SellerHandler internal sellerH;
    BuyerHandler internal buyerH;

    function setUp() public override {
        super.setUp();
        _whitelistDefaultMocks();

        // Deploy handlers
        sellerH = new SellerHandler(address(diamond), address(buyers), address(erc721), address(erc1155));
        buyerH = new BuyerHandler(address(diamond), address(getter), address(sellerH));

        // Wire references (for whitelisting buyer)
        sellerH.setBuyer(address(buyerH));
        buyerH.setSeller(address(sellerH));

        // Seed tokens to the seller handler and approvals from its own context
        erc721.mint(address(sellerH), 100);
        erc1155.mint(address(sellerH), 5, 20);
        sellerH.setupApprovals();

        // Fund buyer handler for purchases
        vm.deal(address(buyerH), 1000 ether);

        // Snapshot canaries
        initialFee = getter.getInnovationFee();
        initialMax = getter.getBuyerWhitelistMaxBatchSize();
        initialWlLen = getter.getWhitelistedCollections().length;

        // Register handlers as fuzz targets
        targetContract(address(sellerH));
        targetContract(address(buyerH));
    }

    /// Invariant: across arbitrary handler calls (create/update/whitelist/add/remove/buy/withdraw),
    /// admin state must not drift (no setInnovationFee, no collection edits used here).
    function invariant_NoDriftOnForeignState() public view {
        assertEq(getter.getInnovationFee(), initialFee, "innovationFee drifted during ops");
        assertEq(getter.getBuyerWhitelistMaxBatchSize(), initialMax, "maxBatch drifted during ops");
        assertEq(getter.getWhitelistedCollections().length, initialWlLen, "collections length drifted during ops");
    }
}
