// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";
import {IdeationMarketFacet} from "../src/facets/IdeationMarketFacet.sol";

/**
 * @title MarketplaceFeeAndRoyaltyETHTest
 * @notice ETH-path fee snapshots, fee boundaries, and ERC2981 royalty behavior.
 */
contract MarketplaceFeeAndRoyaltyETHTest is MarketTestBase {
    function testRoyaltyReceiverEqualsSeller() public {
        MockERC721Royalty r = new MockERC721Royalty();
        r.mint(seller, 1);
        r.setRoyalty(seller, 10_000); // 10%

        vm.prank(owner);
        collections.addWhitelistedCollection(address(r));

        vm.prank(seller);
        r.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(r), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        // Seller receives sale - fee (0.99), since royalty loops back to seller.
        assertEq(seller.balance - sellerBalBefore, 0.99 ether);
        assertEq(owner.balance - ownerBalBefore, 0.01 ether);
    }

    function testFeeRoyaltyRounding_TinyPrices() public {
        // innovationFee is 1% by default in your setup (1000/100_000)
        MockERC721Royalty r = new MockERC721Royalty();
        address RR = vm.addr(0xBEEF);
        r.setRoyalty(RR, 1_000); // 1% of 100_000

        vm.prank(owner);
        collections.addWhitelistedCollection(address(r));

        // --- Case 1: price = 1 wei → fee=0, royalty=0 (floor), seller gets 1 wei
        r.mint(seller, 1);
        vm.prank(seller);
        r.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(r), 1, address(0), 1, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id1 = getter.getNextListingId() - 1;

        uint256 ownerBal1 = owner.balance;
        uint256 rrBal1 = RR.balance;
        uint256 sellerBal1 = seller.balance;

        vm.deal(buyer, 1);
        vm.prank(buyer);
        market.purchaseListing{value: 1}(id1, 1, address(0), 0, address(0), 0, 0, 0, address(0));

        assertEq(owner.balance - ownerBal1, 0); // fee 0
        assertEq(RR.balance - rrBal1, 0); // royalty 0
        assertEq(seller.balance - sellerBal1, 1);

        // --- Case 2: price = 101 wei → fee=1, royalty=1, seller gets 99
        r.mint(seller, 2);
        vm.prank(seller);
        r.approve(address(diamond), 2);

        vm.prank(seller);
        market.createListing(
            address(r), 2, address(0), 101, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id2 = getter.getNextListingId() - 1;

        uint256 ownerBal2 = owner.balance;
        uint256 rrBal2 = RR.balance;
        uint256 sellerBal2 = seller.balance;

        vm.deal(buyer, 101);
        vm.prank(buyer);
        market.purchaseListing{value: 101}(id2, 101, address(0), 0, address(0), 0, 0, 0, address(0));

        assertEq(owner.balance - ownerBal2, 1); // fee 1
        assertEq(RR.balance - rrBal2, 1); // royalty 1
        assertEq(seller.balance - sellerBal2, 99); // seller gets 99

        // --- Case 3: price = 199 wei → fee=1, royalty=1, seller 197
        r.mint(seller, 3);
        vm.prank(seller);
        r.approve(address(diamond), 3);

        vm.prank(seller);
        market.createListing(
            address(r), 3, address(0), 199, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id3 = getter.getNextListingId() - 1;

        uint256 ownerBal3 = owner.balance;
        uint256 rrBal3 = RR.balance;
        uint256 sellerBal3 = seller.balance;

        vm.deal(buyer, 199);
        vm.prank(buyer);
        market.purchaseListing{value: 199}(id3, 199, address(0), 0, address(0), 0, 0, 0, address(0));

        assertEq(owner.balance - ownerBal3, 1); // fee 1
        assertEq(RR.balance - rrBal3, 1); // royalty 1
        assertEq(seller.balance - sellerBal3, 197); // seller gets 197
    }

    function testRoyaltyPaymentWithOwnerFee() public {
        // Prepare royalty NFT (10%) and whitelist
        MockERC721Royalty royaltyNft = new MockERC721Royalty();
        royaltyNft.mint(seller, 1);
        address royaltyReceiver = address(0xB0B);
        royaltyNft.setRoyalty(royaltyReceiver, 10_000); // 10% of 100_000

        vm.prank(owner);
        collections.addWhitelistedCollection(address(royaltyNft));

        // Approve & list for 1 ETH
        vm.prank(seller);
        royaltyNft.approve(address(diamond), 1);
        vm.prank(seller);
        market.createListing(
            address(royaltyNft), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        // Capture balances before purchase
        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;
        uint256 royaltyBalBefore = royaltyReceiver.balance;

        // Purchase at 1 ETH
        vm.deal(buyer, 2 ether);
        vm.startPrank(buyer);
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.RoyaltyPaid(id, royaltyReceiver, address(0), 0.1 ether); // currency is address(0) for ETH

        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();

        // Atomic payments: fee(1%)=0.01; royalty(10%)=0.1 → seller gets 0.89
        assertEq(seller.balance - sellerBalBefore, 0.89 ether);
        assertEq(owner.balance - ownerBalBefore, 0.01 ether);
        assertEq(royaltyReceiver.balance - royaltyBalBefore, 0.1 ether);

        // Non-custodial: diamond holds no balance
        assertEq(address(diamond).balance, 0);
    }

    function testRoyaltyEqualsPostFeeProceedsBoundary() public {
        // fee = 1% (0.01 ETH), royalty = 99% (0.99 ETH) -> seller net 0
        MockERC721Royalty r = new MockERC721Royalty();
        r.mint(seller, 1);
        r.setRoyalty(address(0xB0B), 99_000);

        vm.prank(owner);
        collections.addWhitelistedCollection(address(r));

        vm.prank(seller);
        r.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(r), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        uint256 sellerBalBefore = seller.balance;
        uint256 ownerBalBefore = owner.balance;
        uint256 royaltyBalBefore = address(0xB0B).balance;

        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));

        assertEq(owner.balance - ownerBalBefore, 0.01 ether);
        assertEq(address(0xB0B).balance - royaltyBalBefore, 0.99 ether);
        assertEq(seller.balance - sellerBalBefore, 0);
    }

    function testInnovationFeeUpdateSemantics() public {
        _whitelistCollectionAndApproveERC721();

        // Listing #1 under initial fee (1000 = 1%)
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id1 = getter.getNextListingId() - 1;
        assertEq(getter.getListingByListingId(id1).feeRate, 1000);

        // Update fee to 2.5% and create Listing #2 using new fee
        vm.startPrank(owner);
        uint32 prev = getter.getInnovationFee();
        uint32 next = 2500;
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.InnovationFeeUpdated(prev, next);
        market.setInnovationFee(2500);
        vm.stopPrank();

        vm.prank(seller);
        erc721.approve(address(diamond), 2);
        vm.prank(seller);
        market.createListing(
            address(erc721), 2, address(0), 2 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id2 = getter.getNextListingId() - 1;
        assertEq(getter.getListingByListingId(id2).feeRate, 2500);

        // Listing #1 still has old fee until updated
        assertEq(getter.getListingByListingId(id1).feeRate, 1000);

        // Updating #1 "refreshes" fee to current (2500)
        vm.prank(seller);
        market.updateListing(id1, 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));
        assertEq(getter.getListingByListingId(id1).feeRate, 2500);
    }

    // purchase-time royalty > proceeds reverts (listing itself may succeed)
    function testPurchaseRevertsWhenRoyaltyExceedsProceeds() public {
        // High-royalty token (e.g., 99.5%)
        MockERC721Royalty royaltyNft = new MockERC721Royalty();
        royaltyNft.mint(seller, 1);
        royaltyNft.setRoyalty(address(0xB0B), 99_500);

        vm.prank(owner);
        collections.addWhitelistedCollection(address(royaltyNft));

        vm.prank(seller);
        royaltyNft.approve(address(diamond), 1);

        // Listing will succeed with your current code (no listing-time check)
        vm.prank(seller);
        market.createListing(
            address(royaltyNft), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 2 ether);
        vm.startPrank(buyer);
        vm.expectRevert(IdeationMarket__RoyaltyFeeExceedsProceeds.selector);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
        vm.stopPrank();
    }
}
