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
import {IERC1155} from "../interfaces/IERC1155.sol";
import {IERC2981} from "../interfaces/IERC2981.sol";

contract DiamondInit {
    function init(uint32 innovationFee, uint16 buyerWhitelistMaxBatchSize) external {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Diamond and ERC165 interfaces
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCutFacet).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupeFacet).interfaceId] = true;
        ds.supportedInterfaces[type(IERC173).interfaceId] = true;

        // NFT and multi-token interfaces
        ds.supportedInterfaces[type(IERC721).interfaceId] = true;
        ds.supportedInterfaces[type(IERC1155).interfaceId] = true;
        ds.supportedInterfaces[type(IERC2981).interfaceId] = true;

        // Initialize marketplace state variables. / Constructor for IdeationMarketFacet.
        AppStorage storage s = LibAppStorage.appStorage();
        s.innovationFee = innovationFee; // represents a rate in basis points (e.g., 100 = 0.1%)
        s.buyerWhitelistMaxBatchSize = buyerWhitelistMaxBatchSize;
    }
}
