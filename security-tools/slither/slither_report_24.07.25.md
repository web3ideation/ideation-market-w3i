**THIS CHECKLIST IS NOT COMPLETE**. Use `--show-ignored-findings` to show all the results.
Summary
 - [reentrancy-events](#reentrancy-events) (2 results) (Low)
 - [assembly](#assembly) (5 results) (Informational)
 - [cyclomatic-complexity](#cyclomatic-complexity) (3 results) (Informational)
 - [low-level-calls](#low-level-calls) (2 results) (Informational)
 - [naming-convention](#naming-convention) (26 results) (Informational)
 - [too-many-digits](#too-many-digits) (1 results) (Informational)
## reentrancy-events
Impact: Low
Confidence: Medium
 - [ ] ID-0
Reentrancy in [IdeationMarketFacet.updateListing(uint128,uint256,address,uint256,uint256,uint256,bool,bool,address[])](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L542-L648):
	External calls:
	- [IBuyerWhitelistFacet(address(this)).addBuyerWhitelistAddresses(listingId,newAllowedBuyers)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L629)
	Event emitted after the call(s):
	- [ListingUpdated(listedItem.listingId,tokenAddress,tokenId,newErc1155Quantity,newPrice,listedItem.feeRate,seller,newBuyerWhitelistEnabled,newPartialBuyEnabled,newDesiredTokenAddress,newDesiredTokenId,newDesiredErc1155Quantity)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L634-L647)

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L542-L648


 - [ ] ID-1
Reentrancy in [IdeationMarketFacet.createListing(address,uint256,address,uint256,address,uint256,uint256,uint256,bool,bool,address[])](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L159-L285):
	External calls:
	- [IBuyerWhitelistFacet(address(this)).addBuyerWhitelistAddresses(newListingId,allowedBuyers)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L266)
	Event emitted after the call(s):
	- [ListingCreated(s.listingIdCounter,tokenAddress,tokenId,erc1155Quantity,price,s.innovationFee,seller,buyerWhitelistEnabled,partialBuyEnabled,desiredTokenAddress,desiredTokenId,desiredErc1155Quantity)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L271-L284)

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L159-L285


## assembly
Impact: Informational
Confidence: High
 - [ ] ID-2
[IdeationMarketDiamond.fallback()](4naly3er/contracts/src/IdeationMarketDiamond.sol#L36-L59) uses assembly
	- [INLINE ASM](4naly3er/contracts/src/IdeationMarketDiamond.sol#L40-L42)
	- [INLINE ASM](4naly3er/contracts/src/IdeationMarketDiamond.sol#L47-L58)

4naly3er/contracts/src/IdeationMarketDiamond.sol#L36-L59


 - [ ] ID-3
[LibAppStorage.appStorage()](4naly3er/contracts/src/libraries/LibAppStorage.sol#L39-L44) uses assembly
	- [INLINE ASM](4naly3er/contracts/src/libraries/LibAppStorage.sol#L41-L43)

4naly3er/contracts/src/libraries/LibAppStorage.sol#L39-L44


 - [ ] ID-4
[LibDiamond.diamondStorage()](4naly3er/contracts/src/libraries/LibDiamond.sol#L48-L54) uses assembly
	- [INLINE ASM](4naly3er/contracts/src/libraries/LibDiamond.sol#L51-L53)

4naly3er/contracts/src/libraries/LibDiamond.sol#L48-L54


 - [ ] ID-5
[LibDiamond.enforceHasContractCode(address,string)](4naly3er/contracts/src/libraries/LibDiamond.sol#L232-L238) uses assembly
	- [INLINE ASM](4naly3er/contracts/src/libraries/LibDiamond.sol#L234-L236)

4naly3er/contracts/src/libraries/LibDiamond.sol#L232-L238


 - [ ] ID-6
[LibDiamond.initializeDiamondCut(address,bytes)](4naly3er/contracts/src/libraries/LibDiamond.sol#L212-L230) uses assembly
	- [INLINE ASM](4naly3er/contracts/src/libraries/LibDiamond.sol#L222-L225)

4naly3er/contracts/src/libraries/LibDiamond.sol#L212-L230


## cyclomatic-complexity
Impact: Informational
Confidence: High
 - [ ] ID-7
[IdeationMarketFacet.updateListing(uint128,uint256,address,uint256,uint256,uint256,bool,bool,address[])](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L542-L648) has a high cyclomatic complexity (12).

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L542-L648


 - [ ] ID-8
[IdeationMarketFacet.createListing(address,uint256,address,uint256,address,uint256,uint256,uint256,bool,bool,address[])](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L159-L285) has a high cyclomatic complexity (17).

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L159-L285


 - [ ] ID-9
[IdeationMarketFacet.purchaseListing(uint128,uint256,uint256,address,uint256,uint256,uint256,address)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L287-L510) has a high cyclomatic complexity (28).

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L287-L510


## low-level-calls
Impact: Informational
Confidence: High
 - [ ] ID-10
Low level call in [IdeationMarketFacet.withdrawProceeds()](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L650-L664):
	- [(success,None) = address(msg.sender).call{value: proceeds}()](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L659)

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L650-L664


 - [ ] ID-11
Low level call in [LibDiamond.initializeDiamondCut(address,bytes)](4naly3er/contracts/src/libraries/LibDiamond.sol#L212-L230):
	- [(success,error) = _init.delegatecall(_calldata)](4naly3er/contracts/src/libraries/LibDiamond.sol#L217)

4naly3er/contracts/src/libraries/LibDiamond.sol#L212-L230


## naming-convention
Impact: Informational
Confidence: High
 - [ ] ID-12
Parameter [DiamondLoupeFacet.supportsInterface(bytes4)._interfaceId](4naly3er/contracts/src/facets/DiamondLoupeFacet.sol#L63) is not in mixedCase

4naly3er/contracts/src/facets/DiamondLoupeFacet.sol#L63


 - [ ] ID-13
Parameter [LibDiamond.initializeDiamondCut(address,bytes)._init](4naly3er/contracts/src/libraries/LibDiamond.sol#L212) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L212


 - [ ] ID-14
Parameter [DiamondLoupeFacet.facetAddress(bytes4)._functionSelector](4naly3er/contracts/src/facets/DiamondLoupeFacet.sol#L55) is not in mixedCase

4naly3er/contracts/src/facets/DiamondLoupeFacet.sol#L55


 - [ ] ID-15
Parameter [LibDiamond.addFacet(LibDiamond.DiamondStorage,address)._facetAddress](4naly3er/contracts/src/libraries/LibDiamond.sol#L166) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L166


 - [ ] ID-16
Parameter [LibDiamond.addFunctions(address,bytes4[])._facetAddress](4naly3er/contracts/src/libraries/LibDiamond.sol#L99) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L99


 - [ ] ID-17
Parameter [LibDiamond.enforceHasContractCode(address,string)._contract](4naly3er/contracts/src/libraries/LibDiamond.sol#L232) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L232


 - [ ] ID-18
Parameter [LibDiamond.removeFunctions(address,bytes4[])._functionSelectors](4naly3er/contracts/src/libraries/LibDiamond.sol#L148) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L148


 - [ ] ID-19
Parameter [LibDiamond.initializeDiamondCut(address,bytes)._calldata](4naly3er/contracts/src/libraries/LibDiamond.sol#L212) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L212


 - [ ] ID-20
Parameter [LibDiamond.diamondCut(IDiamondCutFacet.FacetCut[],address,bytes)._init](4naly3er/contracts/src/libraries/LibDiamond.sol#L76) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L76


 - [ ] ID-21
Parameter [DiamondCutFacet.diamondCut(IDiamondCutFacet.FacetCut[],address,bytes)._init](4naly3er/contracts/src/facets/DiamondCutFacet.sol#L18) is not in mixedCase

4naly3er/contracts/src/facets/DiamondCutFacet.sol#L18


 - [ ] ID-22
Parameter [LibDiamond.replaceFunctions(address,bytes4[])._functionSelectors](4naly3er/contracts/src/libraries/LibDiamond.sol#L123) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L123


 - [ ] ID-23
Parameter [LibDiamond.addFunction(LibDiamond.DiamondStorage,bytes4,uint96,address)._facetAddress](4naly3er/contracts/src/libraries/LibDiamond.sol#L172) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L172


 - [ ] ID-24
Parameter [LibDiamond.addFunction(LibDiamond.DiamondStorage,bytes4,uint96,address)._selectorPosition](4naly3er/contracts/src/libraries/LibDiamond.sol#L172) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L172


 - [ ] ID-25
Parameter [LibDiamond.enforceHasContractCode(address,string)._errorMessage](4naly3er/contracts/src/libraries/LibDiamond.sol#L232) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L232


 - [ ] ID-26
Parameter [LibDiamond.removeFunction(LibDiamond.DiamondStorage,address,bytes4)._selector](4naly3er/contracts/src/libraries/LibDiamond.sol#L180) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L180


 - [ ] ID-27
Parameter [LibDiamond.replaceFunctions(address,bytes4[])._facetAddress](4naly3er/contracts/src/libraries/LibDiamond.sol#L123) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L123


 - [ ] ID-28
Parameter [DiamondCutFacet.diamondCut(IDiamondCutFacet.FacetCut[],address,bytes)._diamondCut](4naly3er/contracts/src/facets/DiamondCutFacet.sol#L18) is not in mixedCase

4naly3er/contracts/src/facets/DiamondCutFacet.sol#L18


 - [ ] ID-29
Parameter [LibDiamond.setContractOwner(address)._newOwner](4naly3er/contracts/src/libraries/LibDiamond.sol#L58) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L58


 - [ ] ID-30
Parameter [LibDiamond.diamondCut(IDiamondCutFacet.FacetCut[],address,bytes)._calldata](4naly3er/contracts/src/libraries/LibDiamond.sol#L76) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L76


 - [ ] ID-31
Parameter [LibDiamond.removeFunction(LibDiamond.DiamondStorage,address,bytes4)._facetAddress](4naly3er/contracts/src/libraries/LibDiamond.sol#L180) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L180


 - [ ] ID-32
Parameter [DiamondLoupeFacet.facetFunctionSelectors(address)._facet](4naly3er/contracts/src/facets/DiamondLoupeFacet.sol#L34) is not in mixedCase

4naly3er/contracts/src/facets/DiamondLoupeFacet.sol#L34


 - [ ] ID-33
Parameter [LibDiamond.addFunctions(address,bytes4[])._functionSelectors](4naly3er/contracts/src/libraries/LibDiamond.sol#L99) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L99


 - [ ] ID-34
Parameter [DiamondCutFacet.diamondCut(IDiamondCutFacet.FacetCut[],address,bytes)._calldata](4naly3er/contracts/src/facets/DiamondCutFacet.sol#L18) is not in mixedCase

4naly3er/contracts/src/facets/DiamondCutFacet.sol#L18


 - [ ] ID-35
Parameter [LibDiamond.removeFunctions(address,bytes4[])._facetAddress](4naly3er/contracts/src/libraries/LibDiamond.sol#L148) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L148


 - [ ] ID-36
Parameter [LibDiamond.addFunction(LibDiamond.DiamondStorage,bytes4,uint96,address)._selector](4naly3er/contracts/src/libraries/LibDiamond.sol#L172) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L172


 - [ ] ID-37
Parameter [LibDiamond.diamondCut(IDiamondCutFacet.FacetCut[],address,bytes)._diamondCut](4naly3er/contracts/src/libraries/LibDiamond.sol#L76) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L76


## too-many-digits
Impact: Informational
Confidence: Medium
 - [ ] ID-38
[IdeationMarketFacet.purchaseListing(uint128,uint256,uint256,address,uint256,uint256,uint256,address)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L287-L510) uses literals with too many digits:
	- [innovationProceeds = ((purchasePrice * listedItem.feeRate) / 100000)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L364)

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L287-L510


