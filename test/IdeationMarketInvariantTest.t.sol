// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

contract IdeationMarketInvariantTest is MarketTestBase {
    // This seeds a couple of flows so the contract holds some ETH, then asserts:
    // sum of per-address proceeds == getter.getBalance() == address(diamond).balance

    address[] internal actors;

    function setUp() public override {
        owner = vm.addr(0x9001);
        seller = vm.addr(0x9002);
        buyer = vm.addr(0x9003);

        vm.startPrank(owner);
        DiamondInit init = new DiamondInit();
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        DiamondLoupeFacet loupeFacet = new DiamondLoupeFacet();
        OwnershipFacet ownershipFacet = new OwnershipFacet();
        IdeationMarketFacet marketFacet = new IdeationMarketFacet();
        CollectionWhitelistFacet collectionFacet = new CollectionWhitelistFacet();
        BuyerWhitelistFacet buyerFacet = new BuyerWhitelistFacet();
        GetterFacet getterFacet = new GetterFacet();

        diamond = new IdeationMarketDiamond(owner, address(cutFacet));

        // loupe
        bytes4[] memory loupeSelectors = new bytes4[](5);
        loupeSelectors[0] = IDiamondLoupeFacet.facets.selector;
        loupeSelectors[1] = IDiamondLoupeFacet.facetFunctionSelectors.selector;
        loupeSelectors[2] = IDiamondLoupeFacet.facetAddresses.selector;
        loupeSelectors[3] = IDiamondLoupeFacet.facetAddress.selector;
        loupeSelectors[4] = IERC165.supportsInterface.selector;
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](6);
        cuts[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(loupeFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: loupeSelectors
        });
        // ownership
        bytes4[] memory ownershipSelectors = new bytes4[](3);
        ownershipSelectors[0] = IERC173.owner.selector;
        ownershipSelectors[1] = IERC173.transferOwnership.selector;
        ownershipSelectors[2] = OwnershipFacet.acceptOwnership.selector;
        cuts[1] = IDiamondCutFacet.FacetCut({
            facetAddress: address(ownershipFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: ownershipSelectors
        });
        // market
        bytes4[] memory marketSelectors = new bytes4[](7);
        marketSelectors[0] = IdeationMarketFacet.createListing.selector;
        marketSelectors[1] = IdeationMarketFacet.purchaseListing.selector;
        marketSelectors[2] = IdeationMarketFacet.cancelListing.selector;
        marketSelectors[3] = IdeationMarketFacet.updateListing.selector;
        marketSelectors[4] = IdeationMarketFacet.withdrawProceeds.selector;
        marketSelectors[5] = IdeationMarketFacet.setInnovationFee.selector;
        marketSelectors[6] = IdeationMarketFacet.cleanListing.selector;
        cuts[2] = IDiamondCutFacet.FacetCut({
            facetAddress: address(marketFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: marketSelectors
        });
        // collections
        bytes4[] memory colSelectors = new bytes4[](4);
        colSelectors[0] = CollectionWhitelistFacet.addWhitelistedCollection.selector;
        colSelectors[1] = CollectionWhitelistFacet.removeWhitelistedCollection.selector;
        colSelectors[2] = CollectionWhitelistFacet.batchAddWhitelistedCollections.selector;
        colSelectors[3] = CollectionWhitelistFacet.batchRemoveWhitelistedCollections.selector;
        cuts[3] = IDiamondCutFacet.FacetCut({
            facetAddress: address(collectionFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: colSelectors
        });
        // buyers
        bytes4[] memory buyerSelectors = new bytes4[](2);
        buyerSelectors[0] = BuyerWhitelistFacet.addBuyerWhitelistAddresses.selector;
        buyerSelectors[1] = BuyerWhitelistFacet.removeBuyerWhitelistAddresses.selector;
        cuts[4] = IDiamondCutFacet.FacetCut({
            facetAddress: address(buyerFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: buyerSelectors
        });
        // getter
        bytes4[] memory getterSelectors = new bytes4[](12);
        getterSelectors[0] = GetterFacet.getListingsByNFT.selector;
        getterSelectors[1] = GetterFacet.getListingByListingId.selector;
        getterSelectors[2] = GetterFacet.getProceeds.selector;
        getterSelectors[3] = GetterFacet.getBalance.selector;
        getterSelectors[4] = GetterFacet.getInnovationFee.selector;
        getterSelectors[5] = GetterFacet.getNextListingId.selector;
        getterSelectors[6] = GetterFacet.isCollectionWhitelisted.selector;
        getterSelectors[7] = GetterFacet.getWhitelistedCollections.selector;
        getterSelectors[8] = GetterFacet.getContractOwner.selector;
        getterSelectors[9] = GetterFacet.isBuyerWhitelisted.selector;
        getterSelectors[10] = GetterFacet.getBuyerWhitelistMaxBatchSize.selector;
        getterSelectors[11] = GetterFacet.getPendingOwner.selector;
        cuts[5] = IDiamondCutFacet.FacetCut({
            facetAddress: address(getterFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: getterSelectors
        });

        IDiamondCutFacet(address(diamond)).diamondCut(
            cuts, address(init), abi.encodeCall(DiamondInit.init, (INNOVATION_FEE, MAX_BATCH))
        );
        vm.stopPrank();

        // cache handles
        getter = GetterFacet(address(diamond));
        market = IdeationMarketFacet(address(diamond));
        collections = CollectionWhitelistFacet(address(diamond));

        // set up one flow so contract holds ETH
        erc721 = new MockERC721();
        vm.prank(owner);
        collections.addWhitelistedCollection(address(erc721));
        erc721.mint(seller, 1);
        vm.prank(seller);
        erc721.approve(address(diamond), 1);

        vm.prank(seller);
        market.createListing(
            address(erc721), 1, address(0), 1 ether, address(0), 0, 0, 0, false, false, new address[](0)
        );
        uint128 id = getter.getNextListingId() - 1;

        vm.deal(buyer, 2 ether);
        vm.prank(buyer);
        market.purchaseListing{value: 1 ether}(id, 1 ether, 0, address(0), 0, 0, 0, address(0));

        // track a few plausible recipients (extend as needed)
        actors.push(owner);
        actors.push(seller);
        actors.push(buyer);
        actors.push(address(0)); // zero-address royalties, if any
    }

    function invariant_ProceedsSumEqualsDiamondBalance() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; i++) {
            sum += getter.getProceeds(actors[i]);
        }
        assertEq(sum, getter.getBalance());
        assertEq(getter.getBalance(), address(diamond).balance);
    }
}
