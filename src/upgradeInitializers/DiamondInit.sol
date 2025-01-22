// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * \
 * Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
 * EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
 *
 * Implementation of a diamond.
 * /*****************************************************************************
 */
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IDiamondLoupeFacet} from "../interfaces/IDiamondLoupeFacet.sol";
import {IDiamondCutFacet} from "../interfaces/IDiamondCutFacet.sol";
import {IERC173} from "../interfaces/IERC173.sol";
import {IERC165} from "../interfaces/IERC165.sol";
import {LibAppStorage, AppStorage} from "../libraries/LibAppStorage.sol";
import {IERC721} from "../interfaces/IERC721.sol";
import {IERC721Receiver} from "../interfaces/IERC721Receiver.sol";

// It is expected that this contract is customized if you want to deploy your diamond
// with data from a deployment script. Use the init function to initialize state variables
// of your diamond. Add parameters to the init function if you need to.

contract DiamondInit {
    // You can add parameters to this function in order to pass in
    // data to set your own state variables
    function init(uint32 ideationMarketFee) external {
        // adding ERC165 data
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCutFacet).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupeFacet).interfaceId] = true;
        ds.supportedInterfaces[type(IERC173).interfaceId] = true;

        // depending on the contracts add supported interfaces

        ds.supportedInterfaces[type(IERC721).interfaceId] = true;
        ds.supportedInterfaces[type(IERC721Receiver).interfaceId] = true;

        // // ERC20
        // ds.supportedInterfaces[0x36372b07] = true; // IERC20
        // ds.supportedInterfaces[0xa219a025] = true; // IERC20MetaData

        // // ERC1155
        // ds.supportedInterfaces[0xd9b67a26] = true; // IERC1155
        // ds.supportedInterfaces[0x0e89341c] = true; // IERC1155MetadataURI

        // constructor for IdeationMarketFacet
        AppStorage storage s = LibAppStorage.appStorage();
        s.ideationMarketFee = ideationMarketFee; // represents a rate in basis points (e.g., 100 = 0.1%)

        // Modify `init()` to initialize any extra state variables in `LibDiamond.DiamondStorage` struct during deployment.
        // You can also add parameters to `init()` if needed to set your own state variables.

        // add your own state variables
        // EIP-2535 specifies that the `diamondCut` function takes two optional
        // arguments: address _init and bytes calldata _calldata
        // These arguments are used to execute an arbitrary function using delegatecall
        // in order to set state variables in the diamond during deployment or an upgrade
        // More info here: https://eips.ethereum.org/EIPS/eip-2535#diamond-interface
    }
}
