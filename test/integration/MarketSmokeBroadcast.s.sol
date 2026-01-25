// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Listing} from "../../src/libraries/LibAppStorage.sol";

// same interfaces as in the test file
interface IERC721 {
    function ownerOf(uint256 id) external view returns (address);
    function approve(address to, uint256 id) external;
    function getApproved(uint256 id) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function setApprovalForAll(address operator, bool approved) external;
    function safeTransferFrom(address from, address to, uint256 id) external;
}

// Diamond loupe (for selector presence checks)
interface IDiamondLoupe {
    function facetAddress(bytes4 _functionSelector) external view returns (address facetAddress_);
}

interface IGetterFacet {
    function getNextListingId() external view returns (uint128);
    function isCollectionWhitelisted(address collection) external view returns (bool);
    function isCurrencyAllowed(address currency) external view returns (bool);
    function getListingByListingId(uint128 listingId) external view returns (Listing memory listing);
    function isPaused() external view returns (bool);
    function getContractOwner() external view returns (address);
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
    // Set DIAMOND_ADDRESS to override.
    address diamond;
    address constant TOKEN721 = 0x41655AE49482de69eEC8F6875c34A8Ada01965e2;

    address constant ACCOUNT1 = 0xE8dF60a93b2B328397a8CBf73f0d732aaa11e33D; // 721 id 16
    address constant ACCOUNT2 = 0x8a200122f666af83aF2D4f425aC7A35fa5491ca7; // 721 id 534

    uint256 constant TOKEN1 = 16;
    uint256 constant TOKEN2 = 534;

    uint256 constant PRICE1 = 200_000_000_000_000;
    uint256 constant PRICE2 = 300_000_000_000_000;

    IGetterFacet getter;
    IIdeationMarketFacet market;
    ICollectionWhitelistFacet cwl;
    IERC721 erc721 = IERC721(TOKEN721);

    function run() external {
        diamond = vm.envOr("DIAMOND_ADDRESS", address(0x1107Eb26D47A5bF88E9a9F97cbC7EA38c3E1D7EC));
        getter = IGetterFacet(diamond);
        market = IIdeationMarketFacet(diamond);
        cwl = ICollectionWhitelistFacet(diamond);
        console.log("diamond", diamond);

        // Preflight: make sure this diamond has the selectors we intend to use.
        // This prevents spending gas only to hit "function does not exist" on a wrong deployment.
        {
            IDiamondLoupe loupe = IDiamondLoupe(diamond);
            bytes4 createSel = IIdeationMarketFacet.createListing.selector;
            bytes4 purchaseSel = IIdeationMarketFacet.purchaseListing.selector;
            bytes4 cancelSel = IIdeationMarketFacet.cancelListing.selector;
            bytes4 addAllowedCurrencySel = bytes4(keccak256("addAllowedCurrency(address)"));
            bytes4 addWhitelistedCollectionSel = bytes4(keccak256("addWhitelistedCollection(address)"));

            address createFacet = loupe.facetAddress(createSel);
            address purchaseFacet = loupe.facetAddress(purchaseSel);
            address cancelFacet = loupe.facetAddress(cancelSel);
            address currencyFacet = loupe.facetAddress(addAllowedCurrencySel);
            address collectionFacet = loupe.facetAddress(addWhitelistedCollectionSel);

            console.log("createListing facet", createFacet);
            console.log("purchaseListing facet", purchaseFacet);
            console.log("cancelListing facet", cancelFacet);
            console.log("addAllowedCurrency facet", currencyFacet);
            console.log("addWhitelistedCollection facet", collectionFacet);

            require(createFacet != address(0), "diamond missing createListing(selector)");
            require(purchaseFacet != address(0), "diamond missing purchaseListing(selector)");
            require(cancelFacet != address(0), "diamond missing cancelListing(selector)");
            require(currencyFacet != address(0), "diamond missing addAllowedCurrency(selector)");
            require(collectionFacet != address(0), "diamond missing addWhitelistedCollection(selector)");
        }

        uint256 pk1 = vm.envUint("PRIVATE_KEY_1"); // MUST control ACCOUNT1
        uint256 pk2 = vm.envUint("PRIVATE_KEY_2"); // MUST control ACCOUNT2

        // # ensure env keys match the fixed addresses
        require(vm.addr(pk1) == ACCOUNT1, "PRIVATE_KEY_1 does not control ACCOUNT1");
        require(vm.addr(pk2) == ACCOUNT2, "PRIVATE_KEY_2 does not control ACCOUNT2");

        require(!getter.isPaused(), "diamond is paused");

        // Strong guard: setup steps require diamond owner privileges.
        require(getter.getContractOwner() == ACCOUNT1, "diamond owner is not ACCOUNT1");

        // whitelist ETH as currency if not yet (non-custodial multi-currency requirement)
        if (!getter.isCurrencyAllowed(address(0))) {
            vm.startBroadcast(pk1);
            (bool success,) = diamond.call(abi.encodeWithSignature("addAllowedCurrency(address)", address(0)));
            require(success, "ETH whitelisting failed - CurrencyWhitelistFacet may need to be deployed");
            vm.stopBroadcast();
            console.log("ETH whitelisted as currency");
        }

        // whitelist 721 if needed (owner is ACCOUNT1)
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
        if (erc721.getApproved(tokenId) != diamond && !erc721.isApprovedForAll(owner, diamond)) {
            erc721.approve(diamond, tokenId);
        }
        vm.stopBroadcast();
    }
}
