## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Third-Party Libraries

This project includes code from the following open-source project(s):

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) - Licensed under the MIT License.
- further see the "third-party-licenses" folder

<br><br><br><br><br>


notes:
 logic	After a collection is de-whitelisted, its already-listed tokens can still be bought. buyItem() has no onlyWhitelistedCollection check, so a policy change doesn’t fully take effect. -> i think thats fine. just keep in mind that when revoking a collection from the whitelist to cancel all the listings manually.
 approved operators of erc721 can interact with the marketplacediamond on behalv of the owner, tho approced operators of erc1155 can NOT interact with the marketplacediamond on behalv of the owner because for the isApproved check the Owner address must be known tho it is not so it simply is impossible without offchain tracing. [I could add this funcitonality in the future by: require that users “register” as the controller in your protocol pre-listing]


# IdeationMarketDiamond

A decentralized NFT marketplace built on the EIP-2535 Diamonds standard, allowing users to list, buy, sell, and swap NFTs efficiently while ensuring modularity, upgradability, and security. The repository leverages OpenZeppelin’s standards and introduces custom facets for enhanced functionality.

## Overview

The IdeationMarketDiamond implements a robust diamond structure for managing the marketplace. The diamond pattern enables modular development by splitting the contract's logic into various facets, ensuring efficient use of gas and the ability to upgrade specific components without redeploying the entire system.

### Features

- **EIP-2535 Compliant:** Modular and upgradable contract design.
- **NFT Marketplace:** List, buy, cancel, and update NFTs.
- **NFT Swapping:** Swap NFTs directly or with additional ETH.
- **Marketplace Fee:** Configurable fees for transactions.
- **Ownership Management:** Transfer ownership securely.

---

## Contracts Overview

### Core Contracts

- **`IdeationMarketDiamond.sol`**
  The base diamond contract that acts as the central entry point for delegating calls to facets.

- **`DiamondInit.sol`**
  A contract to initialize state variables during diamond deployment.

### Facets

- **`DiamondCutFacet.sol`**
  Enables adding, replacing, or removing facets.

- **`DiamondLoupeFacet.sol`**
  Implements EIP-2535 loupe functions for querying facets and their functions.

- **`OwnershipFacet.sol`**
  Manages ownership of the diamond contract.

- **`IdeationMarketFacet.sol`**
  Core marketplace functionality, including:
  - Listing NFTs
  - Buying NFTs
  - Canceling listings
  - Updating listings
  - Setting marketplace fees
  - Managing proceeds

### Libraries

- **`LibDiamond.sol`**
  Core library for managing diamond storage and functionality.

- **`LibAppStorage.sol`**
  Defines the application-specific storage structure for the marketplace.

---

## Deployment

### Prerequisites

Ensure the following tools are installed:

- [Foundry](https://github.com/foundry-rs/foundry) or [Hardhat](https://hardhat.org/)
- [Node.js](https://nodejs.org/)
- [Solidity](https://soliditylang.org/)

### Deployment Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/IdeationMarketDiamond.git
   cd IdeationMarketDiamond
   ```

2. Install dependencies:
   ```bash
   forge install
   ```

3. Deploy the diamond:
   Update the deploy script (`script/deployDiamond.s.sol`) with the desired owner address and fee percentage. Then run:
   ```bash
   forge script script/deployDiamond.s.sol --broadcast
   ```

4. Verify deployment:
   ```bash
   forge verify-contract --chain <chain-id> <contract-address>
   ```

---

## Usage

### Core Functions

#### Listing an NFT
```solidity
function listItem(
    address nftAddress,
    uint256 tokenId,
    uint256 price,
    address desiredNftAddress,
    uint256 desiredTokenId
) external;
```
List an NFT for sale or swap.

#### Buying an NFT
```solidity
function buyItem(address nftAddress, uint256 tokenId) external payable;
```
Buy an NFT by sending the required ETH.

#### Updating a Listing
```solidity
function updateListing(
    address nftAddress,
    uint256 tokenId,
    uint256 newPrice,
    address newDesiredNftAddress,
    uint256 newDesiredTokenId
) external;
```
Update the price or swap conditions of a listed NFT.

#### Canceling a Listing
```solidity
function cancelListing(address nftAddress, uint256 tokenId) external;
```
Cancel an active NFT listing.

#### Withdrawing Proceeds
```solidity
function withdrawProceeds() external;
```
Withdraw accumulated proceeds from sales.

#### Setting Fees
```solidity
function innovationFee(uint32 fee) external;
```
Update the marketplace/innovation fee (only accessible by the owner).

---

## Security Considerations

1. **Reentrancy Protection:**
   The `nonReentrant` modifier is applied to critical functions to prevent reentrancy attacks.

2. **Upgradability:**
   Changes to the diamond structure follow EIP-2535 guidelines to ensure compatibility.

3. **Ownership Management:**
   Ownership functions are secured using the `onlyOwner` modifier.

4. **Approval Validation:**
   The marketplace ensures that NFTs are approved for transfer before completing transactions.

---

## Testing

### Unit Tests

The repository includes unit tests to validate core functionality. To run tests:

```bash
forge test
```

### Areas Tested

- Listing, buying, and canceling NFTs
- Fee calculations and updates
- Ownership transfer
- Reentrancy attacks

---

## Contributing

Contributions are welcome! Please fork the repository, make changes, and submit a pull request.

---

## License

This project is licensed under the MIT License. See the `LICENSE` file for details.

---

## Contact

For questions or support, please reach out to [your-email@example.com](mailto:your-email@example.com).

---

## Acknowledgments

This project leverages:

- [EIP-2535 Diamonds](https://eips.ethereum.org/EIPS/eip-2535)
- [OpenZeppelin Contracts](https://openzeppelin.com/contracts/)
- [Foundry](https://github.com/foundry-rs/foundry)

