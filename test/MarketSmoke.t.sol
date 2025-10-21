// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

// ---- Minimal interfaces (matching your live diamond on Louper) ----
// Louper shows these function names/selectors on your diamond at
// 0x8cE90712463c87a6d62941D67C3507D090Ea9d79. :contentReference[oaicite:1]{index=1}
interface IERC721 {
    function ownerOf(uint256 id) external view returns (address);
    function approve(address to, uint256 id) external;
    function getApproved(uint256 id) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function setApprovalForAll(address operator, bool approved) external;
    function safeTransferFrom(address from, address to, uint256 id) external;
}

interface IGetterFacet {
    function getNextListingId() external view returns (uint128);
    function isCollectionWhitelisted(address collection) external view returns (bool);
    function getListingByListingId(uint128 listingId)
        external
        view
        returns (
            uint128 listingId_,
            uint32 feeRate,
            bool buyerWhitelistEnabled,
            bool partialBuyEnabled,
            address tokenAddress,
            uint256 tokenId,
            uint256 erc1155Quantity,
            uint256 price,
            address seller,
            address desiredTokenAddress,
            uint256 desiredTokenId,
            uint256 desiredErc1155Quantity
        );
}

interface ICollectionWhitelistFacet {
    function addWhitelistedCollection(address tokenAddress) external;
}

interface IBuyerWhitelistFacet {
    function addBuyerWhitelistAddresses(uint128 listingId, address[] calldata buyers) external;
    function removeBuyerWhitelistAddresses(uint128 listingId, address[] calldata buyers) external;
}

interface IIdeationMarketFacet {
    function createListing(
        address tokenAddress,
        uint256 tokenId,
        address erc1155Holder,
        uint256 price,
        address desiredTokenAddress,
        uint256 desiredTokenId,
        uint256 desiredErc1155Quantity,
        uint256 erc1155Quantity,
        bool buyerWhitelistEnabled,
        bool partialBuyEnabled,
        address[] calldata allowedBuyers
    ) external;

    function purchaseListing(
        uint128 listingId,
        uint256 expectedPrice,
        uint256 expectedErc1155Quantity,
        address expectedDesiredTokenAddress,
        uint256 expectedDesiredTokenId,
        uint256 expectedDesiredErc1155Quantity,
        uint256 erc1155PurchaseQuantity,
        address desiredErc1155Holder
    ) external payable;

    function cancelListing(uint128 listingId) external;
}

// Minimal 1155 just for fork tests
contract Mock1155 {
    mapping(address => mapping(uint256 => uint256)) public balanceOf;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    function mint(address to, uint256 id, uint256 amt) external {
        balanceOf[to][id] += amt;
    }

    function setApprovalForAll(address op, bool ok) external {
        isApprovedForAll[msg.sender][op] = ok;
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata /*data*/ )
        external
    {
        require(from == msg.sender || isApprovedForAll[from][msg.sender], "not-approved");
        uint256 bal = balanceOf[from][id];
        require(bal >= amount, "insufficient");
        unchecked {
            balanceOf[from][id] = bal - amount;
        }
        balanceOf[to][id] += amount;
    }

    function supportsInterface(bytes4 iid) external pure returns (bool) {
        return iid == 0x01ffc9a7 || iid == 0xd9b67a26;
    }
}

