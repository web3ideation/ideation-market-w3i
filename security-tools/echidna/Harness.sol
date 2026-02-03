// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title Echidna fuzz harness for the Ideation Market Diamond
 * @notice Behavior-exercising invariants (listing/purchase/cancel/clean, partial buys, whitelists, fee/royalty bounds).
 * @dev Self-contained under `security-tools/echidna/` and imports from the mirrored `./src/` tree.
 */
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

import "./src/libraries/LibAppStorage.sol";

import "./src/interfaces/IDiamondInspectFacet.sol";
import "./src/interfaces/IDiamondLoupeFacet.sol";
import "./src/interfaces/IDiamondUpgradeFacet.sol";
import "./src/interfaces/IERC165.sol";
import "./src/interfaces/IERC173.sol";
import "./src/interfaces/IERC721.sol";
import "./src/interfaces/IERC1155.sol";
import "./src/interfaces/IERC2981.sol";
import "./src/interfaces/IBuyerWhitelistFacet.sol";

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

interface IERC20Minimal {
    function balanceOf(address a) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
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

    uint96 internal constant MAX_ROYALTY_BPS = 2000; // 20.00% (curated collection assumption)

    function setRoyalty(address receiver, uint96 bps) external {
        royaltyReceiver = receiver;
        royaltyBps = uint96(bps % (MAX_ROYALTY_BPS + 1));
    }

    function supportsInterface(bytes4 interfaceId) external pure override(MockERC721, IERC165) returns (bool) {
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

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
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
        require(from == msg.sender || _operatorApproval[from][msg.sender], "1155 not approved");
        require(ids.length == amounts.length, "len mismatch");
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 tokenId = ids[i];
            uint256 amount = amounts[i];
            require(_bal[tokenId][from] >= amount, "no bal");
            unchecked {
                _bal[tokenId][from] -= amount;
                _bal[tokenId][to] += amount;
            }
        }
        if (to.code.length > 0) {
            try IERC1155Receiver(to).onERC1155BatchReceived(msg.sender, from, ids, amounts, "") returns (bytes4 ret) {
                require(ret == IERC1155Receiver.onERC1155BatchReceived.selector, "bad 1155 receiver");
            } catch {
                revert("no 1155 receiver");
            }
        }
    }

    function mint(address to, uint256 id, uint256 amount) external {
        require(to != address(0), "zero addr");
        _bal[id][to] += amount;
    }
}

