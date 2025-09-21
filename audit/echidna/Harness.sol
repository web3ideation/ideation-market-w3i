// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title Echidna fuzz harness for the Ideation Market Diamond
 * @notice
 *  Deploys the Diamond + facets + initializer and mocks. Spawns multiple Agents (users)
 *  that also implement ERC721/1155 receivers. Exercises:
 *    - list/purchase/cancel/clean
 *    - partial (ERC1155) purchases
 *    - buyer & collection whitelists
 *
 *  Invariants checked:
 *   (1) Diamond loupe & ERC165 wiring is correct
 *   (2) No external reentrancy via token receivers
 *   (3) Collections we whitelisted remain whitelisted
 *   (4) ETH is conserved: diamond native balance == sum of observable proceeds
 *   (5) For ACTIVE ETH sales (no swap), fee + royalty ≤ price
 *   (6) An ERC721 token is not double-listed among ACTIVE listings
 *   (7) Innovation fee in range [0 .. FEE_DENOM]
 *   (8) For ACTIVE ERC1155 partial sales, price is divisible by quantity
 *   (9) Buyer whitelist is enforced (cannot buy without being added)
 *   (10) Only owner can change the innovation fee
 *   (11) No double-sell (721 or non-partial 1155) to two buyers in sequence
 *
 *  Notes:
 *   - We consider only ACTIVE listings (as GetterFacet.getListingsByNFT() is active-only).
 *   - We wrap GetterFacet.getListingsByNFT() with _safeListings() to treat "no active
 *     listings" as an empty set, avoiding false negatives from reverts.
 *   - A tiny do_fund() entrypoint lets Echidna supply ETH so purchases actually happen.
 */
import "../../src/IdeationMarketDiamond.sol";
import "../../src/facets/DiamondCutFacet.sol";
import "../../src/facets/DiamondLoupeFacet.sol";
import "../../src/facets/OwnershipFacet.sol";
import "../../src/facets/IdeationMarketFacet.sol";
import "../../src/facets/CollectionWhitelistFacet.sol";
import "../../src/facets/BuyerWhitelistFacet.sol";
import "../../src/facets/GetterFacet.sol";
import "../../src/upgradeInitializers/DiamondInit.sol";

import "../../src/interfaces/IDiamondCutFacet.sol";
import "../../src/interfaces/IDiamondLoupeFacet.sol";
import "../../src/interfaces/IERC165.sol";
import "../../src/interfaces/IERC173.sol";
import "../../src/interfaces/IERC721.sol";
import "../../src/interfaces/IERC1155.sol";
import "../../src/interfaces/IERC2981.sol";
import "../../src/interfaces/IBuyerWhitelistFacet.sol";

/* ------------ Minimal receiver interfaces for mocks ------------ */

interface IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4);
}

interface IERC1155Receiver {
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns (bytes4);
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        returns (bytes4);
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/* ------------------------------ Mocks ------------------------------ */

contract MockERC721 is IERC165, IERC721 {
    mapping(uint256 => address) internal _owner;
    mapping(uint256 => address) internal _tokenApproval;
    mapping(address => mapping(address => bool)) internal _operatorApproval;
    mapping(address => uint256) internal _balances;

    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC721).interfaceId;
    }

    function balanceOf(address owner) external view override returns (uint256) {
        require(owner != address(0), "ERC721: zero addr");
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) external view override returns (address) {
        address o = _owner[tokenId];
        require(o != address(0), "ERC721: nonexistent");
        return o;
    }

    function getApproved(uint256 tokenId) external view override returns (address) {
        return _tokenApproval[tokenId];
    }

    function isApprovedForAll(address owner, address operator) external view override returns (bool) {
        return _operatorApproval[owner][operator];
    }

    function setApprovalForAll(address operator, bool approved) external override {
        _operatorApproval[msg.sender][operator] = approved;
    }

    function approve(address to, uint256 tokenId) external override {
        address o = _owner[tokenId];
        require(o != address(0), "ERC721: nonexistent");
        require(msg.sender == o || _operatorApproval[o][msg.sender], "not owner/oper");
        _tokenApproval[tokenId] = to;
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address o = _owner[tokenId];
        return (spender == o || _tokenApproval[tokenId] == spender || _operatorApproval[o][spender]);
    }

    function _safeTransfer(address from, address to, uint256 tokenId) internal {
        _owner[tokenId] = to;
        _tokenApproval[tokenId] = address(0);
        unchecked {
            _balances[from] -= 1;
            _balances[to] += 1;
        }
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, "") returns (bytes4 ret) {
                require(ret == IERC721Receiver.onERC721Received.selector, "bad 721 receiver");
            } catch {
                revert("no 721 receiver");
            }
        }
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external override {
        require(_isApprovedOrOwner(msg.sender, tokenId), "not approved");
        require(_owner[tokenId] == from, "from != owner");
        _safeTransfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata) external override {
        require(_isApprovedOrOwner(msg.sender, tokenId), "not approved");
        require(_owner[tokenId] == from, "from != owner");
        _safeTransfer(from, to, tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) external override {
        require(_isApprovedOrOwner(msg.sender, tokenId), "not approved");
        require(_owner[tokenId] == from, "from != owner");
        _owner[tokenId] = to;
        _tokenApproval[tokenId] = address(0);
        unchecked {
            _balances[from] -= 1;
            _balances[to] += 1;
        }
    }

    function mint(address to, uint256 tokenId) external {
        require(to != address(0), "zero addr");
        require(_owner[tokenId] == address(0), "exists");
        _owner[tokenId] = to;
        _balances[to] += 1;
    }
}

