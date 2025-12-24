// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MarketTestBase.t.sol";

/// @title CollectionWhitelistFacetEdgeTest
/// @notice Edge cases for add/remove + batch ops on the collection whitelist.
/// @dev Uses fresh mock contracts per test to avoid interference with
///      MarketTestBase's default whitelisted mocks.
contract CollectionWhitelistFacetEdgeTest is MarketTestBase {
    /* --------------------------------------------------------------------- */
    /* single add/remove                                                      */
    /* --------------------------------------------------------------------- */

    function testAddThenRemove_New721() public {
        MockERC721 a = _new721();

        // add by owner
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(a));
        vm.stopPrank();

        assertTrue(getter.isCollectionWhitelisted(address(a)));

        // remove by owner
        vm.startPrank(owner);
        collections.removeWhitelistedCollection(address(a));
        vm.stopPrank();

        assertFalse(getter.isCollectionWhitelisted(address(a)));
    }

    function testAddDuplicate_Reverts() public {
        MockERC1155 a = _new1155();

        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(a));
        // second add should revert with the facet's duplicate error
        vm.expectRevert(CollectionWhitelist__AlreadyWhitelisted.selector);
        collections.addWhitelistedCollection(address(a));
        vm.stopPrank();
    }

    function testRemoveNonWhitelisted_Reverts() public {
        MockERC721 a = _new721();

        vm.startPrank(owner);
        vm.expectRevert(CollectionWhitelist__NotWhitelisted.selector);
        collections.removeWhitelistedCollection(address(a));
        vm.stopPrank();
    }

    /* --------------------------------------------------------------------- */
    /* onlyOwner guards                                                       */
    /* --------------------------------------------------------------------- */

    function testOnlyOwner_AddRemove_RevertsForNonOwner() public {
        MockERC721 a = _new721();

        vm.startPrank(buyer);
        vm.expectRevert("LibDiamond: Must be contract owner");
        collections.addWhitelistedCollection(address(a));
        vm.stopPrank();

        vm.startPrank(buyer);
        vm.expectRevert("LibDiamond: Must be contract owner");
        collections.removeWhitelistedCollection(address(a));
        vm.stopPrank();
    }

    /* --------------------------------------------------------------------- */
    /* batch operations                                                       */
    /* --------------------------------------------------------------------- */

    function testBatchAdd_And_BatchRemove_WithDuplicates() public {
        MockERC721 a = _new721();
        MockERC1155 b = _new1155();

        address[] memory addrs = new address[](2);
        addrs[0] = address(a);
        addrs[1] = address(b);

        // batch add
        vm.startPrank(owner);
        collections.batchAddWhitelistedCollections(addrs);
        vm.stopPrank();

        assertTrue(getter.isCollectionWhitelisted(address(a)));
        assertTrue(getter.isCollectionWhitelisted(address(b)));

        // batch remove with a duplicate of `a` to ensure duplicate handling
        address[] memory rem = new address[](3);
        rem[0] = address(a);
        rem[1] = address(a);
        rem[2] = address(b);

        vm.startPrank(owner);
        collections.batchRemoveWhitelistedCollections(rem);
        vm.stopPrank();

        assertFalse(getter.isCollectionWhitelisted(address(a)));
        assertFalse(getter.isCollectionWhitelisted(address(b)));
    }

    /* --------------------------------------------------------------------- */
    /* zero address input                                                     */
    /* --------------------------------------------------------------------- */

    function testAddZeroAddress_Reverts() public {
        vm.startPrank(owner);
        vm.expectRevert(); // robust to exact error type/name
        collections.addWhitelistedCollection(address(0));
        vm.stopPrank();
    }

    function testBatchAdd_WithZeroAddress_Reverts() public {
        MockERC721 a = _new721();

        address[] memory addrs = new address[](2);
        addrs[0] = address(0);
        addrs[1] = address(a);

        vm.startPrank(owner);
        vm.expectRevert(); // if any element is invalid, whole call should revert
        collections.batchAddWhitelistedCollections(addrs);
        vm.stopPrank();

        // nothing should have been added
        assertFalse(getter.isCollectionWhitelisted(address(a)));
    }

    /* --------------------------------------------------------------------- */
    /* enumeration signal (getWhitelistedCollections)                         */
    /* --------------------------------------------------------------------- */

    function testGetWhitelistedCollections_ReflectsAddsAndRemoves() public {
        MockERC721 a = _new721();
        MockERC1155 b = _new1155();

        // add two fresh ones
        vm.startPrank(owner);
        collections.addWhitelistedCollection(address(a));
        collections.addWhitelistedCollection(address(b));
        vm.stopPrank();

        {
            address[] memory all = getter.getWhitelistedCollections();
            assertTrue(_contains(all, address(a)));
            assertTrue(_contains(all, address(b)));
        }

        // remove one and ensure it disappears
        vm.startPrank(owner);
        collections.removeWhitelistedCollection(address(a));
        vm.stopPrank();

        {
            address[] memory all2 = getter.getWhitelistedCollections();
            assertFalse(_contains(all2, address(a)));
            assertTrue(_contains(all2, address(b)));
        }
    }
}
