// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Listing} from "../src/libraries/LibAppStorage.sol";

// same interfaces as in the test file
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
    function isCurrencyAllowed(address currency) external view returns (bool);
    function getListingByListingId(uint128 listingId) external view returns (Listing memory listing);
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
        address currency,
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
        address expectedCurrency,
        uint256 expectedErc1155Quantity,
        address expectedDesiredTokenAddress,
        uint256 expectedDesiredTokenId,
        uint256 expectedDesiredErc1155Quantity,
        uint256 erc1155PurchaseQuantity,
        address desiredErc1155Holder
    ) external payable;
    function cancelListing(uint128 listingId) external;
}

contract MarketSmokeBroadcast is Script {
    // live addresses (same as tests) :contentReference[oaicite:12]{index=12}
    address constant DIAMOND = 0x8cE90712463c87a6d62941D67C3507D090Ea9d79;
    address constant TOKEN721 = 0x41655AE49482de69eEC8F6875c34A8Ada01965e2;

    address constant ACCOUNT1 = 0xE8dF60a93b2B328397a8CBf73f0d732aaa11e33D; // 721 id 16
    address constant ACCOUNT2 = 0x8a200122f666af83aF2D4f425aC7A35fa5491ca7; // 721 id 534

    uint256 constant TOKEN1 = 16;
    uint256 constant TOKEN2 = 534;

    uint256 constant PRICE1 = 200_000_000_000_000;
    uint256 constant PRICE2 = 300_000_000_000_000;

    IGetterFacet getter = IGetterFacet(DIAMOND);
    IIdeationMarketFacet market = IIdeationMarketFacet(DIAMOND);
    ICollectionWhitelistFacet cwl = ICollectionWhitelistFacet(DIAMOND);
    IERC721 erc721 = IERC721(TOKEN721);

    function run() external {
        uint256 pk1 = vm.envUint("PRIVATE_KEY_1"); // MUST control ACCOUNT1
        uint256 pk2 = vm.envUint("PRIVATE_KEY_2"); // MUST control ACCOUNT2

        // # ensure env keys match the fixed addresses
        require(vm.addr(pk1) == ACCOUNT1, "PRIVATE_KEY_1 does not control ACCOUNT1");
        require(vm.addr(pk2) == ACCOUNT2, "PRIVATE_KEY_2 does not control ACCOUNT2");

        // whitelist ETH as currency if not yet (non-custodial multi-currency requirement)
        if (!getter.isCurrencyAllowed(address(0))) {
            vm.startBroadcast(pk1);
            (bool success,) = DIAMOND.call(abi.encodeWithSignature("addAllowedCurrency(address)", address(0)));
            require(success, "ETH whitelisting failed - CurrencyWhitelistFacet may need to be deployed");
            vm.stopBroadcast();
            console.log("ETH whitelisted as currency");
        }

        // whitelist 721 if needed (owner is ACCOUNT1 per your deploy log) :contentReference[oaicite:13]{index=13}
        if (!getter.isCollectionWhitelisted(TOKEN721)) {
            vm.startBroadcast(pk1);
            cwl.addWhitelistedCollection(TOKEN721);
            vm.stopBroadcast();
        }

        // A) 721 list->buy->cleanup (A1->A2->back)
        // # run only if A1 still owns TOKEN1 on live Sepolia
        if (erc721.ownerOf(TOKEN1) == ACCOUNT1) {
            _approve721IfNeeded(pk1, ACCOUNT1, TOKEN1);
            uint128 idA = getter.getNextListingId();

            vm.startBroadcast(pk1);
            {
                market.createListing(
                    TOKEN721,
                    TOKEN1,
                    address(0),
                    PRICE1,
                    address(0),
                    address(0),
                    0,
                    0,
                    0,
                    false,
                    false,
                    new address[](0)
                );
            }
            vm.stopBroadcast();

            vm.startBroadcast(pk2);
            market.purchaseListing{value: PRICE1}(idA, PRICE1, address(0), 0, address(0), 0, 0, 0, address(0));
            erc721.safeTransferFrom(ACCOUNT2, ACCOUNT1, TOKEN1); // cleanup
            vm.stopBroadcast();
        } else {
            console.log("SKIP A: TOKEN1 not owned by ACCOUNT1 on live Sepolia");
        }

        // B) 721 list->cancel (A2)
        // # run only if A2 still owns TOKEN2 on live Sepolia
        if (erc721.ownerOf(TOKEN2) == ACCOUNT2) {
            _approve721IfNeeded(pk2, ACCOUNT2, TOKEN2);
            uint128 idB = getter.getNextListingId();

            vm.startBroadcast(pk2);
            {
                market.createListing(
                    TOKEN721,
                    TOKEN2,
                    address(0),
                    PRICE2,
                    address(0),
                    address(0),
                    0,
                    0,
                    0,
                    false,
                    false,
                    new address[](0)
                );
            }
            vm.stopBroadcast();

            vm.startBroadcast(pk2);
            market.cancelListing(idB);
            vm.stopBroadcast();
        } else {
            console.log("SKIP B: TOKEN2 not owned by ACCOUNT2 on live Sepolia");
        }
    }

    function _approve721IfNeeded(uint256 pk, address owner, uint256 tokenId) internal {
        vm.startBroadcast(pk);
        if (erc721.getApproved(tokenId) != DIAMOND && !erc721.isApprovedForAll(owner, DIAMOND)) {
            erc721.approve(DIAMOND, tokenId);
        }
        vm.stopBroadcast();
    }
}
