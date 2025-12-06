// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import {Listing} from "../src/libraries/LibAppStorage.sol";
import {IdeationMarket__ContractPaused} from "../src/facets/IdeationMarketFacet.sol";

/// @title PauseFacetTest
/// @notice Comprehensive tests for emergency pause functionality
/// @dev Tests pause/unpause access control, paused function behavior, and non-paused function access during pause
contract PauseFacetTest is MarketTestBase {
    address user1;
    address user2;
    address attacker;

    // Events to test
    event Paused(address indexed triggeredBy);
    event Unpaused(address indexed triggeredBy);

    function setUp() public override {
        super.setUp();

        // Additional test addresses
        user1 = vm.addr(0x2001);
        user2 = vm.addr(0x2002);
        attacker = vm.addr(0x2003);

        // Whitelist collections and give users some tokens
        _whitelistDefaultMocks();
        vm.startPrank(seller);
        erc721.mint(user1, 10);
        erc721.mint(user2, 11);
        erc721.mint(attacker, 12);
        vm.stopPrank();
    }

    // ============================================
    // Diamond Routing Verification
    // ============================================

    /// @notice Verify pause/unpause selectors route to PauseFacet through diamond
    function testPauseFacetSelectorsRoutedCorrectly() public view {
        // Verify pause() selector routes to PauseFacet implementation
        address pauseAddr = loupe.facetAddress(PauseFacet.pause.selector);
        assertEq(pauseAddr, pauseImpl, "pause() must route to PauseFacet implementation");

        // Verify unpause() selector routes to PauseFacet implementation
        address unpauseAddr = loupe.facetAddress(PauseFacet.unpause.selector);
        assertEq(unpauseAddr, pauseImpl, "unpause() must route to PauseFacet implementation");

        // Verify isPaused() selector routes to GetterFacet implementation
        address isPausedAddr = loupe.facetAddress(GetterFacet.isPaused.selector);
        assertEq(isPausedAddr, getterImpl, "isPaused() must route to GetterFacet implementation");
    }

    // ============================================
    // Access Control Tests
    // ============================================

    /// @notice Test that only owner can pause the marketplace
    function testPauseOnlyOwner() public {
        vm.prank(owner);
        pauseFacet.pause();
        assertTrue(getter.isPaused());
    }

    /// @notice Test that non-owner cannot pause
    function testPauseRevertsForNonOwner() public {
        vm.prank(user1);
        vm.expectRevert("LibDiamond: Must be contract owner");
        pauseFacet.pause();
    }

    /// @notice Test that only owner can unpause
    function testUnpauseOnlyOwner() public {
        // Setup: pause first
        vm.prank(owner);
        pauseFacet.pause();

        // Test unpause
        vm.prank(owner);
        pauseFacet.unpause();
        assertFalse(getter.isPaused());
    }

    /// @notice Test that non-owner cannot unpause
    function testUnpauseRevertsForNonOwner() public {
        // Setup: pause first
        vm.prank(owner);
        pauseFacet.pause();

        // Test unpause by non-owner
        vm.prank(user1);
        vm.expectRevert("LibDiamond: Must be contract owner");
        pauseFacet.unpause();
    }

    // ============================================
    // State Management Tests
    // ============================================

    /// @notice Test pause emits correct event
    function testPauseEmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit Paused(owner);
        pauseFacet.pause();
    }

    /// @notice Test unpause emits correct event
    function testUnpauseEmitsEvent() public {
        // Setup: pause first
        vm.prank(owner);
        pauseFacet.pause();

        // Test unpause event
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit Unpaused(owner);
        pauseFacet.unpause();
    }

    /// @notice Test cannot pause when already paused
    function testCannotPauseWhenAlreadyPaused() public {
        vm.startPrank(owner);
        pauseFacet.pause();

        // Try to pause again
        vm.expectRevert(PauseFacet.Pause__AlreadyPaused.selector);
        pauseFacet.pause();
        vm.stopPrank();
    }

    /// @notice Test cannot unpause when not paused
    function testCannotUnpauseWhenNotPaused() public {
        vm.prank(owner);
        vm.expectRevert(PauseFacet.Pause__NotPaused.selector);
        pauseFacet.unpause();
    }

    /// @notice Test initial state is not paused
    function testInitialStateNotPaused() public view {
        assertFalse(getter.isPaused());
    }

    /// @notice Test pause-unpause cycle
    function testPauseUnpauseCycle() public {
        vm.startPrank(owner);

        // Initial state
        assertFalse(getter.isPaused());

        // Pause
        pauseFacet.pause();
        assertTrue(getter.isPaused());

        // Unpause
        pauseFacet.unpause();
        assertFalse(getter.isPaused());

        // Pause again
        pauseFacet.pause();
        assertTrue(getter.isPaused());

        vm.stopPrank();
    }

    // ============================================
    // Paused Function Behavior Tests
    // ============================================

    /// @notice Test createListing reverts when paused
    function testCreateListingRevertsWhenPaused() public {
        // Setup: pause marketplace
        vm.prank(owner);
        pauseFacet.pause();

        // Setup listing parameters
        address tokenAddress = address(erc721);
        uint256 tokenId = 10;
        address erc1155Holder = address(0);
        uint256 price = 1 ether;
        address currency = address(0); // ETH
        address desiredTokenAddress = address(0);
        uint256 desiredTokenId = 0;
        uint256 desiredErc1155Quantity = 0;
        uint256 erc1155Quantity = 0;
        bool buyerWhitelistEnabled = false;
        bool partialBuyEnabled = false;
        address[] memory allowedBuyers = new address[](0);

        // Attempt to create listing
        vm.startPrank(user1);
        erc721.approve(address(diamond), tokenId);
        vm.expectRevert(IdeationMarket__ContractPaused.selector);
        market.createListing(
            tokenAddress,
            tokenId,
            erc1155Holder,
            price,
            currency,
            desiredTokenAddress,
            desiredTokenId,
            desiredErc1155Quantity,
            erc1155Quantity,
            buyerWhitelistEnabled,
            partialBuyEnabled,
            allowedBuyers
        );
        vm.stopPrank();
    }

    /// @notice Test purchaseListing reverts when paused
    function testPurchaseListingRevertsWhenPaused() public {
        // Setup: create listing while unpaused
        vm.startPrank(user1);
        erc721.approve(address(diamond), 10);
        market.createListing(
            address(erc721),
            10,
            address(0), // erc1155Holder
            1 ether,
            address(0), // ETH
            address(0),
            0,
            0,
            0,
            false,
            false,
            new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;
        vm.stopPrank();

        // Then pause
        vm.prank(owner);
        pauseFacet.pause();

        // Attempt to purchase
        vm.prank(user2);
        vm.deal(user2, 1 ether);
        vm.expectRevert(IdeationMarket__ContractPaused.selector);
        market.purchaseListing{value: 1 ether}(
            listingId,
            1 ether, // expectedPrice
            address(0), // expectedCurrency
            0, // expectedErc1155Quantity
            address(0), // expectedDesiredTokenAddress
            0, // expectedDesiredTokenId
            0, // expectedDesiredErc1155Quantity
            0, // erc1155PurchaseQuantity
            address(0) // desiredErc1155Holder
        );
    }

    /// @notice Test updateListing reverts when paused
    function testUpdateListingRevertsWhenPaused() public {
        // Setup: create listing while unpaused
        vm.startPrank(user1);
        erc721.approve(address(diamond), 10);
        market.createListing(
            address(erc721),
            10,
            address(0), // erc1155Holder
            1 ether,
            address(0), // ETH
            address(0),
            0,
            0,
            0,
            false,
            false,
            new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;
        vm.stopPrank();

        // Then pause
        vm.prank(owner);
        pauseFacet.pause();

        // Attempt to update
        vm.prank(user1);
        vm.expectRevert(IdeationMarket__ContractPaused.selector);
        market.updateListing(
            listingId,
            2 ether, // newPrice
            address(0), // newCurrency
            address(0), // newDesiredTokenAddress
            0, // newDesiredTokenId
            0, // newDesiredErc1155Quantity
            0, // newErc1155Quantity
            false, // newBuyerWhitelistEnabled
            false, // newPartialBuyEnabled
            new address[](0) // newAllowedBuyers
        );
    }

    // ============================================
    // Non-Paused Function Access Tests
    // ============================================

    /// @notice Test cancelListing works when paused (users can exit)
    function testCancelListingWorksWhenPaused() public {
        // Setup: create listing while unpaused
        vm.startPrank(user1);
        erc721.approve(address(diamond), 10);
        market.createListing(
            address(erc721), 10, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;
        vm.stopPrank();

        // Then pause
        vm.prank(owner);
        pauseFacet.pause();

        // Cancel should work
        vm.prank(user1);
        market.cancelListing(listingId);
    }

    /// @notice Test cleanListing works when paused (cleanup needed)
    function testCleanListingWorksWhenPaused() public {
        // Setup: create listing and revoke approval
        vm.startPrank(user1);
        erc721.approve(address(diamond), 10);
        market.createListing(
            address(erc721), 10, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;
        erc721.approve(address(0), 10); // Revoke approval
        vm.stopPrank();

        // Then pause
        vm.prank(owner);
        pauseFacet.pause();

        // Clean should work
        vm.prank(user2);
        market.cleanListing(listingId);
    }

    /// @notice Test setInnovationFee works when paused (owner admin function)
    function testSetInnovationFeeWorksWhenPaused() public {
        vm.startPrank(owner);
        pauseFacet.pause();

        // setInnovationFee should work
        market.setInnovationFee(2000); // 2%
        assertEq(getter.getInnovationFee(), 2000);

        vm.stopPrank();
    }

    /// @notice Test buyer whitelist operations work when paused
    function testBuyerWhitelistWorksWhenPaused() public {
        // Setup: create listing with whitelist enabled
        vm.startPrank(user1);
        erc721.approve(address(diamond), 10);
        market.createListing(
            address(erc721),
            10,
            address(0),
            1 ether,
            address(0),
            address(0),
            0,
            0,
            0,
            true,
            false,
            new address[](0) // whitelist enabled
        );
        uint128 listingId = getter.getNextListingId() - 1;
        vm.stopPrank();

        // Then pause
        vm.prank(owner);
        pauseFacet.pause();

        // Whitelist operations should work
        address[] memory buyersToAdd = new address[](1);
        buyersToAdd[0] = user2;

        vm.startPrank(user1);
        buyers.addBuyerWhitelistAddresses(listingId, buyersToAdd);
        assertTrue(getter.isBuyerWhitelisted(listingId, user2));

        buyers.removeBuyerWhitelistAddresses(listingId, buyersToAdd);
        assertFalse(getter.isBuyerWhitelisted(listingId, user2));
        vm.stopPrank();
    }

    /// @notice Test collection whitelist operations work when paused (owner admin)
    function testCollectionWhitelistWorksWhenPaused() public {
        vm.startPrank(owner);
        pauseFacet.pause();

        // Collection whitelist should work
        address newCollection = vm.addr(0x9999);
        collections.addWhitelistedCollection(newCollection);
        assertTrue(getter.isCollectionWhitelisted(newCollection));

        vm.stopPrank();
    }

    /// @notice Test all getter functions work when paused
    function testGetterFunctionsWorkWhenPaused() public {
        vm.prank(owner);
        pauseFacet.pause();

        // All getter functions should work
        assertTrue(getter.isPaused());
        assertEq(getter.getInnovationFee(), INNOVATION_FEE);
        assertGt(getter.getNextListingId(), 0);
        assertEq(getter.getContractOwner(), owner);
    }

    /// @notice Test ownership transfer works when paused
    function testOwnershipTransferWorksWhenPaused() public {
        vm.startPrank(owner);
        pauseFacet.pause();

        // Ownership transfer should work
        ownership.transferOwnership(user1);
        assertEq(getter.getPendingOwner(), user1);

        vm.stopPrank();
    }

    /// @notice Test diamondCut works when paused (critical for recovery)
    function testDiamondCutWorksWhenPaused() public {
        vm.startPrank(owner);
        pauseFacet.pause();

        // Diamond cut should work (needed for emergency upgrades)
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](0);
        IDiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), "");

        vm.stopPrank();
    }

    // ============================================
    // Integration Tests
    // ============================================

    /// @notice Test full pause scenario: pause, verify blocked, unpause, verify restored
    function testFullPauseScenario() public {
        // 1. Create listing while unpaused
        vm.startPrank(user1);
        erc721.approve(address(diamond), 10);
        market.createListing(
            address(erc721), 10, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;
        vm.stopPrank();

        // 2. Pause marketplace
        vm.prank(owner);
        pauseFacet.pause();
        assertTrue(getter.isPaused());

        // 3. Verify critical functions are blocked
        vm.prank(user2);
        vm.deal(user2, 1 ether);
        vm.expectRevert(IdeationMarket__ContractPaused.selector);
        market.purchaseListing{value: 1 ether}(listingId, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        // 4. Verify seller can still cancel
        vm.prank(user1);
        market.cancelListing(listingId);

        // 5. Unpause
        vm.prank(owner);
        pauseFacet.unpause();
        assertFalse(getter.isPaused());

        // 6. Verify functions work again
        vm.startPrank(user2);
        erc721.approve(address(diamond), 11);
        market.createListing(
            address(erc721), 11, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();
    }

    /// @notice Test emergency response: attacker detected, pause immediately
    function testEmergencyResponse() public {
        // Simulate normal operation - user creates listing
        vm.startPrank(user1);
        erc721.approve(address(diamond), 10);
        market.createListing(
            address(erc721), 10, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        // Emergency detected by monitoring
        vm.prank(owner);
        pauseFacet.pause();

        // All user transactions should now fail
        vm.startPrank(attacker);
        erc721.approve(address(diamond), 12);
        vm.expectRevert(IdeationMarket__ContractPaused.selector);
        market.createListing(
            address(erc721), 12, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        vm.stopPrank();

        // Owner investigates and can still perform diamond cut if needed
        vm.startPrank(owner);
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](0);
        IDiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), "");

        // Resume operations
        pauseFacet.unpause();
        vm.stopPrank();
    }

    /// @notice Test pause doesn't affect existing listing data
    function testPausePreservesListingData() public {
        // Create listing
        vm.startPrank(user1);
        erc721.approve(address(diamond), 10);
        market.createListing(
            address(erc721), 10, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;
        vm.stopPrank();

        Listing memory listingBefore = getter.getListingByListingId(listingId);

        // Pause
        vm.prank(owner);
        pauseFacet.pause();

        // Verify listing data unchanged
        Listing memory listingAfter = getter.getListingByListingId(listingId);
        assertEq(listingBefore.seller, listingAfter.seller);
        assertEq(listingBefore.price, listingAfter.price);
        assertEq(listingBefore.currency, listingAfter.currency);
        assertEq(listingBefore.tokenAddress, listingAfter.tokenAddress);
        assertEq(listingBefore.tokenId, listingAfter.tokenId);
    }

    /// @notice Test multiple pause/unpause cycles don't corrupt state
    function testMultiplePauseUnpauseCycles() public {
        vm.startPrank(owner);

        for (uint256 i = 0; i < 5; i++) {
            pauseFacet.pause();
            assertTrue(getter.isPaused());

            pauseFacet.unpause();
            assertFalse(getter.isPaused());
        }

        vm.stopPrank();
    }

    // ============================================
    // Edge Cases & Fuzzing
    // ============================================

    /// @notice Fuzz test: random addresses cannot pause
    function testFuzz_OnlyOwnerCanPause(address randomUser) public {
        vm.assume(randomUser != owner && randomUser != address(0));
        vm.prank(randomUser);
        vm.expectRevert("LibDiamond: Must be contract owner");
        pauseFacet.pause();
    }

    /// @notice Fuzz test: pause state is consistent across all checks
    function testFuzz_PauseStateConsistent(bool shouldPause) public {
        vm.startPrank(owner);

        if (shouldPause) {
            if (!getter.isPaused()) {
                pauseFacet.pause();
            }
            assertTrue(getter.isPaused());
        } else {
            if (getter.isPaused()) {
                pauseFacet.unpause();
            }
            assertFalse(getter.isPaused());
        }

        vm.stopPrank();
    }
}