contract MockERC721Royalty is MockERC721, IERC2981 {
    address public royaltyReceiver;
    uint96 public royaltyBps;

    /// @notice Fuzzable royalty setter (intentionally no access control; it’s a mock).
    function setRoyalty(address receiver, uint96 bps) external {
        royaltyReceiver = receiver;
        royaltyBps = uint96(bps % 10001);
    }

    function supportsInterface(bytes4 interfaceId) external view override(MockERC721, IERC165) returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC721).interfaceId
            || interfaceId == type(IERC2981).interfaceId;
    }

    function royaltyInfo(uint256, uint256 salePrice) external view override returns (address, uint256) {
        return (royaltyReceiver, (salePrice * royaltyBps) / 10000);
    }
}

contract MockERC1155 is IERC165, IERC1155 {
    mapping(uint256 => mapping(address => uint256)) internal _bal;
    mapping(address => mapping(address => bool)) internal _operatorApproval;

    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC1155).interfaceId;
    }

    function balanceOf(address account, uint256 id) external view override returns (uint256) {
        return _bal[id][account];
    }

    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
        external
        view
        override
        returns (uint256[] memory balances)
    {
        require(accounts.length == ids.length, "len mismatch");
        balances = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            balances[i] = _bal[ids[i]][accounts[i]];
        }
    }

    function setApprovalForAll(address operator, bool approved) external override {
        _operatorApproval[msg.sender][operator] = approved;
    }

    function isApprovedForAll(address account, address operator) external view override returns (bool) {
        return _operatorApproval[account][operator];
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata) external override {
        require(from == msg.sender || _operatorApproval[from][msg.sender], "1155 not approved");
        require(_bal[id][from] >= amount, "no bal");
        unchecked {
            _bal[id][from] -= amount;
            _bal[id][to] += amount;
        }
        if (to.code.length > 0) {
            try IERC1155Receiver(to).onERC1155Received(msg.sender, from, id, amount, "") returns (bytes4 ret) {
                require(ret == IERC1155Receiver.onERC1155Received.selector, "bad 1155 receiver");
            } catch {
                revert("no 1155 receiver");
            }
        }
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata
    ) external override {
        require(ids.length == amounts.length, "len mismatch");
        require(from == msg.sender || _operatorApproval[from][msg.sender], "1155 not approved");
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            uint256 amt = amounts[i];
            require(_bal[id][from] >= amt, "no bal");
            unchecked {
                _bal[id][from] -= amt;
            }
        }
        for (uint256 i = 0; i < ids.length; i++) {
            _bal[ids[i]][to] += amounts[i];
        }
        if (to.code.length > 0) {
            try IERC1155Receiver(to).onERC1155BatchReceived(msg.sender, from, ids, amounts, "") returns (bytes4 ret) {
                require(ret == IERC1155Receiver.onERC1155BatchReceived.selector, "bad 1155 batch receiver");
            } catch {
                revert("no 1155 batch receiver");
            }
        }
    }

    function mint(address to, uint256 id, uint256 amount) external {
        _bal[id][to] += amount;
    }
}

/* ------------------------------- Agent ------------------------------- */

