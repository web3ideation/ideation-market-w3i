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

        // assert reverse index unchanged before purchase
        Listing[] memory ids = getter.getListingsByNFT(address(erc721), 1);
        assertEq(ids.length, 1, "reverse index length drifted");
        assertEq(ids[0].listingId, listingId, "reverse index id drifted");

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

    function testStorage_MaliciousFacetSmash_TriggersDrift() public {
        _whitelistDefaultMocks();

        // Snapshot canaries
        uint32 fee0 = getter.getInnovationFee();
        uint16 maxBatch0 = getter.getBuyerWhitelistMaxBatchSize();

        // Deploy and cut-in malicious facet
        BadFacetAppSmash bad = new BadFacetAppSmash();

        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](1);
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = BadFacetAppSmash.smash.selector;

        cuts[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(bad),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: sels
        });

        vm.prank(owner);
        IDiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), "");

        // Call the malicious function through the diamond
        uint32 newFee = fee0 + 1;
        uint16 newMax = maxBatch0 + 1;
        BadFacetAppSmash(address(diamond)).smash(newFee, newMax);

        // Assert drift occurred as a proof our canary checks would catch it
        assertEq(getter.getInnovationFee(), newFee, "innovationFee should have changed");
        assertEq(getter.getBuyerWhitelistMaxBatchSize(), newMax, "maxBatch should have changed");
        assertTrue(
            getter.getInnovationFee() != fee0 || getter.getBuyerWhitelistMaxBatchSize() != maxBatch0,
            "no drift observed"
        );
    }
}

// Test-only library that points to the correct AppStorage slot (on purpose),
// used by the malicious facet to mutate innovationFee/maxBatch.
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

/// ==========================================================================
///  Handlers used by the invariant
/// ==========================================================================

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
        buyers = BuyerWhitelistFacet(_buyers); // cast via diamond address is also fine
        erc721 = MockERC721(_erc721);
        erc1155 = MockERC1155(_erc1155);
    }

    function setBuyer(address _buyer) external {
        buyerAddr = _buyer;
    }

    /// Approvals set from SellerHandler context (it owns the tokens)
    function setupApprovals() external {
        // Approve 721 id=100
        erc721.approve(diamond, 100);
        // Approve all 1155
        erc1155.setApprovalForAll(diamond, true);
    }

    /// Create a simple ERC721 listing if not already listed
    function create721Listing() external {
        if (hasListing721) return;

        market.createListing(
            address(erc721), 100, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        lastListingId721 = getter.getNextListingId() - 1;
        hasListing721 = true;
    }

    /// Enable whitelist (no new addresses provided here)
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
            true, // enable whitelist
            listing.partialBuyEnabled,
            new address[](0)
        );
    }

    /// Add buyer (the BuyerHandler address) to whitelist
    function addBuyerToWhitelist() external {
        if (!hasListing721 || buyerAddr == address(0)) return;
        address[] memory a = new address[](1);
        a[0] = buyerAddr;
        buyers.addBuyerWhitelistAddresses(lastListingId721, a);
    }

    /// Remove buyer from whitelist
    function removeBuyerFromWhitelist() external {
        if (!hasListing721 || buyerAddr == address(0)) return;
        address[] memory a = new address[](1);
        a[0] = buyerAddr;
        buyers.removeBuyerWhitelistAddresses(lastListingId721, a);
    }

    /// Cancel current listing (if any)
    function cancel721() external {
        if (!hasListing721) return;
        market.cancelListing(lastListingId721);
        hasListing721 = false;
        lastListingId721 = 0;
    }

    /// Create a small ERC1155 listing to mix flows (whitelist disabled)
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

    /// Attempt to buy the seller's last 721 listing (if present)
    function buySeller721() external {
        uint128 id = sellerH.lastListingId721();
        if (id == 0) return;

        Listing memory listing = getter.getListingByListingId(id);
        // must be ERC721 path
        if (listing.erc1155Quantity != 0) return;

        // Try exact-price purchase
        // (If whitelist not enabled or not added, or approval drifted, this may revert—acceptable for invariants.)
        market.purchaseListing{value: listing.price}(
            id,
            listing.price,
            listing.currency,
            listing.erc1155Quantity, // 0
            listing.desiredTokenAddress,
            listing.desiredTokenId,
            listing.desiredErc1155Quantity,
            0, // erc1155PurchaseQuantity
            address(0)
        );
    }

    function setSeller(address _sellerH) external {
        sellerH = ISellerHandlerView(_sellerH);
    }
}
