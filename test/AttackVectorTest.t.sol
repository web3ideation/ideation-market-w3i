// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

/**
 * @title AttackVectorTest
 * @notice Comprehensive security and attack vector testing for the IdeationMarket
 * @dev Consolidates all security-focused tests from across the test suite including:
 *
 * ┌─────────────────────────────────────────────────────────────┐
 * │ REENTRANCY ATTACKS                                          │
 * ├─────────────────────────────────────────────────────────────┤
 * │ • Reentrancy via ERC721 receiver hooks                      │
 * │ • Reentrancy via ERC1155 receiver hooks                     │
 * │ • Double-sell prevention                                    │
 * └─────────────────────────────────────────────────────────────┘
 *
 * ┌─────────────────────────────────────────────────────────────┐
 * │ MALICIOUS TOKEN CONTRACTS                                   │
 * ├─────────────────────────────────────────────────────────────┤
 * │ • Liar tokens (claim ERC165 but break transfer)             │
 * │ • Admin escalation attempts during transfer                 │
 * │ • Receiver hooks that swallow reverts                       │
 * └─────────────────────────────────────────────────────────────┘
 *
 * ┌─────────────────────────────────────────────────────────────┐
 * │ TOKEN BURN ATTACK VECTORS                                   │
 * ├─────────────────────────────────────────────────────────────┤
 * │ • Clean/cancel after ERC721 burn                            │
 * │ • Clean/cancel after ERC1155 burn                           │
 * │ • Purchase attempts after burn                              │
 * │ • Partial burns leaving insufficient balance                │
 * └─────────────────────────────────────────────────────────────┘
 *
 * ┌─────────────────────────────────────────────────────────────┐
 * │ AUTHORIZATION BYPASS ATTEMPTS                               │
 * ├─────────────────────────────────────────────────────────────┤
 * │ • Malicious initializer escalation                          │
 * │ • Reentrancy-driven side-effect attempts during             │
 * │   cancel/clean query hooks                                  │
 * └─────────────────────────────────────────────────────────────┘
 *
 * @custom:security-critical All tests in this file validate critical security properties
 * @custom:audit-focus Primary file for security audits
 */
