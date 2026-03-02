// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

/**
 * @title MarketplaceSwapFlowTest
 * @notice ERC721/ERC1155 swap-path behavior and swap-related guardrails.
 */
contract MarketplaceSwapFlowTest is MarketTestBase {
    // swap with same NFT reverts
    function testSwapWithSameNFTReverts() public {
        _whitelistCollectionAndApproveERC721();

        vm.startPrank(seller);
        vm.expectRevert(IdeationMarket__NoSwapForSameToken.selector);
        market.createListing(
            address(erc721),
            1,
            address(0),
            0, // price 0 (swap-only) ok
            address(0), // currency
            address(erc721), // desiredTokenAddress (same as listed)
            1, // desiredTokenId
            0, // desiredErc1155Quantity
            0, // erc1155Quantity
            false,
            false,
            new address[](0)
        );
        vm.stopPrank();
    }
}