contract MarketSmoke is Test {
    // ---- Live addresses (from your README + deployment log) ---- :contentReference[oaicite:2]{index=2}
    address constant DIAMOND = 0x8cE90712463c87a6d62941D67C3507D090Ea9d79;
    address constant TOKEN721 = 0x41655AE49482de69eEC8F6875c34A8Ada01965e2;

    // Funded EOAs you provided
    address constant ACCOUNT1 = 0xE8dF60a93b2B328397a8CBf73f0d732aaa11e33D; // owns tokenId 16
    address constant ACCOUNT2 = 0x8a200122f666af83aF2D4f425aC7A35fa5491ca7; // owns tokenId 534

    // Tokens you provided
    uint256 constant TOKEN1 = 16; // ERC-721 owned by ACCOUNT1
    uint256 constant TOKEN2 = 534; // ERC-721 owned by ACCOUNT2

    // Prices (wei). For 1155, treat PRICE1155 as unit price.
    uint256 constant PRICE1 = 200_000_000_000_000; // 0.0002 ETH
    uint256 constant PRICE2 = 300_000_000_000_000; // 0.0003 ETH
    uint256 constant PRICE1155 = 50_000_000_000_000; // 0.00005 ETH

    // 1155 params for partial
    uint256 constant ID1155 = 555;
    uint256 constant QTY1155 = 10;
    uint256 constant PARTIAL1 = 3;
    uint256 constant PARTIAL2 = 7;

    IGetterFacet getter = IGetterFacet(DIAMOND);
    IIdeationMarketFacet market = IIdeationMarketFacet(DIAMOND);
    ICollectionWhitelistFacet cwl = ICollectionWhitelistFacet(DIAMOND);
    IERC721 erc721 = IERC721(TOKEN721);

    function setUp() public {
        // Run on a Sepolia *fork* tied to live state:
        // forge test --fork-url $SEPOLIA_RPC_URL -vvv --match-contract MarketSmoke
        string memory url = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(url);

        // fund local fork accounts for gas
        vm.deal(ACCOUNT1, 10 ether);
        vm.deal(ACCOUNT2, 10 ether);

        // sanity: the two ERC-721s are where you said they are on Sepolia
        assertEq(erc721.ownerOf(TOKEN1), ACCOUNT1, "token 16 not at ACCOUNT1");
        assertEq(erc721.ownerOf(TOKEN2), ACCOUNT2, "token 534 not at ACCOUNT2");

        // whitelist the 721 collection if not yet
        if (!getter.isCollectionWhitelisted(TOKEN721)) {
            vm.startPrank(ACCOUNT1); // diamond owner (per README deploy log) :contentReference[oaicite:3]{index=3}
            cwl.addWhitelistedCollection(TOKEN721);
            vm.stopPrank();
        }
    }

    // 721 list -> buy -> cleanup (A1 sells to A2; then A2 transfers back)
    function test_A_ERC721_ListBuyCleanup() public {
        _approve721IfNeeded(ACCOUNT1, TOKEN1);

        uint128 id = getter.getNextListingId();

        vm.startPrank(ACCOUNT1);
        {
            market.createListing(
                TOKEN721,
                TOKEN1,
                address(0), // erc1155Holder not used for 721
                PRICE1,
                address(0),
                0,
                0,
                0, // erc1155Quantity == 0 => 721 listing
                false, // whitelist OFF
                false, // partial OFF
                new address[](0)
            );
        }
        vm.stopPrank();

        vm.prank(ACCOUNT2);
        market.purchaseListing{value: PRICE1}(id, PRICE1, 0, address(0), 0, 0, 0, address(0));

        assertEq(erc721.ownerOf(TOKEN1), ACCOUNT2, "buyer did not receive 721");

        // cleanup: transfer back so test is re-runnable even on live if mirrored
        vm.startPrank(ACCOUNT2);
        erc721.safeTransferFrom(ACCOUNT2, ACCOUNT1, TOKEN1);
        vm.stopPrank();

        assertEq(erc721.ownerOf(TOKEN1), ACCOUNT1, "cleanup transfer back failed");
    }

    // 721 list -> cancel (A2)
    function test_B_ERC721_ListCancel() public {
        _approve721IfNeeded(ACCOUNT2, TOKEN2);

        uint128 id = getter.getNextListingId();

        vm.startPrank(ACCOUNT2);
        {
            market.createListing(
                TOKEN721, TOKEN2, address(0), PRICE2, address(0), 0, 0, 0, false, false, new address[](0)
            );
        }
        vm.stopPrank();

        vm.prank(ACCOUNT2);
        market.cancelListing(id);

        assertEq(erc721.ownerOf(TOKEN2), ACCOUNT2, "cancel did not restore owner");
    }

    // 721 whitelist: positive (ACCOUNT2 allowed)
    function test_C_ERC721_Whitelist_Positive() public {
        _approve721IfNeeded(ACCOUNT1, TOKEN1);

        uint128 id = getter.getNextListingId();

        vm.startPrank(ACCOUNT1);
        {
            address[] memory allowed = new address[](1);
            allowed[0] = ACCOUNT2;
            market.createListing(
                TOKEN721,
                TOKEN1,
                address(0),
                PRICE1,
                address(0),
                0,
                0,
                0,
                true, // whitelist ON
                false,
                allowed
            );
        }
        vm.stopPrank();

        vm.prank(ACCOUNT2);
        market.purchaseListing{value: PRICE1}(id, PRICE1, 0, address(0), 0, 0, 0, address(0));

        // cleanup
        vm.startPrank(ACCOUNT2);
        erc721.safeTransferFrom(ACCOUNT2, ACCOUNT1, TOKEN1);
        vm.stopPrank();

        assertEq(erc721.ownerOf(TOKEN1), ACCOUNT1, "whitelist+cleanup failed");
    }

    // 721 whitelist: negative (ACCOUNT2 NOT allowed) → expect revert → seller cancels
    function test_D_ERC721_Whitelist_Negative() public {
        _approve721IfNeeded(ACCOUNT1, TOKEN1);

        uint128 id = getter.getNextListingId();

        vm.startPrank(ACCOUNT1);
        {
            address[] memory allowed = new address[](1);
            allowed[0] = ACCOUNT1; // deliberately exclude ACCOUNT2
            market.createListing(
                TOKEN721,
                TOKEN1,
                address(0),
                PRICE1,
                address(0),
                0,
                0,
                0,
                true, // whitelist ON
                false,
                allowed
            );
        }
        vm.stopPrank();

        vm.prank(ACCOUNT2);
        vm.expectRevert(); // generic (custom error selector unknown here)
        market.purchaseListing{value: PRICE1}(id, PRICE1, 0, address(0), 0, 0, 0, address(0));

        // cleanup
        vm.prank(ACCOUNT1);
        market.cancelListing(id);

        assertEq(erc721.ownerOf(TOKEN1), ACCOUNT1, "owner changed unexpectedly");
    }

    // 1155 partial: create (seller A1) → buy 3 + buy 7 (A2) → cleanup: return all
    function test_E_ERC1155_PartialAndFill() public {
        // deploy a local mock 1155 and whitelist it
        Mock1155 token1155 = new Mock1155();

        vm.startPrank(ACCOUNT1);
        cwl.addWhitelistedCollection(address(token1155));
        vm.stopPrank();

        // mint to seller and approve marketplace
        vm.startPrank(ACCOUNT1);
        token1155.mint(ACCOUNT1, ID1155, QTY1155);
        token1155.setApprovalForAll(DIAMOND, true);
        vm.stopPrank();

        // create listing with partial ON
        uint128 id = getter.getNextListingId();

        vm.startPrank(ACCOUNT1);
        {
            market.createListing(
                address(token1155),
                ID1155,
                ACCOUNT1, // erc1155Holder
                PRICE1155 * QTY1155, // Total Listing price at creation
                address(0),
                0,
                0,
                QTY1155, // > 0 => 1155
                false, // whitelist OFF
                true, // partial ON
                new address[](0)
            );
        }
        vm.stopPrank();

        // Buyer takes partials 3 then 7 (total 10)
        vm.prank(ACCOUNT2);
        market.purchaseListing{value: PRICE1155 * PARTIAL1}(
            id, PRICE1155 * QTY1155, QTY1155, address(0), 0, 0, PARTIAL1, ACCOUNT2
        );

        // Buyer partial #2 (use UPDATED remaining terms)
        uint256 remainingQty = QTY1155 - PARTIAL1;
        uint256 remainingTotal = (PRICE1155 * QTY1155) - (PRICE1155 * PARTIAL1);

        vm.prank(ACCOUNT2);
        market.purchaseListing{value: PRICE1155 * PARTIAL2}(
            id, remainingTotal, remainingQty, address(0), 0, 0, PARTIAL2, ACCOUNT2
        );

        // assertion + cleanup (return to seller)
        assertEq(token1155.balanceOf(ACCOUNT2, ID1155), QTY1155, "buyer 1155 qty mismatch");

        vm.startPrank(ACCOUNT2);
        token1155.safeTransferFrom(ACCOUNT2, ACCOUNT1, ID1155, QTY1155, "");
        vm.stopPrank();

        assertEq(token1155.balanceOf(ACCOUNT1, ID1155), QTY1155, "cleanup return failed");
    }

    // --- helpers ---
    function _approve721IfNeeded(address owner, uint256 tokenId) internal {
        vm.startPrank(owner);
        if (erc721.getApproved(tokenId) != DIAMOND && !erc721.isApprovedForAll(owner, DIAMOND)) {
            erc721.approve(DIAMOND, tokenId);
        }
        vm.stopPrank();
    }
}
