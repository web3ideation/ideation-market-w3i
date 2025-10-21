## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
 
## Third-Party Libraries

This project includes code from the following open-source project(s):

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) - Licensed under the MIT License.
- further see the "third-party-licenses" folder

<br><br><br><br><br>


notes:
 logic	After a collection is de-whitelisted, its already-listed tokens can still be bought. purchaseListing() has no onlyWhitelistedCollection check, so a policy change doesn’t fully take effect. -> i think thats fine. just keep in mind that when revoking a collection from the whitelist to cancel all the listings manually.
 approved operators of erc721 can interact with the marketplacediamond on behalv of the owner, tho approced operators of erc1155 can NOT interact with the marketplacediamond on behalv of the owner because for the isApproved check the Owner address must be known tho it is not so it simply is impossible without offchain tracing. [I could add this funcitonality in the future by: require that users “register” as the controller in your protocol pre-listing]
 listedItem.seller == address(0) means that the listing is inactive
 quantity == 0 means its an erc721
 quantity > 0 means its an erc1155
 royalties don't get sent to the defined receiver but credited to their proceeds -> thus they have to actively withdraw them
 before creating the listing the user needs to approve the marketplace (approveForAll) to handle their Token (the ideationMarket fronten already does that)
 explain how to update the whitelist (since that can be done with updatelisting but also directly with the addBuyerWhitelistAddresses)
 highlight that only curated utility token contracts are whitelisted.
 explain the diamondstructure and where devs can find which functions (for example getters you would expect in the ideationmarketfacet are in the getterFacet)


deployment log:
  Deployed diamondInit contract at address: 0x100e67Eb0DCDADEAB6a1258a0b7126bCA4feA709
  Deployed diamondLoupeFacet contract at address: 0x84B5151b8258B025284F163650d220b930204A8F
  Deployed ownershipFacet contract at address: 0x032a247637cD41c675cC82A7149B907a559841aa
  Deployed ideationMarketFacet contract at address: 0xbDD69f91a78883bf7dD725ed1564278C01642e61
  Deployed collectionWhitelistFacet contract at address: 0x36aA6b50b09795c267f66E9580366B6BEa91bcE1
  Deployed buyerWhitelistFacet contract at address: 0x6916B9C69a6ddF63b2638Bc1a6a9910FCDb2ECB1
  Deployed getterFacet contract at address: 0x0e09AD33ddcc746308630F05bF7b71cE03BCfED8
  Deployed diamondCutFacet contract at address: 0x516817c98DA9A426c51731c7eD71d2Dd4d618783
  Deployed Diamond contract at address: 0x8cE90712463c87a6d62941D67C3507D090Ea9d79
  Diamond cuts complete
  Owner of Diamond: 0xE8dF60a93b2B328397a8CBf73f0d732aaa11e33D
https://louper.dev/diamond/0x8cE90712463c87a6d62941D67C3507D090Ea9d79?network=sepolia
https://sepolia.etherscan.io/address/0x8cE90712463c87a6d62941D67C3507D090Ea9d79

for etherscan interaction:
add token address to 'collection whitelist'
approve marketplace to handle the token in the token contract
empty fields either '0' or '0x0000000000000000000000000000000000000000' or 'false'; erc1155 Quanitity for erc721 '1' empty array '[]', price in Wei, payableAmount in ETH


running the sepolia tests:
'source .env' to initiate the dot env variables
'forge test --fork-url $SEPOLIA_RPC_URL -vvv --match-contract DiamondHealth' run the diamondhealth testscript against the local forked sepolia testnet
'forge test --fork-url $SEPOLIA_RPC_URL -vvv --match-contract MarketSmoke' run the MarketSmoke testscript against the local forked sepolia testnet
'forge script test/MarketSmokeBroadcast.s.sol:MarketSmokeBroadcast --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv' run the MarketSmokeBroadcast testscript against the real live sepolia testnet
'forge script test/MarketSmokeBroadcastFull.s.sol:MarketSmokeBroadcastFull --rpc-url $SEPOLIA_RPC_URL --broadcast -vvv' run the MarketSmokeBroadcastFull testscript against the real live sepolia testnet


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
function createListing(
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
function purchaseListing(address nftAddress, uint256 tokenId) external payable;
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





known/accepted flaws:
-no fee limit - the owner can also set fees >100%
-when a token contract has a royalty receiver set to zero address the royalty proceeds will be accredited to the zero address
-buyerWhitelist can be edited even when the flag is disabled for the listing
- more in todo.md "addon projects"