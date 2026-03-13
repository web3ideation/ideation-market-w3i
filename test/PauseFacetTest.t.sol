// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import {Listing} from "../src/libraries/LibAppStorage.sol";
import {IdeationMarket__ContractPaused} from "../src/facets/IdeationMarketFacet.sol";

/**
 * @title PauseFacetTest
 * @notice Scope/category: emergency pause circuit-breaker behavior and permissions
 * across marketplace, admin, and recovery operations.
 *
 * Covered categories:
 * - Selector routing and owner-only access control for pause/unpause
 * - Pause state transitions, events, and repeat-cycle stability
 * - `whenNotPaused` enforcement on create/purchase/update
 * - Allowed operations while paused (cancel/clean/admin/getters/upgrade/ownership transfer)
 * - Integration/fuzz checks for emergency response and state consistency
 */
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

    /// @notice Test upgradeDiamond works when paused (critical for recovery)
    function testUpgradeDiamondWorksWhenPaused() public {
        vm.prank(owner);
        pauseFacet.pause();

        // Upgrades should work (needed for emergency upgrades)
        _upgradeNoopWithInit(address(0), "");
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

        // Owner investigates and can still perform upgrades if needed
        _upgradeNoopWithInit(address(0), "");

        // Resume operations
        vm.prank(owner);
        pauseFacet.unpause();
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

    /// @notice Fuzz test: randomized role/action sequence preserves pause semantics.
    /// forge-config: default.fuzz.runs = 2048
    function testFuzz_PauseRoleActionSequence(uint8 steps, uint256 actorSeed, uint256 tokenSeed) public {
        steps = uint8(bound(steps, 4, 12));

        // Seed one stable listing used by update/purchase probes.
        vm.startPrank(user1);
        erc721.approve(address(diamond), 10);
        market.createListing(
            address(erc721), 10, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;
        vm.stopPrank();

        bool expectedPaused = getter.isPaused();

        for (uint256 i = 0; i < steps; i++) {
            uint256 actionSeed = uint256(keccak256(abi.encode(actorSeed, i)));
            uint8 action = uint8(actionSeed % 4);

            if (action == 0) {
                uint8 actorPick = uint8((actionSeed >> 8) % 4);
                address actor = actorPick == 0 ? owner : actorPick == 1 ? user1 : actorPick == 2 ? user2 : attacker;

                bool before = getter.isPaused();
                if (actor == owner) {
                    vm.prank(owner);
                    if (before) {
                        pauseFacet.unpause();
                    } else {
                        pauseFacet.pause();
                    }
                    expectedPaused = !before;
                } else {
                    vm.prank(actor);
                    vm.expectRevert("LibDiamond: Must be contract owner");
                    if (before) {
                        pauseFacet.unpause();
                    } else {
                        pauseFacet.pause();
                    }
                    expectedPaused = before;
                }
            } else if (action == 1) {
                uint256 tokenId = 1000 + (tokenSeed % 100000) + i;

                vm.prank(seller);
                erc721.mint(user2, tokenId);

                vm.prank(user2);
                erc721.approve(address(diamond), tokenId);

                if (expectedPaused) {
                    vm.prank(user2);
                    vm.expectRevert(IdeationMarket__ContractPaused.selector);
                    market.createListing(
                        address(erc721),
                        tokenId,
                        address(0),
                        1 ether,
                        address(0),
                        address(0),
                        0,
                        0,
                        0,
                        false,
                        false,
                        new address[](0)
                    );
                } else {
                    vm.prank(user2);
                    try market.createListing(
                        address(erc721),
                        tokenId,
                        address(0),
                        1 ether,
                        address(0),
                        address(0),
                        0,
                        0,
                        0,
                        false,
                        false,
                        new address[](0)
                    ) {} catch {}
                }
            } else if (action == 2) {
                uint256 newPrice = 1 ether + ((actionSeed >> 16) % 2 ether);

                if (expectedPaused) {
                    vm.prank(user1);
                    vm.expectRevert(IdeationMarket__ContractPaused.selector);
                    market.updateListing(
                        listingId, newPrice, address(0), address(0), 0, 0, 0, false, false, new address[](0)
                    );
                } else {
                    vm.prank(user1);
                    try market.updateListing(
                        listingId, newPrice, address(0), address(0), 0, 0, 0, false, false, new address[](0)
                    ) {} catch {}
                }
            } else {
                vm.deal(user2, 1 ether);
                if (expectedPaused) {
                    vm.prank(user2);
                    vm.expectRevert(IdeationMarket__ContractPaused.selector);
                    market.purchaseListing{value: 1 ether}(
                        listingId, 2 ether, address(0), 0, address(0), 0, 0, 0, address(0)
                    );
                } else {
                    vm.prank(user2);
                    try market.purchaseListing{value: 1 ether}(
                        listingId, 2 ether, address(0), 0, address(0), 0, 0, 0, address(0)
                    ) {} catch {}
                }
            }

            assertEq(getter.isPaused(), expectedPaused, "pause state drifted from expected sequence state");
        }
    }

    /// @notice Fuzz test: pause guards hold across listing modes (ETH/ERC20, ERC721/ERC1155, whitelist/partial).
    /// forge-config: default.fuzz.runs = 1024
    function testFuzz_PauseGuardsAcrossListingModes(
        bool useERC20,
        bool useERC1155,
        bool partialBuyEnabled,
        bool buyerWhitelistEnabled,
        uint96 priceSeed,
        uint16 qtySeed
    ) public {
        uint256 price = uint256(bound(priceSeed, 1e12, 10 ether));
        uint256 erc1155Qty = uint256(bound(qtySeed, 2, 10));

        bool partialMode = useERC1155 && partialBuyEnabled;
        if (partialMode) {
            price = erc1155Qty * uint256(bound(priceSeed, 1e12, 1 ether));
        }

        address currency = address(0);
        MockERC20 token;
        if (useERC20) {
            token = new MockERC20("Pause Fuzz Token", "PFT");
            currency = address(token);
            vm.prank(owner);
            currencies.addAllowedCurrency(currency);

            token.mint(user2, 1_000_000 ether);
            vm.prank(user2);
            token.approve(address(diamond), type(uint256).max);
        }

        address[] memory allowedBuyers = buyerWhitelistEnabled ? new address[](1) : new address[](0);
        if (buyerWhitelistEnabled) {
            allowedBuyers[0] = user2;
        }

        uint128 listingId;
        if (useERC1155) {
            vm.prank(seller);
            erc1155.mint(user1, 99, erc1155Qty);

            vm.startPrank(user1);
            erc1155.setApprovalForAll(address(diamond), true);
            market.createListing(
                address(erc1155),
                99,
                user1,
                price,
                currency,
                address(0),
                0,
                0,
                erc1155Qty,
                buyerWhitelistEnabled,
                partialMode,
                allowedBuyers
            );
            listingId = getter.getNextListingId() - 1;
            vm.stopPrank();
        } else {
            uint256 tokenId = 20 + (uint256(priceSeed) % 10000);
            vm.prank(seller);
            erc721.mint(user1, tokenId);

            vm.startPrank(user1);
            erc721.approve(address(diamond), tokenId);
            market.createListing(
                address(erc721),
                tokenId,
                address(0),
                price,
                currency,
                address(0),
                0,
                0,
                0,
                buyerWhitelistEnabled,
                false,
                allowedBuyers
            );
            listingId = getter.getNextListingId() - 1;
            vm.stopPrank();
        }

        vm.prank(owner);
        pauseFacet.pause();
        assertTrue(getter.isPaused(), "pause state should be true after owner pause");

        // Create should be blocked while paused.
        vm.prank(seller);
        erc721.mint(attacker, 4242);
        vm.prank(attacker);
        erc721.approve(address(diamond), 4242);
        vm.prank(attacker);
        vm.expectRevert(IdeationMarket__ContractPaused.selector);
        market.createListing(
            address(erc721), 4242, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );

        // Update should be blocked while paused.
        vm.prank(user1);
        vm.expectRevert(IdeationMarket__ContractPaused.selector);
        market.updateListing(
            listingId,
            price + 1,
            currency,
            address(0),
            0,
            0,
            useERC1155 ? erc1155Qty : 0,
            buyerWhitelistEnabled,
            partialMode,
            allowedBuyers
        );

        // Purchase should be blocked while paused.
        uint256 purchaseQty = useERC1155 ? uint256(bound(qtySeed, 1, erc1155Qty)) : 0;
        vm.deal(user2, 10 ether);
        vm.prank(user2);
        vm.expectRevert(IdeationMarket__ContractPaused.selector);
        market.purchaseListing{value: useERC20 ? 0 : price}(
            listingId, price, currency, useERC1155 ? erc1155Qty : 0, address(0), 0, 0, purchaseQty, address(0)
        );

        // Seller exit path must remain available while paused.
        vm.prank(user1);
        market.cancelListing(listingId);
    }
}
