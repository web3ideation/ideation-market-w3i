// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IERC173} from "../interfaces/IERC173.sol";

error Ownership__CallerIsNotThePendingOwner();

contract OwnershipFacet is IERC173 {
    /// @notice Emitted once a new owner is nominated
    event OwnershipTransferInitiated(address indexed previousOwner, address indexed newOwner);

    /// @notice Owner nominates a new owner
    function transferOwnership(address newOwner) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.diamondStorage().pendingContractOwner = newOwner;
        emit OwnershipTransferInitiated(msg.sender, newOwner);
    }

    /// @notice Pending owner calls to accept and finalize transfer
    function acceptOwnership() external {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        if (msg.sender != ds.pendingContractOwner) {
            revert Ownership__CallerIsNotThePendingOwner();
        }
        LibDiamond.setContractOwner(msg.sender);
        ds.pendingContractOwner = address(0);
    }

    /// @inheritdoc IERC173
    function owner() external view override returns (address) {
        return LibDiamond.contractOwner();
    }
}
