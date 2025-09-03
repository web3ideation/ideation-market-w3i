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

abstract contract MarketTestBase is Test {
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

    // Raw facet implementation addresses (useful for diamondCut edge tests)
    address internal loupeImpl;
    address internal ownershipImpl;
    address internal marketImpl;
    address internal collectionsImpl;
    address internal buyersImpl;
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

        // cache impl addrs
        loupeImpl = address(loupeFacet);
        ownershipImpl = address(ownershipFacet);
        marketImpl = address(marketFacet);
        collectionsImpl = address(collectionFacet);
        buyersImpl = address(buyerFacet);
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
            try market.purchaseListing{value: price}(listingId, price, 0, address(0), 0, 0, 0, address(0)) {
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
            try market.purchaseListing{value: price}(listingId, price, qty, address(0), 0, 0, qty, address(0)) {
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
