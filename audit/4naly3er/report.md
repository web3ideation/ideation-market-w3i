# Report


## Gas Optimizations


| |Issue|Instances|
|-|:-|:-:|
| [GAS-1](#GAS-1) | `a = a + b` is more gas effective than `a += b` for state variables (excluding arrays and mappings) | 4 |
| [GAS-2](#GAS-2) | Using bools for storage incurs overhead | 5 |
| [GAS-3](#GAS-3) | For Operations that will not overflow, you could use unchecked | 106 |
| [GAS-4](#GAS-4) | Use Custom Errors instead of Revert Strings to save Gas | 12 |
| [GAS-5](#GAS-5) | Avoid contract existence checks by using low level calls | 5 |
| [GAS-6](#GAS-6) | Functions guaranteed to revert when called by normal users can be marked `payable` | 4 |
| [GAS-7](#GAS-7) | `++i` costs less gas compared to `i++` or `i += 1` (same for `--i` vs `i--` or `i -= 1`) | 18 |
| [GAS-8](#GAS-8) | Use != 0 instead of > 0 for unsigned integer comparison | 28 |
### <a name="GAS-1"></a>[GAS-1] `a = a + b` is more gas effective than `a += b` for state variables (excluding arrays and mappings)
This saves **16 gas per instance.**

*Instances (4)*:
```solidity
File: facets/IdeationMarketFacet.sol

376:                 s.proceeds[royaltyReceiver] += royaltyAmount; // Update proceeds for the Royalty Receiver

386:         s.proceeds[listedItem.seller] += sellerProceeds;

387:         s.proceeds[LibDiamond.contractOwner()] += innovationProceeds;

389:             s.proceeds[msg.sender] += excessPayment;

```
[Link to code](--forcefacets/IdeationMarketFacet.sol)

### <a name="GAS-2"></a>[GAS-2] Using bools for storage incurs overhead
Use uint256(1) and uint256(2) for true/false to avoid a Gwarmaccess (100 gas), and to avoid Gsset (20000 gas) when changing from ‘false’ to ‘true’, after having been ‘true’ in the past. See [source](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/58f635312aa21f947cae5f8578638a85aa2519f5/contracts/security/ReentrancyGuard.sol#L23-L27).

*Instances (5)*:
```solidity
File: facets/BuyerWhitelistFacet.sol

27:         mapping(address => bool) storage listingWhitelist = s.whitelistedBuyersByListingId[listingId];

52:         mapping(address => bool) storage listingWhitelist = s.whitelistedBuyersByListingId[listingId];

```
[Link to code](--forcefacets/BuyerWhitelistFacet.sol)

```solidity
File: libraries/LibAppStorage.sol

29:     mapping(address => bool) whitelistedCollections; // whitelisted collection (NFT) Address => true (or false if this collection has not been whitelisted)

32:     mapping(uint128 => mapping(address => bool)) whitelistedBuyersByListingId; // listingId => whitelistedBuyer => true (or false if the buyers adress is not on the whitelist)

```
[Link to code](--forcelibraries/LibAppStorage.sol)

```solidity
File: libraries/LibDiamond.sol

42:         mapping(bytes4 => bool) supportedInterfaces;

```
[Link to code](--forcelibraries/LibDiamond.sol)

### <a name="GAS-3"></a>[GAS-3] For Operations that will not overflow, you could use unchecked

*Instances (106)*:
```solidity
File: IdeationMarketDiamond.sol

13: import {LibDiamond} from "./libraries/LibDiamond.sol";

14: import {IDiamondCutFacet} from "./interfaces/IDiamondCutFacet.sol";

```
[Link to code](--forceIdeationMarketDiamond.sol)

```solidity
File: facets/BuyerWhitelistFacet.sol

4: import "../libraries/LibAppStorage.sol";

5: import "../interfaces/IERC721.sol";

6: import "../interfaces/IERC1155.sol";

38:                 i++;

63:                 i++;

```
[Link to code](--forcefacets/BuyerWhitelistFacet.sol)

```solidity
File: facets/CollectionWhitelistFacet.sol

4: import "../libraries/LibAppStorage.sol";

5: import "../libraries/LibDiamond.sol";

47:         uint256 lastIndex = s.whitelistedCollectionsArray.length - 1;

85:                 i++;

105:                 uint256 lastIndex = arr.length - 1;

123:                 i++;

```
[Link to code](--forcefacets/CollectionWhitelistFacet.sol)

```solidity
File: facets/DiamondCutFacet.sol

10: import {IDiamondCutFacet} from "../interfaces/IDiamondCutFacet.sol";

11: import {LibDiamond} from "../libraries/LibDiamond.sol";

```
[Link to code](--forcefacets/DiamondCutFacet.sol)

```solidity
File: facets/DiamondLoupeFacet.sol

10: import {LibDiamond} from "../libraries/LibDiamond.sol";

11: import {IDiamondLoupeFacet} from "../interfaces/IDiamondLoupeFacet.sol";

12: import {IERC165} from "../interfaces/IERC165.sol";

26:                 i++;

```
[Link to code](--forcefacets/DiamondLoupeFacet.sol)

```solidity
File: facets/GetterFacet.sol

4: import "../libraries/LibAppStorage.sol";

5: import "../libraries/LibDiamond.sol";

28:                 activeCount++;

31:                 i++;

48:                 arrayIndex++;

51:                 i++;

100:         return s.listingIdCounter + 1;

```
[Link to code](--forcefacets/GetterFacet.sol)

```solidity
File: facets/IdeationMarketFacet.sol

4: import "../libraries/LibAppStorage.sol";

5: import "../libraries/LibDiamond.sol";

6: import "../interfaces/IERC721.sol";

7: import "../interfaces/IERC165.sol";

8: import "../interfaces/IERC2981.sol";

9: import "../interfaces/IERC1155.sol";

10: import "../interfaces/IBuyerWhitelistFacet.sol";

166:         uint256 desiredErc1155Quantity, // >0 for swap ERC1155, 0 for only swap ERC721 or non swap

167:         uint256 erc1155Quantity, // >0 for ERC1155, 0 for only ERC721

170:         address[] calldata allowedBuyers // whitelisted Buyers

243:         s.listingIdCounter++;

294:         uint256 erc1155PurchaseQuantity, // the exact ERC1155 quantity the buyer wants when partialBuyEnabled = true; for ERC721 must be 0

295:         address desiredErc1155Holder // if it is a swap listing where the desired token is an erc1155, the buyer needs to specify the owner of that erc1155, because in case he is not the owner but authorized, the marketplace needs this info to check the approval

333:             purchasePrice = listedItem.price * erc1155PurchaseQuantity / listedItem.erc1155Quantity;

364:         uint256 innovationProceeds = ((purchasePrice * listedItem.feeRate) / 100000);

367:         uint256 sellerProceeds = purchasePrice - innovationProceeds;

375:                 sellerProceeds -= royaltyAmount; // NFT royalties get deducted from the sellerProceeds

376:                 s.proceeds[royaltyReceiver] += royaltyAmount; // Update proceeds for the Royalty Receiver

382:         uint256 excessPayment = msg.value - purchasePrice;

386:         s.proceeds[listedItem.seller] += sellerProceeds;

387:         s.proceeds[LibDiamond.contractOwner()] += innovationProceeds;

389:             s.proceeds[msg.sender] += excessPayment;

394:             address desiredOwner; // initializing this for erc721 cleanup

395:             uint256 remainingBalance = 0; // initializing this for erc1155 cleanup

411:                 remainingBalance = swapBalance - listedItem.desiredErc1155Quantity + 1; // using this +1 trick for the '<=' comparison in the cleanup

447:                 ? desiredErc1155Holder // ERC-1155 swap

448:                 : desiredOwner; // ERC-721 swap

465:                     deprecatedListingArray[i] = deprecatedListingArray[deprecatedListingArray.length - 1];

469:                         i++;

482:             s.listings[listingId].erc1155Quantity -= erc1155PurchaseQuantity;

483:             s.listings[listingId].price -= purchasePrice;

547:         uint256 newDesiredErc1155Quantity, // >0 for swap ERC1155, 0 for only swap ERC721 or non swap

548:         uint256 newErc1155Quantity, // >0 for ERC1155, 0 for only ERC721

551:         address[] calldata newAllowedBuyers // whitelisted Buyers

623:         listedItem.feeRate = s.innovationFee; // note that with updating a listing the up to date innovationFee will be set

624:         listedItem.buyerWhitelistEnabled = newBuyerWhitelistEnabled; // other than in the createListing function where the buyerWhitelist gets passed withing creating the listing, when setting the buyerWhitelist from originally false to true through the updateListing function, the whitelist has to get filled through additional calling of the addBuyerWhitelistAddresses function

763:                 listingArray[i] = listingArray[listingArray.length - 1];

767:                     i++;

```
[Link to code](--forcefacets/IdeationMarketFacet.sol)

```solidity
File: facets/OwnershipFacet.sol

4: import {LibDiamond} from "../libraries/LibDiamond.sol";

5: import {IERC173} from "../interfaces/IERC173.sol";

```
[Link to code](--forcefacets/OwnershipFacet.sol)

```solidity
File: interfaces/IERC1155.sol

6: import {IERC165} from "./IERC165.sol";

```
[Link to code](--forceinterfaces/IERC1155.sol)

```solidity
File: interfaces/IERC2981.sol

6: import {IERC165} from "./IERC165.sol";

```
[Link to code](--forceinterfaces/IERC2981.sol)

```solidity
File: interfaces/IERC4907.sol

5: import {IERC721} from "./IERC721.sol";

```
[Link to code](--forceinterfaces/IERC4907.sol)

```solidity
File: interfaces/IERC721.sol

6: import {IERC165} from "./IERC165.sol";

```
[Link to code](--forceinterfaces/IERC721.sol)

```solidity
File: libraries/LibAppStorage.sol

6:     uint32 feeRate; // storing the fee at the time of listing

7:     bool buyerWhitelistEnabled; // true means only whitelisted buyers can purchase.

8:     bool partialBuyEnabled; // true means that the ERC1155 Listing can be bought in multiple parts

12:     uint256 erc1155Quantity; // For ERC1155 >1 and for ERC721 ==0

15:     address desiredTokenAddress; // For swap Listing !=address(0)

17:     uint256 desiredErc1155Quantity; // For swap ERC1155 >1 and for swap ERC721 ==0 or non swap

22:     uint32 innovationFee; // e.g., 1000 = 1% // this is the innovation/Marketplace fee (excluding gascosts) for each sale

23:     uint16 buyerWhitelistMaxBatchSize; // should be 300

26:     mapping(uint128 => Listing) listings; // Listings by listinngId

27:     mapping(address => mapping(uint256 => uint128[])) tokenToListingIds; // reverse index from token to ListingIds

28:     mapping(address => uint256) proceeds; // Proceeds by seller address

29:     mapping(address => bool) whitelistedCollections; // whitelisted collection (NFT) Address => true (or false if this collection has not been whitelisted)

30:     address[] whitelistedCollectionsArray; // for lookups

31:     mapping(address => uint256) whitelistedCollectionsIndex; // to make lookups and deletions more efficient

32:     mapping(uint128 => mapping(address => bool)) whitelistedBuyersByListingId; // listingId => whitelistedBuyer => true (or false if the buyers adress is not on the whitelist)

```
[Link to code](--forcelibraries/LibAppStorage.sol)

```solidity
File: libraries/LibDiamond.sol

11: import {IDiamondCutFacet} from "../interfaces/IDiamondCutFacet.sol";

24:         uint96 functionSelectorPosition; // position in facetFunctionSelectors.functionSelectors array

29:         uint256 facetAddressPosition; // position of facetAddress in facetAddresses array

92:                 facetIndex++;

116:             selectorPosition++;

118:                 selectorIndex++;

141:             selectorPosition++;

143:                 selectorIndex++;

161:                 selectorIndex++;

186:         uint256 lastSelectorPosition = ds.facetFunctionSelectors[_facetAddress].functionSelectors.length - 1;

200:             uint256 lastFacetAddressPosition = ds.facetAddresses.length - 1;

```
[Link to code](--forcelibraries/LibDiamond.sol)

```solidity
File: upgradeInitializers/DiamondInit.sol

12: import {LibDiamond} from "../libraries/LibDiamond.sol";

13: import {IDiamondLoupeFacet} from "../interfaces/IDiamondLoupeFacet.sol";

14: import {IDiamondCutFacet} from "../interfaces/IDiamondCutFacet.sol";

15: import {IERC173} from "../interfaces/IERC173.sol";

16: import {IERC165} from "../interfaces/IERC165.sol";

17: import {LibAppStorage, AppStorage} from "../libraries/LibAppStorage.sol";

18: import {IERC721} from "../interfaces/IERC721.sol";

19: import {IERC1155} from "../interfaces/IERC1155.sol";

20: import {IERC2981} from "../interfaces/IERC2981.sol";

39:         s.innovationFee = innovationFee; // represents a rate in basis points (e.g., 100 = 0.1%)

```
[Link to code](--forceupgradeInitializers/DiamondInit.sol)

### <a name="GAS-4"></a>[GAS-4] Use Custom Errors instead of Revert Strings to save Gas
Custom errors are available from solidity version 0.8.4. Custom errors save [**~50 gas**](https://gist.github.com/IllIllI000/ad1bd0d29a0101b25e57c293b4b0c746) each time they're hit by [avoiding having to allocate and store the revert string](https://blog.soliditylang.org/2021/04/21/custom-errors/#errors-in-depth). Not defining the strings also save deployment gas

Additionally, custom errors can be used inside and outside of contracts (including interfaces and libraries).

Source: <https://blog.soliditylang.org/2021/04/21/custom-errors/>:

> Starting from [Solidity v0.8.4](https://github.com/ethereum/solidity/releases/tag/v0.8.4), there is a convenient and gas-efficient way to explain to users why an operation failed through the use of custom errors. Until now, you could already use strings to give more information about failures (e.g., `revert("Insufficient funds.");`), but they are rather expensive, especially when it comes to deploy cost, and it is difficult to use dynamic information in them.

Consider replacing **all revert strings** with custom errors in the solution, and particularly those that have multiple occurrences:

*Instances (12)*:
```solidity
File: libraries/LibDiamond.sol

70:         require(msg.sender == diamondStorage().contractOwner, "LibDiamond: Must be contract owner");

89:                 revert("LibDiamondCut: Incorrect FacetCutAction");

100:         require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");

102:         require(_facetAddress != address(0), "LibDiamondCut: Add facet can't be address(0)");

114:             require(oldFacetAddress == address(0), "LibDiamondCut: Can't add function that already exists");

124:         require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");

126:         require(_facetAddress != address(0), "LibDiamondCut: Add facet can't be address(0)");

138:             require(oldFacetAddress != _facetAddress, "LibDiamondCut: Can't replace function with same function");

149:         require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");

152:         require(_facetAddress == address(0), "LibDiamondCut: Remove facet address must be address(0)");

181:         require(_facetAddress != address(0), "LibDiamondCut: Can't remove function that doesn't exist");

183:         require(_facetAddress != address(this), "LibDiamondCut: Can't remove immutable function");

```
[Link to code](--forcelibraries/LibDiamond.sol)

### <a name="GAS-5"></a>[GAS-5] Avoid contract existence checks by using low level calls
Prior to 0.8.10 the compiler inserted extra code, including `EXTCODESIZE` (**100 gas**), to check for contract existence for external function calls. In more recent solidity versions, the compiler will not insert these checks if the external call has a return value. Similar behavior can be achieved in earlier versions by using low-level calls, since low level calls never check for contract existence

*Instances (5)*:
```solidity
File: facets/IdeationMarketFacet.sol

187:             if (token.balanceOf(erc1155Holder, tokenId) == 0) {

350:             uint256 balance = IERC1155(listedItem.tokenAddress).balanceOf(listedItem.seller, listedItem.tokenId);

399:                 uint256 swapBalance = desiredToken.balanceOf(desiredErc1155Holder, listedItem.desiredTokenId);

402:                     desiredToken.balanceOf(msg.sender, listedItem.desiredTokenId) == 0

```
[Link to code](--forcefacets/IdeationMarketFacet.sol)

```solidity
File: libraries/LibDiamond.sol

217:         (bool success, bytes memory error) = _init.delegatecall(_calldata);

```
[Link to code](--forcelibraries/LibDiamond.sol)

### <a name="GAS-6"></a>[GAS-6] Functions guaranteed to revert when called by normal users can be marked `payable`
If a function modifier such as `onlyOwner` is used, the function will revert if a normal user tries to pay the function. Marking the function as `payable` will lower the gas cost for legitimate callers because the compiler will not include checks for whether a payment was provided.

*Instances (4)*:
```solidity
File: facets/CollectionWhitelistFacet.sol

26:     function addWhitelistedCollection(address tokenAddress) external onlyOwner {

41:     function removeWhitelistedCollection(address tokenAddress) external onlyOwner {

66:     function batchAddWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {

93:     function batchRemoveWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {

```
[Link to code](--forcefacets/CollectionWhitelistFacet.sol)

### <a name="GAS-7"></a>[GAS-7] `++i` costs less gas compared to `i++` or `i += 1` (same for `--i` vs `i--` or `i -= 1`)
Pre-increments and pre-decrements are cheaper.

For a `uint256 i` variable, the following is true with the Optimizer enabled at 10k:

**Increment:**

- `i += 1` is the most expensive form
- `i++` costs 6 gas less than `i += 1`
- `++i` costs 5 gas less than `i++` (11 gas less than `i += 1`)

**Decrement:**

- `i -= 1` is the most expensive form
- `i--` costs 11 gas less than `i -= 1`
- `--i` costs 5 gas less than `i--` (16 gas less than `i -= 1`)

Note that post-increments (or post-decrements) return the old value before incrementing or decrementing, hence the name *post-increment*:

```solidity
uint i = 1;  
uint j = 2;
require(j == i++, "This will be false as i is incremented after the comparison");
```
  
However, pre-increments (or pre-decrements) return the new value:
  
```solidity
uint i = 1;  
uint j = 2;
require(j == ++i, "This will be true as i is incremented before the comparison");
```

In the pre-increment case, the compiler has to create a temporary variable (when used) for returning `1` instead of `2`.

Consider using pre-increments and pre-decrements where they are relevant (meaning: not where post-increments/decrements logic are relevant).

*Saves 5 gas per instance*

*Instances (18)*:
```solidity
File: facets/BuyerWhitelistFacet.sol

38:                 i++;

63:                 i++;

```
[Link to code](--forcefacets/BuyerWhitelistFacet.sol)

```solidity
File: facets/CollectionWhitelistFacet.sol

85:                 i++;

123:                 i++;

```
[Link to code](--forcefacets/CollectionWhitelistFacet.sol)

```solidity
File: facets/DiamondLoupeFacet.sol

26:                 i++;

```
[Link to code](--forcefacets/DiamondLoupeFacet.sol)

```solidity
File: facets/GetterFacet.sol

28:                 activeCount++;

31:                 i++;

48:                 arrayIndex++;

51:                 i++;

```
[Link to code](--forcefacets/GetterFacet.sol)

```solidity
File: facets/IdeationMarketFacet.sol

243:         s.listingIdCounter++;

469:                         i++;

767:                     i++;

```
[Link to code](--forcefacets/IdeationMarketFacet.sol)

```solidity
File: libraries/LibDiamond.sol

92:                 facetIndex++;

116:             selectorPosition++;

118:                 selectorIndex++;

141:             selectorPosition++;

143:                 selectorIndex++;

161:                 selectorIndex++;

```
[Link to code](--forcelibraries/LibDiamond.sol)

### <a name="GAS-8"></a>[GAS-8] Use != 0 instead of > 0 for unsigned integer comparison

*Instances (28)*:
```solidity
File: facets/BuyerWhitelistFacet.sol

82:         if (erc1155Quantity > 0) {

```
[Link to code](--forcefacets/BuyerWhitelistFacet.sol)

```solidity
File: facets/IdeationMarketFacet.sol

166:         uint256 desiredErc1155Quantity, // >0 for swap ERC1155, 0 for only swap ERC721 or non swap

167:         uint256 erc1155Quantity, // >0 for ERC1155, 0 for only ERC721

180:         if (erc1155Quantity > 0) {

217:         if (erc1155Quantity == 0 && s.tokenToListingIds[tokenAddress][tokenId].length > 0) {

230:         if (erc1155Quantity > 0) {

268:             if (allowedBuyers.length > 0) revert IdeationMarket__WhitelistDisabled();

332:         if (erc1155PurchaseQuantity > 0 && erc1155PurchaseQuantity != listedItem.erc1155Quantity) {

340:         if (listedItem.desiredErc1155Quantity > 0 && desiredErc1155Holder == address(0)) {

349:         if (listedItem.erc1155Quantity > 0) {

373:             if (royaltyAmount > 0) {

388:         if (excessPayment > 0) {

396:             if (listedItem.desiredErc1155Quantity > 0) {

446:             address obsoleteSeller = (listedItem.desiredErc1155Quantity > 0)

488:         if (erc1155PurchaseQuantity > 0) {

547:         uint256 newDesiredErc1155Quantity, // >0 for swap ERC1155, 0 for only swap ERC721 or non swap

548:         uint256 newErc1155Quantity, // >0 for ERC1155, 0 for only ERC721

563:         if (newErc1155Quantity > 0) {

606:         if (newErc1155Quantity > 0) {

612:             if (erc1155Quantity > 0) {

631:             if (newAllowedBuyers.length > 0) revert IdeationMarket__WhitelistDisabled();

684:             if (listedItem.erc1155Quantity > 0) {

743:         } else if (desiredErc1155Quantity > 0) {

```
[Link to code](--forcefacets/IdeationMarketFacet.sol)

```solidity
File: libraries/LibDiamond.sol

100:         require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");

124:         require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");

149:         require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");

219:             if (error.length > 0) {

237:         require(contractSize > 0, _errorMessage);

```
[Link to code](--forcelibraries/LibDiamond.sol)


## Non Critical Issues


| |Issue|Instances|
|-|:-|:-:|
| [NC-1](#NC-1) | `constant`s should be defined rather than using magic numbers | 1 |
| [NC-2](#NC-2) | Control structures do not follow the Solidity Style Guide | 30 |
| [NC-3](#NC-3) | Critical Changes Should Use Two-step Procedure | 1 |
| [NC-4](#NC-4) | Default Visibility for constants | 2 |
| [NC-5](#NC-5) | Functions should not be longer than 50 lines | 101 |
| [NC-6](#NC-6) | Lines are too long | 3 |
| [NC-7](#NC-7) | Use a `modifier` instead of a `require/if` statement for a special `msg.sender` actor | 8 |
| [NC-8](#NC-8) | Consider using named mappings | 11 |
| [NC-9](#NC-9) | Take advantage of Custom Error's return value property | 53 |
| [NC-10](#NC-10) | Use scientific notation for readability reasons for large multiples of ten | 1 |
| [NC-11](#NC-11) | Avoid the use of sensitive terms | 116 |
| [NC-12](#NC-12) | Strings should use double quotes rather than single quotes | 2 |
| [NC-13](#NC-13) | Use Underscores for Number Literals (add an underscore every 3 digits) | 2 |
| [NC-14](#NC-14) | Event is missing `indexed` fields | 4 |
| [NC-15](#NC-15) | Variables need not be initialized to zero | 14 |
### <a name="NC-1"></a>[NC-1] `constant`s should be defined rather than using magic numbers
Even [assembly](https://github.com/code-423n4/2022-05-opensea-seaport/blob/9d7ce4d08bf3c3010304a0476a785c70c0e90ae7/contracts/lib/TokenTransferrer.sol#L35-L39) can benefit from using readable constants instead of hex/numeric literals

*Instances (1)*:
```solidity
File: facets/IdeationMarketFacet.sol

364:         uint256 innovationProceeds = ((purchasePrice * listedItem.feeRate) / 100000);

```
[Link to code](--forcefacets/IdeationMarketFacet.sol)

### <a name="NC-2"></a>[NC-2] Control structures do not follow the Solidity Style Guide
See the [control structures](https://docs.soliditylang.org/en/latest/style-guide.html#control-structures) section of the Solidity Style Guide

*Instances (30)*:
```solidity
File: IdeationMarketDiamond.sol

45:         if (facet == address(0)) revert Diamond__FunctionDoesNotExist();

```
[Link to code](--forceIdeationMarketDiamond.sol)

```solidity
File: facets/BuyerWhitelistFacet.sol

31:             if (allowedBuyer == address(0)) revert BuyerWhitelist__ZeroAddress();

56:             if (disallowedBuyer == address(0)) revert BuyerWhitelist__ZeroAddress();

71:         if (batchSize == 0) revert BuyerWhitelist__EmptyCalldata();

77:         if (seller == address(0)) revert BuyerWhitelist__ListingDoesNotExist();

90:             if (

```
[Link to code](--forcefacets/BuyerWhitelistFacet.sol)

```solidity
File: facets/CollectionWhitelistFacet.sol

28:         if (s.whitelistedCollections[tokenAddress]) revert CollectionWhitelist__AlreadyWhitelisted();

29:         if (tokenAddress == address(0)) revert CollectionWhitelist__ZeroAddress();

43:         if (!s.whitelistedCollections[tokenAddress]) revert CollectionWhitelist__NotWhitelisted();

74:             if (addr == address(0)) revert CollectionWhitelist__ZeroAddress();

```
[Link to code](--forcefacets/CollectionWhitelistFacet.sol)

```solidity
File: facets/IdeationMarketFacet.sol

135:         if (LibAppStorage.appStorage().listings[listingId].seller == address(0)) revert IdeationMarket__NotListed();

141:         if (s.reentrancyLock) revert IdeationMarket__Reentrant();

193:             if (

268:             if (allowedBuyers.length > 0) revert IdeationMarket__WhitelistDisabled();

295:         address desiredErc1155Holder // if it is a swap listing where the desired token is an erc1155, the buyer needs to specify the owner of that erc1155, because in case he is not the owner but authorized, the marketplace needs this info to check the approval

308:         if (

318:         if (

374:                 if (sellerProceeds < royaltyAmount) revert IdeationMarket__RoyaltyFeeExceedsProceeds();

400:                 if (swapBalance == 0) revert IdeationMarket__WrongErc1155HolderParameter();

401:                 if (

428:                 if (

453:                 if (

572:             if (

631:             if (newAllowedBuyers.length > 0) revert IdeationMarket__WhitelistDisabled();

711:         if (

740:             if (desiredTokenId != 0) revert IdeationMarket__InvalidNoSwapParameters();

741:             if (desiredErc1155Quantity != 0) revert IdeationMarket__InvalidNoSwapParameters();

742:             if (price <= 0) revert IdeationMarket__FreeListingsNotSupported();

```
[Link to code](--forcefacets/IdeationMarketFacet.sol)

```solidity
File: libraries/LibAppStorage.sol

29:     mapping(address => bool) whitelistedCollections; // whitelisted collection (NFT) Address => true (or false if this collection has not been whitelisted)

32:     mapping(uint128 => mapping(address => bool)) whitelistedBuyersByListingId; // listingId => whitelistedBuyer => true (or false if the buyers adress is not on the whitelist)

```
[Link to code](--forcelibraries/LibAppStorage.sol)

### <a name="NC-3"></a>[NC-3] Critical Changes Should Use Two-step Procedure
The critical procedures should be two step process.

See similar findings in previous Code4rena contests for reference: <https://code4rena.com/reports/2022-06-illuminate/#2-critical-changes-should-use-two-step-procedure>

**Recommended Mitigation Steps**

Lack of two-step procedure for critical operations leaves them error-prone. Consider adding two step procedure on the critical functions.

*Instances (1)*:
```solidity
File: libraries/LibDiamond.sol

58:     function setContractOwner(address _newOwner) internal {

```
[Link to code](--forcelibraries/LibDiamond.sol)

### <a name="NC-4"></a>[NC-4] Default Visibility for constants
Some constants are using the default visibility. For readability, consider explicitly declaring them as `internal`.

*Instances (2)*:
```solidity
File: libraries/LibAppStorage.sol

37:     bytes32 constant APP_STORAGE_POSITION = keccak256("diamond.standard.app.storage");

```
[Link to code](--forcelibraries/LibAppStorage.sol)

```solidity
File: libraries/LibDiamond.sol

20:     bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

```
[Link to code](--forcelibraries/LibDiamond.sol)

### <a name="NC-5"></a>[NC-5] Functions should not be longer than 50 lines
Overly complex code can make understanding functionality more difficult, try to further modularize your code to ensure readability 

*Instances (101)*:
```solidity
File: IdeationMarketDiamond.sol

25:         functionSelectors[0] = IDiamondCutFacet.diamondCut.selector;

```
[Link to code](--forceIdeationMarketDiamond.sol)

```solidity
File: facets/BuyerWhitelistFacet.sol

21:     function addBuyerWhitelistAddresses(uint128 listingId, address[] calldata allowedBuyers) external {

46:     function removeBuyerWhitelistAddresses(uint128 listingId, address[] calldata disallowedBuyers) external {

70:     function validateWhitelistBatch(AppStorage storage s, uint128 listingId, uint256 batchSize) internal view {

```
[Link to code](--forcefacets/BuyerWhitelistFacet.sol)

```solidity
File: facets/CollectionWhitelistFacet.sol

26:     function addWhitelistedCollection(address tokenAddress) external onlyOwner {

41:     function removeWhitelistedCollection(address tokenAddress) external onlyOwner {

66:     function batchAddWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {

93:     function batchRemoveWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {

```
[Link to code](--forcefacets/CollectionWhitelistFacet.sol)

```solidity
File: facets/DiamondCutFacet.sol

18:     function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external override {

```
[Link to code](--forcefacets/DiamondCutFacet.sol)

```solidity
File: facets/DiamondLoupeFacet.sol

17:     function facets() external view override returns (Facet[] memory facets_) {

24:             facets_[i].functionSelectors = ds.facetFunctionSelectors[facetAddress_].functionSelectors;

41:         facetFunctionSelectors_ = ds.facetFunctionSelectors[_facet].functionSelectors;

46:     function facetAddresses() external view override returns (address[] memory facetAddresses_) {

55:     function facetAddress(bytes4 _functionSelector) external view override returns (address facetAddress_) {

63:     function supportsInterface(bytes4 _interfaceId) external view override returns (bool) {

```
[Link to code](--forcefacets/DiamondLoupeFacet.sol)

```solidity
File: facets/GetterFacet.sol

15:     function getListingsByNFT(address tokenAddress, uint256 tokenId)

61:     function getListingByListingId(uint128 listingId) external view returns (Listing memory listing) {

75:     function getProceeds(address seller) external view returns (uint256) {

84:     function getBalance() external view returns (uint256) {

89:     function getInnovationFee() external view returns (uint32 innovationFee) {

98:     function getNextListingId() external view returns (uint128) {

108:     function isCollectionWhitelisted(address collection) external view returns (bool) {

117:     function getWhitelistedCollections() external view returns (address[] memory) {

126:     function getContractOwner() external view returns (address) {

134:     function isBuyerWhitelisted(uint128 listingId, address buyer) external view returns (bool) {

144:     function getBuyerWhitelistMaxBatchSize() external view returns (uint16 maxBatchSize) {

149:     function getPendingOwner() external view returns (address) {

```
[Link to code](--forcefacets/GetterFacet.sol)

```solidity
File: facets/IdeationMarketFacet.sol

513:     function cancelListing(uint128 listingId) public listingExists(listingId) {

624:         listedItem.buyerWhitelistEnabled = newBuyerWhitelistEnabled; // other than in the createListing function where the buyerWhitelist gets passed withing creating the listing, when setting the buyerWhitelist from originally false to true through the updateListing function, the whitelist has to get filled through additional calling of the addBuyerWhitelistAddresses function

650:     function withdrawProceeds() external nonReentrant {

666:     function setInnovationFee(uint32 newFee) external {

675:     function cleanListing(uint128 listingId) external listingExists(listingId) {

709:     function requireERC721Approval(address tokenAddress, uint256 tokenId) internal view {

721:     function requireERC1155Approval(address tokenAddress, address tokenOwner) internal view {

754:     function deleteListingAndCleanup(AppStorage storage s, uint128 listingId, address tokenAddress, uint256 tokenId)

```
[Link to code](--forcefacets/IdeationMarketFacet.sol)

```solidity
File: facets/OwnershipFacet.sol

14:     function transferOwnership(address newOwner) external override {

31:     function owner() external view override returns (address) {

```
[Link to code](--forcefacets/OwnershipFacet.sol)

```solidity
File: interfaces/IBuyerWhitelistFacet.sol

10:     function addBuyerWhitelistAddresses(uint128 listingId, address[] calldata allowedBuyers) external;

15:     function removeBuyerWhitelistAddresses(uint128 listingId, address[] calldata disallowedBuyers) external;

```
[Link to code](--forceinterfaces/IBuyerWhitelistFacet.sol)

```solidity
File: interfaces/IDiamondCutFacet.sol

30:     function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external;

```
[Link to code](--forceinterfaces/IDiamondCutFacet.sol)

```solidity
File: interfaces/IDiamondLoupeFacet.sol

18:     function facets() external view returns (Facet[] memory facets_);

23:     function facetFunctionSelectors(address _facet) external view returns (bytes4[] memory facetFunctionSelectors_);

27:     function facetAddresses() external view returns (address[] memory facetAddresses_);

33:     function facetAddress(bytes4 _functionSelector) external view returns (address facetAddress_);

```
[Link to code](--forceinterfaces/IDiamondLoupeFacet.sol)

```solidity
File: interfaces/IERC1155.sol

44:     function balanceOf(address account, uint256 id) external view returns (uint256);

53:     function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)

67:     function setApprovalForAll(address operator, bool approved) external;

74:     function isApprovedForAll(address account, address operator) external view returns (bool);

94:     function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data) external;

```
[Link to code](--forceinterfaces/IERC1155.sol)

```solidity
File: interfaces/IERC165.sol

11:     function supportsInterface(bytes4 interfaceId) external view returns (bool);

```
[Link to code](--forceinterfaces/IERC165.sol)

```solidity
File: interfaces/IERC173.sol

13:     function owner() external view returns (address owner_);

18:     function transferOwnership(address _newOwner) external;

```
[Link to code](--forceinterfaces/IERC173.sol)

```solidity
File: interfaces/IERC2981.sol

22:     function royaltyInfo(uint256 tokenId, uint256 salePrice)

```
[Link to code](--forceinterfaces/IERC2981.sol)

```solidity
File: interfaces/IERC4907.sol

22:     function setUser(uint256 tokenId, address user, uint64 expires) external;

28:     function userOf(uint256 tokenId) external view returns (address);

34:     function userExpires(uint256 tokenId) external view returns (uint256);

```
[Link to code](--forceinterfaces/IERC4907.sol)

```solidity
File: interfaces/IERC721.sol

30:     function balanceOf(address owner) external view returns (uint256 balance);

39:     function ownerOf(uint256 tokenId) external view returns (address owner);

55:     function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;

73:     function safeTransferFrom(address from, address to, uint256 tokenId) external;

91:     function transferFrom(address from, address to, uint256 tokenId) external;

106:     function approve(address to, uint256 tokenId) external;

118:     function setApprovalForAll(address operator, bool approved) external;

127:     function getApproved(uint256 tokenId) external view returns (address operator);

134:     function isApprovedForAll(address owner, address operator) external view returns (bool);

```
[Link to code](--forceinterfaces/IERC721.sol)

```solidity
File: libraries/LibAppStorage.sol

39:     function appStorage() internal pure returns (AppStorage storage s) {

```
[Link to code](--forcelibraries/LibAppStorage.sol)

```solidity
File: libraries/LibDiamond.sol

16: error InitializationFunctionReverted(address _initializationContractAddress, bytes _calldata);

24:         uint96 functionSelectorPosition; // position in facetFunctionSelectors.functionSelectors array

48:     function diamondStorage() internal pure returns (DiamondStorage storage ds) {

58:     function setContractOwner(address _newOwner) internal {

65:     function contractOwner() internal view returns (address contractOwner_) {

76:     function diamondCut(IDiamondCutFacet.FacetCut[] memory _diamondCut, address _init, bytes memory _calldata)

83:                 addFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);

85:                 replaceFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);

87:                 removeFunctions(_diamondCut[facetIndex].facetAddress, _diamondCut[facetIndex].functionSelectors);

99:     function addFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {

100:         require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");

103:         uint96 selectorPosition = uint96(ds.facetFunctionSelectors[_facetAddress].functionSelectors.length);

115:             addFunction(ds, selector, selectorPosition, _facetAddress);

123:     function replaceFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {

124:         require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");

127:         uint96 selectorPosition = uint96(ds.facetFunctionSelectors[_facetAddress].functionSelectors.length);

140:             addFunction(ds, selector, selectorPosition, _facetAddress);

148:     function removeFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {

149:         require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");

166:     function addFacet(DiamondStorage storage ds, address _facetAddress) internal {

168:         ds.facetFunctionSelectors[_facetAddress].facetAddressPosition = ds.facetAddresses.length;

172:     function addFunction(DiamondStorage storage ds, bytes4 _selector, uint96 _selectorPosition, address _facetAddress)

176:         ds.facetFunctionSelectors[_facetAddress].functionSelectors.push(_selector);

180:     function removeFunction(DiamondStorage storage ds, address _facetAddress, bytes4 _selector) internal {

186:         uint256 lastSelectorPosition = ds.facetFunctionSelectors[_facetAddress].functionSelectors.length - 1;

189:             bytes4 lastSelector = ds.facetFunctionSelectors[_facetAddress].functionSelectors[lastSelectorPosition];

190:             ds.facetFunctionSelectors[_facetAddress].functionSelectors[selectorPosition] = lastSelector;

191:             ds.selectorToFacetAndPosition[lastSelector].functionSelectorPosition = uint96(selectorPosition);

194:         ds.facetFunctionSelectors[_facetAddress].functionSelectors.pop();

201:             uint256 facetAddressPosition = ds.facetFunctionSelectors[_facetAddress].facetAddressPosition;

205:                 ds.facetFunctionSelectors[lastFacetAddress].facetAddressPosition = facetAddressPosition;

208:             delete ds.facetFunctionSelectors[_facetAddress].facetAddressPosition;

212:     function initializeDiamondCut(address _init, bytes memory _calldata) internal {

232:     function enforceHasContractCode(address _contract, string memory _errorMessage) internal view {

```
[Link to code](--forcelibraries/LibDiamond.sol)

```solidity
File: upgradeInitializers/DiamondInit.sol

23:     function init(uint32 innovationFee, uint16 buyerWhitelistMaxBatchSize) external {

```
[Link to code](--forceupgradeInitializers/DiamondInit.sol)

### <a name="NC-6"></a>[NC-6] Lines are too long
Usually lines in source code are limited to [80](https://softwareengineering.stackexchange.com/questions/148677/why-is-80-characters-the-standard-limit-for-code-width) characters. Today's screens are much larger so it's reasonable to stretch this in some cases. Since the files will most likely reside in GitHub, and GitHub starts using a scroll bar in all cases when the length is over [164](https://github.com/aizatto/character-length) characters, the lines below should be split when they reach that length

*Instances (3)*:
```solidity
File: facets/IdeationMarketFacet.sol

295:         address desiredErc1155Holder // if it is a swap listing where the desired token is an erc1155, the buyer needs to specify the owner of that erc1155, because in case he is not the owner but authorized, the marketplace needs this info to check the approval

624:         listedItem.buyerWhitelistEnabled = newBuyerWhitelistEnabled; // other than in the createListing function where the buyerWhitelist gets passed withing creating the listing, when setting the buyerWhitelist from originally false to true through the updateListing function, the whitelist has to get filled through additional calling of the addBuyerWhitelistAddresses function

```
[Link to code](--forcefacets/IdeationMarketFacet.sol)

```solidity
File: libraries/LibAppStorage.sol

32:     mapping(uint128 => mapping(address => bool)) whitelistedBuyersByListingId; // listingId => whitelistedBuyer => true (or false if the buyers adress is not on the whitelist)

```
[Link to code](--forcelibraries/LibAppStorage.sol)

### <a name="NC-7"></a>[NC-7] Use a `modifier` instead of a `require/if` statement for a special `msg.sender` actor
If a function is supposed to be access-controlled, a `modifier` should be used instead of a `require/if` statement for more readability.

*Instances (8)*:
```solidity
File: facets/BuyerWhitelistFacet.sol

84:             if (msg.sender != seller && !token.isApprovedForAll(seller, msg.sender)) {

```
[Link to code](--forcefacets/BuyerWhitelistFacet.sol)

```solidity
File: facets/IdeationMarketFacet.sol

183:             if (msg.sender != erc1155Holder && !token.isApprovedForAll(erc1155Holder, msg.sender)) {

302:             if (!s.whitelistedBuyersByListingId[listingId][msg.sender]) {

344:         if (msg.sender == listedItem.seller) {

532:         if (!isAuthorized && msg.sender != diamondOwner) {

566:             if (msg.sender != seller && !token.isApprovedForAll(seller, msg.sender)) {

```
[Link to code](--forcefacets/IdeationMarketFacet.sol)

```solidity
File: facets/OwnershipFacet.sol

23:         if (msg.sender != ds.pendingContractOwner) {

```
[Link to code](--forcefacets/OwnershipFacet.sol)

```solidity
File: libraries/LibDiamond.sol

70:         require(msg.sender == diamondStorage().contractOwner, "LibDiamond: Must be contract owner");

```
[Link to code](--forcelibraries/LibDiamond.sol)

### <a name="NC-8"></a>[NC-8] Consider using named mappings
Consider moving to solidity version 0.8.18 or later, and using [named mappings](https://ethereum.stackexchange.com/questions/51629/how-to-name-the-arguments-in-mapping/145555#145555) to make it easier to understand the purpose of each mapping

*Instances (11)*:
```solidity
File: facets/BuyerWhitelistFacet.sol

27:         mapping(address => bool) storage listingWhitelist = s.whitelistedBuyersByListingId[listingId];

52:         mapping(address => bool) storage listingWhitelist = s.whitelistedBuyersByListingId[listingId];

```
[Link to code](--forcefacets/BuyerWhitelistFacet.sol)

```solidity
File: libraries/LibAppStorage.sol

26:     mapping(uint128 => Listing) listings; // Listings by listinngId

27:     mapping(address => mapping(uint256 => uint128[])) tokenToListingIds; // reverse index from token to ListingIds

28:     mapping(address => uint256) proceeds; // Proceeds by seller address

29:     mapping(address => bool) whitelistedCollections; // whitelisted collection (NFT) Address => true (or false if this collection has not been whitelisted)

31:     mapping(address => uint256) whitelistedCollectionsIndex; // to make lookups and deletions more efficient

32:     mapping(uint128 => mapping(address => bool)) whitelistedBuyersByListingId; // listingId => whitelistedBuyer => true (or false if the buyers adress is not on the whitelist)

```
[Link to code](--forcelibraries/LibAppStorage.sol)

```solidity
File: libraries/LibDiamond.sol

35:         mapping(bytes4 => FacetAddressAndPosition) selectorToFacetAndPosition;

37:         mapping(address => FacetFunctionSelectors) facetFunctionSelectors;

42:         mapping(bytes4 => bool) supportedInterfaces;

```
[Link to code](--forcelibraries/LibDiamond.sol)

### <a name="NC-9"></a>[NC-9] Take advantage of Custom Error's return value property
An important feature of Custom Error is that values such as address, tokenID, msg.value can be written inside the () sign, this kind of approach provides a serious advantage in debugging and examining the revert details of dapps such as tenderly.

*Instances (53)*:
```solidity
File: IdeationMarketDiamond.sol

45:         if (facet == address(0)) revert Diamond__FunctionDoesNotExist();

56:             case 0 { revert(0, returndatasize()) }

```
[Link to code](--forceIdeationMarketDiamond.sol)

```solidity
File: facets/BuyerWhitelistFacet.sol

31:             if (allowedBuyer == address(0)) revert BuyerWhitelist__ZeroAddress();

56:             if (disallowedBuyer == address(0)) revert BuyerWhitelist__ZeroAddress();

71:         if (batchSize == 0) revert BuyerWhitelist__EmptyCalldata();

73:             revert BuyerWhitelist__ExceedsMaxBatchSize();

77:         if (seller == address(0)) revert BuyerWhitelist__ListingDoesNotExist();

85:                 revert BuyerWhitelist__NotAuthorizedOperator();

93:             ) revert BuyerWhitelist__NotAuthorizedOperator();

```
[Link to code](--forcefacets/BuyerWhitelistFacet.sol)

```solidity
File: facets/CollectionWhitelistFacet.sol

28:         if (s.whitelistedCollections[tokenAddress]) revert CollectionWhitelist__AlreadyWhitelisted();

29:         if (tokenAddress == address(0)) revert CollectionWhitelist__ZeroAddress();

43:         if (!s.whitelistedCollections[tokenAddress]) revert CollectionWhitelist__NotWhitelisted();

74:             if (addr == address(0)) revert CollectionWhitelist__ZeroAddress();

```
[Link to code](--forcefacets/CollectionWhitelistFacet.sol)

```solidity
File: facets/IdeationMarketFacet.sol

135:         if (LibAppStorage.appStorage().listings[listingId].seller == address(0)) revert IdeationMarket__NotListed();

141:         if (s.reentrancyLock) revert IdeationMarket__Reentrant();

184:                 revert IdeationMarket__NotAuthorizedOperator();

188:                 revert IdeationMarket__WrongErc1155HolderParameter();

197:                 revert IdeationMarket__NotAuthorizedOperator();

204:                 revert IdeationMarket__PartialBuyNotPossible();

212:                 revert IdeationMarket__InvalidUnitPrice();

218:             revert IdeationMarket__AlreadyListed();

232:                 revert IdeationMarket__WrongQuantityParameter();

237:                 revert IdeationMarket__WrongQuantityParameter();

268:             if (allowedBuyers.length > 0) revert IdeationMarket__WhitelistDisabled();

314:             revert IdeationMarket__ListingTermsChanged();

323:             revert IdeationMarket__InvalidPurchaseQuantity();

326:             revert IdeationMarket__PartialBuyNotPossible();

341:             revert IdeationMarket__WrongErc1155HolderParameter();

345:             revert IdeationMarket__SameBuyerAsSeller();

374:                 if (sellerProceeds < royaltyAmount) revert IdeationMarket__RoyaltyFeeExceedsProceeds();

400:                 if (swapBalance == 0) revert IdeationMarket__WrongErc1155HolderParameter();

405:                     revert IdeationMarket__NotAuthorizedOperator();

432:                     revert IdeationMarket__NotAuthorizedOperator();

533:             revert IdeationMarket__NotAuthorizedToCancel();

567:                 revert IdeationMarket__NotAuthorizedOperator();

576:                 revert IdeationMarket__NotAuthorizedOperator();

589:             revert IdeationMarket__PartialBuyNotPossible();

596:                 revert IdeationMarket__InvalidUnitPrice();

608:                 revert IdeationMarket__WrongQuantityParameter();

613:                 revert IdeationMarket__WrongQuantityParameter();

631:             if (newAllowedBuyers.length > 0) revert IdeationMarket__WhitelistDisabled();

655:             revert IdeationMarket__NoProceeds();

661:             revert IdeationMarket__TransferFailed();

701:             revert IdeationMarket__StillApproved();

717:             revert IdeationMarket__NotApprovedForMarketplace();

723:             revert IdeationMarket__NotApprovedForMarketplace();

736:             revert IdeationMarket__NoSwapForSameToken();

740:             if (desiredTokenId != 0) revert IdeationMarket__InvalidNoSwapParameters();

741:             if (desiredErc1155Quantity != 0) revert IdeationMarket__InvalidNoSwapParameters();

742:             if (price <= 0) revert IdeationMarket__FreeListingsNotSupported();

745:                 revert IdeationMarket__NotSupportedTokenStandard();

749:                 revert IdeationMarket__NotSupportedTokenStandard();

```
[Link to code](--forcefacets/IdeationMarketFacet.sol)

```solidity
File: facets/OwnershipFacet.sol

24:             revert Ownership__CallerIsNotThePendingOwner();

```
[Link to code](--forcefacets/OwnershipFacet.sol)

### <a name="NC-10"></a>[NC-10] Use scientific notation for readability reasons for large multiples of ten
The more a number has zeros, the harder it becomes to see with the eyes if it's the intended value. To ease auditing and bug bounty hunting, consider using the scientific notation

*Instances (1)*:
```solidity
File: facets/IdeationMarketFacet.sol

364:         uint256 innovationProceeds = ((purchasePrice * listedItem.feeRate) / 100000);

```
[Link to code](--forcefacets/IdeationMarketFacet.sol)

### <a name="NC-11"></a>[NC-11] Avoid the use of sensitive terms
Use [alternative variants](https://www.zdnet.com/article/mysql-drops-master-slave-and-blacklist-whitelist-terminology/), e.g. allowlist/denylist instead of whitelist/blacklist

*Instances (116)*:
```solidity
File: facets/BuyerWhitelistFacet.sol

8: error BuyerWhitelist__ListingDoesNotExist();

9: error BuyerWhitelist__NotAuthorizedOperator();

10: error BuyerWhitelist__ExceedsMaxBatchSize();

11: error BuyerWhitelist__ZeroAddress();

12: error BuyerWhitelist__EmptyCalldata();

14: contract BuyerWhitelistFacet {

15:     event BuyerWhitelisted(uint128 indexed listingId, address indexed buyer);

16:     event BuyerRemovedFromWhitelist(uint128 indexed listingId, address indexed buyer);

21:     function addBuyerWhitelistAddresses(uint128 listingId, address[] calldata allowedBuyers) external {

25:         validateWhitelistBatch(s, listingId, len);

27:         mapping(address => bool) storage listingWhitelist = s.whitelistedBuyersByListingId[listingId];

31:             if (allowedBuyer == address(0)) revert BuyerWhitelist__ZeroAddress();

33:             if (!listingWhitelist[allowedBuyer]) {

34:                 listingWhitelist[allowedBuyer] = true;

35:                 emit BuyerWhitelisted(listingId, allowedBuyer);

46:     function removeBuyerWhitelistAddresses(uint128 listingId, address[] calldata disallowedBuyers) external {

50:         validateWhitelistBatch(s, listingId, len);

52:         mapping(address => bool) storage listingWhitelist = s.whitelistedBuyersByListingId[listingId];

56:             if (disallowedBuyer == address(0)) revert BuyerWhitelist__ZeroAddress();

58:             if (listingWhitelist[disallowedBuyer]) {

59:                 listingWhitelist[disallowedBuyer] = false;

60:                 emit BuyerRemovedFromWhitelist(listingId, disallowedBuyer);

70:     function validateWhitelistBatch(AppStorage storage s, uint128 listingId, uint256 batchSize) internal view {

71:         if (batchSize == 0) revert BuyerWhitelist__EmptyCalldata();

72:         if (batchSize > s.buyerWhitelistMaxBatchSize) {

73:             revert BuyerWhitelist__ExceedsMaxBatchSize();

77:         if (seller == address(0)) revert BuyerWhitelist__ListingDoesNotExist();

85:                 revert BuyerWhitelist__NotAuthorizedOperator();

93:             ) revert BuyerWhitelist__NotAuthorizedOperator();

```
[Link to code](--forcefacets/BuyerWhitelistFacet.sol)

```solidity
File: facets/CollectionWhitelistFacet.sol

7: error CollectionWhitelist__AlreadyWhitelisted();

8: error CollectionWhitelist__NotWhitelisted();

9: error CollectionWhitelist__ZeroAddress();

11: contract CollectionWhitelistFacet {

13:     event CollectionAddedToWhitelist(address indexed tokenAddress);

16:     event CollectionRemovedFromWhitelist(address indexed tokenAddress);

26:     function addWhitelistedCollection(address tokenAddress) external onlyOwner {

28:         if (s.whitelistedCollections[tokenAddress]) revert CollectionWhitelist__AlreadyWhitelisted();

29:         if (tokenAddress == address(0)) revert CollectionWhitelist__ZeroAddress();

31:         s.whitelistedCollections[tokenAddress] = true;

32:         s.whitelistedCollectionsIndex[tokenAddress] = s.whitelistedCollectionsArray.length;

33:         s.whitelistedCollectionsArray.push(tokenAddress);

35:         emit CollectionAddedToWhitelist(tokenAddress);

41:     function removeWhitelistedCollection(address tokenAddress) external onlyOwner {

43:         if (!s.whitelistedCollections[tokenAddress]) revert CollectionWhitelist__NotWhitelisted();

46:         uint256 index = s.whitelistedCollectionsIndex[tokenAddress];

47:         uint256 lastIndex = s.whitelistedCollectionsArray.length - 1;

48:         address lastAddress = s.whitelistedCollectionsArray[lastIndex];

52:             s.whitelistedCollectionsArray[index] = lastAddress;

53:             s.whitelistedCollectionsIndex[lastAddress] = index;

57:         s.whitelistedCollectionsArray.pop();

58:         delete s.whitelistedCollectionsIndex[tokenAddress];

59:         s.whitelistedCollections[tokenAddress] = false;

61:         emit CollectionRemovedFromWhitelist(tokenAddress);

66:     function batchAddWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {

68:         address[] storage arr = s.whitelistedCollectionsArray;

74:             if (addr == address(0)) revert CollectionWhitelist__ZeroAddress();

76:             if (!s.whitelistedCollections[addr]) {

77:                 s.whitelistedCollections[addr] = true;

78:                 s.whitelistedCollectionsIndex[addr] = arr.length;

81:                 emit CollectionAddedToWhitelist(addr);

93:     function batchRemoveWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {

95:         address[] storage arr = s.whitelistedCollectionsArray;

102:             if (s.whitelistedCollections[addr]) {

104:                 uint256 index = s.whitelistedCollectionsIndex[addr];

111:                     s.whitelistedCollectionsIndex[lastAddress] = index;

116:                 delete s.whitelistedCollectionsIndex[addr];

117:                 s.whitelistedCollections[addr] = false;

119:                 emit CollectionRemovedFromWhitelist(addr);

```
[Link to code](--forcefacets/CollectionWhitelistFacet.sol)

```solidity
File: facets/GetterFacet.sol

108:     function isCollectionWhitelisted(address collection) external view returns (bool) {

110:         return s.whitelistedCollections[collection];

117:     function getWhitelistedCollections() external view returns (address[] memory) {

119:         return s.whitelistedCollectionsArray;

134:     function isBuyerWhitelisted(uint128 listingId, address buyer) external view returns (bool) {

139:         return s.whitelistedBuyersByListingId[listingId][buyer];

144:     function getBuyerWhitelistMaxBatchSize() external view returns (uint16 maxBatchSize) {

145:         return LibAppStorage.appStorage().buyerWhitelistMaxBatchSize;

```
[Link to code](--forcefacets/GetterFacet.sol)

```solidity
File: facets/IdeationMarketFacet.sol

10: import "../interfaces/IBuyerWhitelistFacet.sol";

25: error IdeationMarket__CollectionNotWhitelisted(address tokenAddress);

26: error IdeationMarket__BuyerNotWhitelisted(uint128 listingId, address buyer);

33: error IdeationMarket__WhitelistDisabled();

62:         bool buyerWhitelistEnabled,

100:         bool buyerWhitelistEnabled,

128:     event CollectionWhitelistRevokedCancelTriggered(uint128 indexed listingId, address indexed tokenAddress);

168:         bool buyerWhitelistEnabled,

170:         address[] calldata allowedBuyers // whitelisted Buyers

175:         if (!s.whitelistedCollections[tokenAddress]) {

176:             revert IdeationMarket__CollectionNotWhitelisted(tokenAddress);

255:             buyerWhitelistEnabled: buyerWhitelistEnabled,

264:         if (buyerWhitelistEnabled) {

266:             IBuyerWhitelistFacet(address(this)).addBuyerWhitelistAddresses(newListingId, allowedBuyers);

268:             if (allowedBuyers.length > 0) revert IdeationMarket__WhitelistDisabled();

279:             buyerWhitelistEnabled,

301:         if (listedItem.buyerWhitelistEnabled) {

302:             if (!s.whitelistedBuyersByListingId[listingId][msg.sender]) {

303:                 revert IdeationMarket__BuyerNotWhitelisted(listingId, msg.sender);

549:         bool newBuyerWhitelistEnabled,

551:         address[] calldata newAllowedBuyers // whitelisted Buyers

581:         if (!s.whitelistedCollections[tokenAddress]) {

583:             emit CollectionWhitelistRevokedCancelTriggered(listingId, tokenAddress);

624:         listedItem.buyerWhitelistEnabled = newBuyerWhitelistEnabled; // other than in the createListing function where the buyerWhitelist gets passed withing creating the listing, when setting the buyerWhitelist from originally false to true through the updateListing function, the whitelist has to get filled through additional calling of the addBuyerWhitelistAddresses function

627:         if (newBuyerWhitelistEnabled) {

629:             IBuyerWhitelistFacet(address(this)).addBuyerWhitelistAddresses(listingId, newAllowedBuyers);

631:             if (newAllowedBuyers.length > 0) revert IdeationMarket__WhitelistDisabled();

642:             newBuyerWhitelistEnabled,

682:         if (s.whitelistedCollections[listedItem.tokenAddress]) {

```
[Link to code](--forcefacets/IdeationMarketFacet.sol)

```solidity
File: interfaces/IBuyerWhitelistFacet.sol

6: interface IBuyerWhitelistFacet {

10:     function addBuyerWhitelistAddresses(uint128 listingId, address[] calldata allowedBuyers) external;

15:     function removeBuyerWhitelistAddresses(uint128 listingId, address[] calldata disallowedBuyers) external;

```
[Link to code](--forceinterfaces/IBuyerWhitelistFacet.sol)

```solidity
File: libraries/LibAppStorage.sol

7:     bool buyerWhitelistEnabled; // true means only whitelisted buyers can purchase.

23:     uint16 buyerWhitelistMaxBatchSize; // should be 300

29:     mapping(address => bool) whitelistedCollections; // whitelisted collection (NFT) Address => true (or false if this collection has not been whitelisted)

30:     address[] whitelistedCollectionsArray; // for lookups

31:     mapping(address => uint256) whitelistedCollectionsIndex; // to make lookups and deletions more efficient

32:     mapping(uint128 => mapping(address => bool)) whitelistedBuyersByListingId; // listingId => whitelistedBuyer => true (or false if the buyers adress is not on the whitelist)

```
[Link to code](--forcelibraries/LibAppStorage.sol)

```solidity
File: upgradeInitializers/DiamondInit.sol

23:     function init(uint32 innovationFee, uint16 buyerWhitelistMaxBatchSize) external {

40:         s.buyerWhitelistMaxBatchSize = buyerWhitelistMaxBatchSize;

```
[Link to code](--forceupgradeInitializers/DiamondInit.sol)

### <a name="NC-12"></a>[NC-12] Strings should use double quotes rather than single quotes
See the Solidity Style Guide: https://docs.soliditylang.org/en/v0.8.20/style-guide.html#other-recommendations

*Instances (2)*:
```solidity
File: facets/IdeationMarketFacet.sol

411:                 remainingBalance = swapBalance - listedItem.desiredErc1155Quantity + 1; // using this +1 trick for the '<=' comparison in the cleanup

```
[Link to code](--forcefacets/IdeationMarketFacet.sol)

```solidity
File: libraries/LibDiamond.sol

181:         require(_facetAddress != address(0), "LibDiamondCut: Can't remove function that doesn't exist");

```
[Link to code](--forcelibraries/LibDiamond.sol)

### <a name="NC-13"></a>[NC-13] Use Underscores for Number Literals (add an underscore every 3 digits)

*Instances (2)*:
```solidity
File: facets/IdeationMarketFacet.sol

364:         uint256 innovationProceeds = ((purchasePrice * listedItem.feeRate) / 100000);

```
[Link to code](--forcefacets/IdeationMarketFacet.sol)

```solidity
File: libraries/LibAppStorage.sol

22:     uint32 innovationFee; // e.g., 1000 = 1% // this is the innovation/Marketplace fee (excluding gascosts) for each sale

```
[Link to code](--forcelibraries/LibAppStorage.sol)

### <a name="NC-14"></a>[NC-14] Event is missing `indexed` fields
Index event fields make the field more quickly accessible to off-chain tools that parse events. However, note that each index field costs extra gas during emission, so it's not necessarily best to index the maximum allowed per event (three fields). Each event should use three indexed fields if there are three or more fields, and gas usage is not particularly of concern for the events in question. If there are fewer than three fields, all of the fields should be indexed.

*Instances (4)*:
```solidity
File: interfaces/IERC1155.sol

30:     event ApprovalForAll(address indexed account, address indexed operator, bool approved);

39:     event URI(string value, uint256 indexed id);

```
[Link to code](--forceinterfaces/IERC1155.sol)

```solidity
File: interfaces/IERC4907.sol

21:     /// @param expires  UNIX timestamp, The new user could use the NFT before expires

```
[Link to code](--forceinterfaces/IERC4907.sol)

```solidity
File: interfaces/IERC721.sol

25:     event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

```
[Link to code](--forceinterfaces/IERC721.sol)

### <a name="NC-15"></a>[NC-15] Variables need not be initialized to zero
The default value for variables is zero, so initializing them to zero is superfluous.

*Instances (14)*:
```solidity
File: facets/BuyerWhitelistFacet.sol

29:         for (uint256 i = 0; i < len;) {

54:         for (uint256 i = 0; i < len;) {

```
[Link to code](--forcefacets/BuyerWhitelistFacet.sol)

```solidity
File: facets/CollectionWhitelistFacet.sol

72:         for (uint256 i = 0; i < len;) {

99:         for (uint256 i = 0; i < len;) {

```
[Link to code](--forcefacets/CollectionWhitelistFacet.sol)

```solidity
File: facets/DiamondLoupeFacet.sol

21:         for (uint256 i = 0; i < numFacets;) {

```
[Link to code](--forcefacets/DiamondLoupeFacet.sol)

```solidity
File: facets/GetterFacet.sol

25:         uint256 activeCount = 0;

26:         for (uint256 i = 0; i < totalIds;) {

43:         uint256 arrayIndex = 0;

44:         for (uint256 i = 0; i < totalIds;) {

```
[Link to code](--forcefacets/GetterFacet.sol)

```solidity
File: facets/IdeationMarketFacet.sol

395:             uint256 remainingBalance = 0; // initializing this for erc1155 cleanup

452:             for (uint256 i = 0; i < len;) {

761:         for (uint256 i = 0; i < len;) {

```
[Link to code](--forcefacets/IdeationMarketFacet.sol)

```solidity
File: libraries/LibDiamond.sol

80:         for (uint256 facetIndex = 0; facetIndex < cutLen;) {

111:         for (uint256 selectorIndex = 0; selectorIndex < selLen;) {

```
[Link to code](--forcelibraries/LibDiamond.sol)


## Low Issues


| |Issue|Instances|
|-|:-|:-:|
| [L-1](#L-1) | Division by zero not prevented | 1 |
| [L-2](#L-2) | External call recipient may consume all transaction gas | 1 |
| [L-3](#L-3) | Initializers could be front-run | 1 |
| [L-4](#L-4) | Use `Ownable2Step.transferOwnership` instead of `Ownable.transferOwnership` | 2 |
| [L-5](#L-5) | Upgradeable contract not initialized | 2 |
### <a name="L-1"></a>[L-1] Division by zero not prevented
The divisions below take an input parameter which does not have any zero-value checks, which may lead to the functions reverting when zero is passed.

*Instances (1)*:
```solidity
File: facets/IdeationMarketFacet.sol

333:             purchasePrice = listedItem.price * erc1155PurchaseQuantity / listedItem.erc1155Quantity;

```
[Link to code](--forcefacets/IdeationMarketFacet.sol)

### <a name="L-2"></a>[L-2] External call recipient may consume all transaction gas
There is no limit specified on the amount of gas used, so the recipient can use up all of the transaction's gas, causing it to revert. Use `addr.call{gas: <amount>}("")` or [this](https://github.com/nomad-xyz/ExcessivelySafeCall) library instead.

*Instances (1)*:
```solidity
File: facets/IdeationMarketFacet.sol

659:         (bool success,) = payable(msg.sender).call{value: proceeds}("");

```
[Link to code](--forcefacets/IdeationMarketFacet.sol)

### <a name="L-3"></a>[L-3] Initializers could be front-run
Initializers could be front-run, allowing an attacker to either set their own values, take ownership of the contract, and in the best case forcing a re-deployment

*Instances (1)*:
```solidity
File: upgradeInitializers/DiamondInit.sol

23:     function init(uint32 innovationFee, uint16 buyerWhitelistMaxBatchSize) external {

```
[Link to code](--forceupgradeInitializers/DiamondInit.sol)

### <a name="L-4"></a>[L-4] Use `Ownable2Step.transferOwnership` instead of `Ownable.transferOwnership`
Use [Ownable2Step.transferOwnership](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable2Step.sol) which is safer. Use it as it is more secure due to 2-stage ownership transfer.

**Recommended Mitigation Steps**

Use <a href="https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable2Step.sol">Ownable2Step.sol</a>
  
  ```solidity
      function acceptOwnership() external {
          address sender = _msgSender();
          require(pendingOwner() == sender, "Ownable2Step: caller is not the new owner");
          _transferOwnership(sender);
      }
```

*Instances (2)*:
```solidity
File: facets/OwnershipFacet.sol

14:     function transferOwnership(address newOwner) external override {

```
[Link to code](--forcefacets/OwnershipFacet.sol)

```solidity
File: interfaces/IERC173.sol

18:     function transferOwnership(address _newOwner) external;

```
[Link to code](--forceinterfaces/IERC173.sol)

### <a name="L-5"></a>[L-5] Upgradeable contract not initialized
Upgradeable contracts are initialized via an initializer function rather than by a constructor. Leaving such a contract uninitialized may lead to it being taken over by a malicious user

*Instances (2)*:
```solidity
File: libraries/LibDiamond.sol

96:         initializeDiamondCut(_init, _calldata);

212:     function initializeDiamondCut(address _init, bytes memory _calldata) internal {

```
[Link to code](--forcelibraries/LibDiamond.sol)


## Medium Issues


| |Issue|Instances|
|-|:-|:-:|
| [M-1](#M-1) | Centralization Risk for trusted owners | 4 |
| [M-2](#M-2) | Direct `supportsInterface()` calls may cause caller to revert | 5 |
### <a name="M-1"></a>[M-1] Centralization Risk for trusted owners

#### Impact:
Contracts have owners with privileged rights to perform admin tasks and need to be trusted to not perform malicious updates or drain funds.

*Instances (4)*:
```solidity
File: facets/CollectionWhitelistFacet.sol

26:     function addWhitelistedCollection(address tokenAddress) external onlyOwner {

41:     function removeWhitelistedCollection(address tokenAddress) external onlyOwner {

66:     function batchAddWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {

93:     function batchRemoveWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {

```
[Link to code](--forcefacets/CollectionWhitelistFacet.sol)

### <a name="M-2"></a>[M-2] Direct `supportsInterface()` calls may cause caller to revert
Calling `supportsInterface()` on a contract that doesn't implement the ERC-165 standard will result in the call reverting. Even if the caller does support the function, the contract may be malicious and consume all of the transaction's available gas. Call it via a low-level [staticcall()](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/f959d7e4e6ee0b022b41e5b644c79369869d8411/contracts/utils/introspection/ERC165Checker.sol#L119), with a fixed amount of gas, and check the return code, or use OpenZeppelin's [`ERC165Checker.supportsInterface()`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/f959d7e4e6ee0b022b41e5b644c79369869d8411/contracts/utils/introspection/ERC165Checker.sol#L36-L39).

*Instances (5)*:
```solidity
File: facets/IdeationMarketFacet.sol

231:             if (!IERC165(tokenAddress).supportsInterface(type(IERC1155).interfaceId)) {

236:             if (!IERC165(tokenAddress).supportsInterface(type(IERC721).interfaceId)) {

370:         if (IERC165(listedItem.tokenAddress).supportsInterface(type(IERC2981).interfaceId)) {

744:             if (!IERC165(desiredTokenAddress).supportsInterface(type(IERC1155).interfaceId)) {

748:             if (!IERC165(desiredTokenAddress).supportsInterface(type(IERC721).interfaceId)) {

```
[Link to code](--forcefacets/IdeationMarketFacet.sol)