contract AttackVectorTest is MarketTestBase {
    // =========================================================================
    // REENTRANCY ATTACKS
    // =========================================================================

    /// @notice Seller-side reentrancy attempt during ETH payout must be blocked.
    /// @dev Attack vector: seller is a contract; its receive() tries to purchase another listing.
    /// Expected: reentrant purchaseListing call fails (nonReentrant), original purchase succeeds.
    function testReentrancy_SellerReceive_CannotReenterPurchase() public {
        StrictERC721 s = new StrictERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(s));

        // Listing B (target of reentry): normal seller lists tokenId=2
        s.mint(seller, 2);
        vm.prank(seller);
        s.approve(address(diamond), 2);

        uint256 priceB = 0.5 ether;
        vm.prank(seller);
        market.createListing(
            address(s), 2, address(0), priceB, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 listingB = getter.getNextListingId() - 1;

        // Listing A: seller is a contract that will try to reenter during payout
        SellerReenterOnReceive sellerContract = new SellerReenterOnReceive(address(market));
        s.mint(address(sellerContract), 1);

        uint256 priceA = 1 ether;
        uint128 listingA = sellerContract.approveAndListERC721(address(diamond), address(s), 1, priceA);

        // Configure the reentry attempt to buy listingB.
        sellerContract.setReentryTarget(listingB, priceB);

        // Prefund the seller contract so it can attempt a full-price reentrant purchase.
        vm.deal(address(sellerContract), 10 ether);

        // Snapshot balances
        uint256 sellerContractBalBefore = address(sellerContract).balance;
        uint256 ownerBalBefore = owner.balance;

        // Buyer purchases listingA; during payout sellerContract.receive() attempts reentrancy.
        vm.deal(buyer, priceA);
        vm.prank(buyer);
        market.purchaseListing{value: priceA}(listingA, priceA, address(0), 0, address(0), 0, 0, 0, address(0));

        // Reentry attempt happened and failed (must not succeed)
        assertTrue(sellerContract.attempted(), "seller did not attempt reentry");
        assertTrue(sellerContract.reentryFailed(), "reentry did not fail as expected");

        // ListingA consumed; buyer owns tokenId=1
        assertEq(s.ownerOf(1), buyer);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingA));
        getter.getListingByListingId(listingA);

        // ListingB should still exist (reentrant purchase did NOT go through)
        Listing memory lb = getter.getListingByListingId(listingB);
        assertEq(lb.price, priceB);
        assertEq(s.ownerOf(2), seller);

        // Seller contract got paid proceeds; owner got fee
        uint256 fee = (priceA * getter.getInnovationFee()) / 100_000;
        assertEq(owner.balance - ownerBalBefore, fee, "owner fee mismatch");
        assertEq(address(sellerContract).balance - sellerContractBalBefore, priceA - fee, "seller proceeds mismatch");
    }

    /// @notice If seller cannot receive ETH, purchase must revert atomically (no partial state changes).
    function testSellerReceive_Reverts_PurchaseRevertsAtomically() public {
        StrictERC721 s = new StrictERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(s));

        SellerRevertOnReceive badSeller = new SellerRevertOnReceive(address(market));
        s.mint(address(badSeller), 1);

        uint256 price = 1 ether;
        uint128 listingId = badSeller.approveAndListERC721(address(diamond), address(s), 1, price);
        uint256 ownerBalBefore = owner.balance;

        vm.deal(buyer, price);
        uint256 buyerBalBefore = buyer.balance;
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__EthTransferFailed.selector, address(badSeller)));
        market.purchaseListing{value: price}(listingId, price, address(0), 0, address(0), 0, 0, 0, address(0));

        // Listing should remain (tx reverted)
        Listing memory L = getter.getListingByListingId(listingId);
        assertEq(L.price, price);
        assertEq(s.ownerOf(1), address(badSeller));

        // No ETH moved to owner
        assertEq(owner.balance, ownerBalBefore);
        // Buyer ETH unchanged (value is refunded on revert; forge default gas price is 0)
        assertEq(buyer.balance, buyerBalBefore);
    }

    /// @notice CRITICAL: Tests that purchaseListing cannot be reentered from ERC721 receiver hook
    /// @dev Attack vector: onERC721Received tries to call purchaseListing again
    /// Expected: Reentrancy guard blocks the second call, only one purchase succeeds
    function testReentrancy_BuyerReceiver_ERC721_Strict() public {
        StrictERC721 s = new StrictERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(s));

        s.mint(seller, 1);
        vm.prank(seller);
        s.approve(address(diamond), 1);

        uint256 price = 1 ether;
        vm.prank(seller);
        market.createListing(
            address(s), 1, address(0), price, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        ReenteringReceiver721 recv = new ReenteringReceiver721(address(market), id, price);
        vm.deal(address(recv), 2 * price); // fund for reentrant attempt

        // Snapshot balances before purchase
        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;

        // Initial purchase by the receiver; its hook tries to reenter and must fail
        vm.prank(address(recv));
        market.purchaseListing{value: price}(id, price, address(0), 0, address(0), 0, 0, 0, address(0));

        // Single sale only - reentrancy was blocked
        assertEq(s.ownerOf(1), address(recv));
        assertEq(recv.reentryRevertSelector(), IdeationMarket__Reentrant.selector);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);

        // Verify atomic payment - seller and owner received funds
        assertEq(seller.balance - sellerBalBefore, price * 99 / 100);
        assertEq(owner.balance - ownerBalBefore, price * 1 / 100);
    }

    /// @notice CRITICAL: Tests that purchaseListing cannot be reentered from ERC1155 receiver hook
    /// @dev Attack vector: onERC1155Received tries to call purchaseListing again
    /// Expected: Reentrancy guard blocks the second call, only one purchase succeeds
    function testReentrancy_BuyerReceiver_ERC1155_Strict() public {
        StrictERC1155 s = new StrictERC1155();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(s));

        uint256 tid = 7;
        uint256 qty = 5;
        uint256 price = 5 ether;

        s.mint(seller, tid, qty);
        vm.prank(seller);
        s.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(s), tid, seller, price, address(0), address(0), 0, 0, qty, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        ReenteringReceiver1155 recv = new ReenteringReceiver1155(address(market), id, price, qty);
        vm.deal(address(recv), 2 * price); // fund for reentrant attempt

        // Snapshot balances before purchase
        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;

        vm.prank(address(recv));
        market.purchaseListing{value: price}(id, price, address(0), qty, address(0), 0, 0, qty, address(0));

        // Single sale only - reentrancy was blocked
        assertEq(s.balanceOf(address(recv), tid), qty);
        assertEq(recv.reentryRevertSelector(), IdeationMarket__Reentrant.selector);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);

        // Verify atomic payment - seller and owner received funds
        assertEq(seller.balance - sellerBalBefore, price * 99 / 100);
        assertEq(owner.balance - ownerBalBefore, price * 1 / 100);
    }

    /// @notice Double-sell prevention: after first ERC721 sale, second purchase must revert
    function testDoubleSell_Prevented_ERC721_Strict() public {
        StrictERC721 s = new StrictERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(s));

        s.mint(seller, 1);
        vm.prank(seller);
        s.approve(address(diamond), 1);

        uint256 price = 1 ether;
        vm.prank(seller);
        market.createListing(
            address(s), 1, address(0), price, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, price);
        vm.prank(buyer);
        market.purchaseListing{value: price}(id, price, address(0), 0, address(0), 0, 0, 0, address(0));

        address buyer2 = vm.addr(0xBEEF);
        vm.deal(buyer2, price);
        vm.startPrank(buyer2);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__NotListed.selector));
        market.purchaseListing{value: price}(id, price, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    /// @notice Double-sell prevention: after full ERC1155 fill, second purchase must revert
    function testDoubleSell_Prevented_ERC1155_FullFill_Strict() public {
        StrictERC1155 s = new StrictERC1155();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(s));

        uint256 tid = 9;
        uint256 qty = 6;
        uint256 price = 6 ether;

        s.mint(seller, tid, qty);
        vm.prank(seller);
        s.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(s), tid, seller, price, address(0), address(0), 0, 0, qty, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, price);
        vm.prank(buyer);
        market.purchaseListing{value: price}(id, price, address(0), qty, address(0), 0, 0, qty, address(0));

        address buyer2 = vm.addr(0xC0DE);
        vm.deal(buyer2, price);
        vm.startPrank(buyer2);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__NotListed.selector));
        market.purchaseListing{value: price}(id, price, address(0), qty, address(0), 0, 0, qty, address(0));
        vm.stopPrank();
    }

    /// @notice CRITICAL: Malicious listed ERC1155 attempts reentrancy during transfer to buyer
    /// @dev Attack vector: Seller's token contract tries to reenter purchaseListing during safeTransferFrom
    /// Expected: Reentrancy guard blocks the attempt, transfer completes successfully
    function testReentrancy_MaliciousERC1155Listed_Succeeds_NoReentrancy() public {
        // Deploy malicious 1155 bound to this diamond
        MaliciousERC1155 m1155 = new MaliciousERC1155(address(diamond));

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(m1155));
        vm.stopPrank();

        uint256 id = 909;
        uint256 qty = 5;
        uint256 price = 1 ether;

        m1155.mint(seller, id, qty);

        vm.prank(seller);
        m1155.setApprovalForAll(address(diamond), true);

        // List qty=5 for 1 ETH
        vm.prank(seller);
        market.createListing(
            address(m1155), id, seller, price, address(0), address(0), 0, 0, qty, false, false, new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        // Snapshot balances before purchase
        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;

        vm.deal(buyer, price);
        vm.prank(buyer);
        market.purchaseListing{value: price}(listingId, price, address(0), qty, address(0), 0, 0, qty, address(0));

        // Buyer received all 5; reentrancy attempt was blocked by guard
        assertEq(m1155.balanceOf(buyer, id), qty);

        // Verify atomic payment - seller and owner received funds
        assertEq(seller.balance - sellerBalBefore, price * 99 / 100);
        assertEq(owner.balance - ownerBalBefore, price * 1 / 100);

        // Listing consumed
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingId));
        getter.getListingByListingId(listingId);
    }

    /// @notice CRITICAL: Malicious desired ERC1155 (in swap) attempts reentrancy during transfer to seller
    /// @dev Attack vector: Buyer's swap token tries to reenter purchaseListing during safeTransferFrom
    /// Expected: Reentrancy guard blocks the attempt, swap completes successfully
    function testReentrancy_MaliciousERC1155Desired_Succeeds_NoReentrancy() public {
        // Listed side uses regular erc1155; desired side is malicious
        MaliciousERC1155 m1155 = new MaliciousERC1155(address(diamond));

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        collections.addWhitelistedCollection(address(m1155));
        vm.stopPrank();

        uint256 idListed = 1001;
        uint256 idDesired = 2002;
        uint256 qtyListed = 2;
        uint256 qtyDesired = 1;
        uint256 price = 0.25 ether;

        erc1155.mint(seller, idListed, 10);
        m1155.mint(buyer, idDesired, 5);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);
        vm.prank(buyer);
        m1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155),
            idListed,
            seller,
            price,
            address(0), // currency (ETH)
            address(m1155),
            idDesired,
            qtyDesired,
            qtyListed,
            false,
            false,
            new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        // Snapshot balances before swap
        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;

        vm.deal(buyer, price);
        vm.prank(buyer);
        market.purchaseListing{value: price}(
            listingId, price, address(0), qtyListed, address(m1155), idDesired, qtyDesired, qtyListed, buyer
        );

        // Transfer should have succeeded despite malicious hook attempting reentrancy
        assertEq(erc1155.balanceOf(buyer, idListed), qtyListed);
        assertEq(m1155.balanceOf(seller, idDesired), qtyDesired);

        // Verify atomic payment - seller and owner received funds
        assertEq(seller.balance - sellerBalBefore, price * 99 / 100);
        assertEq(owner.balance - ownerBalBefore, price * 1 / 100);

        // Listing consumed
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingId));
        getter.getListingByListingId(listingId);
    }

    /// @notice Reentrancy via ERC20 transfer hook is blocked while preserving listing state integrity
    function testReentrancy_ERC20PaymentPath_CaughtAndBlocked_NoExtraListingConsumed() public {
        ReentrantERC20Catching token = new ReentrantERC20Catching(address(diamond));

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(erc721));
        currencies.addAllowedCurrency(address(token));
        vm.stopPrank();

        vm.startPrank(seller);
        erc721.approve(address(diamond), 1);
        erc721.approve(address(diamond), 2);

        market.createListing(
            address(erc721), 2, address(0), 1 ether, address(token), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 listingB = getter.getNextListingId() - 1;

        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(token), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 listingA = getter.getNextListingId() - 1;
        vm.stopPrank();

        token.setTarget(listingB, 1 ether);
        token.mint(buyer, 2 ether);

        uint128 nextBefore = getter.getNextListingId();

        vm.startPrank(buyer);
        token.approve(address(diamond), 2 ether);
        market.purchaseListing(listingA, 1 ether, address(token), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        assertTrue(token.attempted(), "erc20 reentry attempt not observed");
        assertEq(token.reentryRevertSelector(), IdeationMarket__Reentrant.selector);

        assertEq(erc721.ownerOf(1), buyer);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingA));
        getter.getListingByListingId(listingA);

        Listing memory lb = getter.getListingByListingId(listingB);
        assertEq(lb.price, 1 ether);
        assertEq(erc721.ownerOf(2), seller);

        assertEq(getter.getNextListingId(), nextBefore, "unexpected listing state delta");
    }

    /// @notice Reentrant attempt from ERC721 getApproved hook cannot cancel unrelated listing
    function testReentrancy_CancelListing_QueryHook_CannotCancelOtherListing() public {
        ReentrantQueryHookERC721 hookToken = new ReentrantQueryHookERC721(address(market));

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(hookToken));
        collections.addWhitelistedCollection(address(erc721));
        vm.stopPrank();

        vm.startPrank(seller);
        erc721.approve(address(diamond), 2);
        market.createListing(
            address(erc721), 2, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 listingB = getter.getNextListingId() - 1;

        hookToken.mint(seller, 11);
        hookToken.setApprovalForAll(operator, true);
        hookToken.approve(address(diamond), 11);
        market.createListing(
            address(hookToken), 11, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 listingA = getter.getNextListingId() - 1;
        vm.stopPrank();

        hookToken.setReentryMode(1, listingB);
        uint128 nextBefore = getter.getNextListingId();

        vm.prank(operator);
        market.cancelListing(listingA);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingA));
        getter.getListingByListingId(listingA);

        Listing memory lb = getter.getListingByListingId(listingB);
        assertEq(lb.price, 1 ether);
        assertEq(erc721.ownerOf(2), seller);

        assertEq(getter.getNextListingId(), nextBefore, "unexpected listing state delta");
    }

    /// @notice Reentrant attempt from ERC721 ownerOf hook cannot clean unrelated valid listing
    function testReentrancy_CleanListing_QueryHook_CannotCleanOtherValidListing() public {
        ReentrantQueryHookERC721 hookToken = new ReentrantQueryHookERC721(address(market));

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(hookToken));
        collections.addWhitelistedCollection(address(erc721));
        vm.stopPrank();

        vm.startPrank(seller);
        erc721.mint(seller, 3);
        erc721.approve(address(diamond), 3);
        market.createListing(
            address(erc721), 3, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 listingB = getter.getNextListingId() - 1;

        hookToken.mint(seller, 21);
        hookToken.approve(address(diamond), 21);
        market.createListing(
            address(hookToken), 21, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 listingA = getter.getNextListingId() - 1;

        hookToken.transferFrom(seller, operator, 21);
        vm.stopPrank();

        hookToken.setReentryMode(2, listingB);
        uint128 nextBefore = getter.getNextListingId();

        vm.prank(buyer);
        market.cleanListing(listingA);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingA));
        getter.getListingByListingId(listingA);

        Listing memory lb = getter.getListingByListingId(listingB);
        assertEq(lb.price, 1 ether);
        assertEq(erc721.ownerOf(3), seller);

        assertEq(getter.getNextListingId(), nextBefore, "unexpected listing state delta");
    }

    // =========================================================================
    // MALICIOUS TOKEN CONTRACTS
    // =========================================================================

    /// @notice Liar token: Claims ERC165 ERC721 support but reverts on transfer
    /// Expected: Purchase reverts, listing remains intact, no state changes
    function testERC721_LiarToken_TransferReverts_RollsBackListing() public {
        LiarERC721 liar = new LiarERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(liar));

        liar.mint(seller, 1);
        vm.prank(seller);
        liar.approve(address(diamond), 1);

        uint256 price = 1 ether;
        vm.prank(seller);
        market.createListing(
            address(liar), 1, address(0), price, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, price);
        vm.startPrank(buyer);
        vm.expectRevert(bytes("liar721: transfer breaks"));
        market.purchaseListing{value: price}(id, price, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // No state moved
        assertEq(liar.ownerOf(1), seller);
        Listing memory L = getter.getListingByListingId(id);
        assertEq(L.price, price);
    }

    /// @notice Liar token: Claims ERC165 ERC1155 support but reverts on transfer
    /// Expected: Purchase reverts, listing remains intact, no state changes
    function testERC1155_LiarToken_TransferReverts_RollsBackListing() public {
        LiarERC1155 liar = new LiarERC1155();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(liar));

        uint256 tid = 3;
        uint256 qty = 4;
        uint256 price = 4 ether;

        liar.mint(seller, tid, qty);
        vm.prank(seller);
        liar.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(liar), tid, seller, price, address(0), address(0), 0, 0, qty, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, price);
        vm.startPrank(buyer);
        vm.expectRevert(bytes("liar1155: transfer breaks"));
        market.purchaseListing{value: price}(id, price, address(0), qty, address(0), 0, 0, qty, address(0));
        vm.stopPrank();

        // No state moved
        assertEq(liar.balanceOf(seller, tid), qty);
        Listing memory L = getter.getListingByListingId(id);
        assertEq(L.price, price);
        assertEq(L.erc1155Quantity, qty);
    }

    /// @notice Malformed ERC165 responses must not allow listing creation
    function testMalformedERC165Response_RevertsListingCreation_NoStateDelta() public {
        MalformedERC165ERC721 malformed = new MalformedERC165ERC721();

        vm.prank(owner);
        collections.addWhitelistedCollection(address(malformed));

        malformed.mint(seller, 77);
        vm.prank(seller);
        malformed.approve(address(diamond), 77);

        uint128 nextBefore = getter.getNextListingId();

        vm.prank(seller);
        vm.expectRevert();
        market.createListing(
            address(malformed), 77, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );

        assertEq(getter.getNextListingId(), nextBefore, "listing id advanced on malformed ERC165");
    }

    /// @notice Malicious token attempts to call setInnovationFee during transfer
    /// Expected: Admin call reverts, purchase succeeds, fee unchanged
    function testAdminCallDuringTransfer_DoesNotBypassOnlyOwner_ERC721() public {
        MaliciousAdminERC721 m = new MaliciousAdminERC721(address(market));
        vm.prank(owner);
        collections.addWhitelistedCollection(address(m));

        m.mint(seller, 1);
        vm.prank(seller);
        m.approve(address(diamond), 1);

        uint32 feeBefore = getter.getInnovationFee();
        uint256 price = 1 ether;

        vm.prank(seller);
        market.createListing(
            address(m), 1, address(0), price, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, price);
        vm.prank(buyer);
        market.purchaseListing{value: price}(id, price, address(0), 0, address(0), 0, 0, 0, address(0));

        // Transfer succeeded; fee unchanged
        assertEq(getter.getInnovationFee(), feeBefore);
        assertEq(m.ownerOf(1), buyer);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// @notice Post-purchase transfer to a swallowing ERC721 receiver still preserves normal transfer semantics
    function testERC721ReceiverSwallowsRevert_DoesNotMaskMarketplaceChecks() public {
        _whitelistCollectionAndApproveERC721();
        SwallowingERC721Receiver recv = new SwallowingERC721Receiver();

        // list and sell to receiver
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        // Then send to receiver via normal transfer to assert hook didn't break semantics
        vm.prank(buyer);
        erc721.safeTransferFrom(buyer, address(recv), 1);

        assertEq(erc721.ownerOf(1), address(recv));
    }

    /// @notice ERC721 swallowing receiver can be the direct marketplace buyer without masking purchase flow
    function testReceiverHooksThatSwallowReverts_ERC721_DuringMarketplaceTransfer() public {
        _whitelistCollectionAndApproveERC721();

        // Mint + approve a fresh token for direct marketplace delivery to a swallowing receiver
        erc721.mint(seller, 99);
        vm.prank(seller);
        erc721.approve(address(diamond), 99);

        vm.prank(seller);
        market.createListing(
            address(erc721), 99, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        SwallowingERC721Receiver rcvr = new SwallowingERC721Receiver();
        vm.deal(address(rcvr), 1 ether);

        // Buy as the receiver so onERC721Received executes inside marketplace purchase flow
        vm.prank(address(rcvr));
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        assertEq(erc721.ownerOf(99), address(rcvr));
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// @notice ERC1155 swallowing receiver does not block marketplace delivery during purchase flow
    function testReceiverHooksThatSwallowReverts_ERC1155() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        erc1155.mint(seller, 55, 5);
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155), 55, seller, 5 ether, address(0), address(0), 0, 0, 5, false, true, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        SwallowingERC1155Receiver rcvr = new SwallowingERC1155Receiver();
        vm.deal(address(rcvr), 10 ether);

        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;

        // Buy all 5 to receiver; its hook swallows internal errors but returns selector
        vm.prank(address(rcvr));
        market.purchaseListing{value: 5 ether}(id, 5 ether, address(0), 5, address(0), 0, 0, 5, address(0));

        assertEq(erc1155.balanceOf(address(rcvr), 55), 5);
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);

        assertGt(seller.balance, sellerBalBefore, "seller did not receive proceeds");
        assertEq(owner.balance + seller.balance, ownerBalBefore + sellerBalBefore + 5 ether, "payment mismatch");
    }

    // =========================================================================
    // TOKEN BURN ATTACK VECTORS
    // =========================================================================

    /// @notice Clean listing after ERC721 burn by third party
    function testCleanListingAfterERC721BurnByThirdUser() public {
        uint128 id = _createListingERC721(false, new address[](0));

        // "Burn" by transferring to address(0) — clears per-token approval in the mock
        vm.prank(seller);
        erc721.transferFrom(seller, address(0), 1);

        // Any third party may clean an invalid listing
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(id, address(erc721), 1, seller, operator);

        vm.prank(operator);
        market.cleanListing(id);

        // Listing removed
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// @notice Owner can cancel listing after ERC721 burn
    function testCancelListingAfterERC721BurnByOwner() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.prank(seller);
        erc721.transferFrom(seller, address(0), 1); // burn

        // Diamond owner can cancel any listing, even after burn
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceled(id, address(erc721), 1, seller, owner);

        vm.prank(owner);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// @notice Seller can cancel their own listing after ERC721 burn
    function testCancelListingAfterERC721BurnBySeller() public {
        uint128 id = _createListingERC721(false, new address[](0));

        vm.prank(seller);
        erc721.transferFrom(seller, address(0), 1); // burn

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceled(id, address(erc721), 1, seller, seller);

        vm.prank(seller);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// @notice Operator-for-all can cancel listing after ERC721 burn
    function testCancelListingAfterERC721BurnByOperatorForAll() public {
        uint128 id = _createListingERC721(false, new address[](0));

        // Grant blanket operator rights (NOT the marketplace; a real operator)
        vm.prank(seller);
        erc721.setApprovalForAll(operator, true);

        // Burn after listing
        vm.prank(seller);
        erc721.transferFrom(seller, address(0), 1);

        // Operator-for-all may cancel on behalf of the (former) seller
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceled(id, address(erc721), 1, seller, operator);

        vm.prank(operator);
        market.cancelListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// @notice Purchase must revert after ERC721 is burned
    function testPurchaseRevertsAfterERC721Burn() public {
        _whitelistCollectionAndApproveERC721();

        // Create listing: ERC721 #1, price = 1 ETH
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // "Burn" token by sending to the zero address (owner becomes address(0))
        vm.prank(seller);
        erc721.transferFrom(seller, address(0), 1);

        // Buyer attempts purchase → must revert with SellerNotTokenOwner(listingId)
        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__SellerNotTokenOwner.selector, id));
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }

    /// @notice Clean listing after ERC1155 full burn by third party
    function testCleanListingAfterERC1155BurnAllByThirdUser() public {
        // Whitelist & approve marketplace for ERC1155
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // IMPORTANT: seller has 10 units from setUp(); list all 10 so a full burn invalidates the listing
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Burn all 10 units by sending to the zero address -> seller balance becomes 0 (< listed 10)
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, address(0), 1, 10, "");

        // revoke approval; listing is already invalid so cleanListing will cancel either way.
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), false);

        // Third party can now clean the invalid listing
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(id, address(erc1155), 1, seller, operator);

        vm.prank(operator);
        market.cleanListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// @notice ERC1155 partial burn leaving less than listed → purchase reverts, then clean
    function testERC1155PartialBurnBelowListed_PurchaseRevertsThenClean() public {
        // Whitelist & approve
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // Seller has 10 of id=1 from setUp. List qty=10, price=10 ETH.
        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Burn 7 → seller balance becomes 3 (< 10 listed)
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, address(0), 1, 7, "");

        // Purchase (attempt to buy all 10) → must revert with SellerInsufficientTokenBalance(10, 3)
        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(IdeationMarket__SellerInsufficientTokenBalance.selector, 10, 3));
        market.purchaseListing{value: 10 ether}(id, 10 ether, address(0), 10, address(0), 0, 0, 10, address(0));
        vm.stopPrank();

        // Revoke marketplace approval or cleanListing will revert with StillApproved
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), false);

        // Third party can clean the invalid listing
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(id, address(erc1155), 1, seller, operator);

        vm.prank(operator);
        market.cleanListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// @notice Clean listing after balance drift (transfer) while approval intact
    function testCleanListingERC1155_BalanceDrift_ApprovalIntact_Cancels() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        // Seller lists qty=10 of id=77; approval to marketplace is TRUE.
        uint256 id1155 = 77;
        uint256 listedQty = 10;
        erc1155.mint(seller, id1155, listedQty);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        // Non-zero price to avoid FreeListingsNotSupported
        vm.prank(seller);
        market.createListing(
            address(erc1155),
            id1155,
            seller,
            10 ether,
            address(0),
            address(0),
            0,
            0,
            listedQty,
            false,
            false,
            new address[](0)
        );
        uint128 listingId = getter.getNextListingId() - 1;

        // Drift: seller moves 6 away → remaining 4 (< 10); approval STILL true.
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, buyer, id1155, 6, "");

        // Expect cancellation event, then anyone can clean.
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCanceledDueToInvalidListing(
            listingId, address(erc1155), id1155, seller, operator
        );

        vm.prank(operator);
        market.cleanListing(listingId);

        // Listing is gone.
        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, listingId));
        getter.getListingByListingId(listingId);
    }

    /// @notice Balance drift via burn (approval intact) triggers cancellation
    function testCleanListingERC1155_BalanceDrift_ApprovalIntact_Cancels_BurnVariant() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));

        uint256 tid = 600;
        uint256 listedQty = 8;
        erc1155.mint(seller, tid, 10);

        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        vm.prank(seller);
        market.createListing(
            address(erc1155),
            tid,
            seller,
            1 wei,
            address(0),
            address(0),
            0,
            0,
            listedQty,
            false,
            false,
            new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Burn 5 units so remaining = 5 (< 8).
        vm.prank(seller);
        erc1155.safeTransferFrom(seller, address(0), tid, 5, "");

        vm.prank(operator);
        market.cleanListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    /// @notice Clean listing after off-market transfer (owner changed, approval intact)
    function testCleanListingCancelsAfterOwnerChangedOffMarket() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Off-market transfer to some other address; marketplace approval on seller is now meaningless
        vm.prank(seller);
        erc721.transferFrom(seller, operator, 1);

        // Anyone can clean invalid listing
        vm.prank(buyer);
        market.cleanListing(id);

        vm.expectRevert(abi.encodeWithSelector(Getter__ListingNotFound.selector, id));
        getter.getListingByListingId(id);
    }

    // =========================================================================
    // AUTHORIZATION BYPASS ATTEMPTS
    // =========================================================================

    /// @notice Malicious initializer cannot escalate privileges during upgradeDiamond
    function testUpgradeDiamond_MaliciousInitializerCannotEscalate() public {
        address ownerBefore = IERC173(address(diamond)).owner();
        uint32 feeBefore = getter.getInnovationFee();

        MaliciousInitTryAdmin bad = new MaliciousInitTryAdmin();

        // The initializer swallows its own failures and returns successfully.
        // upgradeDiamond should succeed, but state (owner/fee) must be unchanged.
        _upgradeNoopWithInit(
            address(bad),
            abi.encodeWithSelector(MaliciousInitTryAdmin.initTryAdmin.selector, vm.addr(0xBEEF), uint32(999_999))
        );

        assertEq(IERC173(address(diamond)).owner(), ownerBefore, "owner changed via initializer");
        assertEq(getter.getInnovationFee(), feeBefore, "fee changed via initializer");
    }
}
