// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IERC173} from "../interfaces/IERC173.sol";

error Ownership__CallerIsNotThePendingOwner();

/// @title OwnershipFacet (ERC-173 two-step ownership)
/// @notice Implements ERC-173 with nomination + acceptance to finalize transfers.
/// @dev Uses LibDiamond storage: sets `pendingContractOwner` on nominate; `setContractOwner` on accept.
contract OwnershipFacet is IERC173 {
    /// @notice Emitted once a new owner is nominated
    event OwnershipTransferInitiated(address indexed previousOwner, address indexed newOwner);

    /// @notice Owner nominates a new owner
    /// @dev Sets `pendingContractOwner`. The nominee must call `acceptOwnership` to finalize.
    /// @param newOwner The address nominated to become the new owner.
    /// @dev Setting `newOwner` to address(0) does not renounce ownership in this two-step model; it only makes
    /// `acceptOwnership()` impossible until a nonzero nominee is set.
    function transferOwnership(address newOwner) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.diamondStorage().pendingContractOwner = newOwner;
        emit OwnershipTransferInitiated(msg.sender, newOwner);
    }

    /// @notice Pending owner calls to accept and finalize transfer
    /// @dev Reverts with `Ownership__CallerIsNotThePendingOwner` if caller is not the nominee.
    /// Resets `pendingContractOwner` to zero after success and emits ERC-173 `OwnershipTransferred`.
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
