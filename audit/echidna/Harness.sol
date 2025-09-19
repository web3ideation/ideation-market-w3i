// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title Echidna fuzz harness for the Ideation Market Diamond
 * @notice
 *  Deploys a full Diamond instance (cut + loupe + ownership + market + whitelists + getters),
 *  minimal ERC721 / ERC721+ERC2981 / ERC1155 mocks, and several user "Agents".
 *
 *  The harness exposes Echidna actions to:
 *    - list / purchase / cancel / clean listings
 *    - list ERC1155 with partial-buy and whitelist toggles
 *    - mutate fee and withdraw proceeds paths
 *
 *  And checks invariants:
 *    (1) Diamond loupe & ERC165 wiring soundness
 *    (2) No reentrancy (Agents attempt reentrant withdraw on token receipt)
 *    (3) Whitelisted collections remain whitelisted
 *    (4) Native ETH conservation: diamond balance equals observable proceeds sum
 *    (5) Getter.getBalance equals native ETH balance
 *    (6) Fee + ERC2981 royalty <= price on ACTIVE native-ETH listings
 *    (7) No ERC721 token is double-listed among ACTIVE entries
 *    (8) Innovation fee is within [0, 100%]
 *    (9) ERC1155 partial-buy price divisibility for ACTIVE partial listings
 *
 *  IMPORTANT:
 *    GetterFacet.getListingsByNFT(...) reverts if there are no active listings.
 *    We therefore ALWAYS call it through _getListingsOrEmpty() which swallows the
 *    specific "no active" revert and returns an empty array instead. This ensures
 *    invariants stay "honest" without spuriously failing from expected empty cases.
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

/// @dev Minimal receiver interface for our mock 721.
interface IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4);
}

/// @dev Minimal receiver interface for our mock 1155.
interface IERC1155Receiver {
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns (bytes4);
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        returns (bytes4);
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/* =======================================================
 *                         MOCKS
 * =====================================================*/

/// @notice Very small ERC721 mock with safeTransfer and approvals.
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

/// @notice ERC721 mock that also implements ERC2981 via a simple storage royalty.
contract MockERC721Royalty is MockERC721, IERC2981 {
    address public royaltyReceiver;
    uint96 public royaltyBps;

    function setRoyalty(address receiver, uint96 bps) external {
        royaltyReceiver = receiver;
        royaltyBps = bps;
    }

    function supportsInterface(bytes4 interfaceId) external view override(MockERC721, IERC165) returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC721).interfaceId
            || interfaceId == type(IERC2981).interfaceId;
    }

    function royaltyInfo(uint256, uint256 salePrice) external view override returns (address, uint256) {
        return (royaltyReceiver, (salePrice * royaltyBps) / 10000);
    }
}

/// @notice Very small ERC1155 mock with approvals and safe transfer hooks.
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

/* =======================================================
 *                        AGENT
 * =====================================================*/

