## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
 
## Third-Party Libraries

This project includes code from the following open-source project(s):

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) - Licensed under the MIT License.
- [mudgen/diamond](https://github.com/mudgen/diamond) - Licensed under the MIT License.
- [diamond-3-foundry (Alex Babits)](https://github.com/alexbabits/diamond-3-foundry) - Licensed under the MIT License.
- further see the "third-party-licenses" folder

Portions of this project are based on and adapted from the Diamonds reference implementations and Alex Babits' diamond-3-foundry educational template. See [NOTICE](NOTICE) for detailed third-party attributions.

## ERC-8109 note

This repo originally started from a classic diamond template, but the *upgrade entrypoint* has been migrated to
**ERC-8109**. The on-chain upgrade function is `upgradeDiamond(...)`.

<br><br><br><br><br>


notes: // !!!W check these if they are still up to date and integrate the info in the final readme
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


deployment 1 log:
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

deployment 2 log
Diamond Address: 0xF422A7779D2feB884CcC1773b88d98494A946604
Owner: 0xE8dF60a93b2B328397a8CBf73f0d732aaa11e33D
Version: 1.0.0
Implementation ID: 0x359675c94671bb21ec1b9cdf35889444129ffe792962a68e660b24c9b1eb1fed
FACETS:
DiamondInit: 0xc82B382b69cB613703cF6F01ba4867Ff5443a4E4
DiamondLoupeFacet: 0x64218c3Fa4896be3F596177c1080C59751e013e7
OwnershipFacet: 0x57db2c739633EF5A050CDB1dBB29f48f092b5078
IdeationMarketFacet: 0x5Aa7C259D668cf3868b5D1831b760EfB2E9443e8
CollectionWhitelistFacet: 0x1aF98799D02d1a46123725bDD65b96b2A7FAb2F8
BuyerWhitelistFacet: 0xf14A6B456B465A38aCF44180B85AA3334F92a1F5
GetterFacet: 0x80525592f21245EdfdDa6c725AC31c73f04F76D2
CurrencyWhitelistFacet: 0x827E91DF79357679F9B02690746fa3F0e7dB3C11
VersionFacet: 0xbd390aD3058E0BA40AcDa61a72ebAEEF58891394
PauseFacet: 0x4285d039DBDBee9bAa4785b9e1919095Dc030CF6
DiamondCutFacet: 0x8D6805898180257A38F89d1DFb868C1A8c38E2Fb
EXPLORERS:
Louper: https://louper.dev/diamond/0xF422A7779D2feB884CcC1773b88d98494A946604?network=sepolia
Etherscan: https://sepolia.etherscan.io/address/0xF422A7779D2feB884CcC1773b88d98494A946604

deployment 3 log:
  Deployed diamondInit contract at address: 0x6ab53B38A5703387e0E2Ee3D1AD99894728e587c
  Deployed diamondLoupeFacet contract at address: 0x16D2e785ec9f270C8e0CdB6dc0Ca0f0f9646610C
  Deployed ownershipFacet contract at address: 0x1dEEE0f8e73a19E31c49D51419C47e15f48667f9
  Deployed ideationMarketFacet contract at address: 0x6f4e8be1EEaF712a3ff85E7FFe992d21794E790E
  Deployed collectionWhitelistFacet contract at address: 0x1eeDB782151377AC05d61EecC3Bdf4ECCbf3B298
  Deployed buyerWhitelistFacet contract at address: 0x1b0Dc3BD49A8bd493387bb49376212B9b0A9A64f
  Deployed getterFacet contract at address: 0xb42c109A61Cb882B11bb7E98B9A0302C3E486327
  Deployed currencyWhitelistFacet contract at address: 0xf98025444A70391286e15014023758624754d780
  Deployed versionFacet contract at address: 0xeDD15c75a980da4eD70F609c30F8E73bCDBdd186
  Deployed pauseFacet contract at address: 0xc39f8c071668Eea19392F1Ea3AC7fe8A5391b4b3
  Deployed diamondUpgradeFacet contract at address: 0xDA227064DadE08d65d1880488B368B1A73AAA489
  Deployed Diamond contract at address: 0x1107Eb26D47A5bF88E9a9F97cbC7EA38c3E1D7EC
  Diamond upgrade complete
  Owner of Diamond: 0xE8dF60a93b2B328397a8CBf73f0d732aaa11e33D
  Setting version: 1.0.0
  Version set: 1.0.0
  Implementation ID:
  0x94e212f6785d382d4e9f65c8e49dfa69523440374e542ea38617b9fc295a69a4
EXPLORERS:
Louper: https://louper.dev/diamond/0x1107Eb26D47A5bF88E9a9F97cbC7EA38c3E1D7EC?network=sepolia
Etherscan: https://sepolia.etherscan.io/address/0x1107Eb26D47A5bF88E9a9F97cbC7EA38c3E1D7EC


for etherscan interaction: // !!!W check these if they are still up to date and integrate the info in the final readme
add token address to 'collection whitelist'
approve marketplace to handle the token in the token contract
empty fields either '0' or '0x0000000000000000000000000000000000000000' or 'false'; erc1155 Quanitity for erc721 '1' empty array '[]', price in Wei, payableAmount in ETH


running the sepolia tests: // !!!W check these if they are still up to date and integrate the info in the final readme
'source .env' to initiate the dot env variables
'forge test --fork-url $SEPOLIA_RPC_URL -vvv --match-contract DiamondHealth' run the diamondhealth testscript against the local forked sepolia testnet
'forge test --fork-url $SEPOLIA_RPC_URL -vvv --match-contract MarketSmoke' run the MarketSmoke testscript against the local forked sepolia testnet
'forge script test/MarketSmokeBroadcast.s.sol:MarketSmokeBroadcast --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv' run the MarketSmokeBroadcast testscript against the real live sepolia testnet
'forge script test/MarketSmokeBroadcastFull.s.sol:MarketSmokeBroadcastFull --rpc-url $SEPOLIA_RPC_URL --broadcast -vvv' run the MarketSmokeBroadcastFull testscript against the real live sepolia testnet


# IdeationMarketDiamond

A decentralized NFT marketplace built on a diamond architecture with an **ERC-8109** upgrade interface (`upgradeDiamond`).
It allows users to list, buy, sell, and swap NFTs while keeping the contract modular, upgradeable, and security-auditable.

## Overview

The IdeationMarketDiamond implements a robust diamond structure for managing the marketplace. The diamond pattern enables modular development by splitting the contract's logic into various facets, ensuring efficient use of gas and the ability to upgrade specific components without redeploying the entire system.

### Features

- **ERC-8109 Upgrades:** Modular and upgradable via `upgradeDiamond`.
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

- **`DiamondUpgradeFacet.sol`**
  Implements ERC-8109 `upgradeDiamond(...)` to add/replace/remove selectors.

- **`DiamondLoupeFacet.sol`**
  Provides loupe/introspection and includes the ERC-8109 required `functionFacetPairs()`.

- **`OwnershipFacet.sol`**
  Manages ownership of the diamond contract.

- **`VersionFacet.sol`**
  Tracks diamond versioning with cryptographic implementation fingerprints for audit verification.

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

## Diamond Versioning

The IdeationMarketDiamond implements a comprehensive versioning system designed to provide transparency and verifiability for auditors, users, and integrators.

### Overview

Each diamond deployment or upgrade is assigned:
- **Version String:** Semantic version (e.g., "1.0.0", "1.2.1") for human-readable tracking
- **Implementation ID:** Cryptographic hash uniquely identifying the exact diamond configuration
- **Timestamp:** When the version was set

### Implementation ID

The `implementationId` is a deterministic `bytes32` hash computed as:

```solidity
keccak256(abi.encode(
    chainId,           // Network chain ID
    diamondAddress,    // Diamond contract address
    facetAddresses[],  // Sorted array of facet addresses
    selectors[][]      // Sorted array of selectors per facet
))
```

This fingerprint guarantees that:
- Any change to facets or their functions produces a different ID
- Two diamonds with identical configuration produce the same ID
- Auditors can verify the deployed diamond matches the audited version

### Querying Version Information

```solidity
// Get current version
(string memory version, bytes32 implementationId, uint256 timestamp) = 
    GetterFacet(diamond).getVersion();

// Get previous version (after upgrades)
(string memory prevVersion, bytes32 prevId, uint256 prevTimestamp) = 
    GetterFacet(diamond).getPreviousVersion();

// Convenience getters
string memory version = GetterFacet(diamond).getVersionString();
bytes32 id = GetterFacet(diamond).getImplementationId();
```

### Setting Versions (Automatic)

The deployment and upgrade scripts automatically compute and set the version after every upgrade.

#### Initial Deployment

```bash
# Version defaults to "1.0.0" or set via VERSION_STRING
VERSION_STRING="1.0.0" forge script script/DeployDiamond.s.sol:DeployDiamond \
    --rpc-url $RPC_URL --broadcast
```

The script automatically:
1. Deploys all facets and the diamond
2. Executes `upgradeDiamond`
3. **Automatically queries all facets and selectors via DiamondLoupe**
4. **Computes the implementationId hash deterministically**
5. **Calls `setVersion()` with the version string and ID**

#### Upgrade Workflow

```bash
# Version set via VERSION_STRING
DIAMOND_ADDRESS=0x... VERSION_STRING="1.1.0" \
forge script script/UpgradeDiamond.s.sol:UpgradeDiamond \
    --rpc-url $RPC_URL --broadcast
```

The upgrade script automatically:
1. Performs the upgrade (deploy facets, add/replace/remove functions via `upgradeDiamond`)
2. **Automatically computes and sets the new version**
3. Shows before/after version information

**No separate versioning step needed!** The version is always set automatically after any diamond modification.

#### Manual Version Setting (Owner Only)

If you ever need to manually update the version (e.g., to correct metadata), the diamond owner can call `setVersion()` directly:

```solidity
// Only the diamond owner can do this
VersionFacet(diamondAddress).setVersion("1.0.1", computedImplementationId);
```

### For Auditors

When auditing this diamond:

1. **Record the Version:** Note the `implementationId` at audit time
2. **Document in Report:** Include version string and implementationId in your audit report
3. **Verification:** Users can call `getImplementationId()` to verify they're using the audited configuration

### For Frontend Integrators

```javascript
// Check if diamond matches audited version
const auditedImplementationId = "0x..."; // From audit report
const currentId = await getterFacet.getImplementationId();

if (currentId === auditedImplementationId) {
    // Show: "✓ Audited version 1.0.0"
} else {
    // Show: "⚠ Warning: Post-audit upgrade detected"
    const prevId = await getterFacet.getPreviousVersion();
    // Check if previous version was audited
}
```

### Version History

The `VersionFacet` maintains:
- **Current version:** Active diamond configuration
- **Previous version:** Last configuration before most recent upgrade
- **Events:** Logs every Version update on the EVM Log
```
VersionUpdated(string version, bytes32 indexed implementationId, uint256 timestamp);
```

This provides a minimal audit trail while keeping storage efficient.

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
  Selector/facet upgrades are executed via ERC-8109 `upgradeDiamond`.

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

- [mudgen/diamond](https://github.com/mudgen/diamond) (basis for the diamond template)
- [alexbabits/diamond-3-foundry](https://github.com/alexbabits/diamond-3-foundry) (educational Foundry/AppStorage adaptation)
- [OpenZeppelin Contracts](https://openzeppelin.com/contracts/)
- [Foundry](https://github.com/foundry-rs/foundry)





known/accepted flaws:
-no fee limit - the owner can also set fees >100%
-when a token contract has a royalty receiver set to zero address the royalty proceeds will be accredited to the zero address
-buyerWhitelist can be edited even when the flag is disabled for the listing
- more in todo.md "addon projects"