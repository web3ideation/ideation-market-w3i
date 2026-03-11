// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

/**
 * @title MarketplaceEventsTest
 * @notice Event emission correctness across marketplace flows.
 */
contract MarketplaceEventsTest is MarketTestBase {
    /// ListingCreated fires with exact parameters for ERC721 listing
    function testEmitListingCreated() public {
        _whitelistCollectionAndApproveERC721();
        uint128 expectedId = getter.getNextListingId();

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCreated(
            expectedId,
            address(erc721),
            1,
            0, // erc1155Quantity (ERC721 -> 0)
            1 ether,
            address(0), // currency
            getter.getInnovationFee(),
            seller,
            false,
            false,
            address(0),
            0,
            0
        );

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
    }

    function testEmitListingCreated_ERC1155() public {
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc1155));
        vm.prank(seller);
        erc1155.setApprovalForAll(address(diamond), true);

        uint128 expectedId = getter.getNextListingId();

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingCreated(
            expectedId,
            address(erc1155),
            1,
            10, // erc1155Quantity
            10 ether, // price
            address(0), // currency
            getter.getInnovationFee(),
            seller,
            false, // buyerWhitelistEnabled
            false, // partialBuyEnabled
            address(0), // desiredTokenAddress
            0, // desiredTokenId
            0 // desiredErc1155Quantity
        );

        vm.prank(seller);
        market.createListing(
            address(erc1155), 1, seller, 10 ether, address(0), address(0), 0, 0, 10, false, false, new address[](0)
        );
    }

    /// ListingUpdated fires with exact parameters on price change
    function testEmitListingUpdated() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingUpdated(
            id,
            address(erc721),
            1,
            0,
            2 ether,
            address(0),
            getter.getInnovationFee(),
            seller,
            false,
            false,
            address(0),
            0,
            0
        );

        vm.prank(seller);
        market.updateListing(id, 2 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0));
    }

    /// ListingPurchased fires with exact parameters on ERC721 full purchase
    function testEmitListingPurchased() public {
        _whitelistCollectionAndApproveERC721();
        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        uint32 feeSnap = getter.getListingByListingId(id).feeRate;

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingPurchased(
            id, address(erc721), 1, 0, false, 1 ether, address(0), feeSnap, seller, buyer, address(0), 0, 0
        );

        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
    }

    /// RoyaltyPaid fires with exact parameters
    function testEmitRoyaltyPaid() public {
        // Prepare royalty NFT (10%) and whitelist
        MockERC721Royalty royaltyNft = new MockERC721Royalty();
        address royaltyReceiver = address(0xB0B);
        royaltyNft.setRoyalty(royaltyReceiver, 10_000); // 10% of 100_000

        vm.prank(owner);
        collections.addWhitelistedCollection(address(royaltyNft));
        royaltyNft.mint(seller, 1);

        vm.prank(seller);
        royaltyNft.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(royaltyNft), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.RoyaltyPaid(id, royaltyReceiver, address(0), 0.1 ether);

        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
    }

    /// Royalty-paid purchase emits both RoyaltyPaid and ListingPurchased in protocol order.
    function testRoyaltyPurchase_EmitsPurchasedThenRoyalty() public {
        MockERC721Royalty royaltyNft = new MockERC721Royalty();
        address royaltyReceiver = address(0xB0B);
        royaltyNft.setRoyalty(royaltyReceiver, 10_000); // 10%

        vm.prank(owner);
        collections.addWhitelistedCollection(address(royaltyNft));
        royaltyNft.mint(seller, 1);
        vm.prank(seller);
        royaltyNft.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(royaltyNft), 1, address(0), 1 ether, address(0), address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 1 ether);
        uint32 feeSnap = getter.getListingByListingId(id).feeRate;

        // Protocol emits RoyaltyPaid during payment distribution, then ListingPurchased at function end.
        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.RoyaltyPaid(id, royaltyReceiver, address(0), 0.1 ether);

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.ListingPurchased(
            id, address(royaltyNft), 1, 0, false, 1 ether, address(0), feeSnap, seller, buyer, address(0), 0, 0
        );

        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, address(0), 0, address(0), 0, 0, 0, address(0));
    }

    /// InnovationFeeUpdated fires with exact parameters
    function testEmitInnovationFeeUpdated() public {
        uint32 previous = getter.getInnovationFee();
        uint32 next = 777;

        vm.expectEmit(true, true, true, true, address(diamond));
        emit IdeationMarketFacet.InnovationFeeUpdated(previous, next);

        vm.prank(owner);
        market.setInnovationFee(next);

        assertEq(getter.getInnovationFee(), next);
    }
}
