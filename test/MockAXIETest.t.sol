// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {Pausable} from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {MockAXIE} from "../src/mocks/MockAXIE.sol";

contract AxieMockTest is Test {
    MockAXIE internal axie;

    address internal minter = vm.addr(0xA11CE);
    address internal alice = vm.addr(0xB0B);
    address internal bob = vm.addr(0xBEEF);

    function setUp() public {
        axie = new MockAXIE();

        axie.grantRole(axie.MINTER_ROLE(), minter);
        axie.grantRole(axie.SEEDER_ROLE(), minter);
    }

    function testMintWithExplicitIdAndOwnerOf() public {
        MockAXIE.AxieData memory data = _sampleData(0, 0, 1521001390, 11, 22, 3, 60);

        vm.prank(minter);
        axie.mintAxieWithId(alice, 27, data);

        assertEq(axie.ownerOf(27), alice);
        assertEq(axie.currentAxieId(), 27);
        assertEq(axie.stageOf(27), axie.STAGE_ADULT());
    }

    function testApproveAndSetApprovalForAllWork() public {
        MockAXIE.AxieData memory data = _sampleData(0, 0, 1, 1, 1, 0, 1);

        vm.prank(minter);
        axie.mintAxieWithId(alice, 29, data);

        vm.prank(alice);
        axie.approve(bob, 29);
        assertEq(axie.getApproved(29), bob);

        vm.prank(alice);
        axie.setApprovalForAll(bob, true);
        assertTrue(axie.isApprovedForAll(alice, bob));
    }

    function testTokenURIUsesLiveStyleBaseUri() public {
        MockAXIE.AxieData memory data = _sampleData(0, 0, 1, 1, 2, 0, 1);

        vm.prank(minter);
        axie.mintAxieWithId(alice, 3270162, data);

        assertEq(axie.tokenURI(3270162), "https://metadata.axieinfinity.com/axie/3270162");
    }

    function testAxieAndGetAxieReturnStoredValues() public {
        MockAXIE.AxieData memory data = _sampleData(7, 9, 123456789, 555, 777, 2, 42);

        vm.prank(minter);
        axie.mintAxieWithId(alice, 101, data);

        (
            uint256 sireId,
            uint256 matronId,
            uint256 birthDate,
            MockAXIE.Gene memory genes,
            uint8 breedCount,
            uint16 level
        ) = axie.axie(101);

        assertEq(sireId, 7);
        assertEq(matronId, 9);
        assertEq(birthDate, 123456789);
        assertEq(genes.x, 555);
        assertEq(genes.y, 777);
        assertEq(breedCount, 2);
        assertEq(level, 42);

        MockAXIE.AxieData memory got = axie.getAxie(101);
        assertEq(got.sireId, 7);
        assertEq(got.matronId, 9);
        assertEq(got.birthDate, 123456789);
        assertEq(got.genes.x, 555);
        assertEq(got.genes.y, 777);
        assertEq(got.breedCount, 2);
        assertEq(got.level, 42);
    }

    function testEnumerableFunctionsWork() public {
        MockAXIE.AxieData memory d1 = _sampleData(0, 0, 1, 1, 1, 0, 1);
        MockAXIE.AxieData memory d2 = _sampleData(0, 0, 2, 2, 2, 1, 2);
        MockAXIE.AxieData memory d3 = _sampleData(0, 0, 3, 3, 3, 2, 3);

        vm.startPrank(minter);
        axie.mintAxieWithId(alice, 27, d1);
        axie.mintAxieWithId(alice, 29, d2);
        axie.mintAxieWithId(alice, 3270162, d3);
        vm.stopPrank();

        assertEq(axie.totalSupply(), 3);
        assertEq(axie.tokenByIndex(0), 27);
        assertEq(axie.tokenByIndex(1), 29);
        assertEq(axie.tokenByIndex(2), 3270162);

        assertEq(axie.tokenOfOwnerByIndex(alice, 0), 27);
        assertEq(axie.tokenOfOwnerByIndex(alice, 1), 29);
        assertEq(axie.tokenOfOwnerByIndex(alice, 2), 3270162);
    }

    function testPauseBlocksTransferAndMint() public {
        MockAXIE.AxieData memory data = _sampleData(0, 0, 1, 1, 1, 0, 1);

        vm.prank(minter);
        axie.mintAxieWithId(alice, 77, data);

        axie.pause();

        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        axie.transferFrom(alice, bob, 77);

        vm.prank(minter);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        axie.mintAxieWithId(alice, 88, data);
    }

    function testSupportsInterfaceCoverage() public view {
        bytes4 IERC721_ID = 0x80ac58cd;
        bytes4 IERC721_METADATA_ID = 0x5b5e139f;
        bytes4 IERC721_ENUMERABLE_ID = 0x780e9d63;
        bytes4 IACCESS_CONTROL_ID = 0x7965db0b;

        assertTrue(axie.supportsInterface(IERC721_ID));
        assertTrue(axie.supportsInterface(IERC721_METADATA_ID));
        assertTrue(axie.supportsInterface(IERC721_ENUMERABLE_ID));
        assertTrue(axie.supportsInterface(IACCESS_CONTROL_ID));
    }

    function _sampleData(
        uint256 sireId,
        uint256 matronId,
        uint256 birthDate,
        uint256 geneX,
        uint256 geneY,
        uint8 breedCount,
        uint16 level
    ) internal pure returns (MockAXIE.AxieData memory) {
        return MockAXIE.AxieData({
            sireId: sireId,
            matronId: matronId,
            birthDate: birthDate,
            genes: MockAXIE.Gene({x: geneX, y: geneY}),
            breedCount: breedCount,
            level: level
        });
    }
}