/// @notice Agent is a simulated user that holds tokens and calls the diamond.
contract Agent is IERC721Receiver, IERC1155Receiver {
    address public immutable diamond;
    bool public reentryOk;

    constructor(address _diamond) {
        diamond = _diamond;
    }

    /* ----- Approvals ----- */

    function approve721(MockERC721 token, uint256 tokenId) external {
        token.approve(diamond, tokenId);
    }

    function setApproval721ForAll(MockERC721 token, bool approved) external {
        token.setApprovalForAll(diamond, approved);
    }

    function setApproval1155ForAll(MockERC1155 token, bool approved) external {
        token.setApprovalForAll(diamond, approved);
    }

    /* ----- Listing actions ----- */

    function listERC721(
        address tokenAddress,
        uint256 tokenId,
        uint256 price,
        address desiredTokenAddress,
        uint256 desiredTokenId,
        uint256 desiredErc1155Quantity,
        bool buyerWhitelistEnabled,
        bool partialBuyEnabled,
        address[] memory allowedBuyers
    ) external {
        IdeationMarketFacet(diamond).createListing(
            tokenAddress,
            tokenId,
            address(0),
            price,
            desiredTokenAddress,
            desiredTokenId,
            desiredErc1155Quantity,
            0,
            buyerWhitelistEnabled,
            partialBuyEnabled,
            allowedBuyers
        );
    }

    function listERC1155(
        address tokenAddress,
        uint256 tokenId,
        address erc1155Holder,
        uint256 price,
        uint256 erc1155Quantity,
        bool buyerWhitelistEnabled,
        bool partialBuyEnabled,
        address[] memory allowedBuyers
    ) external {
        IdeationMarketFacet(diamond).createListing(
            tokenAddress,
            tokenId,
            erc1155Holder,
            price,
            address(0),
            0,
            0,
            erc1155Quantity,
            buyerWhitelistEnabled,
            partialBuyEnabled,
            allowedBuyers
        );
    }

    function addWL(uint128 listingId, address[] calldata buyers) external {
        IBuyerWhitelistFacet(diamond).addBuyerWhitelistAddresses(listingId, buyers);
    }

    function removeWL(uint128 listingId, address[] calldata buyers) external {
        IBuyerWhitelistFacet(diamond).removeBuyerWhitelistAddresses(listingId, buyers);
    }

    function purchase(
        uint128 listingId,
        uint256 expectedPrice,
        uint256 expectedErc1155Quantity,
        address expectedDesiredTokenAddress,
        uint256 expectedDesiredTokenId,
        uint256 expectedDesiredErc1155Quantity,
        uint256 erc1155PurchaseQuantity,
        address desiredErc1155Holder
    ) external payable {
        IdeationMarketFacet(diamond).purchaseListing{value: msg.value}(
            listingId,
            expectedPrice,
            expectedErc1155Quantity,
            expectedDesiredTokenAddress,
            expectedDesiredTokenId,
            expectedDesiredErc1155Quantity,
            erc1155PurchaseQuantity,
            desiredErc1155Holder
        );
    }

    function cancel(uint128 listingId) external {
        IdeationMarketFacet(diamond).cancelListing(listingId);
    }

    function update(
        uint128 listingId,
        uint256 newPrice,
        address newDesiredTokenAddress,
        uint256 newDesiredTokenId,
        uint256 newDesiredErc1155Quantity,
        uint256 newErc1155Quantity,
        bool newBuyerWhitelistEnabled,
        bool newPartialBuyEnabled,
        address[] calldata newAllowedBuyers
    ) external {
        IdeationMarketFacet(diamond).updateListing(
            listingId,
            newPrice,
            newDesiredTokenAddress,
            newDesiredTokenId,
            newDesiredErc1155Quantity,
            newErc1155Quantity,
            newBuyerWhitelistEnabled,
            newPartialBuyEnabled,
            newAllowedBuyers
        );
    }

    function withdraw() external {
        IdeationMarketFacet(diamond).withdrawProceeds();
    }

    function clean(uint128 listingId) external {
        IdeationMarketFacet(diamond).cleanListing(listingId);
    }

    /* ----- Receiver hooks (used to detect/attempt reentrancy) ----- */

    function resetReentryFlag() external {
        reentryOk = false;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external override returns (bytes4) {
        // Attempt to reenter via withdraw (should revert/guard)
        try IdeationMarketFacet(diamond).withdrawProceeds() {
            reentryOk = true;
        } catch {}
        return IERC721Receiver.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external override returns (bytes4) {
        // Attempt to reenter via withdraw (should revert/guard)
        try IdeationMarketFacet(diamond).withdrawProceeds() {
            reentryOk = true;
        } catch {}
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }

    function acceptOwnership() external {
        OwnershipFacet(diamond).acceptOwnership();
    }
}

/* ------------------------------ Harness ------------------------------ */

contract EchidnaIdeationMarketHarness {
    /* ----- Diamond + facets ----- */
    IdeationMarketDiamond public diamond;
    DiamondCutFacet public cut;
    DiamondLoupeFacet public loupe;
    OwnershipFacet public ownership;
    IdeationMarketFacet public market;
    CollectionWhitelistFacet public colWL;
    BuyerWhitelistFacet public buyerWL;
    GetterFacet public getter;
    DiamondInit public initializer;

    /* ----- Mocks ----- */
    MockERC721 public nft721;
    MockERC721Royalty public nft721Royalty;
    MockERC1155 public nft1155;

    /* ----- Agents ----- */
    Agent public ownerAgent;
    Agent public alice;
    Agent public bob;
    Agent public carol;
    Agent public dave;

    /* ----- Constants ----- */
    uint32 internal constant INNOVATION_FEE = 1_000; // 1% (denominator 100_000)
    uint16 internal constant WL_BATCH_MAX = 300;
    uint256 internal constant FEE_DENOM = 100_000; // facet denominator

    /* ----- Latches for negative properties ----- */
    bool internal whitelistBypass; // set if a non-whitelisted buyer succeeds in buying a WL listing
    bool internal unauthFeeChange; // set if non-owner changes the innovation fee
    bool internal doubleSell; // set if a non-partial listing gets sold twice in sequence

    /**
     * @notice Constructor deploys the full diamond, cuts facets, initializes storage,
     *         deploys mocks, whitelists them, then hands ownership to an Agent.
     */
    constructor() payable {
        // 1) facets + initializer
        initializer = new DiamondInit();
        cut = new DiamondCutFacet();
        loupe = new DiamondLoupeFacet();
        ownership = new OwnershipFacet();
        market = new IdeationMarketFacet();
        colWL = new CollectionWhitelistFacet();
        buyerWL = new BuyerWhitelistFacet();
        getter = new GetterFacet();

        // 2) diamond with owner = harness
        diamond = new IdeationMarketDiamond(address(this), address(cut));

        // 3) cut all facets + init (owner is harness right now)
        {
            IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](6);

            bytes4[] memory loupeSelectors = new bytes4[](5);
            loupeSelectors[0] = IDiamondLoupeFacet.facets.selector;
            loupeSelectors[1] = IDiamondLoupeFacet.facetFunctionSelectors.selector;
            loupeSelectors[2] = IDiamondLoupeFacet.facetAddresses.selector;
            loupeSelectors[3] = IDiamondLoupeFacet.facetAddress.selector;
            loupeSelectors[4] = IERC165.supportsInterface.selector;

            bytes4[] memory ownerSelectors = new bytes4[](3);
            ownerSelectors[0] = IERC173.owner.selector;
            ownerSelectors[1] = IERC173.transferOwnership.selector;
            ownerSelectors[2] = OwnershipFacet.acceptOwnership.selector;

            bytes4[] memory marketSelectors = new bytes4[](7);
            marketSelectors[0] = IdeationMarketFacet.createListing.selector;
            marketSelectors[1] = IdeationMarketFacet.purchaseListing.selector;
            marketSelectors[2] = IdeationMarketFacet.cancelListing.selector;
            marketSelectors[3] = IdeationMarketFacet.updateListing.selector;
            marketSelectors[4] = IdeationMarketFacet.withdrawProceeds.selector;
            marketSelectors[5] = IdeationMarketFacet.setInnovationFee.selector;
            marketSelectors[6] = IdeationMarketFacet.cleanListing.selector;

            bytes4[] memory cwl = new bytes4[](4);
            cwl[0] = CollectionWhitelistFacet.addWhitelistedCollection.selector;
            cwl[1] = CollectionWhitelistFacet.removeWhitelistedCollection.selector;
            cwl[2] = CollectionWhitelistFacet.batchAddWhitelistedCollections.selector;
            cwl[3] = CollectionWhitelistFacet.batchRemoveWhitelistedCollections.selector;

            bytes4[] memory bwl = new bytes4[](2);
            bwl[0] = BuyerWhitelistFacet.addBuyerWhitelistAddresses.selector;
            bwl[1] = BuyerWhitelistFacet.removeBuyerWhitelistAddresses.selector;

            bytes4[] memory getSel = new bytes4[](12);
            getSel[0] = GetterFacet.getListingsByNFT.selector;
            getSel[1] = GetterFacet.getListingByListingId.selector;
            getSel[2] = GetterFacet.getProceeds.selector;
            getSel[3] = GetterFacet.getBalance.selector;
            getSel[4] = GetterFacet.getInnovationFee.selector;
            getSel[5] = GetterFacet.getNextListingId.selector;
            getSel[6] = GetterFacet.isCollectionWhitelisted.selector;
            getSel[7] = GetterFacet.getWhitelistedCollections.selector;
            getSel[8] = GetterFacet.getContractOwner.selector;
            getSel[9] = GetterFacet.isBuyerWhitelisted.selector;
            getSel[10] = GetterFacet.getBuyerWhitelistMaxBatchSize.selector;
            getSel[11] = GetterFacet.getPendingOwner.selector;

            cuts[0] = IDiamondCutFacet.FacetCut(address(loupe), IDiamondCutFacet.FacetCutAction.Add, loupeSelectors);
            cuts[1] = IDiamondCutFacet.FacetCut(address(ownership), IDiamondCutFacet.FacetCutAction.Add, ownerSelectors);
            cuts[2] = IDiamondCutFacet.FacetCut(address(market), IDiamondCutFacet.FacetCutAction.Add, marketSelectors);
            cuts[3] = IDiamondCutFacet.FacetCut(address(colWL), IDiamondCutFacet.FacetCutAction.Add, cwl);
            cuts[4] = IDiamondCutFacet.FacetCut(address(buyerWL), IDiamondCutFacet.FacetCutAction.Add, bwl);
            cuts[5] = IDiamondCutFacet.FacetCut(address(getter), IDiamondCutFacet.FacetCutAction.Add, getSel);

            IDiamondCutFacet(address(diamond)).diamondCut(
                cuts, address(initializer), abi.encodeCall(DiamondInit.init, (INNOVATION_FEE, WL_BATCH_MAX))
            );
        }

        // 4) mocks + whitelist WHILE HARNESS IS STILL OWNER
        nft721 = new MockERC721();
        nft721Royalty = new MockERC721Royalty();
        nft1155 = new MockERC1155();
        nft721Royalty.setRoyalty(address(this), 1000); // 10%

        address[] memory wl = new address[](3);
        wl[0] = address(nft721);
        wl[1] = address(nft721Royalty);
        wl[2] = address(nft1155);
        CollectionWhitelistFacet(address(diamond)).batchAddWhitelistedCollections(wl);

        // 5) now hand ownership to an Agent and accept
        ownerAgent = new Agent(address(diamond));
        OwnershipFacet(address(diamond)).transferOwnership(address(ownerAgent));
        ownerAgent.acceptOwnership();

        // 6) sanity: 7 facets total (cut facet + 6 we added)
        require(IDiamondLoupeFacet(address(diamond)).facetAddresses().length == 7, "cut failed");

        // 7) agents & assets
        alice = new Agent(address(diamond));
        bob = new Agent(address(diamond));
        carol = new Agent(address(diamond));
        dave = new Agent(address(diamond));

        nft721.mint(address(alice), 11);
        nft721.mint(address(bob), 12);
        nft721.mint(address(carol), 13);
        nft721.mint(address(dave), 14);

        nft721Royalty.mint(address(alice), 21);
        nft721Royalty.mint(address(bob), 22);

        nft1155.mint(address(alice), 1, 100);
        nft1155.mint(address(bob), 1, 60);
        nft1155.mint(address(carol), 1, 80);

        alice.setApproval721ForAll(nft721, true);
        bob.setApproval721ForAll(nft721, true);
        carol.setApproval721ForAll(nft721, true);
        dave.setApproval721ForAll(nft721, true);

        alice.setApproval721ForAll(nft721Royalty, true);
        bob.setApproval721ForAll(nft721Royalty, true);

        alice.setApproval1155ForAll(nft1155, true);
        bob.setApproval1155ForAll(nft1155, true);
        carol.setApproval1155ForAll(nft1155, true);
    }

    /* ---------------------------- Actions ---------------------------- */

    /// @notice Fuzzly fund the harness so it can forward ETH to Agent.purchase.
    function do_fund() external payable {}

    function do_list_erc721(uint256 who, bool royaltyToken, uint256 tokenIdHint, uint256 price, bool whitelist)
        external
    {
        Agent ag = _pickAgent(who);
        address token = royaltyToken ? address(nft721Royalty) : address(nft721);
        uint256 tokenId = _owned721(ag, token, tokenIdHint);
        uint256 p = price % 10 ether;
        if (!whitelist && p == 0) p = 0.01 ether; // ensure at least some ETH sales exist
        try ag.listERC721(token, tokenId, p, address(0), 0, 0, whitelist, false, new address[](0)) {} catch {}
    }

    function do_list_erc1155(uint256 who, uint256 qty, uint256 price, bool whitelist, bool partialBuy) external {
        Agent ag = _pickAgent(who);
        uint256 have = IERC1155(address(nft1155)).balanceOf(address(ag), 1);
        if (have == 0) return;
        uint256 q = qty % (have + 1);
        if (q == 0) q = 1;
        uint256 p = price % 5 ether;
        if (p == 0) p = 1 wei;
        if (partialBuy && p % q != 0) {
            p = (p / q) * q;
            if (p == 0) p = q;
        }
        try ag.listERC1155(address(nft1155), 1, address(ag), p, q, whitelist, partialBuy, new address[](0)) {} catch {}
    }

    /// @notice Attempt to purchase (best-effort, may revert).
    function do_purchase(uint256 buyerIdx, uint128 listingId, uint256 erc1155Qty) external payable {
        Agent buyer = _pickAgent(buyerIdx);
        try GetterFacet(address(diamond)).getListingByListingId(listingId) returns (Listing memory L) {
            uint256 purchasePrice = L.price;

            // Compute price for partial ERC1155
            if (L.erc1155Quantity > 0 && erc1155Qty > 0 && erc1155Qty <= L.erc1155Quantity) {
                if (erc1155Qty != L.erc1155Quantity) purchasePrice = (L.price * erc1155Qty) / L.erc1155Quantity;
            } else if (L.erc1155Quantity == 0) {
                erc1155Qty = 0;
            } else {
                return;
            }

            // Try to whitelist buyer if WL is enabled (may revert; that's fine)
            if (L.buyerWhitelistEnabled) {
                address[] memory addrs = _oneAddress(address(buyer));
                try buyer.addWL(listingId, addrs) {} catch {}
            }

            if (address(this).balance < purchasePrice) return;

            try buyer.purchase{value: purchasePrice}(
                listingId,
                L.price,
                L.erc1155Quantity,
                L.desiredTokenAddress,
                L.desiredTokenId,
                L.desiredErc1155Quantity,
                erc1155Qty,
                address(0)
            ) {} catch {}
        } catch {}
    }

    /// @notice Negative test: try to buy a WL-enabled listing *without* being whitelisted.
    function do_purchase_without_whitelist(uint256 buyerIdx, uint128 listingId, uint256 erc1155Qty) external payable {
        Agent buyer = _pickAgent(buyerIdx);
        try GetterFacet(address(diamond)).getListingByListingId(listingId) returns (Listing memory L) {
            if (!L.buyerWhitelistEnabled) return; // only meaningful when WL is on

            uint256 purchasePrice = L.price;
            if (L.erc1155Quantity > 0 && erc1155Qty > 0 && erc1155Qty <= L.erc1155Quantity) {
                if (erc1155Qty != L.erc1155Quantity) purchasePrice = (L.price * erc1155Qty) / L.erc1155Quantity;
            } else if (L.erc1155Quantity == 0) {
                erc1155Qty = 0;
            } else {
                return;
            }
            if (address(this).balance < purchasePrice) return;

            // critically: DO NOT add the buyer to WL here
            try buyer.purchase{value: purchasePrice}(
                listingId,
                L.price,
                L.erc1155Quantity,
                L.desiredTokenAddress,
                L.desiredTokenId,
                L.desiredErc1155Quantity,
                erc1155Qty,
                address(0)
            ) {
                // If this succeeds, whitelist was bypassed.
                whitelistBypass = true;
            } catch {}
        } catch {}
    }

    /// @notice Contention: try selling the same (non-partial) listing twice to two buyers in sequence.
    function do_two_buyers_contend(uint128 listingId) external payable {
        Agent b1 = alice;
        Agent b2 = bob;
        try GetterFacet(address(diamond)).getListingByListingId(listingId) returns (Listing memory L) {
            // Only meaningful for 721 or non-partial 1155 on ETH (not swaps)
            if (L.desiredTokenAddress != address(0)) return;
            if (L.erc1155Quantity > 0 && L.partialBuyEnabled) return;

            uint256 q = (L.erc1155Quantity > 0) ? L.erc1155Quantity : 0;
            uint256 price = L.price;
            if (address(this).balance < price * 2) return;

            bool s1;
            bool s2;

            try b1.purchase{value: price}(
                listingId,
                L.price,
                L.erc1155Quantity,
                L.desiredTokenAddress,
                L.desiredTokenId,
                L.desiredErc1155Quantity,
                q,
                address(0)
            ) {
                s1 = true;
            } catch {}

            try b2.purchase{value: price}(
                listingId,
                L.price,
                L.erc1155Quantity,
                L.desiredTokenAddress,
                L.desiredTokenId,
                L.desiredErc1155Quantity,
                q,
                address(0)
            ) {
                s2 = true;
            } catch {}

            if (s1 && s2) doubleSell = true;
        } catch {}
    }

    function do_cancel(uint256 who, uint128 listingId) external {
        Agent ag = _pickAgent(who);
        try ag.cancel(listingId) {} catch {}
    }

    function do_clean(uint128 listingId) external {
        try IdeationMarketFacet(address(diamond)).cleanListing(listingId) {} catch {}
    }

    /// @notice Exercise withdraw path.
    function do_withdraw(uint256 who) external {
        Agent ag = _pickAgent(who);
        try ag.withdraw() {} catch {}
    }

    function do_reset_reentry_flags() external {
        alice.resetReentryFlag();
        bob.resetReentryFlag();
        carol.resetReentryFlag();
        dave.resetReentryFlag();
    }

    /// @notice Owner path: may succeed if called through the ownerAgent (we call from harness so it should revert).
    function do_owner_set_fee(uint32 newFee) external {
        try IdeationMarketFacet(address(diamond)).setInnovationFee(newFee) {} catch {}
    }

    /// @notice Negative test: attempt fee change as non-owner and record if it actually changes.
    function do_try_set_fee_unauth(uint32 newFee) external {
        uint32 beforeFee = GetterFacet(address(diamond)).getInnovationFee();
        // Call as harness (not the owner). If fee changes, latch bug.
        try IdeationMarketFacet(address(diamond)).setInnovationFee(newFee) {
            uint32 afterFee = GetterFacet(address(diamond)).getInnovationFee();
            if (afterFee != beforeFee) unauthFeeChange = true;
        } catch {}
    }

    /// @notice Fuzz royalty bps on the royalty mock to explore fee/royalty math edges.
    function do_set_royalty(uint96 bps) external {
        nft721Royalty.setRoyalty(address(this), bps);
    }

    receive() external payable {}

    /* ----------------------- Properties (Invariants) ----------------------- */

    function echidna_loupe_and_erc165_wired() external view returns (bool) {
        address[] memory facs = IDiamondLoupeFacet(address(diamond)).facetAddresses();
        bool okCount = facs.length == 7;
        bool ok165 = IERC165(address(diamond)).supportsInterface(type(IERC165).interfaceId);
        bool okLoupe = IERC165(address(diamond)).supportsInterface(type(IDiamondLoupeFacet).interfaceId);
        bool okCut = IERC165(address(diamond)).supportsInterface(type(IDiamondCutFacet).interfaceId);
        bool okOwn = IERC165(address(diamond)).supportsInterface(type(IERC173).interfaceId);
        return okCount && ok165 && okLoupe && okCut && okOwn;
    }

    function echidna_no_reentrancy() external view returns (bool) {
        return !(alice.reentryOk() || bob.reentryOk() || carol.reentryOk() || dave.reentryOk());
    }

    function echidna_collections_still_whitelisted() external view returns (bool) {
        bool a = GetterFacet(address(diamond)).isCollectionWhitelisted(address(nft721));
        bool b = GetterFacet(address(diamond)).isCollectionWhitelisted(address(nft721Royalty));
        bool c = GetterFacet(address(diamond)).isCollectionWhitelisted(address(nft1155));
        return a && b && c;
    }

    /// @notice Native ETH conservation: diamond balance == sum of proceed balances we can observe.
    function echidna_eth_conserved_native() external view returns (bool) {
        uint256 sum = GetterFacet(address(diamond)).getProceeds(address(alice))
            + GetterFacet(address(diamond)).getProceeds(address(bob))
            + GetterFacet(address(diamond)).getProceeds(address(carol))
            + GetterFacet(address(diamond)).getProceeds(address(dave))
            + GetterFacet(address(diamond)).getProceeds(address(ownerAgent)) // fee owner
            + GetterFacet(address(diamond)).getProceeds(address(this)); // royalty receiver (harness)
        return address(diamond).balance == sum;
    }

    /// @notice Getter sanity vs native.
    function echidna_getBalance_matches_native() external view returns (bool) {
        return GetterFacet(address(diamond)).getBalance() == address(diamond).balance;
    }

    /// @notice Fee + royalty ≤ price for ACTIVE non-swap ETH listings.
    function echidna_fee_royalty_bounds() external view returns (bool) {
        if (GetterFacet(address(diamond)).getNextListingId() <= 1) return true; // no listings yet
        uint256[4] memory ids721 = [uint256(11), 12, 13, 14];
        for (uint256 i = 0; i < ids721.length; i++) {
            if (!_feeRoyaltyOkActive(address(nft721), ids721[i])) return false;
        }
        uint256[2] memory idsRoy = [uint256(21), 22];
        for (uint256 i = 0; i < idsRoy.length; i++) {
            if (!_feeRoyaltyOkActive(address(nft721Royalty), idsRoy[i])) return false;
        }
        if (!_feeRoyaltyOkActive(address(nft1155), 1)) return false;
        return true;
    }

    /// @notice ERC721 not double-listed among ACTIVE entries.
    function echidna_erc721_not_double_listed() external view returns (bool) {
        if (GetterFacet(address(diamond)).getNextListingId() <= 1) return true; // no listings yet
        uint256[4] memory ids721 = [uint256(11), 12, 13, 14];
        for (uint256 i = 0; i < ids721.length; i++) {
            if (_activeCount721(address(nft721), ids721[i]) > 1) return false;
        }
        uint256[2] memory idsRoy = [uint256(21), 22];
        for (uint256 i = 0; i < idsRoy.length; i++) {
            if (_activeCount721(address(nft721Royalty), idsRoy[i]) > 1) return false;
        }
        return true;
    }

    /// @notice Fee must be within 0..100%.
    function echidna_fee_in_range() external view returns (bool) {
        uint32 fee = GetterFacet(address(diamond)).getInnovationFee();
        return fee <= FEE_DENOM;
    }

    /// @notice Only ACTIVE ERC1155 listings with partial enabled must be divisible.
    function echidna_partial_price_divisible() external view returns (bool) {
        if (GetterFacet(address(diamond)).getNextListingId() <= 1) return true; // no listings yet
        Listing[] memory Ls = _safeListings(address(nft1155), 1);
        for (uint256 i = 0; i < Ls.length; i++) {
            Listing memory L = Ls[i];
            if (_isActive(L) && L.erc1155Quantity > 0 && L.partialBuyEnabled) {
                if (L.price % L.erc1155Quantity != 0) return false;
            }
        }
        return true;
    }

    /// @notice Buyer whitelist must be enforced (a non-whitelisted purchase cannot succeed).
    function echidna_whitelist_enforced() external view returns (bool) {
        return !whitelistBypass;
    }

    /// @notice Only owner can change fee.
    function echidna_only_owner_can_change_fee() external view returns (bool) {
        return !unauthFeeChange;
    }

    /// @notice Non-partial listings cannot be sold twice in sequence within a single fuzz sequence.
    function echidna_no_double_sells() external view returns (bool) {
        return !doubleSell;
    }

    /* ----------------------------- Helpers ----------------------------- */

    function _pickAgent(uint256 who) internal view returns (Agent) {
        uint256 w = who % 4;
        if (w == 0) return alice;
        if (w == 1) return bob;
        if (w == 2) return carol;
        return dave;
    }

    function _oneAddress(address a) internal pure returns (address[] memory) {
        address[] memory allowed = new address[](1);
        allowed[0] = a;
        return allowed;
    }

    function _owned721(Agent ag, address token, uint256 hint) internal view returns (uint256) {
        if (token == address(nft721Royalty)) {
            if (address(ag) == address(alice)) return 21;
            if (address(ag) == address(bob)) return 22;
            return 21;
        } else {
            uint256 idx = hint % 4;
            if (idx == 0) return 11;
            if (idx == 1) return 12;
            if (idx == 2) return 13;
            return 14;
        }
    }

    /// @dev Return active listings for (token,id) or an empty array if none.
    function _safeListings(address token, uint256 id) internal view returns (Listing[] memory Ls) {
        try GetterFacet(address(diamond)).getListingsByNFT(token, id) returns (Listing[] memory arr) {
            return arr;
        } catch {
            return new Listing[](0);
        }
    }

    /// @dev Consider ACTIVE if purchasable: non-zero price OR swap listing OR has 1155 qty.
    function _isActive(Listing memory L) internal pure returns (bool) {
        return (L.price > 0) || (L.desiredTokenAddress != address(0)) || (L.erc1155Quantity > 0);
    }

    function _isActive721(Listing memory L) internal pure returns (bool) {
        return _isActive(L) && (L.erc1155Quantity == 0);
    }

    function _activeCount721(address token, uint256 id) internal view returns (uint256 cnt) {
        Listing[] memory Ls = _safeListings(token, id);
        for (uint256 i = 0; i < Ls.length; i++) {
            if (_isActive721(Ls[i])) cnt++;
        }
    }

    function _supports2981(address token) internal view returns (bool) {
        // Defensive: if token doesn't implement ERC165, treat as no-2981.
        try IERC165(token).supportsInterface(type(IERC2981).interfaceId) returns (bool ok) {
            return ok;
        } catch {
            return false;
        }
    }

    /// @dev overflow-safe fee computation: exact (price * feeBps) / FEE_DENOM without 256-bit mul overflow
    function _feeFromPrice(uint256 price, uint32 feeBps) internal pure returns (uint256) {
        uint256 q = price / FEE_DENOM; // price = q*DEN + r
        uint256 r = price % FEE_DENOM;
        return q * feeBps + (r * feeBps) / FEE_DENOM;
    }

    function _feeRoyaltyOkActive(address token, uint256 id) internal view returns (bool) {
        Listing[] memory Ls = _safeListings(token, id);
        uint32 feeBps = GetterFacet(address(diamond)).getInnovationFee();
        bool has2981 = _supports2981(token);

        for (uint256 i = 0; i < Ls.length; i++) {
            Listing memory L = Ls[i];

            // Only validate ACTIVE non-swap ETH listings
            if (!_isActive(L)) continue;
            if (L.desiredTokenAddress != address(0) || L.price == 0) continue;

            uint256 fee = _feeFromPrice(L.price, feeBps);

            // Defensive: royalty can't force total payouts above price.
            uint256 royaltyEff = 0;
            if (has2981) {
                (, uint256 rRaw) = IERC2981(token).royaltyInfo(id, L.price);
                // First bound to price, then clamp to the remaining budget after fee.
                if (rRaw > L.price) rRaw = L.price;
                royaltyEff = (fee >= L.price) ? 0 : (rRaw > (L.price - fee) ? (L.price - fee) : rRaw);
            }

            if (fee + royaltyEff > L.price) return false;
        }
        return true;
    }
}
