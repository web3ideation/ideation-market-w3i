# Ideation Market (Diamond)

A curated NFT marketplace built as an **ERC-8109 diamond** (upgrade/inspect surface), using classic EIP-2535-style selector→facet dispatch.

It uses the standard EIP-2535-style selector→facet dispatch pattern, and layers ERC-8109’s `upgradeDiamond(...)` upgrade entrypoint plus `functionFacetPairs()` introspection on top.

Supports:
- ERC-721 and ERC-1155 listings
- Optional swaps (NFT-for-NFT, with optional ETH or ERC-20 payment)
- Optional per-listing buyer whitelists
- Optional ERC-1155 partial buys
- Collection whitelist (curated NFT contracts)
- Currency allowlist (curated payment tokens)

This README aims to match the code in:
- [src/IdeationMarketDiamond.sol](src/IdeationMarketDiamond.sol)
- [src/facets](src/facets)

---

## License / Attribution

MIT licensed. See [LICENSE](LICENSE).

This repo contains third-party dependencies and developer/security tooling that may be licensed separately. See [NOTICE](NOTICE) and the respective subdirectories.

Notable upstream inspirations:
- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts)
- [mudgen/diamond](https://github.com/mudgen/diamond)
- [alexbabits/diamond-3-foundry](https://github.com/alexbabits/diamond-3-foundry)

---

## ERC-8109 Note

This repo’s diamond implements the ERC-8109 upgrade entrypoint `DiamondUpgradeFacet.upgradeDiamond(...)` and the ERC-8109 inspect surface via `DiamondLoupeFacet.functionFacetPairs()`.

The underlying call routing is still the classic EIP-2535-style selector→facet mapping with `delegatecall`.

Strict ERC-8109 specifies the fallback “unknown selector” revert as `FunctionNotFound(bytes4)`. This implementation uses a different custom error (`Diamond__FunctionDoesNotExist()`), while still matching the ERC-8109 upgrade + inspect surfaces and emitting the per-selector upgrade events.

The EIP-2535 `diamondCut(...)` entrypoint is not exposed in this repo.

---

## Diamond / Facets Map

The diamond delegates calls to facets. Read-only queries are intentionally separated into `GetterFacet`.

- `IdeationMarketDiamond` — diamond proxy/dispatcher.
- `DiamondUpgradeFacet` — ERC-8109 `upgradeDiamond(...)` (add/replace/remove selectors, optional initializer delegatecall).
- `DiamondLoupeFacet` — introspection + ERC-8109-required `functionFacetPairs()`.
- `OwnershipFacet` — ERC-173 **two-step** ownership (`transferOwnership` + `acceptOwnership`).
- `IdeationMarketFacet` — marketplace core (create/purchase/update/cancel/clean, payments, swaps, fees).
- `CollectionWhitelistFacet` — owner-managed NFT collection whitelist.
- `CurrencyWhitelistFacet` — owner-managed payment currency allowlist.
- `BuyerWhitelistFacet` — per-listing buyer whitelist mutations (seller or authorized operator).
- `PauseFacet` — emergency pause/unpause.
- `VersionFacet` — owner-only version writes.
- `GetterFacet` — read-only queries (listings, whitelists, version, pause state, etc.).


---

## Core Concepts (Marketplace Semantics)

### Listings and IDs

- Listings are keyed by an incrementing `listingId` (not by `(tokenAddress, tokenId)`).
- A listing is created by calling `createListing(...)` as the token owner/holder or an authorized operator (depending on ERC-721 vs ERC-1155).
- On creation, the contract increments a monotonic counter and assigns the next `listingId` (in creation order, never reused).
- The listing then persists in the diamond’s storage as a `Listing` struct under `AppStorage.listings[listingId]` until it is canceled/cleaned.
- Read the current listing terms via `GetterFacet.getListingByListingId(listingId)`.
- `listing.seller == address(0)` means the listing is **inactive / deleted / nonexistent**.
- Non-swap listings require `price > 0` (free listings are not supported).
- Token standard is inferred from `erc1155Quantity`:
  - `erc1155Quantity == 0` → ERC-721 listing
  - `erc1155Quantity > 0` → ERC-1155 listing
- ERC-721 has a single-active-listing guard via `activeListingIdByERC721[tokenAddress][tokenId]`.

### Approvals and Operators

Before listing or swapping, the diamond must be approved to transfer tokens:

- ERC-721: `approve(diamond, tokenId)` or `setApprovalForAll(diamond, true)`
- ERC-1155: `setApprovalForAll(diamond, true)`

For swap purchases, the holder of the desired NFT must also approve the diamond to transfer the desired token.

Who may create/update/cancel listings:

- ERC-721: token owner, `getApproved(tokenId)`, or `isApprovedForAll(owner, operator)`.
- ERC-1155: because ERC-1155 has no `ownerOf`, functions take an explicit `erc1155Holder` when needed.
  - Operators can act on behalf of a holder if `isApprovedForAll(holder, operator)`.
  - The contract cannot infer the holder on-chain; callers must provide it.

### Buyer Whitelists (Per Listing)

Listings can enable `buyerWhitelistEnabled`.

- If enabled, only addresses in the per-listing whitelist can purchase.
- Initial whitelist entries can be supplied during `createListing` / `updateListing`.
- The seller (or an authorized operator) can add/remove addresses via `BuyerWhitelistFacet`.
- There is a max batch size (`buyerWhitelistMaxBatchSize`) set during initialization.

How to update the whitelist:

- **At listing create/update time:** pass addresses in `allowedBuyers`.
  - This only *adds* addresses (no removals).
  - `allowedBuyers` is only accepted when `buyerWhitelistEnabled == true` (otherwise `createListing` / `updateListing` revert).
- **After the listing exists:** call the dedicated facet methods on the diamond:
  - `BuyerWhitelistFacet.addBuyerWhitelistAddresses(listingId, allowedBuyers)`
  - `BuyerWhitelistFacet.removeBuyerWhitelistAddresses(listingId, disallowedBuyers)`
  These can be used for incremental updates without changing other listing terms.

Note: whitelist storage can be modified even if `buyerWhitelistEnabled == false`; purchases are only restricted when the flag is enabled.

### Swaps

Listings may optionally specify a desired NFT (`desiredTokenAddress`, `desiredTokenId`, `desiredErc1155Quantity`).

- If `desiredTokenAddress == address(0)`, the listing is a normal sale (no swap).
- If `desiredTokenAddress != address(0)`, `purchaseListing` transfers the desired NFT to the seller as part of the purchase.
  - ERC-721 desired: transferred from the desired token’s current owner; the caller must be the owner or an authorized operator.
  - ERC-1155 desired: transferred from `desiredErc1155Holder`; the caller must be that holder or an authorized operator.
- Same-token swaps are rejected (same contract + same tokenId).

### Curation: Collection Whitelist vs Currency Allowlist

This market is intentionally curated:

- **Collection whitelist** (NFT contracts): enforced for `createListing`, `updateListing`, and `purchaseListing`.
- **Currency allowlist** (payment currencies): enforced for `createListing` and `updateListing`.

Policy changes take effect immediately:

- If a collection is de-whitelisted after listings exist, `purchaseListing` will revert for those listings.
- `updateListing` will auto-cancel if the collection was revoked.
- Anyone can call `cleanListing` to remove listings that fail collection-whitelist, ownership/balance, or marketplace-approval checks.

Currency allowlist changes only affect `createListing` / `updateListing`. Existing listings can still be purchased in their configured currency (and `cleanListing` does not validate the currency allowlist).

### Fees and Royalties

- Fee denominator is **100_000**. Example: `1_000` = 1%.
- The current fee (`innovationFee`) is snapshotted into each listing at creation time as `Listing.feeRate`.
- ERC-2981 royalties (when supported) are paid **directly** to the royalty receiver during purchase.
- If `royaltyReceiver == address(0)`, royalties are skipped.

There is **no** “proceeds mapping” and **no** `withdrawProceeds()` flow in this design.

### Payments

- ETH listings require **exact** `msg.value` (no overpayment).
- ERC-20 listings require `msg.value == 0`.
- ERC-20 transfers are executed directly from buyer → recipients using `transferFrom`.
  The diamond does **not** custody ERC-20 balances.

### ERC-1155 Partial Buys

ERC-1155 listings can enable `partialBuyEnabled`.

- Not allowed for swap listings.
- `price % erc1155Quantity == 0` is required (stable per-unit price).
- Purchases specify `erc1155PurchaseQuantity`.

### Pause

When paused:
- `createListing`, `updateListing`, `purchaseListing` revert
- `cancelListing` and `cleanListing` remain callable

---

## Key Write Methods (Exact Signatures)

Canonical signatures live in [src/facets/IdeationMarketFacet.sol](src/facets/IdeationMarketFacet.sol).

### `createListing`

```solidity
function createListing(
    address tokenAddress,
    uint256 tokenId,
    address erc1155Holder,
    uint256 price,
    address currency,
    address desiredTokenAddress,
    uint256 desiredTokenId,
    uint256 desiredErc1155Quantity,
    uint256 erc1155Quantity,
    bool buyerWhitelistEnabled,
    bool partialBuyEnabled,
    address[] calldata allowedBuyers
) external;
```

### `purchaseListing`

```solidity
function purchaseListing(
    uint128 listingId,
    uint256 expectedPrice,
    address expectedCurrency,
    uint256 expectedErc1155Quantity,
    address expectedDesiredTokenAddress,
    uint256 expectedDesiredTokenId,
    uint256 expectedDesiredErc1155Quantity,
    uint256 erc1155PurchaseQuantity,
    address desiredErc1155Holder
) external payable;
```

`expected*` arguments provide front-run protection and must match the current listing terms (e.g., read via `GetterFacet.getListingByListingId`).

---

## Etherscan “Write” Cheatsheet

Common flow on a fresh deployment:

1. Owner: whitelist the NFT collection
   - `CollectionWhitelistFacet.addWhitelistedCollection(collection)`
2. Owner: allow a payment currency (if not already allowed)
   - `CurrencyWhitelistFacet.addAllowedCurrency(currency)`
   - Note: the initializer [src/upgradeInitializers/DiamondInit.sol](src/upgradeInitializers/DiamondInit.sol) seeds `address(0)` (ETH) plus many widely used ERC-20 addresses.
3. Seller: approve the diamond on the NFT contract
   - ERC-721: `approve(diamond, tokenId)` or `setApprovalForAll(diamond, true)`
   - ERC-1155: `setApprovalForAll(diamond, true)`
4. Seller: call `createListing(...)`
5. Buyer: read the listing via `GetterFacet.getListingByListingId(listingId)` and pass the returned values as `expected*` when calling `purchaseListing`.

If the listing currency is an ERC-20 token (i.e., `listing.currency != address(0)`):

6. Buyer: approve the diamond to spend that ERC-20 before calling `purchaseListing`.
  - On the ERC-20 token contract, call `approve(spender = diamond, amount = purchasePrice)` (or a larger allowance).

Parameter conventions for Etherscan writes (common “empty field” values):

- All ETH-denominated amounts are in **wei**.
- On Etherscan, the transaction **Value** field maps to `msg.value` and must be entered in **wei**.
- Zero address: `0x0000000000000000000000000000000000000000` (used for “no swap” and for ETH currency)
- Zero integers: `0`
- False booleans: `false`
- Empty arrays: `[]`
- ERC-721 listings: set `erc1155Quantity = 0` and pass `erc1155Holder = 0x0000000000000000000000000000000000000000`
- Non-swap listings: set `desiredTokenAddress = 0x0000000000000000000000000000000000000000`, `desiredTokenId = 0`, `desiredErc1155Quantity = 0`

Buying a simple ERC-721 ETH listing (no swap) requires:

- `expectedCurrency = 0x0000000000000000000000000000000000000000`
- `expectedErc1155Quantity = 0`
- `expectedDesiredTokenAddress = 0x0000000000000000000000000000000000000000`
- `expectedDesiredTokenId = 0`
- `expectedDesiredErc1155Quantity = 0`
- `erc1155PurchaseQuantity = 0`
- `desiredErc1155Holder = 0x0000000000000000000000000000000000000000`
- `msg.value` must equal `expectedPrice`

Buying an ERC-721 ERC-20 listing (no swap) is the same, except:

- Ensure the ERC-20 `approve(...)` is done first
- `msg.value` must be `0`

ERC-1155 listings and swaps require supplying the correct holder parameters and quantities.

---

## Diamond Versioning (VersionFacet + implementationId)

The diamond tracks:
- a human-readable `versionString`
- a deterministic `implementationId` fingerprint

The `implementationId` is computed by scripts by querying facets/selectors via loupe, sorting deterministically, and hashing.
See [script/DeployDiamond.s.sol](script/DeployDiamond.s.sol) for the canonical computation.

Conceptually:

```solidity
keccak256(abi.encode(
  chainId,
  diamondAddress,
  sortedFacetAddresses,
  sortedSelectorsPerFacet
));
```

Why this matters:
- Any selector/facet change produces a new `implementationId`.
- Frontends/auditors can check interaction against a known configuration.

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

Note: The deployment and upgrade scripts automatically compute and set the version after every upgrade.


---

## Deploy / Upgrade / Verify (Foundry)

### Deploy

Deployment is driven by [script/DeployDiamond.s.sol](script/DeployDiamond.s.sol).

Env vars used by the script:
- `SEPOLIA_RPC_URL` (or any chain RPC URL)
- `DEV_PRIVATE_KEY` (deployer key; becomes initial owner)
- `VERSION_STRING` (optional; defaults to `1.0.0`)
- `ETHERSCAN_API_KEY` (optional, for `--verify`)

Example:

```bash
source .env
forge script script/DeployDiamond.s.sol:DeployDiamond \
  --rpc-url $SEPOLIA_RPC_URL --broadcast --verify -vvvv
```

### Upgrade example (dummy)

There is an example upgrade flow in [script/UpgradeDummy.s.sol](script/UpgradeDummy.s.sol) plus initializer logic under [src/upgradeInitializers](src/upgradeInitializers).

This script deploys and installs `DummyUpgradeFacet` as a minimal upgrade target for validating upgrade mechanics; it is not part of the default production facet set.

### Deploy mocks + mint (optional)

For local/testnet convenience there is [script/DeployMocksAndMint.s.sol](script/DeployMocksAndMint.s.sol).

---

## Tests

### Unit tests

```bash
forge test
```

### Sepolia broadcast scripts

Broadcastable smoke scripts against live Sepolia deployment, live under [test/integration](test/integration).

They expect:
- `SEPOLIA_RPC_URL`
- `PRIVATE_KEY_1` / `PRIVATE_KEY_2` (must control the hardcoded accounts inside the scripts)
- `DIAMOND_ADDRESS` (optional override)

Additional requirements:
- The two hardcoded accounts must hold the expected NFTs used by the smoke flow (seller/buyer token assumptions in the script).
- If you cannot use those exact accounts/NFTs, adapt the script constants (accounts, token contract, token IDs, prices) to assets you control on the target network.

```bash
source .env

forge script test/integration/MarketSmokeBroadcast.s.sol:MarketSmokeBroadcast \
  --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv

forge script test/integration/MarketSmokeBroadcastFull.s.sol:MarketSmokeBroadcastFull \
  --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv
```

### Optional fork tests (disabled by default)

Fork-style tests exist as `*.sol.disabled` under [test/integration](test/integration).
Running them requires renaming to `.sol` (or copying), then executing:

```bash
forge test --fork-url $SEPOLIA_RPC_URL -vvv --match-contract DiamondHealth
forge test --fork-url $SEPOLIA_RPC_URL -vvv --match-contract MarketSmoke
```

Requirements / assumptions for fork tests:
- `SEPOLIA_RPC_URL` is required.
- `DIAMOND_ADDRESS` can be overridden; otherwise the default address hardcoded in the test is used.
- `MarketSmoke` assumes specific account and NFT ownership state on Sepolia (hardcoded addresses and token IDs in the test constants).

Note:
- Unlike broadcast scripts, fork tests do not require private keys, but they still require the expected on-chain ownership assumptions to be true.
- If those assumptions are not accessible in your environment, adapt the test constants (accounts, token contract, token IDs, prices) to accounts/NFTs you can use.

---

## Helper Scripts

Small utilities under [script](script) for day-to-day development/ops tasks.

- Selector clash check (facets): `bash script/check-selectors.sh`
- Compare deployed runtime bytecode (across networks): `bash script/compare-contract-code.sh --rpc-a <RPC_A> --addr-a <ADDR_A> --rpc-b <RPC_B> --addr-b <ADDR_B>`
- Generate Etherscan Standard-JSON input (manual verification helper):
  - One contract: `python3 script/make_etherscan_input.py <file.sol:ContractName> [out.json]`
  - All facets + diamond: `python3 script/make_etherscan_input.py --all [out_dir]`

---

## Security Tooling

Wrapper scripts live in [script](script) and reports/artifacts are stored under [security-tools](security-tools).

- Slither: `bash script/run-slither.sh`
- 4naly3er: `bash script/run-4naly3er.sh`
- Echidna: `bash script/run-echidna.sh`
- Gas snapshots: `bash script/gas-snapshot-update.sh` / `bash script/gas-snapshot-check.sh`

Echidna notes:
- The harness is [security-tools/echidna/Harness.sol](security-tools/echidna/Harness.sol).
- The runner mirrors [src](src) into `security-tools/echidna/src/` for self-contained compilation.
- Corpus and crytic artifacts are written under `security-tools/echidna/echidna_corpus/` and `security-tools/echidna/crytic-export/`.

---

## Known / Accepted Limitations

- **No fee cap:** `setInnovationFee` has no upper bound. If `innovationFee > 100_000`, purchases will revert due to underflow in proceeds calculation.
- **Buyer whitelist storage is mutable regardless of flag:** addresses can be added/removed even when `buyerWhitelistEnabled == false`. This is intended for preparing a listings whitelist despite its state.
- **Currency allowlist is curated:** `DiamondInit` seeds a curated token list; on testnets those addresses may not exist.

More follow-ups live in [ToDo.md](ToDo.md) (developer notes).

---

## Sepolia Deployments (Historical) !!!W archive this after golife

Archived deployment logs captured during development.

Note: older logs may mention facets that existed before the ERC-8109 migration (kept as-is for traceability).

<details>
<summary>Deployment log 1</summary>

```
Deployed diamondInit contract at address: 0x100e67Eb0DCDADEAB6a1258a0b7126bCA4feA709
Deployed diamondLoupeFacet contract at address: 0x84B5151b8258B025284F163650d220b930204A8F
Deployed ownershipFacet contract at address: 0x032a247637cD41c675cC82A7149B907a559841aa
Deployed ideationMarketFacet contract at address: 0xbDD69f91a78883bf7dD725ed1564278C01642e61
Deployed collectionWhitelistFacet contract at address: 0x36aA6b50b09795c267f66E9580366B6BEa91bcE1
Deployed buyerWhitelistFacet contract at address: 0x6916B9C69a6ddF63b2638Bc1a6a9910FCDb2ECB1
Deployed getterFacet contract at address: 0x0e09AD33ddcc746308630F05bF7b71cE03BCfED8
Deployed diamondCutFacet contract at address: 0x516817c98DA9A426c51731c7eD71d2Dd4d618783
Deployed Diamond contract at address: 0x8cE90712463c87a6d62941D67C3507D090Ea9d79
Owner of Diamond: 0xE8dF60a93b2B328397a8CBf73f0d732aaa11e33D

Louper:    https://louper.dev/diamond/0x8cE90712463c87a6d62941D67C3507D090Ea9d79?network=sepolia
Etherscan: https://sepolia.etherscan.io/address/0x8cE90712463c87a6d62941D67C3507D090Ea9d79
```

</details>

<details>
<summary>Deployment log 2</summary>

```
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

Louper:    https://louper.dev/diamond/0xF422A7779D2feB884CcC1773b88d98494A946604?network=sepolia
Etherscan: https://sepolia.etherscan.io/address/0xF422A7779D2feB884CcC1773b88d98494A946604
```

</details>

<details>
<summary>Deployment log 3</summary>

```
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
Owner of Diamond: 0xE8dF60a93b2B328397a8CBf73f0d732aaa11e33D

Louper:    https://louper.dev/diamond/0x1107Eb26D47A5bF88E9a9F97cbC7EA38c3E1D7EC?network=sepolia
Etherscan: https://sepolia.etherscan.io/address/0x1107Eb26D47A5bF88E9a9F97cbC7EA38c3E1D7EC

ERC20 Mocks:

Deployed MockERC20_18: 0xC740Ee33A12c21Fa7F3cdd426D6051e16EaB456e
Deployed MockUSDC_6: 0xEaefa01B8c4c8126226A8B2DA2cF6Eb0E5B0bD26
Deployed MockWBTC_8: 0xB1A8786Fd1bBDB7F56f8cEa78A77897a0Aa9fAb2
Deployed MockEURS_2: 0xe06E78AB6314993FCa9106536aecfE4284aA791a
Deployed MockUSDTLike_6: 0xd11Db19892F8c9C89A03Ba6EFD636795cbBc0d74
Minted to: 0xE8dF60a93b2B328397a8CBf73f0d732aaa11e33D
Minted to: 0x8a200122f666af83aF2D4f425aC7A35fa5491ca7
Minted to: 0xf034e8ad11F249c8081d9da94852bE1734bc11a4
```

</details>