contract MockERC20 is IERC20Minimal {
    mapping(address => uint256) internal _bal;
    mapping(address => mapping(address => uint256)) internal _allow;

    function balanceOf(address a) external view returns (uint256) {
        return _bal[a];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allow[msg.sender][spender] = amount;
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allow[owner][spender];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(_bal[msg.sender] >= amount, "no bal");
        unchecked {
            _bal[msg.sender] -= amount;
            _bal[to] += amount;
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 a = _allow[from][msg.sender];
        require(a >= amount, "no allow");
        require(_bal[from] >= amount, "no bal");
        unchecked {
            _allow[from][msg.sender] = a - amount;
            _bal[from] -= amount;
            _bal[to] += amount;
        }
        return true;
    }

    function mint(address to, uint256 amount) external {
        _bal[to] += amount;
    }
}

/* ------------------------------ Agent ------------------------------ */

contract Agent is IERC721Receiver, IERC1155Receiver {
    address public diamond;

    bool public reentryOk;

    uint128 internal lastListingId;
    uint256 internal lastExpectedPrice;
    address internal lastExpectedCurrency;
    uint256 internal lastExpectedErc1155Quantity;
    address internal lastExpectedDesiredTokenAddress;
    uint256 internal lastExpectedDesiredTokenId;
    uint256 internal lastExpectedDesiredErc1155Quantity;
    uint256 internal lastErc1155PurchaseQuantity;
    address internal lastDesiredErc1155Holder;
    uint256 internal lastMsgValue;

    constructor(address _diamond) {
        diamond = _diamond;
    }

    receive() external payable {}

    function setApproval721ForAll(IERC721 token, bool approved) external {
        token.setApprovalForAll(address(diamond), approved);
    }

    function setApproval1155ForAll(IERC1155 token, bool approved) external {
        token.setApprovalForAll(address(diamond), approved);
    }

    function approveERC20(IERC20Minimal token, uint256 amount) external {
        token.approve(address(diamond), amount);
    }

    function pause() external {
        PauseFacet(diamond).pause();
    }

    function unpause() external {
        PauseFacet(diamond).unpause();
    }

    function addAllowedCurrency(address currency) external {
        CurrencyWhitelistFacet(diamond).addAllowedCurrency(currency);
    }

    function removeAllowedCurrency(address currency) external {
        CurrencyWhitelistFacet(diamond).removeAllowedCurrency(currency);
    }

    function addWhitelistedCollection(address tokenAddress) external {
        CollectionWhitelistFacet(diamond).addWhitelistedCollection(tokenAddress);
    }

    function removeWhitelistedCollection(address tokenAddress) external {
        CollectionWhitelistFacet(diamond).removeWhitelistedCollection(tokenAddress);
    }

    function listERC721(
        address tokenAddress,
        uint256 tokenId,
        uint256 price,
        address currency,
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
            currency,
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
        address currency,
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
            currency,
            address(0),
            0,
            0,
            erc1155Quantity,
            buyerWhitelistEnabled,
            partialBuyEnabled,
            allowedBuyers
        );
    }

    function update(
        uint128 listingId,
        uint256 newPrice,
        address newCurrency,
        address newDesiredTokenAddress,
        uint256 newDesiredTokenId,
        uint256 newDesiredErc1155Quantity,
        uint256 newErc1155Quantity,
        bool newBuyerWhitelistEnabled,
        bool newPartialBuyEnabled,
        address[] memory newAllowedBuyers
    ) external {
        IdeationMarketFacet(diamond).updateListing(
            listingId,
            newPrice,
            newCurrency,
            newDesiredTokenAddress,
            newDesiredTokenId,
            newDesiredErc1155Quantity,
            newErc1155Quantity,
            newBuyerWhitelistEnabled,
            newPartialBuyEnabled,
            newAllowedBuyers
        );
    }

    function purchase(
        uint128 listingId,
        uint256 expectedPrice,
        address expectedCurrency,
        uint256 expectedErc1155Quantity,
        address expectedDesiredTokenAddress,
        uint256 expectedDesiredTokenId,
        uint256 expectedDesiredErc1155Quantity,
        uint256 erc1155PurchaseQuantity,
        address desiredErc1155Holder
    ) external payable {
        lastListingId = listingId;
        lastExpectedPrice = expectedPrice;
        lastExpectedCurrency = expectedCurrency;
        lastExpectedErc1155Quantity = expectedErc1155Quantity;
        lastExpectedDesiredTokenAddress = expectedDesiredTokenAddress;
        lastExpectedDesiredTokenId = expectedDesiredTokenId;
        lastExpectedDesiredErc1155Quantity = expectedDesiredErc1155Quantity;
        lastErc1155PurchaseQuantity = erc1155PurchaseQuantity;
        lastDesiredErc1155Holder = desiredErc1155Holder;
        lastMsgValue = msg.value;

        IdeationMarketFacet(diamond).purchaseListing{value: msg.value}(
            listingId,
            expectedPrice,
            expectedCurrency,
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

    function clean(uint128 listingId) external {
        IdeationMarketFacet(diamond).cleanListing(listingId);
    }

    function resetReentryFlag() external {
        reentryOk = false;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external override returns (bytes4) {
        if (lastListingId != 0 && lastMsgValue > 0 && address(this).balance >= lastMsgValue) {
            try IdeationMarketFacet(diamond).purchaseListing{value: lastMsgValue}(
                lastListingId,
                lastExpectedPrice,
                lastExpectedCurrency,
                lastExpectedErc1155Quantity,
                lastExpectedDesiredTokenAddress,
                lastExpectedDesiredTokenId,
                lastExpectedDesiredErc1155Quantity,
                lastErc1155PurchaseQuantity,
                lastDesiredErc1155Holder
            ) {
                reentryOk = true;
            } catch {}
        }
        return IERC721Receiver.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external override returns (bytes4) {
        if (lastListingId != 0 && lastMsgValue > 0 && address(this).balance >= lastMsgValue) {
            try IdeationMarketFacet(diamond).purchaseListing{value: lastMsgValue}(
                lastListingId,
                lastExpectedPrice,
                lastExpectedCurrency,
                lastExpectedErc1155Quantity,
                lastExpectedDesiredTokenAddress,
                lastExpectedDesiredTokenId,
                lastExpectedDesiredErc1155Quantity,
                lastErc1155PurchaseQuantity,
                lastDesiredErc1155Holder
            ) {
                reentryOk = true;
            } catch {}
        }
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }

    function acceptOwnership() external {
        OwnershipFacet(diamond).acceptOwnership();
    }
}

/* ------------------------------ Harness ------------------------------ */

contract EchidnaIdeationMarketHarness {
    IdeationMarketDiamond public diamond;

    DiamondUpgradeFacet public upgradeFacet;
    DiamondLoupeFacet public loupe;
    OwnershipFacet public ownership;
    IdeationMarketFacet public market;
    CollectionWhitelistFacet public colWL;
    BuyerWhitelistFacet public buyerWL;
    GetterFacet public getter;
    CurrencyWhitelistFacet public currencyWL;
    VersionFacet public versionFacet;
    PauseFacet public pauseFacet;
    DiamondInit public initializer;

    MockERC721 public nft721;
    MockERC721Royalty public nft721Royalty;
    MockERC1155 public nft1155;
    MockERC1155 public nft1155Swap;
    MockERC721 public nft721Swap;
    MockERC20 public erc20;

    Agent public ownerAgent;
    Agent public alice;
    Agent public bob;
    Agent public carol;
    Agent public dave;

    uint32 internal constant INNOVATION_FEE = 1_000;
    uint16 internal constant WL_BATCH_MAX = 300;
    uint256 internal constant FEE_DENOM = 100_000;

    bool internal whitelistBypass;
    bool internal unauthFeeChange;
    bool internal doubleSell;

    bool internal pauseBypass;
    bool internal currencyBypass;
    bool internal collectionPurchaseBypass;
    bool internal collectionUpdateBypass;
    bool internal collectionCreateBypass;

    uint128[64] internal recentListingIds;
    uint256 internal recentListingCursor;

    constructor() payable {
        initializer = new DiamondInit();
        upgradeFacet = new DiamondUpgradeFacet();
        loupe = new DiamondLoupeFacet();
        ownership = new OwnershipFacet();
        market = new IdeationMarketFacet();
        colWL = new CollectionWhitelistFacet();
        buyerWL = new BuyerWhitelistFacet();
        getter = new GetterFacet();
        currencyWL = new CurrencyWhitelistFacet();
        versionFacet = new VersionFacet();
        pauseFacet = new PauseFacet();

        diamond = new IdeationMarketDiamond(address(this), address(upgradeFacet));

        IDiamondUpgradeFacet.FacetFunctions[] memory addFns = new IDiamondUpgradeFacet.FacetFunctions[](9);

        bytes4[] memory loupeSelectors = new bytes4[](6);
        loupeSelectors[0] = IDiamondLoupeFacet.facets.selector;
        loupeSelectors[1] = IDiamondLoupeFacet.facetFunctionSelectors.selector;
        loupeSelectors[2] = IDiamondLoupeFacet.facetAddresses.selector;
        loupeSelectors[3] = IDiamondLoupeFacet.facetAddress.selector;
        loupeSelectors[4] = IERC165.supportsInterface.selector;
        loupeSelectors[5] = IDiamondInspectFacet.functionFacetPairs.selector;

        bytes4[] memory ownerSelectors = new bytes4[](3);
        ownerSelectors[0] = IERC173.owner.selector;
        ownerSelectors[1] = IERC173.transferOwnership.selector;
        ownerSelectors[2] = OwnershipFacet.acceptOwnership.selector;

        bytes4[] memory marketSelectors = new bytes4[](6);
        marketSelectors[0] = IdeationMarketFacet.createListing.selector;
        marketSelectors[1] = IdeationMarketFacet.purchaseListing.selector;
        marketSelectors[2] = IdeationMarketFacet.cancelListing.selector;
        marketSelectors[3] = IdeationMarketFacet.updateListing.selector;
        marketSelectors[4] = IdeationMarketFacet.setInnovationFee.selector;
        marketSelectors[5] = IdeationMarketFacet.cleanListing.selector;

        bytes4[] memory cwlSelectors = new bytes4[](4);
        cwlSelectors[0] = CollectionWhitelistFacet.addWhitelistedCollection.selector;
        cwlSelectors[1] = CollectionWhitelistFacet.removeWhitelistedCollection.selector;
        cwlSelectors[2] = CollectionWhitelistFacet.batchAddWhitelistedCollections.selector;
        cwlSelectors[3] = CollectionWhitelistFacet.batchRemoveWhitelistedCollections.selector;

        bytes4[] memory bwlSelectors = new bytes4[](2);
        bwlSelectors[0] = BuyerWhitelistFacet.addBuyerWhitelistAddresses.selector;
        bwlSelectors[1] = BuyerWhitelistFacet.removeBuyerWhitelistAddresses.selector;

        bytes4[] memory currencySelectors = new bytes4[](2);
        currencySelectors[0] = CurrencyWhitelistFacet.addAllowedCurrency.selector;
        currencySelectors[1] = CurrencyWhitelistFacet.removeAllowedCurrency.selector;

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

        addFns[0] = IDiamondUpgradeFacet.FacetFunctions({facet: address(loupe), selectors: loupeSelectors});
        addFns[1] = IDiamondUpgradeFacet.FacetFunctions({facet: address(ownership), selectors: ownerSelectors});
        addFns[2] = IDiamondUpgradeFacet.FacetFunctions({facet: address(market), selectors: marketSelectors});
        addFns[3] = IDiamondUpgradeFacet.FacetFunctions({facet: address(colWL), selectors: cwlSelectors});
        addFns[4] = IDiamondUpgradeFacet.FacetFunctions({facet: address(buyerWL), selectors: bwlSelectors});
        addFns[5] = IDiamondUpgradeFacet.FacetFunctions({facet: address(getter), selectors: getterSelectors});
        addFns[6] = IDiamondUpgradeFacet.FacetFunctions({facet: address(currencyWL), selectors: currencySelectors});
        addFns[7] = IDiamondUpgradeFacet.FacetFunctions({facet: address(versionFacet), selectors: versionSelectors});
        addFns[8] = IDiamondUpgradeFacet.FacetFunctions({facet: address(pauseFacet), selectors: pauseSelectors});

        IDiamondUpgradeFacet(address(diamond)).upgradeDiamond(
            addFns,
            new IDiamondUpgradeFacet.FacetFunctions[](0),
            new bytes4[](0),
            address(initializer),
            abi.encodeCall(DiamondInit.init, (INNOVATION_FEE, WL_BATCH_MAX)),
            bytes32(0),
            bytes("")
        );

        nft721 = new MockERC721();
        nft721Royalty = new MockERC721Royalty();
        nft1155 = new MockERC1155();
        nft1155Swap = new MockERC1155();
        nft721Swap = new MockERC721();
        erc20 = new MockERC20();
        nft721Royalty.setRoyalty(address(this), 1000);

        address[] memory wl = new address[](3);
        wl[0] = address(nft721);
        wl[1] = address(nft721Royalty);
        wl[2] = address(nft1155);
        CollectionWhitelistFacet(address(diamond)).batchAddWhitelistedCollections(wl);

        // Allow harness ERC-20 currency for fuzzing (diamond owner is still this harness at this point)
        CurrencyWhitelistFacet(address(diamond)).addAllowedCurrency(address(erc20));

        ownerAgent = new Agent(address(diamond));
        OwnershipFacet(address(diamond)).transferOwnership(address(ownerAgent));
        ownerAgent.acceptOwnership();

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

        // Desired ERC-1155 swap inventory (tokenId 2)
        nft1155Swap.mint(address(alice), 2, 25);
        nft1155Swap.mint(address(bob), 2, 25);
        nft1155Swap.mint(address(carol), 2, 25);
        nft1155Swap.mint(address(dave), 2, 25);

        // Swap token inventory (each agent owns one token id)
        nft721Swap.mint(address(alice), 31);
        nft721Swap.mint(address(bob), 32);
        nft721Swap.mint(address(carol), 33);
        nft721Swap.mint(address(dave), 34);

        alice.setApproval721ForAll(nft721, true);
        bob.setApproval721ForAll(nft721, true);
        carol.setApproval721ForAll(nft721, true);
        dave.setApproval721ForAll(nft721, true);

        alice.setApproval721ForAll(nft721Royalty, true);
        bob.setApproval721ForAll(nft721Royalty, true);

        alice.setApproval721ForAll(nft721Swap, true);
        bob.setApproval721ForAll(nft721Swap, true);
        carol.setApproval721ForAll(nft721Swap, true);
        dave.setApproval721ForAll(nft721Swap, true);

        alice.setApproval1155ForAll(nft1155, true);
        bob.setApproval1155ForAll(nft1155, true);
        carol.setApproval1155ForAll(nft1155, true);

        alice.setApproval1155ForAll(nft1155Swap, true);
        bob.setApproval1155ForAll(nft1155Swap, true);
        carol.setApproval1155ForAll(nft1155Swap, true);
        dave.setApproval1155ForAll(nft1155Swap, true);

        // Seed ERC-20 balances and approvals for ERC-20 listings/purchases
        erc20.mint(address(alice), 1_000_000e18);
        erc20.mint(address(bob), 1_000_000e18);
        erc20.mint(address(carol), 1_000_000e18);
        erc20.mint(address(dave), 1_000_000e18);
        alice.approveERC20(erc20, type(uint256).max);
        bob.approveERC20(erc20, type(uint256).max);
        carol.approveERC20(erc20, type(uint256).max);
        dave.approveERC20(erc20, type(uint256).max);
    }

    function do_fund() external payable {}

    function do_fund_agents(uint256 amountWei) external {
        uint256 amt = amountWei % 1 ether;
        if (address(this).balance < amt * 4) return;
        (bool s1,) = payable(address(alice)).call{value: amt}("");
        (bool s2,) = payable(address(bob)).call{value: amt}("");
        (bool s3,) = payable(address(carol)).call{value: amt}("");
        (bool s4,) = payable(address(dave)).call{value: amt}("");
        s1;
        s2;
        s3;
        s4;
    }

    function do_list_erc721(uint256 who, bool royaltyToken, uint256 tokenIdHint, uint256 price, bool whitelist)
        external
    {
        Agent ag = _pickAgent(who);
        address token = royaltyToken ? address(nft721Royalty) : address(nft721);
        uint256 tokenId = _owned721(ag, token, tokenIdHint);
        // ETH purchases require exact `msg.value == purchasePrice`.
        // Keep prices in a small range so Echidna can realistically hit them.
        uint256 p = (price % 1e12) + 1;

        uint128 nextId = GetterFacet(address(diamond)).getNextListingId();
        address[] memory allowed = whitelist ? _oneAddress(address(_pickDifferentBuyer(ag))) : new address[](0);
        bool paused = GetterFacet(address(diamond)).isPaused();
        bool wlOk = GetterFacet(address(diamond)).isCollectionWhitelisted(token);
        bool ok;
        try ag.listERC721(token, tokenId, p, address(0), address(0), 0, 0, whitelist, false, allowed) {
            _recordListing(nextId);
            ok = true;
        } catch {}

        if (ok && paused) pauseBypass = true;
        if (ok && !wlOk) collectionCreateBypass = true;
    }

    function do_list_erc721_erc20(uint256 who, bool royaltyToken, uint256 tokenIdHint, uint256 price, bool whitelist)
        external
    {
        Agent ag = _pickAgent(who);
        address token = royaltyToken ? address(nft721Royalty) : address(nft721);
        uint256 tokenId = _owned721(ag, token, tokenIdHint);
        uint256 p = (price % 1e18) + 1;

        uint128 nextId = GetterFacet(address(diamond)).getNextListingId();
        address[] memory allowed = whitelist ? _oneAddress(address(_pickDifferentBuyer(ag))) : new address[](0);
        bool paused = GetterFacet(address(diamond)).isPaused();
        bool wlOk = GetterFacet(address(diamond)).isCollectionWhitelisted(token);
        bool curOk = GetterFacet(address(diamond)).isCurrencyAllowed(address(erc20));
        bool ok;
        try ag.listERC721(token, tokenId, p, address(erc20), address(0), 0, 0, whitelist, false, allowed) {
            _recordListing(nextId);
            ok = true;
        } catch {}

        if (ok && paused) pauseBypass = true;
        if (ok && !wlOk) collectionCreateBypass = true;
        if (ok && wlOk && !paused && !curOk) currencyBypass = true;
    }

    function do_list_swap_erc721(uint256 who, bool royaltyToken, uint256 tokenIdHint, uint256 desiredBuyer) external {
        Agent seller = _pickAgent(who);
        address token = royaltyToken ? address(nft721Royalty) : address(nft721);
        uint256 tokenId = _owned721(seller, token, tokenIdHint);

        // Swap listings may have price 0.
        uint256 p = 0;
        Agent desired = _pickDifferentBuyer(_pickAgent(desiredBuyer));
        uint256 desiredTokenId = _ownedSwap721(desired);

        uint128 nextId = GetterFacet(address(diamond)).getNextListingId();
        bool paused = GetterFacet(address(diamond)).isPaused();
        bool wlOk = GetterFacet(address(diamond)).isCollectionWhitelisted(token);
        bool ok;
        try seller.listERC721(
            token, tokenId, p, address(0), address(nft721Swap), desiredTokenId, 0, false, false, new address[](0)
        ) {
            _recordListing(nextId);
            ok = true;
        } catch {}

        if (ok && paused) pauseBypass = true;
        if (ok && !wlOk) collectionCreateBypass = true;
    }

    function do_list_swap_desired_erc1155(uint256 who, bool royaltyToken, uint256 tokenIdHint, uint256 desiredQty)
        external
    {
        Agent seller = _pickAgent(who);
        address token = royaltyToken ? address(nft721Royalty) : address(nft721);
        uint256 tokenId = _owned721(seller, token, tokenIdHint);

        // ERC-1155 desired swap: allow price 0, but require desired quantity > 0.
        uint256 p = 0;
        uint256 q = (desiredQty % 10) + 1;

        uint128 nextId = GetterFacet(address(diamond)).getNextListingId();
        bool paused = GetterFacet(address(diamond)).isPaused();
        bool wlOk = GetterFacet(address(diamond)).isCollectionWhitelisted(token);
        bool ok;
        try seller.listERC721(token, tokenId, p, address(0), address(nft1155Swap), 2, q, false, false, new address[](0))
        {
            _recordListing(nextId);
            ok = true;
        } catch {}

        if (ok && paused) pauseBypass = true;
        if (ok && !wlOk) collectionCreateBypass = true;
    }

    function do_list_erc1155(uint256 who, uint256 qty, uint256 price, bool whitelist, bool partialBuy) external {
        Agent ag = _pickAgent(who);
        uint256 have = IERC1155(address(nft1155)).balanceOf(address(ag), 1);
        if (have == 0) return;

        uint256 q = qty % (have + 1);
        if (q == 0) q = 1;

        // Keep unit prices small and ensure total price is divisible by quantity.
        uint256 unitPrice = (price % 1e12) + 1;
        uint256 p = unitPrice * q;

        uint128 nextId = GetterFacet(address(diamond)).getNextListingId();
        address[] memory allowed = whitelist ? _oneAddress(address(_pickDifferentBuyer(ag))) : new address[](0);
        bool paused = GetterFacet(address(diamond)).isPaused();
        bool wlOk = GetterFacet(address(diamond)).isCollectionWhitelisted(address(nft1155));
        bool ok;
        try ag.listERC1155(address(nft1155), 1, address(ag), p, address(0), q, whitelist, partialBuy, allowed) {
            _recordListing(nextId);
            ok = true;
        } catch {}

        if (ok && paused) pauseBypass = true;
        if (ok && !wlOk) collectionCreateBypass = true;
    }

    function do_update_listing(
        uint128 listingId,
        uint256 price,
        bool useErc20,
        bool setSwap,
        bool whitelist,
        bool partialBuy,
        uint256 qtyHint
    ) external {
        bool paused = GetterFacet(address(diamond)).isPaused();

        try GetterFacet(address(diamond)).getListingByListingId(listingId) returns (Listing memory L) {
            if (L.seller == address(0)) return;

            bool wlOkBefore = GetterFacet(address(diamond)).isCollectionWhitelisted(L.tokenAddress);

            Agent seller = _agentByAddress(L.seller);
            if (address(seller) == address(0)) return;

            address newCurrency = useErc20 ? address(erc20) : address(0);
            bool curAllowed = GetterFacet(address(diamond)).isCurrencyAllowed(newCurrency);

            uint256 newErc1155Quantity = 0;
            bool newPartialBuyEnabled = false;

            if (L.erc1155Quantity > 0) {
                uint256 have = IERC1155(L.tokenAddress).balanceOf(L.seller, L.tokenId);
                if (have == 0) return;
                uint256 q = qtyHint % (have + 1);
                if (q == 0) q = 1;
                newErc1155Quantity = q;

                // Partial buys only allowed if not swap and qty > 1.
                if (partialBuy && !setSwap && q > 1) {
                    newPartialBuyEnabled = true;
                }
            }

            address newDesiredTokenAddress = setSwap ? address(nft721Swap) : address(0);
            uint256 newDesiredTokenId = setSwap ? _ownedSwap721(_pickDifferentBuyer(seller)) : 0;

            uint256 newPrice;
            if (newPartialBuyEnabled) {
                uint256 unitPrice = (price % 1e12) + 1;
                newPrice = unitPrice * newErc1155Quantity;
            } else {
                // Keep prices small for exact-payment reachability. Swap listings may have price 0.
                if (setSwap) {
                    newPrice = price % 2;
                } else {
                    newPrice = (price % 1e12) + 1;
                }
            }

            address[] memory allowed = whitelist ? _oneAddress(address(_pickDifferentBuyer(seller))) : new address[](0);

            bool ok;
            try seller.update(
                listingId,
                newPrice,
                newCurrency,
                newDesiredTokenAddress,
                newDesiredTokenId,
                0,
                newErc1155Quantity,
                whitelist,
                newPartialBuyEnabled,
                allowed
            ) {
                ok = true;
            } catch {}

            if (ok && paused) pauseBypass = true;

            // If the collection was de-whitelisted, updateListing should auto-cancel.
            if (ok && !paused && !wlOkBefore) {
                try GetterFacet(address(diamond)).getListingByListingId(listingId) returns (Listing memory afterL) {
                    if (afterL.seller != address(0)) collectionUpdateBypass = true;
                } catch {
                    // If getter reverts here, treat as not bypassed (listing likely deleted)
                }
            }

            if (ok && !paused && wlOkBefore && !curAllowed) currencyBypass = true;
        } catch {}
    }

    function do_purchase(uint256 buyerIdx, uint128 listingId, uint256 erc1155Qty) external payable {
        Agent buyer = _pickAgent(buyerIdx);
        try GetterFacet(address(diamond)).getListingByListingId(listingId) returns (Listing memory L) {
            if (L.desiredTokenAddress != address(0)) return;
            if (L.currency != address(0)) return;
            if (address(buyer) == L.seller) return;

            uint256 purchaseQty = 0;
            uint256 purchasePrice = L.price;

            if (L.erc1155Quantity > 0) {
                uint256 q = erc1155Qty;
                if (q == 0) q = 1;
                q = q % (L.erc1155Quantity + 1);
                if (q == 0) q = 1;
                if (q > L.erc1155Quantity) return;
                purchaseQty = q;
                if (q != L.erc1155Quantity) {
                    uint256 unitPrice = L.price / L.erc1155Quantity;
                    purchasePrice = unitPrice * q;
                }
            }

            if (address(this).balance < purchasePrice) return;

            bool paused = GetterFacet(address(diamond)).isPaused();
            bool wlOk = GetterFacet(address(diamond)).isCollectionWhitelisted(L.tokenAddress);

            bool ok;
            try buyer.purchase{value: purchasePrice}(
                listingId,
                L.price,
                L.currency,
                L.erc1155Quantity,
                L.desiredTokenAddress,
                L.desiredTokenId,
                L.desiredErc1155Quantity,
                purchaseQty,
                address(0)
            ) {
                ok = true;
            } catch {}

            if (ok && paused) pauseBypass = true;
            if (ok && !paused && !wlOk) collectionPurchaseBypass = true;
        } catch {}
    }

    function do_purchase_erc20(uint256 buyerIdx, uint128 listingId, uint256 erc1155Qty) external payable {
        Agent buyer = _pickAgent(buyerIdx);
        try GetterFacet(address(diamond)).getListingByListingId(listingId) returns (Listing memory L) {
            if (L.desiredTokenAddress != address(0)) return;
            if (L.currency != address(erc20)) return;
            if (address(buyer) == L.seller) return;

            uint256 purchaseQty = 0;
            uint256 purchasePrice = L.price;

            if (L.erc1155Quantity > 0) {
                uint256 q = erc1155Qty;
                if (q == 0) q = 1;
                q = q % (L.erc1155Quantity + 1);
                if (q == 0) q = 1;
                if (q > L.erc1155Quantity) return;
                purchaseQty = q;
                if (q != L.erc1155Quantity) {
                    uint256 unitPrice = L.price / L.erc1155Quantity;
                    purchasePrice = unitPrice * q;
                }
            }

            if (erc20.balanceOf(address(buyer)) < purchasePrice) return;

            bool paused = GetterFacet(address(diamond)).isPaused();
            bool wlOk = GetterFacet(address(diamond)).isCollectionWhitelisted(L.tokenAddress);

            bool ok;
            try buyer.purchase(
                listingId,
                L.price,
                L.currency,
                L.erc1155Quantity,
                L.desiredTokenAddress,
                L.desiredTokenId,
                L.desiredErc1155Quantity,
                purchaseQty,
                address(0)
            ) {
                ok = true;
            } catch {}

            if (ok && paused) pauseBypass = true;
            if (ok && !paused && !wlOk) collectionPurchaseBypass = true;
        } catch {}
    }

    function do_purchase_swap(uint128 listingId) external payable {
        try GetterFacet(address(diamond)).getListingByListingId(listingId) returns (Listing memory L) {
            if (L.desiredTokenAddress != address(nft721Swap)) return;
            if (L.desiredErc1155Quantity != 0) return;

            address desiredOwner = IERC721(address(nft721Swap)).ownerOf(L.desiredTokenId);
            Agent buyer = _agentByAddress(desiredOwner);
            if (address(buyer) == address(0)) return;
            if (address(buyer) == L.seller) return;

            bool paused = GetterFacet(address(diamond)).isPaused();
            bool wlOk = GetterFacet(address(diamond)).isCollectionWhitelisted(L.tokenAddress);

            bool ok;
            try buyer.purchase{value: (L.currency == address(0) ? L.price : 0)}(
                listingId,
                L.price,
                L.currency,
                L.erc1155Quantity,
                L.desiredTokenAddress,
                L.desiredTokenId,
                L.desiredErc1155Quantity,
                0,
                address(0)
            ) {
                ok = true;
            } catch {}

            if (ok && paused) pauseBypass = true;
            if (ok && !paused && !wlOk) collectionPurchaseBypass = true;
        } catch {}
    }

    function do_purchase_swap_erc1155(uint128 listingId, uint256 holderIdx) external payable {
        try GetterFacet(address(diamond)).getListingByListingId(listingId) returns (Listing memory L) {
            if (L.desiredTokenAddress != address(nft1155Swap)) return;
            if (L.desiredErc1155Quantity == 0) return;

            Agent desiredHolder = _pickAgent(holderIdx);
            if (address(desiredHolder) == L.seller) desiredHolder = _pickDifferentBuyer(_agentByAddress(L.seller));
            if (address(desiredHolder) == address(0)) return;

            // Ensure the holder actually has the required desired balance.
            uint256 bal = IERC1155(address(nft1155Swap)).balanceOf(address(desiredHolder), L.desiredTokenId);
            if (bal < L.desiredErc1155Quantity) return;

            bool paused = GetterFacet(address(diamond)).isPaused();
            bool wlOk = GetterFacet(address(diamond)).isCollectionWhitelisted(L.tokenAddress);

            bool ok;
            try desiredHolder.purchase{value: (L.currency == address(0) ? L.price : 0)}(
                listingId,
                L.price,
                L.currency,
                L.erc1155Quantity,
                L.desiredTokenAddress,
                L.desiredTokenId,
                L.desiredErc1155Quantity,
                0,
                address(desiredHolder)
            ) {
                ok = true;
            } catch {}

            if (ok && paused) pauseBypass = true;
            if (ok && !paused && !wlOk) collectionPurchaseBypass = true;
        } catch {}
    }

    function do_purchase_without_whitelist(uint256 buyerIdx, uint128 listingId, uint256 erc1155Qty) external payable {
        Agent buyer = _pickAgent(buyerIdx);
        try GetterFacet(address(diamond)).getListingByListingId(listingId) returns (Listing memory L) {
            if (!L.buyerWhitelistEnabled) return;
            if (L.desiredTokenAddress != address(0)) return;
            if (L.currency != address(0)) return;
            if (address(buyer) == L.seller) return;

            // Only flag bypass if buyer is actually NOT whitelisted.
            try GetterFacet(address(diamond)).isBuyerWhitelisted(listingId, address(buyer)) returns (bool isWL) {
                if (isWL) return;
            } catch {
                return;
            }

            uint256 purchaseQty = 0;
            uint256 purchasePrice = L.price;

            if (L.erc1155Quantity > 0) {
                uint256 q = erc1155Qty;
                if (q == 0) q = 1;
                q = q % (L.erc1155Quantity + 1);
                if (q == 0) q = 1;
                if (q > L.erc1155Quantity) return;
                purchaseQty = q;
                if (q != L.erc1155Quantity) {
                    uint256 unitPrice = L.price / L.erc1155Quantity;
                    purchasePrice = unitPrice * q;
                }
            }

            if (address(this).balance < purchasePrice) return;

            bool ok;
            try buyer.purchase{value: purchasePrice}(
                listingId,
                L.price,
                L.currency,
                L.erc1155Quantity,
                L.desiredTokenAddress,
                L.desiredTokenId,
                L.desiredErc1155Quantity,
                purchaseQty,
                address(0)
            ) {
                ok = true;
            } catch {}

            if (ok) whitelistBypass = true;
        } catch {}
    }

    function do_owner_pause() external {
        try ownerAgent.pause() {} catch {}
    }

    function do_owner_unpause() external {
        try ownerAgent.unpause() {} catch {}
    }

    function do_owner_remove_collection(uint256 which) external {
        address token = _pickCollection(which);
        try ownerAgent.removeWhitelistedCollection(token) {} catch {}
    }

    function do_owner_add_collection(uint256 which) external {
        address token = _pickCollection(which);
        try ownerAgent.addWhitelistedCollection(token) {} catch {}
    }

    function do_owner_remove_erc20_currency() external {
        try ownerAgent.removeAllowedCurrency(address(erc20)) {} catch {}
    }

    function do_owner_add_erc20_currency() external {
        try ownerAgent.addAllowedCurrency(address(erc20)) {} catch {}
    }

    function do_two_buyers_contend(uint128 listingId) external payable {
        try GetterFacet(address(diamond)).getListingByListingId(listingId) returns (Listing memory L) {
            if (L.desiredTokenAddress != address(0)) return;
            if (L.currency != address(0)) return;
            if (L.erc1155Quantity > 0 && L.partialBuyEnabled) return;

            Agent b1 = _pickBuyerNotSeller(L.seller, alice, bob);
            Agent b2 = _pickBuyerNotSeller(L.seller, carol, dave);
            if (address(b1) == address(b2)) return;

            uint256 q = (L.erc1155Quantity > 0) ? L.erc1155Quantity : 0;
            uint256 price = L.price;
            if (address(this).balance < price * 2) return;

            bool s1;
            bool s2;

            try b1.purchase{value: price}(
                listingId,
                L.price,
                L.currency,
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
                L.currency,
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

    function do_try_set_fee_unauth(uint32 newFee) external {
        uint32 beforeFee = GetterFacet(address(diamond)).getInnovationFee();
        try IdeationMarketFacet(address(diamond)).setInnovationFee(newFee) {
            uint32 afterFee = GetterFacet(address(diamond)).getInnovationFee();
            if (afterFee != beforeFee) unauthFeeChange = true;
        } catch {}
    }

    function do_set_royalty(uint96 bps) external {
        nft721Royalty.setRoyalty(address(this), bps);
    }

    receive() external payable {}

    function echidna_loupe_and_erc165_wired() external view returns (bool) {
        address[] memory facs = IDiamondLoupeFacet(address(diamond)).facetAddresses();
        bool okCount = facs.length == 10;
        bool ok165 = IERC165(address(diamond)).supportsInterface(type(IERC165).interfaceId);
        bool okLoupe = IERC165(address(diamond)).supportsInterface(type(IDiamondLoupeFacet).interfaceId);
        bool okInspect = IERC165(address(diamond)).supportsInterface(type(IDiamondInspectFacet).interfaceId);
        bool okUpgrade = IERC165(address(diamond)).supportsInterface(type(IDiamondUpgradeFacet).interfaceId);
        bool okOwn = IERC165(address(diamond)).supportsInterface(type(IERC173).interfaceId);
        return okCount && ok165 && okLoupe && okInspect && okUpgrade && okOwn;
    }

    function echidna_no_reentrancy() external view returns (bool) {
        return !(alice.reentryOk() || bob.reentryOk() || carol.reentryOk() || dave.reentryOk());
    }

    function echidna_collections_still_whitelisted() external pure returns (bool) {
        // Collections may be de-whitelisted by admin actions; enforcement is checked separately.
        return true;
    }

    function echidna_pause_enforced() external view returns (bool) {
        return !pauseBypass;
    }

    function echidna_currency_allowlist_enforced() external view returns (bool) {
        return !currencyBypass;
    }

    function echidna_collection_whitelist_enforced() external view returns (bool) {
        return !(collectionPurchaseBypass || collectionUpdateBypass || collectionCreateBypass);
    }

    function echidna_getBalance_matches_native() external view returns (bool) {
        return GetterFacet(address(diamond)).getBalance() == address(diamond).balance;
    }

    function echidna_fee_royalty_bounds() external view returns (bool) {
        uint256[4] memory ids721 = [uint256(11), 12, 13, 14];
        for (uint256 i = 0; i < ids721.length; i++) {
            if (!_feeRoyaltyOkActive(address(nft721), ids721[i])) return false;
        }
        uint256[2] memory idsRoy = [uint256(21), 22];
        for (uint256 i = 0; i < idsRoy.length; i++) {
            if (!_feeRoyaltyOkActive(address(nft721Royalty), idsRoy[i])) return false;
        }
        return true;
    }

    function echidna_erc721_active_mapping_consistent() external view returns (bool) {
        uint256[4] memory ids721 = [uint256(11), 12, 13, 14];
        for (uint256 i = 0; i < ids721.length; i++) {
            if (!_activeMappingOk(address(nft721), ids721[i])) return false;
        }
        uint256[2] memory idsRoy = [uint256(21), 22];
        for (uint256 i = 0; i < idsRoy.length; i++) {
            if (!_activeMappingOk(address(nft721Royalty), idsRoy[i])) return false;
        }
        return true;
    }

    function echidna_fee_in_range() external view returns (bool) {
        uint32 fee = GetterFacet(address(diamond)).getInnovationFee();
        return fee <= FEE_DENOM;
    }

    function echidna_partial_price_divisible() external view returns (bool) {
        for (uint256 i = 0; i < recentListingIds.length; i++) {
            uint128 id = recentListingIds[i];
            if (id == 0) continue;
            try GetterFacet(address(diamond)).getListingByListingId(id) returns (Listing memory L) {
                if (L.erc1155Quantity > 0 && L.partialBuyEnabled) {
                    if (L.price % L.erc1155Quantity != 0) return false;
                }
            } catch {}
        }
        return true;
    }

    function echidna_whitelist_enforced() external view returns (bool) {
        return !whitelistBypass;
    }

    function echidna_only_owner_can_change_fee() external view returns (bool) {
        return !unauthFeeChange;
    }

    function echidna_no_double_sells() external view returns (bool) {
        return !doubleSell;
    }

    function _recordListing(uint128 listingId) internal {
        recentListingIds[recentListingCursor % recentListingIds.length] = listingId;
        unchecked {
            recentListingCursor++;
        }
    }

    function _pickAgent(uint256 who) internal view returns (Agent) {
        uint256 w = who % 4;
        if (w == 0) return alice;
        if (w == 1) return bob;
        if (w == 2) return carol;
        return dave;
    }

    function _pickDifferentBuyer(Agent seller) internal view returns (Agent) {
        if (address(seller) != address(alice)) return alice;
        return bob;
    }

    function _agentByAddress(address a) internal view returns (Agent) {
        if (a == address(alice)) return alice;
        if (a == address(bob)) return bob;
        if (a == address(carol)) return carol;
        if (a == address(dave)) return dave;
        if (a == address(ownerAgent)) return ownerAgent;
        return Agent(payable(address(0)));
    }

    function _ownedSwap721(Agent ag) internal view returns (uint256) {
        if (address(ag) == address(alice)) return 31;
        if (address(ag) == address(bob)) return 32;
        if (address(ag) == address(carol)) return 33;
        return 34;
    }

    function _pickCollection(uint256 which) internal view returns (address) {
        uint256 w = which % 4;
        if (w == 0) return address(nft721);
        if (w == 1) return address(nft721Royalty);
        if (w == 2) return address(nft1155);
        return address(nft721Swap);
    }

    function _pickBuyerNotSeller(address seller, Agent a, Agent b) internal pure returns (Agent) {
        if (address(a) != seller) return a;
        return b;
    }

    function _oneAddress(address a) internal pure returns (address[] memory allowed) {
        allowed = new address[](1);
        allowed[0] = a;
    }

    function _owned721(Agent ag, address token, uint256 hint) internal view returns (uint256) {
        if (token == address(nft721Royalty)) {
            if (address(ag) == address(alice)) return 21;
            if (address(ag) == address(bob)) return 22;
            return 21;
        }
        uint256 idx = hint % 4;
        if (idx == 0) return 11;
        if (idx == 1) return 12;
        if (idx == 2) return 13;
        return 14;
    }

    function _activeMappingOk(address token, uint256 tokenId) internal view returns (bool) {
        uint128 listingId = GetterFacet(address(diamond)).getActiveListingIdByERC721(token, tokenId);
        if (listingId == 0) return true;
        try GetterFacet(address(diamond)).getListingByListingId(listingId) returns (Listing memory L) {
            if (L.erc1155Quantity != 0) return false;
            if (L.tokenAddress != token) return false;
            if (L.tokenId != tokenId) return false;
            return true;
        } catch {
            return false;
        }
    }

    function _feeRoyaltyOkActive(address token, uint256 tokenId) internal view returns (bool) {
        uint128 listingId = GetterFacet(address(diamond)).getActiveListingIdByERC721(token, tokenId);
        if (listingId == 0) return true;
        try GetterFacet(address(diamond)).getListingByListingId(listingId) returns (Listing memory L) {
            if (L.currency != address(0)) return true;
            if (L.desiredTokenAddress != address(0)) return true;
            uint256 fee = (L.price * uint256(L.feeRate)) / FEE_DENOM;
            uint256 royalty = 0;
            if (IERC165(token).supportsInterface(type(IERC2981).interfaceId)) {
                try IERC2981(token).royaltyInfo(tokenId, L.price) returns (address receiver, uint256 amount) {
                    if (receiver != address(0)) royalty = amount;
                } catch {}
            }
            return fee + royalty <= L.price;
        } catch {
            return true;
        }
    }
}