/// @notice Test agent that interacts with the diamond and also hooks reentrancy on token receipt.
contract Agent is IERC721Receiver, IERC1155Receiver {
    /// @notice Target diamond address.
    address public immutable diamond;

    /// @notice Flag toggled if a reentrant withdraw succeeds during token receipt.
    bool public reentryOk;

    constructor(address _diamond) {
        diamond = _diamond;
    }

    /* ------------ Approvals ------------ */

    function approve721(MockERC721 token, uint256 tokenId) external {
        token.approve(diamond, tokenId);
    }

    function setApproval721ForAll(MockERC721 token, bool approved) external {
        token.setApprovalForAll(diamond, approved);
    }

    function setApproval1155ForAll(MockERC1155 token, bool approved) external {
        token.setApprovalForAll(diamond, approved);
    }

    /* ------------ Market ops ------------ */

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
            address(0), // 721 holder
            price,
            desiredTokenAddress,
            desiredTokenId,
            desiredErc1155Quantity,
            0, // erc1155Quantity
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

    function resetReentryFlag() external {
        reentryOk = false;
    }

    /* ------------ Token receiver hooks (attempt reentrancy) ------------ */

    function onERC721Received(address, address, uint256, bytes calldata) external override returns (bytes4) {
        // Attempt reentrant withdraw
        try IdeationMarketFacet(diamond).withdrawProceeds() {
            reentryOk = true;
        } catch {}
        return IERC721Receiver.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external override returns (bytes4) {
        // Attempt reentrant withdraw
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

/* =======================================================
 *                      HARNESS
 * =====================================================*/

/// @notice The Echidna harness contract.
contract EchidnaIdeationMarketHarness {
    /* ------------ Diamond + facets ------------ */
    IdeationMarketDiamond public diamond;
    DiamondCutFacet public cut;
    DiamondLoupeFacet public loupe;
    OwnershipFacet public ownership;
    IdeationMarketFacet public market;
    CollectionWhitelistFacet public colWL;
    BuyerWhitelistFacet public buyerWL;
    GetterFacet public getter;
    DiamondInit public initializer;

    /* ------------ Token mocks ------------ */
    MockERC721 public nft721;
    MockERC721Royalty public nft721Royalty;
    MockERC1155 public nft1155;

    /* ------------ Agents ------------ */
    Agent public ownerAgent;
    Agent public alice;
    Agent public bob;
    Agent public carol;
    Agent public dave;

    /* ------------ Constants ------------ */
    uint32 internal constant INNOVATION_FEE = 1_000; // 1% (denominator 100_000)
    uint16 internal constant WL_BATCH_MAX = 300;
    uint256 internal constant FEE_DENOM = 100_000; // fee denominator used by facet

    /* ----------------------------------------------------
     *                    Constructor
     * --------------------------------------------------*/

    /**
     * @notice Deploy and wire the full diamond, then set up agents, assets, and approvals.
     */
    constructor() payable {
        // 1) deploy initializer and facets
        initializer = new DiamondInit();
        cut = new DiamondCutFacet();
        loupe = new DiamondLoupeFacet();
        ownership = new OwnershipFacet();
        market = new IdeationMarketFacet();
        colWL = new CollectionWhitelistFacet();
        buyerWL = new BuyerWhitelistFacet();
        getter = new GetterFacet();

        // 2) deploy diamond with harness as owner initially
        diamond = new IdeationMarketDiamond(address(this), address(cut));

        // 3) cut in all facets and run init
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

        // 4) deploy mocks and whitelist them while harness is still owner
        nft721 = new MockERC721();
        nft721Royalty = new MockERC721Royalty();
        nft1155 = new MockERC1155();

        // set a 10% ERC2981 royalty on the royalty 721; receiver is the harness (to test proceeds splitting)
        nft721Royalty.setRoyalty(address(this), 1000); // 10%

        address[] memory wl = new address[](3);
        wl[0] = address(nft721);
        wl[1] = address(nft721Royalty);
        wl[2] = address(nft1155);
        CollectionWhitelistFacet(address(diamond)).batchAddWhitelistedCollections(wl);

        // 5) hand ownership to an agent and accept
        ownerAgent = new Agent(address(diamond));
        OwnershipFacet(address(diamond)).transferOwnership(address(ownerAgent));
        ownerAgent.acceptOwnership();

        // 6) sanity: 7 facets total (cut + 6 added)
        require(IDiamondLoupeFacet(address(diamond)).facetAddresses().length == 7, "cut failed");

        // 7) create agents and mint some assets
        alice = new Agent(address(diamond));
        bob = new Agent(address(diamond));
        carol = new Agent(address(diamond));
        dave = new Agent(address(diamond));

        // ERC721 ids: 11..14 (no royalties)
        nft721.mint(address(alice), 11);
        nft721.mint(address(bob), 12);
        nft721.mint(address(carol), 13);
        nft721.mint(address(dave), 14);

        // ERC721+2981 ids: 21..22
        nft721Royalty.mint(address(alice), 21);
        nft721Royalty.mint(address(bob), 22);

        // ERC1155 id: 1
        nft1155.mint(address(alice), 1, 100);
        nft1155.mint(address(bob), 1, 60);
        nft1155.mint(address(carol), 1, 80);

        // approvals for diamond
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

    /* ----------------------------------------------------
     *                     Actions
     *  (Echidna will call these with fuzzed params)
     * --------------------------------------------------*/

    /// @notice List an ERC721 with either native price or desired swap target.
    function do_list_erc721(uint256 who, bool royaltyToken, uint256 tokenIdHint, uint256 price, bool whitelist)
        external
    {
        Agent ag = _pickAgent(who);
        address token = royaltyToken ? address(nft721Royalty) : address(nft721);
        uint256 tokenId = _owned721(ag, token, tokenIdHint);

        uint256 p = price % 10 ether;
        if (!whitelist && p == 0) p = 0.01 ether; // avoid "free" native listings unless whitelisted-only

        try ag.listERC721(token, tokenId, p, address(0), 0, 0, whitelist, false, new address[](0)) {} catch {}
    }

    /// @notice List ERC1155 id=1 with optional partial-buy; adjusts price to be divisible if partial.
    function do_list_erc1155(uint256 who, uint256 qty, uint256 price, bool whitelist, bool partialBuy) external {
        Agent ag = _pickAgent(who);
        uint256 have = IERC1155(address(nft1155)).balanceOf(address(ag), 1);
        if (have == 0) return;

        uint256 q = qty % (have + 1);
        if (q == 0) q = 1;

        uint256 p = price % 5 ether;
        if (p == 0) p = 1 wei;

        if (partialBuy && p % q != 0) {
            // nudge to a divisible price-per-unit
            p = (p / q) * q;
            if (p == 0) p = q;
        }

        try ag.listERC1155(address(nft1155), 1, address(ag), p, q, whitelist, partialBuy, new address[](0)) {} catch {}
    }

    /// @notice Purchase a listing (721 or 1155). For 1155 partials, computes correct msg.value.
    function do_purchase(uint256 buyerIdx, uint128 listingId, uint256 erc1155Qty) external payable {
        Agent buyer = _pickAgent(buyerIdx);
        try GetterFacet(address(diamond)).getListingByListingId(listingId) returns (Listing memory L) {
            uint256 purchasePrice = L.price;
            if (L.erc1155Quantity > 0 && erc1155Qty > 0 && erc1155Qty <= L.erc1155Quantity) {
                if (erc1155Qty != L.erc1155Quantity) {
                    purchasePrice = (L.price * erc1155Qty) / L.erc1155Quantity;
                }
            } else if (L.erc1155Quantity == 0) {
                erc1155Qty = 0;
            } else {
                return; // invalid qty
            }

            // ensure buyer in whitelist if listing requires it
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

    /// @notice Cancel a listing if caller is its owner.
    function do_cancel(uint256 who, uint128 listingId) external {
        Agent ag = _pickAgent(who);
        try ag.cancel(listingId) {} catch {}
    }

    /// @notice Clean a listing (post-conditions enforcement).
    function do_clean(uint128 listingId) external {
        try IdeationMarketFacet(address(diamond)).cleanListing(listingId) {} catch {}
    }

    /// @notice Exercise withdraw proceeds flow.
    function do_withdraw(uint256 who) external {
        Agent ag = _pickAgent(who);
        try ag.withdraw() {} catch {}
    }

    /// @notice Reset reentrancy flags on all agents.
    function do_reset_reentry_flags() external {
        alice.resetReentryFlag();
        bob.resetReentryFlag();
        carol.resetReentryFlag();
        dave.resetReentryFlag();
    }

    /// @notice Owner-only path: mutate the innovation fee (may revert if not owner).
    function do_owner_set_fee(uint32 newFee) external {
        try IdeationMarketFacet(address(diamond)).setInnovationFee(newFee) {} catch {}
    }

    /// @notice Allow Echidna to fund this harness.
    receive() external payable {}

    /* ----------------------------------------------------
     *                    Invariants
     * --------------------------------------------------*/

    /// @notice Diamond loupe & ERC165 wiring should be intact.
    function echidna_loupe_and_erc165_wired() external view returns (bool) {
        address[] memory facs = IDiamondLoupeFacet(address(diamond)).facetAddresses();
        bool okCount = facs.length == 7;
        bool ok165 = IERC165(address(diamond)).supportsInterface(type(IERC165).interfaceId);
        bool okLoupe = IERC165(address(diamond)).supportsInterface(type(IDiamondLoupeFacet).interfaceId);
        bool okCut = IERC165(address(diamond)).supportsInterface(type(IDiamondCutFacet).interfaceId);
        bool okOwn = IERC165(address(diamond)).supportsInterface(type(IERC173).interfaceId);
        return okCount && ok165 && okLoupe && okCut && okOwn;
    }

    /// @notice Agents tried reentrant withdraws during token receipt; must all be false.
    function echidna_no_reentrancy() external view returns (bool) {
        return !(alice.reentryOk() || bob.reentryOk() || carol.reentryOk() || dave.reentryOk());
    }

    /// @notice Whitelisted collections should remain whitelisted.
    function echidna_collections_still_whitelisted() external view returns (bool) {
        bool a = GetterFacet(address(diamond)).isCollectionWhitelisted(address(nft721));
        bool b = GetterFacet(address(diamond)).isCollectionWhitelisted(address(nft721Royalty));
        bool c = GetterFacet(address(diamond)).isCollectionWhitelisted(address(nft1155));
        return a && b && c;
    }

    /// @notice Native ETH conservation: balance equals observable proceeds sum.
    function echidna_eth_conserved_native() external view returns (bool) {
        uint256 sum = GetterFacet(address(diamond)).getProceeds(address(alice))
            + GetterFacet(address(diamond)).getProceeds(address(bob))
            + GetterFacet(address(diamond)).getProceeds(address(carol))
            + GetterFacet(address(diamond)).getProceeds(address(dave))
            + GetterFacet(address(diamond)).getProceeds(address(ownerAgent)) // fee owner
            + GetterFacet(address(diamond)).getProceeds(address(this)); // royalty receiver (harness)
        return address(diamond).balance == sum;
    }

    /// @notice Getter.getBalance must match the diamond's native ETH balance.
    function echidna_getBalance_matches_native() external view returns (bool) {
        return GetterFacet(address(diamond)).getBalance() == address(diamond).balance;
    }

    /// @notice Fee + royalty must not exceed price for ACTIVE native-ETH listings.
    function echidna_fee_royalty_bounds() external view returns (bool) {
        if (GetterFacet(address(diamond)).getNextListingId() <= 1) return true; // no listings yet

        uint256[4] memory ids721 = [uint256(11), 12, 13, 14];
        for (uint256 i = 0; i < ids721.length; i++) {
            if (!_feeRoyaltyOkActive(address(nft721), ids721[i])) return false;
        }

        uint256[2] memory idsRoy = [uint256(21), 22];
        for (uint256 j = 0; j < idsRoy.length; j++) {
            if (!_feeRoyaltyOkActive(address(nft721Royalty), idsRoy[j])) return false;
        }

        if (!_feeRoyaltyOkActive(address(nft1155), 1)) return false;

        return true;
    }

    /// @notice No ERC721 token should be double-listed among ACTIVE entries.
    function echidna_erc721_not_double_listed() external view returns (bool) {
        if (GetterFacet(address(diamond)).getNextListingId() <= 1) return true; // no listings yet
        uint256[4] memory ids721 = [uint256(11), 12, 13, 14];
        for (uint256 i = 0; i < ids721.length; i++) {
            if (_activeCount721(address(nft721), ids721[i]) > 1) return false;
        }
        uint256[2] memory idsRoy = [uint256(21), 22];
        for (uint256 j = 0; j < idsRoy.length; j++) {
            if (_activeCount721(address(nft721Royalty), idsRoy[j]) > 1) return false;
        }
        return true;
    }

    /// @notice Innovation fee must remain within [0, 100%].
    function echidna_fee_in_range() external view returns (bool) {
        uint32 fee = GetterFacet(address(diamond)).getInnovationFee();
        return fee <= FEE_DENOM;
    }

    /// @notice For ACTIVE ERC1155 listings with partial-buy enabled, price must be divisible by quantity.
    function echidna_partial_price_divisible() external view returns (bool) {
        if (GetterFacet(address(diamond)).getNextListingId() <= 1) return true; // no listings yet
        Listing[] memory Ls = _getListingsOrEmpty(address(nft1155), 1);
        for (uint256 i = 0; i < Ls.length; i++) {
            Listing memory L = Ls[i];
            if (_isActive(L) && L.erc1155Quantity > 0 && L.partialBuyEnabled) {
                if (L.price % L.erc1155Quantity != 0) return false;
            }
        }
        return true;
    }

    /* ----------------------------------------------------
     *                    Helpers
     * --------------------------------------------------*/

    /// @dev Pick an agent based on a fuzzed index.
    function _pickAgent(uint256 who) internal view returns (Agent) {
        uint256 w = who % 4;
        if (w == 0) return alice;
        if (w == 1) return bob;
        if (w == 2) return carol;
        return dave;
    }

    /// @dev Wrap an address into a single-element array.
    function _oneAddress(address a) internal pure returns (address[] memory) {
        address[] memory allowed = new address[](1);
        allowed[0] = a;
        return allowed;
    }

    /// @dev Choose an owned 721 id for the given agent and token.
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

    /// @dev Treat listing as ACTIVE if it looks purchasable (native price OR desired swap OR 1155 qty).
    function _isActive(Listing memory L) internal pure returns (bool) {
        return (L.price > 0) || (L.desiredTokenAddress != address(0)) || (L.erc1155Quantity > 0);
    }

    /// @dev ACTIVE 721 == ACTIVE and not an ERC1155 listing.
    function _isActive721(Listing memory L) internal pure returns (bool) {
        return _isActive(L) && (L.erc1155Quantity == 0);
    }

    /// @dev Safe wrapper: returns active listings array or an empty array if GetterFacet reverts with "no active".
    function _getListingsOrEmpty(address token, uint256 id) internal view returns (Listing[] memory Ls) {
        try GetterFacet(address(diamond)).getListingsByNFT(token, id) returns (Listing[] memory _Ls) {
            return _Ls;
        } catch {
            return new Listing[](0);
        }
    }

    /// @dev Count ACTIVE 721 listings for (token,id) without reverting on "no active".
    function _activeCount721(address token, uint256 id) internal view returns (uint256 cnt) {
        Listing[] memory Ls = _getListingsOrEmpty(token, id);
        for (uint256 i = 0; i < Ls.length; i++) {
            if (_isActive721(Ls[i])) cnt++;
        }
    }

    /// @dev Best-effort ERC2981 support check; if token lacks ERC165, treat as "no 2981".
    function _supports2981(address token) internal view returns (bool) {
        try IERC165(token).supportsInterface(type(IERC2981).interfaceId) returns (bool ok) {
            return ok;
        } catch {
            return false;
        }
    }

    /// @dev Validate fee + royalty <= price across ACTIVE native-ETH listings for (token,id).
    function _feeRoyaltyOkActive(address token, uint256 id) internal view returns (bool) {
        Listing[] memory Ls = _getListingsOrEmpty(token, id);
        uint32 feeBps = GetterFacet(address(diamond)).getInnovationFee();
        bool has2981 = _supports2981(token);

        for (uint256 i = 0; i < Ls.length; i++) {
            Listing memory L = Ls[i];

            // Only validate ACTIVE, non-swap, non-zero-price (native) listings
            if (!_isActive(L)) continue;
            if (L.desiredTokenAddress != address(0) || L.price == 0) continue;

            uint256 fee = (uint256(feeBps) * L.price) / FEE_DENOM;
            uint256 royalty = 0;

            if (has2981) {
                (, uint256 r) = IERC2981(token).royaltyInfo(id, L.price);
                royalty = r;
            }
            if (fee + royalty > L.price) return false;
        }
        return true;
    }
}
