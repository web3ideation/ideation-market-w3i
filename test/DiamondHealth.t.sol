// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

// EIP-2535 loupe (subset)
interface IDiamondLoupe {
    struct Facet {
        address facetAddress;
        bytes4[] functionSelectors;
    }

    function facets() external view returns (Facet[] memory facets_);
    function facetAddresses() external view returns (address[] memory facetAddresses_);
    function facetFunctionSelectors(address _facet) external view returns (bytes4[] memory facetFunctionSelectors_);
}

// ERC165 + ERC173
interface IERC165 {
    function supportsInterface(bytes4 iid) external view returns (bool);
}

interface IOwnershipFacet {
    function owner() external view returns (address);
}

interface IGetterFacet {
    function getContractOwner() external view returns (address);
    function getWhitelistedCollections() external view returns (address[] memory);
}

contract DiamondHealth is Test {
    // live diamond (Sepolia)
    address constant DIAMOND = 0x8cE90712463c87a6d62941D67C3507D090Ea9d79; // :contentReference[oaicite:9]{index=9}

    bytes4 constant IID_ERC165 = 0x01ffc9a7;
    bytes4 constant IID_ERC173 = 0x7f5828d0; // ownership

    function setUp() public {
        // Run on a Sepolia fork so we inspect live state via RPC:
        // forge test --fork-url $SEPOLIA_RPC_URL -vvv --match-contract DiamondHealth
        string memory url = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(url);
    }

    function test_DiamondLoupeAndInterfaces() public {
        IDiamondLoupe loupe = IDiamondLoupe(DIAMOND);

        // 1) facets exist and each has selectors
        IDiamondLoupe.Facet[] memory fs = loupe.facets();
        assertTrue(fs.length > 0, "no facets");
        for (uint256 i = 0; i < fs.length; i++) {
            assertTrue(fs[i].facetAddress != address(0), "zero facet");
            assertTrue(fs[i].functionSelectors.length > 0, "no selectors");
        }

        // 2) ERC165 and ERC173 (ownership) are supported (via ERC165)
        (bool ok, bytes memory ret) =
            DIAMOND.staticcall(abi.encodeWithSelector(IERC165.supportsInterface.selector, IID_ERC165));
        assertTrue(ok && ret.length >= 32 && abi.decode(ret, (bool)), "ERC165 not supported");

        (ok, ret) = DIAMOND.staticcall(abi.encodeWithSelector(IERC165.supportsInterface.selector, IID_ERC173));
        // ERC-173 via ERC-165 is optional; don't fail hard but log it
        if (ok && ret.length >= 32 && abi.decode(ret, (bool))) {
            // ok
        }
        else emit log("NOTE: ERC-173 not reported via ERC-165 (acceptable)");
    }

    function test_ContractOwnerMatchesDeploymentLog() public view {
        // GetterFacet exposes getContractOwner (seen on Louper). :contentReference[oaicite:10]{index=10}
        IGetterFacet getter = IGetterFacet(DIAMOND);
        address owner = getter.getContractOwner();
        assertEq(owner, 0xE8dF60a93b2B328397a8CBf73f0d732aaa11e33D, "owner mismatch with deploy log"); // :contentReference[oaicite:11]{index=11}
    }
}
