// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";

// ---- Interfaces (same as tests) ----
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

// Minimal 1155 used for the live partial-fill flow
contract Mock1155 {
    mapping(address => mapping(uint256 => uint256)) public balanceOf;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    function mint(address to, uint256 id, uint256 amt) external {
        balanceOf[to][id] += amt;
    }

    function setApprovalForAll(address op, bool ok) external {
        isApprovedForAll[msg.sender][op] = ok;
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata) external {
        require(from == msg.sender || isApprovedForAll[from][msg.sender], "not-approved");
        uint256 bal = balanceOf[from][id];
        require(bal >= amount, "insufficient");
        unchecked {
            balanceOf[from][id] = bal - amount;
        }
        balanceOf[to][id] += amount;
    }

    function supportsInterface(bytes4 iid) external pure returns (bool) {
        return iid == 0x01ffc9a7 || iid == 0xd9b67a26; // ERC165 + ERC1155
    }
}

contract MarketSmokeBroadcastFull is Script {
    // Live diamond + 721 collection
    address constant DIAMOND = 0x8cE90712463c87a6d62941D67C3507D090Ea9d79;
    address constant TOKEN721 = 0x41655AE49482de69eEC8F6875c34A8Ada01965e2;

    // EOAs (you control these)
    address constant ACCOUNT1 = 0xE8dF60a93b2B328397a8CBf73f0d732aaa11e33D; // holds tokenId 16
    address constant ACCOUNT2 = 0x8a200122f666af83aF2D4f425aC7A35fa5491ca7; // holds tokenId 534

    // 721 token ids
    uint256 constant TOKEN1 = 16;
    uint256 constant TOKEN2 = 534;

    // Prices (wei)
    uint256 constant PRICE1 = 200_000_000_000_000; // 0.0002
    uint256 constant PRICE2 = 300_000_000_000_000; // 0.0003
    uint256 constant PRICE1155 = 50_000_000_000_000; // 0.00005 (unit)

    // 1155 params
    uint256 constant ID1155 = 555;
    uint256 constant QTY1155 = 10;
    uint256 constant PARTIAL1 = 3;
    uint256 constant PARTIAL2 = 7;

    // Facets
    IGetterFacet getter = IGetterFacet(DIAMOND);
    IIdeationMarketFacet market = IIdeationMarketFacet(DIAMOND);
    ICollectionWhitelistFacet cwl = ICollectionWhitelistFacet(DIAMOND);
    IERC721 erc721 = IERC721(TOKEN721);

    function run() external {
        uint256 pk1 = vm.envUint("PRIVATE_KEY_1");
        uint256 pk2 = vm.envUint("PRIVATE_KEY_2");
        require(vm.addr(pk1) == ACCOUNT1, "PRIVATE_KEY_1 !ACCOUNT1");
        require(vm.addr(pk2) == ACCOUNT2, "PRIVATE_KEY_2 !ACCOUNT2");

        // Whitelist the 721 collection if needed (owner is ACCOUNT1)
        if (!getter.isCollectionWhitelisted(TOKEN721)) {
            vm.startBroadcast(pk1);
            cwl.addWhitelistedCollection(TOKEN721);
            vm.stopBroadcast();
        }

        // === A) 721 list -> buy -> cleanup ===
        if (erc721.ownerOf(TOKEN1) == ACCOUNT1) {
            _approve721IfNeeded(pk1, ACCOUNT1, TOKEN1);
            uint128 idA = getter.getNextListingId();

            vm.startBroadcast(pk1);
            {
                market.createListing(
                    TOKEN721, TOKEN1, address(0), PRICE1, address(0), 0, 0, 0, false, false, new address[](0)
                );
            }
            vm.stopBroadcast();

            vm.startBroadcast(pk2);
            market.purchaseListing{value: PRICE1}(idA, PRICE1, 0, address(0), 0, 0, 0, address(0));
            erc721.safeTransferFrom(ACCOUNT2, ACCOUNT1, TOKEN1); // cleanup
            vm.stopBroadcast();
        } else {
            console.log("SKIP A: TOKEN1 not owned by ACCOUNT1 on live Sepolia");
        }

        // === B) 721 list -> cancel ===
        if (erc721.ownerOf(TOKEN2) == ACCOUNT2) {
            _approve721IfNeeded(pk2, ACCOUNT2, TOKEN2);
            uint128 idB = getter.getNextListingId();

            vm.startBroadcast(pk2);
            {
                market.createListing(
                    TOKEN721, TOKEN2, address(0), PRICE2, address(0), 0, 0, 0, false, false, new address[](0)
                );
            }
            vm.stopBroadcast();

            vm.startBroadcast(pk2);
            market.cancelListing(idB);
            vm.stopBroadcast();
        } else {
            console.log("SKIP B: TOKEN2 not owned by ACCOUNT2 on live Sepolia");
        }

        // === C) 721 whitelist positive (A1 allows A2) ===
        if (erc721.ownerOf(TOKEN1) == ACCOUNT1) {
            _approve721IfNeeded(pk1, ACCOUNT1, TOKEN1);
            uint128 idC = getter.getNextListingId();

            vm.startBroadcast(pk1);
            {
                address[] memory allowOne = new address[](1);
                allowOne[0] = ACCOUNT2;
                market.createListing(TOKEN721, TOKEN1, address(0), PRICE1, address(0), 0, 0, 0, true, false, allowOne);
            }
            vm.stopBroadcast();

            vm.startBroadcast(pk2);
            market.purchaseListing{value: PRICE1}(idC, PRICE1, 0, address(0), 0, 0, 0, address(0));
            erc721.safeTransferFrom(ACCOUNT2, ACCOUNT1, TOKEN1); // cleanup
            vm.stopBroadcast();
        } else {
            console.log("SKIP C: TOKEN1 not owned by ACCOUNT1 (cannot whitelist-purchase)");
        }

        // === E) ERC1155 partial 3 + 7 (deploy + whitelist mock, then cleanup) ===

        // 1) Deploy 1155 ON-CHAIN as ACCOUNT1
        address mock1155;
        Mock1155 token1155;
        vm.startBroadcast(pk1);
        token1155 = new Mock1155();
        mock1155 = address(token1155);
        vm.stopBroadcast();

        // 2) Sanity check it's really on-chain
        require(mock1155.code.length > 0, "Mock1155 not deployed on-chain");

        // 3) Whitelist the *on-chain* address
        if (!getter.isCollectionWhitelisted(mock1155)) {
            vm.startBroadcast(pk1);
            cwl.addWhitelistedCollection(mock1155);
            vm.stopBroadcast();
        }

        // 4) Mint to ACCOUNT1 and approve the diamond (on-chain)
        vm.startBroadcast(pk1);
        token1155.mint(ACCOUNT1, ID1155, QTY1155);
        token1155.setApprovalForAll(DIAMOND, true);
        vm.stopBroadcast();

        // 5) Create listing with TOTAL price
        uint128 idE = getter.getNextListingId();
        vm.startBroadcast(pk1);
        market.createListing(
            mock1155,
            ID1155,
            ACCOUNT1, // erc1155Holder
            PRICE1155 * QTY1155, // total price
            address(0),
            0,
            0,
            QTY1155, // total quantity
            false, // buyerWhitelistEnabled
            true, // partialBuyEnabled
            new address[](0)
        );
        vm.stopBroadcast();

        // 6) Partial purchases
        vm.startBroadcast(pk2);
        market.purchaseListing{value: PRICE1155 * PARTIAL1}(
            idE, PRICE1155 * QTY1155, QTY1155, address(0), 0, 0, PARTIAL1, ACCOUNT2
        );
        vm.stopBroadcast();

        uint256 remainingQty = QTY1155 - PARTIAL1;
        uint256 remainingTotal = (PRICE1155 * QTY1155) - (PRICE1155 * PARTIAL1);

        vm.startBroadcast(pk2);
        market.purchaseListing{value: PRICE1155 * PARTIAL2}(
            idE, remainingTotal, remainingQty, address(0), 0, 0, PARTIAL2, ACCOUNT2
        );
        vm.stopBroadcast();

        // 7) Cleanup: return all 1155 back to ACCOUNT1
        vm.startBroadcast(pk2);
        token1155.safeTransferFrom(ACCOUNT2, ACCOUNT1, ID1155, QTY1155, "");
        vm.stopBroadcast();
    }

    function _approve721IfNeeded(uint256 pk, address owner, uint256 tokenId) internal {
        vm.startBroadcast(pk);
        if (erc721.getApproved(tokenId) != DIAMOND && !erc721.isApprovedForAll(owner, DIAMOND)) {
            erc721.approve(DIAMOND, tokenId);
        }
        vm.stopBroadcast();
    }
}
