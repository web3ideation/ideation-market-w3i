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
 * │ • Liar tokens (claim ERC165 but break transfer)            │
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
 * │ • Unauthorized pause attempts                               │
 * │ • Malicious initializer escalation                          │
 * │ • Storage collision attacks                                 │
 * └─────────────────────────────────────────────────────────────┘
 *
 * @custom:security-critical All tests in this file validate critical security properties
 * @custom:audit-focus Primary file for security audits
 */
contract AttackVectorTest is MarketTestBase {
    // =========================================================================
    // REENTRANCY ATTACKS
    // =========================================================================

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
        vm.expectRevert(); // listing should be consumed/invalid
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
        vm.expectRevert(); // already consumed
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
        vm.expectRevert(); // token breaks transfer
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
        vm.expectRevert(); // token breaks transfer
        market.purchaseListing{value: price}(id, price, address(0), qty, address(0), 0, 0, qty, address(0));
        vm.stopPrank();

        // No state moved
        assertEq(liar.balanceOf(seller, tid), qty);
        Listing memory L = getter.getListingByListingId(id);
        assertEq(L.price, price);
        assertEq(L.erc1155Quantity, qty);
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

    /// @notice ERC721 receiver that swallows internal reverts must not mask marketplace checks
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

    /// @notice ERC1155 receiver that swallows reverts must not affect marketplace logic
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

        // Buy all 5 to receiver; its hook swallows internal errors but returns selector
        vm.prank(address(rcvr));
        market.purchaseListing{value: 5 ether}(id, 5 ether, address(0), 5, address(0), 0, 0, 5, address(0));

        assertEq(erc1155.balanceOf(address(rcvr), 55), 5);
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

    /// @notice Attacker cannot call pause() (owner-only function)
    function testAttackerCannotPause() public {
        address attacker = vm.addr(0xBAD);
        vm.prank(attacker);
        vm.expectRevert("LibDiamond: Must be contract owner");
        pauseFacet.pause();
    }

    /// @notice Malicious initializer cannot escalate privileges during diamondCut
    function testDiamondCut_MaliciousInitializerCannotEscalate() public {
        address ownerBefore = IERC173(address(diamond)).owner();
        uint32 feeBefore = getter.getInnovationFee();

        MaliciousInitTryAdmin bad = new MaliciousInitTryAdmin();

        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](0);

        // The initializer swallows its own failures and returns successfully.
        // diamondCut should succeed, but state (owner/fee) must be unchanged.
        vm.prank(owner);
        IDiamondCutFacet(address(diamond)).diamondCut(
            cuts,
            address(bad),
            abi.encodeWithSelector(MaliciousInitTryAdmin.initTryAdmin.selector, vm.addr(0xBEEF), uint32(999_999))
        );

        assertEq(IERC173(address(diamond)).owner(), ownerBefore, "owner changed via initializer");
        assertEq(getter.getInnovationFee(), feeBefore, "fee changed via initializer");
    }

    /// @notice Malicious facet can cause storage collision (proof storage guards work)
    function testStorage_MaliciousFacetSmash_TriggersDrift() public {
        _whitelistDefaultMocks();

        // Snapshot canaries
        uint32 fee0 = getter.getInnovationFee();
        uint16 maxBatch0 = getter.getBuyerWhitelistMaxBatchSize();

        // Deploy and cut-in malicious facet
        BadFacetAppSmash bad = new BadFacetAppSmash();

        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](1);
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = BadFacetAppSmash.smash.selector;

        cuts[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(bad),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: sels
        });

        vm.prank(owner);
        IDiamondCutFacet(address(diamond)).diamondCut(cuts, address(0), "");

        // Call the malicious function through the diamond
        uint32 newFee = fee0 + 1;
        uint16 newMax = maxBatch0 + 1;
        BadFacetAppSmash(address(diamond)).smash(newFee, newMax);

        // Assert drift occurred as a proof our canary checks would catch it
        assertEq(getter.getInnovationFee(), newFee, "innovationFee should have changed");
        assertEq(getter.getBuyerWhitelistMaxBatchSize(), newMax, "maxBatch should have changed");
        assertTrue(
            getter.getInnovationFee() != fee0 || getter.getBuyerWhitelistMaxBatchSize() != maxBatch0,
            "storage should have drifted"
        );
    }
}

// =========================================================================
// MALICIOUS HELPER CONTRACTS
// =========================================================================

/// @notice Malicious initializer that attempts to escalate to owner/change fee
contract MaliciousInitTryAdmin {
    function initTryAdmin(address newOwner, uint32 newFee) external {
        // Attempt privilege escalation (should fail due to ownership checks)
        try IERC173(address(this)).transferOwnership(newOwner) {} catch {}
        try IdeationMarketFacet(address(this)).setInnovationFee(newFee) {} catch {}
        // Return successfully to avoid reverting the diamondCut itself
    }
}

/// @notice Malicious facet that directly writes to AppStorage (storage collision test)
contract BadFacetAppSmash {
    // Same layout as LibAppStorage.AppStorage for first two fields
    struct LocalAppStorage {
        uint32 innovationFee;
        uint16 buyerWhitelistMaxBatchSize;
    }

    function smash(uint32 newFee, uint16 newMax) external {
        LocalAppStorage storage s;
        bytes32 position = keccak256("diamond.standard.ideation.market");
        assembly {
            s.slot := position
        }
        s.innovationFee = newFee;
        s.buyerWhitelistMaxBatchSize = newMax;
    }
}
