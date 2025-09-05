// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import "forge-std/StdInvariant.sol";
import "forge-std/Vm.sol";
import "forge-std/Test.sol";
import "../src/libraries/LibAppStorage.sol"; // for Listing struct

/// @dev Handler that performs randomized marketplace actions and tracks all actors
contract InvariantHandler {
    using stdStorage for StdStorage;

    Vm internal constant vm = Vm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));

    IdeationMarketFacet public immutable market;
    GetterFacet public immutable getter;
    CollectionWhitelistFacet public immutable collections;

    MockERC721Royalty public immutable erc721Roy; // ERC721 with ERC2981
    MockERC1155 public immutable erc1155;

    address public immutable owner; // diamond owner (innovation fee receiver)
    address public immutable seller; // primary lister

    address[] public buyers; // pool of buyers
    address public royaltyReceiver; // current royalty receiver

    // Track listings we created so we can pick among them
    uint128[] internal _listingIds;

    // Track every address that could have non-zero proceeds
    mapping(address => bool) internal _seen;
    address[] internal _actors;

    // token id cursors (avoid AlreadyListed for ERC721)
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

        // seed buyers
        buyers = _buyers;

        // default royalty receiver (can be updated via list function)
        royaltyReceiver = vm.addr(0x7777);

        // track canonical actors
        _addActor(owner);
        _addActor(seller);
        _addActor(royaltyReceiver);
        for (uint256 i; i < buyers.length; i++) {
            _addActor(buyers[i]);
        }
    }

    // -------- utility --------
    function _addActor(address a) internal {
        if (!_seen[a]) {
            _seen[a] = true;
            _actors.push(a);
        }
    }

    function getActors() external view returns (address[] memory) {
        return _actors;
    }

    function _pushListing(uint128 id) internal {
        _listingIds.push(id);
    }

    function _randomListing(uint256 seed) internal view returns (uint128 id) {
        if (_listingIds.length == 0) return 0;
        return _listingIds[seed % _listingIds.length];
    }

    // -------- actions (called by fuzzer) --------

    /// @notice List a new ERC721 (optionally with royalty). Price > 0 so ETH flows.
    function list721(uint256 priceSeed, uint256 royaltyBpsSeed) external {
        uint256 tokenId = ++_next721Id;

        // seller mints & approves
        vm.prank(seller);
        erc721Roy.mint(seller, tokenId);
        vm.prank(seller);
        erc721Roy.approve(address(market), tokenId);

        // set (possibly zero) royalty on the whole collection for test purposes
        uint256 bps = royaltyBpsSeed % 20_000; // cap at 20% for realism (denom 100_000)
        erc721Roy.setRoyalty(royaltyReceiver, bps);
        _addActor(royaltyReceiver);

        uint256 price = 0.01 ether + (priceSeed % 1 ether);

        vm.prank(seller);
        market.createListing(
            address(erc721Roy), tokenId, address(0), price, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;
        _pushListing(id);
    }

    /// @notice List a new ERC1155. If partial==true ensure divisible unit pricing.
    function list1155(uint256 unitSeed, uint256 qtySeed, bool _partial) external {
        uint256 id = ++_next1155Id;
        uint256 qty = 1 + (qtySeed % 8); // 1..8
        uint256 unit = 0.005 ether + (unitSeed % 5e15); // 0.005..0.01 ether
        bool allowPartial = _partial && qty > 1;

        // price must be divisible by qty when partial buys enabled
        uint256 price = unit * qty;

        // mint & approve-for-all
        vm.prank(seller);
        erc1155.mint(seller, id, qty);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(market), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155),
            id,
            seller, // erc1155Holder
            price,
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

    /// @notice List a swap: ERC721 (owned by seller) wanting another ERC721 (by id).
    function listSwap721For721(uint256 /*seed*/ ) external {
        uint256 offeredId = ++_next721Id;
        uint256 wantedId = ++_nextSwap721Wanted;

        vm.prank(seller);
        erc721Roy.mint(seller, offeredId);
        vm.prank(seller);
        erc721Roy.approve(address(market), offeredId);

        // zero price typical for swaps
        vm.prank(seller);
        market.createListing(
            address(erc721Roy),
            offeredId,
            address(0),
            0,
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

    /// @notice List a swap: ERC721 (owned by seller) wanting ERC1155 quantity.
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

    /// @notice Purchase a non-swap listing, with optional overpay and partial ERC1155 quantity.
    function purchase(uint256 pickSeed, uint256 overpaySeed, uint256 qtySeed, uint256 buyerSeed) external {
        uint128 id = _randomListing(pickSeed);
        if (id == 0) return;

        Listing memory L = getter.getListingByListingId(id);
        // skip removed listings or swaps (handled by purchaseSwap)
        if (L.seller == address(0) || L.desiredTokenAddress != address(0)) return;

        // decide buyer
        address buyer = buyers[buyerSeed % buyers.length];

        // choose purchase quantity
        uint256 buyQty = (L.erc1155Quantity == 0) ? 0 : (1 + (qtySeed % L.erc1155Quantity));
        if (!L.partialBuyEnabled && L.erc1155Quantity > 0) buyQty = L.erc1155Quantity;

        // compute price respecting partial buys
        uint256 purchasePrice = L.price;
        if (buyQty > 0 && buyQty != L.erc1155Quantity) {
            purchasePrice = L.price * buyQty / L.erc1155Quantity;
        }

        // bounded overpay
        uint256 overpay = overpaySeed % 0.1 ether;
        vm.deal(buyer, buyer.balance + purchasePrice + overpay);

        // execute
        vm.prank(buyer);
        market.purchaseListing{value: purchasePrice + overpay}(
            id,
            L.price,
            L.erc1155Quantity,
            L.desiredTokenAddress,
            L.desiredTokenId,
            L.desiredErc1155Quantity,
            buyQty,
            address(0) // desiredErc1155Holder (not used here)
        );

        // track participants that may receive proceeds
        _addActor(L.seller);
        _addActor(buyer);
        _addActor(owner);
        if (royaltyReceiver != address(0)) _addActor(royaltyReceiver);
    }

    /// @notice Purchase a swap listing; mints required "desired" asset to buyer, approves, then purchases.
    function purchaseSwap(uint256 pickSeed, uint256 buyerSeed) external {
        uint128 id = _randomListing(pickSeed);
        if (id == 0) return;

        Listing memory L = getter.getListingByListingId(id);
        if (L.seller == address(0) || L.desiredTokenAddress == address(0)) return;

        address buyer = buyers[buyerSeed % buyers.length];

        if (L.desiredErc1155Quantity > 0) {
            // desired is ERC1155
            vm.prank(buyer);
            erc1155.mint(buyer, L.desiredTokenId, L.desiredErc1155Quantity);
            vm.prank(buyer);
            erc1155.setApprovalForAll(address(market), true);

            vm.prank(buyer);
            market.purchaseListing{value: L.price}(
                id,
                L.price,
                L.erc1155Quantity,
                L.desiredTokenAddress,
                L.desiredTokenId,
                L.desiredErc1155Quantity,
                0,
                buyer // desiredErc1155Holder
            );
        } else {
            // desired is ERC721
            vm.prank(buyer);
            erc721Roy.mint(buyer, L.desiredTokenId);
            vm.prank(buyer);
            erc721Roy.approve(address(market), L.desiredTokenId);

            vm.prank(buyer);
            market.purchaseListing{value: L.price}(
                id, L.price, L.erc1155Quantity, L.desiredTokenAddress, L.desiredTokenId, 0, 0, address(0)
            );
        }

        // no ETH distribution on pure swaps with 0 price,
        // but if L.price > 0, owner/seller/buyer/royaltyReceiver may be involved.
        _addActor(L.seller);
        _addActor(buyer);
        _addActor(owner);
        if (royaltyReceiver != address(0)) _addActor(royaltyReceiver);
    }

    /// @notice Withdraw proceeds for any actor who has a positive balance.
    function withdraw(uint256 whoSeed) external {
        address[] memory A = _actors;
        if (A.length == 0) return;
        address who = A[whoSeed % A.length];
        uint256 p = getter.getProceeds(who);
        if (p == 0) return;

        vm.prank(who);
        market.withdrawProceeds();
    }
}

/// @dev Invariant test: randomize via handler; assert conservation of value across all flows.
contract IdeationMarketInvariantTest is StdInvariant, MarketTestBase {
    InvariantHandler internal handler;

    address internal buyer1;
    address internal buyer2;
    address internal buyer3;

    MockERC721Royalty internal erc721Roy;
    MockERC1155 internal erc1155New;

    function setUp() public override {
        super.setUp();

        // Fresh mock tokens for randomized flows
        erc721Roy = new MockERC721Royalty();
        erc1155New = new MockERC1155();

        // Whitelist them
        _whitelist(address(erc721Roy));
        _whitelist(address(erc1155New));

        // Prefund a small buyer pool generously
        buyer1 = vm.addr(0xB001);
        buyer2 = vm.addr(0xB002);
        buyer3 = vm.addr(0xB003);
        vm.deal(buyer1, 1_000 ether);
        vm.deal(buyer2, 1_000 ether);
        vm.deal(buyer3, 1_000 ether);

        // Deploy handler
        address[] memory pool = new address[](3);
        pool[0] = buyer1;
        pool[1] = buyer2;
        pool[2] = buyer3;

        handler = new InvariantHandler(
            address(market),
            address(getter),
            address(collections),
            address(erc721Roy),
            address(erc1155New),
            owner,
            seller,
            pool
        );

        // Tell the fuzzer to target handler's public/external mutating functions
        targetContract(address(handler));
    }

    /// @notice Σ(proceeds of all known actors) == getter.getBalance() == address(diamond).balance
    function invariant_ProceedsSumEqualsDiamondBalance() public view {
        address[] memory A = handler.getActors();
        uint256 sum;
        for (uint256 i; i < A.length; i++) {
            sum += getter.getProceeds(A[i]);
        }

        uint256 gbal = getter.getBalance();
        uint256 dbal = address(diamond).balance;

        assertEq(sum, gbal, "Sum(proceeds) != getter.getBalance()");
        assertEq(gbal, dbal, "getter.getBalance() != diamond balance");
    }
}
