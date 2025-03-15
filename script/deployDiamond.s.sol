// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

import {IdeationMarketDiamond} from "../src/IdeationMarketDiamond.sol";
import {DiamondInit} from "../src/upgradeInitializers/DiamondInit.sol";

import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../src/facets/DiamondLoupeFacet.sol";
import {OwnershipFacet} from "../src/facets/OwnershipFacet.sol";
import {IdeationMarketFacet} from "../src/facets/IdeationMarketFacet.sol";

import {IDiamondCutFacet} from "../src/interfaces/IDiamondCutFacet.sol";
import {IDiamondLoupeFacet} from "../src/interfaces/IDiamondLoupeFacet.sol";
import {IERC165} from "../src/interfaces/IERC165.sol";
import {IERC173} from "../src/interfaces/IERC173.sol";

// Script to deploy a Diamond with CutFacet, LoupeFacet and OwnershipFacet
// This Script DOES NOT upgrade the diamond with any of the example facets.
contract DeployScript is Script {
    // Constructor arguments
    address owner = 0x64890a1ddD3Cea0A14D62E14fE76C4a1b34A4328; // !!!W Use appropriate address for testing
    uint256 ideationMarketFee = 1000; // Example fee, e.g., 1000 means 1%

    function run() external {
        vm.startBroadcast();

        // Deploy Contracts
        DiamondInit diamondInit = new DiamondInit();
        DiamondCutFacet diamondCutFacet = new DiamondCutFacet();
        DiamondLoupeFacet diamondLoupeFacet = new DiamondLoupeFacet();
        OwnershipFacet ownershipFacet = new OwnershipFacet();
        IdeationMarketFacet ideationMarketFacet = new IdeationMarketFacet(); // Pass required constructor arguments if necessary

        // Deploy the diamond with the initial facet cut for DiamondCutFacet
        IdeationMarketDiamond ideationMarketDiamond = new IdeationMarketDiamond(owner, address(diamondCutFacet));
        console.log("Deployed Diamond.sol at address:", address(ideationMarketDiamond));

        // We prepare an array of `cuts` that we want to upgrade our Diamond with.
        // The remaining cuts that we want the diamond to have are the Loupe, Ownership, and IdeationMarket facets.
        IDiamondCutFacet.FacetCut[] memory cuts = new IDiamondCutFacet.FacetCut[](3);

        // We create and populate array of function selectors needed for FacetCut Structs
        bytes4[] memory loupeSelectors = new bytes4[](5);
        loupeSelectors[0] = IDiamondLoupeFacet.facets.selector;
        loupeSelectors[1] = IDiamondLoupeFacet.facetFunctionSelectors.selector;
        loupeSelectors[2] = IDiamondLoupeFacet.facetAddresses.selector;
        loupeSelectors[3] = IDiamondLoupeFacet.facetAddress.selector;
        loupeSelectors[4] = IERC165.supportsInterface.selector; // The IERC165 function found in the Loupe.

        bytes4[] memory ownershipSelectors = new bytes4[](2);
        ownershipSelectors[0] = IERC173.owner.selector; // IERC173 has all the ownership functions needed.
        ownershipSelectors[1] = IERC173.transferOwnership.selector;

        bytes4[] memory marketSelectors = new bytes4[](10);
        marketSelectors[0] = bytes4(keccak256("listItem(address,uint256,uint256,address,uint256)"));
        marketSelectors[1] = bytes4(keccak256("buyItem(address,uint256)"));
        marketSelectors[2] = bytes4(keccak256("cancelListing(address,uint256)"));
        marketSelectors[3] = bytes4(keccak256("updateListing(address,uint256,uint256,address,uint256)"));
        marketSelectors[4] = bytes4(keccak256("withdrawProceeds()"));
        marketSelectors[5] = bytes4(keccak256("setFee(uint256)"));
        marketSelectors[6] = bytes4(keccak256("getListing(address,uint256)"));
        marketSelectors[7] = bytes4(keccak256("getProceeds(address)"));
        marketSelectors[8] = bytes4(keccak256("getNextListingId()"));
        marketSelectors[9] = bytes4(keccak256("getBalance()"));

        // !!! add collectionWhtielistfacet, BuyerWhitelistFacet and getterfacet

        // Populate the `cuts` array with all data needed for each `FacetCut` struct
        cuts[0] = IDiamondCutFacet.FacetCut({
            facetAddress: address(diamondLoupeFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: loupeSelectors
        });

        cuts[1] = IDiamondCutFacet.FacetCut({
            facetAddress: address(ownershipFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: ownershipSelectors
        });

        cuts[2] = IDiamondCutFacet.FacetCut({
            facetAddress: address(ideationMarketFacet),
            action: IDiamondCutFacet.FacetCutAction.Add,
            functionSelectors: marketSelectors
        });

        // After we have all the cuts setup how we want, we can upgrade the diamond to include these facets.
        // We call `diamondCut` with our `diamond` contract through the `IDiamondCutFacet` interface.
        // `diamondCut` takes in the `cuts` and the `DiamondInit` contract and calls its `init()` function.
        IDiamondCutFacet(address(ideationMarketDiamond)).diamondCut(
            cuts, address(diamondInit), abi.encodeWithSignature("init(uint256,address)", ideationMarketFee, owner)
        );

        // We use `IERC173` instead of an `IOwnershipFacet` interface for the `OwnershipFacet` with no problems
        // because all functions from `OwnershipFacet` are just IERC173 overrides.
        // However, for more complex facets that are not exactly 1:1 with an existing IERC,
        // you can create custom `IExampleFacet` interface that isn't just identical to an IERC.
        console.log("Diamond cuts complete. Owner of Diamond:", IERC173(address(ideationMarketDiamond)).owner());

        vm.stopBroadcast();
    }
}

/* 
                                        Tips

- There are many ways to get a function selector. `facets()` is 0x7a0ed627 for example.                                       
- Function Selector = First 4 bytes of a hashed function signature.
- Function Signature = Function name and it's parameter types. No spaces. "transfer(address,uint256)".

1. `Contract.function.selector` --> console.logBytes4(IDiamondLoupeFacet.facets.selector);
2. `bytes4(keccak256("funcSig")` --> console.logBytes4(bytes4(keccak256("facets()")));
3. `bytes4(abi.encodeWithSignature("funcSig"))` --> console.logBytes4(bytes4(abi.encodeWithSignature("facets()"))); 
4. VSCode extension `Solidity Visual Developer` shows function selectors. Manual copy-paste.

*/
