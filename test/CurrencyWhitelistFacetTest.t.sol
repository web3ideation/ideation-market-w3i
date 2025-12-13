// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import {
    CurrencyWhitelistFacet,
    CurrencyWhitelist__AlreadyAllowed,
    CurrencyWhitelist__NotAllowed
} from "../src/facets/CurrencyWhitelistFacet.sol";
import {IdeationMarket__CurrencyNotAllowed} from "../src/facets/IdeationMarketFacet.sol";

contract CurrencyWhitelistFacetTest is MarketTestBase {
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    MockERC20 internal tokenC;
    MockERC20 internal tokenD;

    event CurrencyAllowed(address indexed currency);
    event CurrencyRemoved(address indexed currency);

    function setUp() public virtual override {
        super.setUp();
        tokenA = new MockERC20("TokenA", "TKA");
        tokenB = new MockERC20("TokenB", "TKB");
        tokenC = new MockERC20("TokenC", "TKC");
        tokenD = new MockERC20("TokenD", "TKD");
    }

    // ----------------------------------------------------------
    // Group 1: Basic Functionality
    // ----------------------------------------------------------

    function testOwnerCanAddAndRemoveCurrency() public {
        _addCurrency(address(tokenA));
        assertTrue(getter.isCurrencyAllowed(address(tokenA)));

        _removeCurrency(address(tokenA));
        assertFalse(getter.isCurrencyAllowed(address(tokenA)));
    }

    function testNonOwnerCannotAddOrRemove() public {
        vm.prank(seller);
        vm.expectRevert(bytes("LibDiamond: Must be contract owner"));
        currencies.addAllowedCurrency(address(tokenA));

        vm.prank(buyer);
        vm.expectRevert(bytes("LibDiamond: Must be contract owner"));
        currencies.removeAllowedCurrency(address(tokenA));
    }

    function testEventsEmittedOnAddAndRemove() public {
        vm.expectEmit(true, true, true, true, address(diamond));
        emit CurrencyAllowed(address(tokenA));
        _addCurrency(address(tokenA));

        vm.expectEmit(true, true, true, true, address(diamond));
        emit CurrencyRemoved(address(tokenA));
        _removeCurrency(address(tokenA));
    }

    function testDoubleAddReverts() public {
        _addCurrency(address(tokenA));

        vm.prank(owner);
        vm.expectRevert(CurrencyWhitelist__AlreadyAllowed.selector);
        currencies.addAllowedCurrency(address(tokenA));
    }

    function testRemoveNonAllowedReverts() public {
        vm.prank(owner);
        vm.expectRevert(CurrencyWhitelist__NotAllowed.selector);
        currencies.removeAllowedCurrency(address(tokenA));
    }

    // ----------------------------------------------------------
    // Group 2: Getter Functions
    // ----------------------------------------------------------

    function testGettersReflectAllowedCurrencies() public {
        uint256 baseLen = getter.getAllowedCurrencies().length;
        _addCurrency(address(tokenA));
        _addCurrency(address(tokenB));
        _addCurrency(address(tokenC));

        assertTrue(getter.isCurrencyAllowed(address(tokenA)));
        assertTrue(getter.isCurrencyAllowed(address(tokenB)));
        assertTrue(getter.isCurrencyAllowed(address(tokenC)));

        address[] memory currenciesArray = getter.getAllowedCurrencies();
        assertEq(currenciesArray.length, baseLen + 3);
        assertEq(_countOccurrences(currenciesArray, address(tokenA)), 1);
        assertEq(_countOccurrences(currenciesArray, address(tokenB)), 1);
        assertEq(_countOccurrences(currenciesArray, address(tokenC)), 1);
    }

    // ----------------------------------------------------------
    // Group 3: Initialization State
    // ----------------------------------------------------------

    function testETHIsInitializedInAllowlist() public view {
        assertTrue(getter.isCurrencyAllowed(address(0)));
    }

    function testCanRemoveETHFromAllowlist() public {
        _removeCurrency(address(0));
        assertFalse(getter.isCurrencyAllowed(address(0)));

        _whitelistCollectionAndApproveERC721();
        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__CurrencyNotAllowed.selector);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        _addCurrency(address(0));
    }

    // ----------------------------------------------------------
    // Group 4: Swap-and-Pop Array Integrity
    // ----------------------------------------------------------

    function testArrayIntegritySwapAndPopRemoval() public {
        _addCurrency(address(tokenA));
        _addCurrency(address(tokenB));
        _addCurrency(address(tokenC));

        _removeCurrency(address(tokenB));
        address[] memory arrAfterB = getter.getAllowedCurrencies();
        assertEq(_countOccurrences(arrAfterB, address(tokenB)), 0);

        _removeCurrency(address(tokenC));
        address[] memory arrAfterC = getter.getAllowedCurrencies();
        assertEq(_countOccurrences(arrAfterC, address(tokenC)), 0);
    }

    function testIndexMappingCorrectAfterSwapAndPop() public {
        uint256 baseLen = getter.getAllowedCurrencies().length;
        _addCurrency(address(tokenA));
        _addCurrency(address(tokenB));
        _addCurrency(address(tokenC));

        _removeCurrency(address(tokenB));
        address[] memory arr = getter.getAllowedCurrencies();
        assertEq(arr.length, baseLen + 2);
        assertTrue(getter.isCurrencyAllowed(address(tokenA)));
        assertTrue(getter.isCurrencyAllowed(address(tokenC)));
        assertEq(_countOccurrences(arr, address(tokenA)), 1);
        assertEq(_countOccurrences(arr, address(tokenC)), 1);
    }

    function testRemoveOnlyElementInArray() public {
        uint256 baseLen = getter.getAllowedCurrencies().length;
        _addCurrency(address(tokenA));
        address[] memory arrWith = getter.getAllowedCurrencies();
        assertEq(arrWith.length, baseLen + 1);
        assertEq(_countOccurrences(arrWith, address(tokenA)), 1);

        _removeCurrency(address(tokenA));
        address[] memory arrWithout = getter.getAllowedCurrencies();
        assertEq(arrWithout.length, baseLen);
        assertEq(_countOccurrences(arrWithout, address(tokenA)), 0);
    }

    function testMultipleCurrenciesInAllowlistAndEdges() public {
        _addCurrency(address(tokenA));
        _addCurrency(address(tokenB));
        _addCurrency(address(tokenC));
        _addCurrency(address(tokenD));

        _removeCurrency(address(tokenB));
        _removeCurrency(address(tokenC));

        address[] memory arr = getter.getAllowedCurrencies();
        assertEq(_countOccurrences(arr, address(tokenA)), 1);
        assertEq(_countOccurrences(arr, address(tokenD)), 1);
        assertEq(_countOccurrences(arr, address(tokenB)), 0);
        assertEq(_countOccurrences(arr, address(tokenC)), 0);
    }

    // ----------------------------------------------------------
    // Group 5: Listing Creation with Currency Validation
    // ----------------------------------------------------------

    function testCannotCreateListingAfterCurrencyRemoved() public {
        _addCurrency(address(tokenA));
        _removeCurrency(address(tokenA));

        _whitelistCollectionAndApproveERC721();
        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__CurrencyNotAllowed.selector);
        market.createListing(
            address(erc721),
            1,
            address(0),
            1 ether,
            address(tokenA),
            address(0),
            0,
            0,
            0,
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();
    }

    // ----------------------------------------------------------
    // Group 6: Existing Listings After Currency Removal
    // ----------------------------------------------------------

    function testRemoveCurrencyDoesNotAffectExistingListings() public {
        _addCurrency(address(tokenA));
        uint128 listingId = _createERC721ListingWithCurrency(address(tokenA), 5 ether, 1);

        _removeCurrency(address(tokenA));

        tokenA.mint(buyer, 5 ether);
        vm.prank(buyer);
        tokenA.approve(address(diamond), 5 ether);

        uint256 ownerStart = tokenA.balanceOf(owner);
        uint256 sellerStart = tokenA.balanceOf(seller);

        vm.prank(buyer);
        market.purchaseListing(listingId, 5 ether, address(tokenA), 0, address(0), 0, 0, 0, address(0));

        uint256 ownerEnd = tokenA.balanceOf(owner);
        uint256 sellerEnd = tokenA.balanceOf(seller);

        uint256 fee = (5 ether * uint256(INNOVATION_FEE)) / 100000;
        uint256 sellerProceeds = 5 ether - fee;

        assertEq(ownerEnd - ownerStart, fee, "Owner fee not paid correctly");
        assertEq(sellerEnd - sellerStart, sellerProceeds, "Seller proceeds not paid correctly");
        assertEq(tokenA.balanceOf(address(diamond)), 0, "Diamond should not hold ERC20");

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingId));
        getter.getListingByListingId(listingId);
    }

    // ----------------------------------------------------------
    // Group 7: ERC20 Payment Distribution
    // ----------------------------------------------------------

    function testPaymentDistributionWithERC20AfterRemoval() public {
        _addCurrency(address(tokenA));
        uint128 listingId = _createERC721ListingWithCurrency(address(tokenA), 5 ether, 1);

        _removeCurrency(address(tokenA));

        tokenA.mint(buyer, 5 ether);
        vm.prank(buyer);
        tokenA.approve(address(diamond), 5 ether);

        uint256 ownerStart = tokenA.balanceOf(owner);
        uint256 sellerStart = tokenA.balanceOf(seller);
        uint256 buyerStart = tokenA.balanceOf(buyer);

        vm.prank(buyer);
        market.purchaseListing(listingId, 5 ether, address(tokenA), 0, address(0), 0, 0, 0, address(0));

        uint256 ownerEnd = tokenA.balanceOf(owner);
        uint256 sellerEnd = tokenA.balanceOf(seller);
        uint256 buyerEnd = tokenA.balanceOf(buyer);

        uint256 fee = (5 ether * uint256(INNOVATION_FEE)) / 100000;
        uint256 sellerProceeds = 5 ether - fee;

        assertEq(ownerEnd - ownerStart, fee);
        assertEq(sellerEnd - sellerStart, sellerProceeds);
        assertEq(buyerStart - buyerEnd, 5 ether);
        assertEq(ownerEnd + sellerEnd, ownerStart + sellerStart + 5 ether);
        assertEq(tokenA.balanceOf(address(diamond)), 0);
    }

    function testMultipleERC20TokensPaymentDistribution() public {
        _addCurrency(address(tokenA));
        _addCurrency(address(tokenB));

        uint128 listingA = _createERC721ListingWithCurrency(address(tokenA), 2 ether, 1);
        uint128 listingB = _createERC721ListingWithCurrency(address(tokenB), 3 ether, 2);

        _removeCurrency(address(tokenA));
        _removeCurrency(address(tokenB));

        tokenA.mint(buyer, 2 ether);
        tokenB.mint(buyer, 3 ether);
        vm.startPrank(buyer);
        tokenA.approve(address(diamond), 2 ether);
        tokenB.approve(address(diamond), 3 ether);
        vm.stopPrank();

        uint256 ownerStartA = tokenA.balanceOf(owner);
        uint256 ownerStartB = tokenB.balanceOf(owner);
        uint256 sellerStartA = tokenA.balanceOf(seller);
        uint256 sellerStartB = tokenB.balanceOf(seller);
        uint256 buyerStartA = tokenA.balanceOf(buyer);
        uint256 buyerStartB = tokenB.balanceOf(buyer);

        vm.prank(buyer);
        market.purchaseListing(listingA, 2 ether, address(tokenA), 0, address(0), 0, 0, 0, address(0));

        vm.prank(buyer);
        market.purchaseListing(listingB, 3 ether, address(tokenB), 0, address(0), 0, 0, 0, address(0));

        uint256 ownerEndA = tokenA.balanceOf(owner);
        uint256 ownerEndB = tokenB.balanceOf(owner);
        uint256 sellerEndA = tokenA.balanceOf(seller);
        uint256 sellerEndB = tokenB.balanceOf(seller);
        uint256 buyerEndA = tokenA.balanceOf(buyer);
        uint256 buyerEndB = tokenB.balanceOf(buyer);

        uint256 feeA = (2 ether * uint256(INNOVATION_FEE)) / 100000;
        uint256 feeB = (3 ether * uint256(INNOVATION_FEE)) / 100000;

        assertEq(ownerEndA - ownerStartA, feeA);
        assertEq(ownerEndB - ownerStartB, feeB);
        assertEq(sellerEndA - sellerStartA, 2 ether - feeA);
        assertEq(sellerEndB - sellerStartB, 3 ether - feeB);
        assertEq(buyerStartA - buyerEndA, 2 ether);
        assertEq(buyerStartB - buyerEndB, 3 ether);
        assertEq(tokenA.balanceOf(address(diamond)), 0);
        assertEq(tokenB.balanceOf(address(diamond)), 0);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingA));
        getter.getListingByListingId(listingA);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingB));
        getter.getListingByListingId(listingB);
    }

    // ----------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------

    function _addCurrency(address token) internal {
        vm.prank(owner);
        currencies.addAllowedCurrency(token);
    }

    function _removeCurrency(address token) internal {
        vm.prank(owner);
        currencies.removeAllowedCurrency(token);
    }

    function _countOccurrences(address[] memory arr, address target) internal pure returns (uint256 count) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == target) {
                count++;
            }
        }
    }

    function _createERC721ListingWithCurrency(address currency, uint256 price, uint256 tokenId)
        internal
        returns (uint128 listingId)
    {
        if (!getter.isCollectionWhitelisted(address(erc721))) {
            vm.startPrank(owner);
            collections.addWhitelistedCollection(address(erc721));
            vm.stopPrank();
        }

        vm.startPrank(seller);
        erc721.approve(address(diamond), tokenId);
        market.createListing(
            address(erc721), tokenId, address(0), price, currency, address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();
        listingId = getter.getNextListingId() - 1;
    }
}

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "allowance");
        allowance[from][msg.sender] = allowed - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
