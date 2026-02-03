**THIS CHECKLIST IS NOT COMPLETE**. Use `--show-ignored-findings` to show all the results.
Summary
 - [boolean-cst](#boolean-cst) (1 results) (Medium)
 - [calls-loop](#calls-loop) (5 results) (Low)
 - [reentrancy-events](#reentrancy-events) (2 results) (Low)
 - [assembly](#assembly) (5 results) (Informational)
 - [cyclomatic-complexity](#cyclomatic-complexity) (5 results) (Informational)
 - [low-level-calls](#low-level-calls) (2 results) (Informational)
 - [naming-convention](#naming-convention) (26 results) (Informational)
 - [too-many-digits](#too-many-digits) (1 results) (Informational)
## boolean-cst
Impact: Medium
Confidence: Medium
 - [ ] ID-0
[IdeationMarketFacet.cleanListing(uint128)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L733-L816) uses a Boolean constant improperly:
	-[false](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L805)

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L733-L816


## calls-loop
Impact: Low
Confidence: Medium
 - [ ] ID-1
[IdeationMarketFacet.cleanListing(uint128)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L733-L816) has external calls inside a loop: [approvedForAll = token_scope_0.isApprovedForAll(listedItem.seller,address(this))](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L786-L794)

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L733-L816


 - [ ] ID-2
[IdeationMarketFacet.cleanListing(uint128)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L733-L816) has external calls inside a loop: [approved_scope_1 = token_scope_0.getApproved(listedItem.tokenId)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L783-L799)

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L733-L816


 - [ ] ID-3
[IdeationMarketFacet.cleanListing(uint128)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L733-L816) has external calls inside a loop: [approved = token.isApprovedForAll(listedItem.seller,address(this))](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L759-L767)

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L733-L816


 - [ ] ID-4
[IdeationMarketFacet.cleanListing(uint128)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L733-L816) has external calls inside a loop: [balance = token.balanceOf(listedItem.seller,listedItem.tokenId)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L748-L756)

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L733-L816


 - [ ] ID-5
[IdeationMarketFacet.cleanListing(uint128)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L733-L816) has external calls inside a loop: [currOwner = token_scope_0.ownerOf(listedItem.tokenId)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L772-L780)

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L733-L816


## reentrancy-events
Impact: Low
Confidence: Medium
 - [ ] ID-6
Reentrancy in [IdeationMarketFacet.updateListing(uint128,uint256,address,uint256,uint256,uint256,bool,bool,address[])](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L590-L706):
	External calls:
	- [IBuyerWhitelistFacet(address(this)).addBuyerWhitelistAddresses(listingId,newAllowedBuyers)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L686)
	Event emitted after the call(s):
	- [ListingUpdated(listedItem.listingId,tokenAddress,tokenId,newErc1155Quantity,newPrice,listedItem.feeRate,seller,newBuyerWhitelistEnabled,newPartialBuyEnabled,newDesiredTokenAddress,newDesiredTokenId,newDesiredErc1155Quantity)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L692-L705)

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L590-L706


 - [ ] ID-7
Reentrancy in [IdeationMarketFacet.createListing(address,uint256,address,uint256,address,uint256,uint256,uint256,bool,bool,address[])](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L159-L302):
	External calls:
	- [IBuyerWhitelistFacet(address(this)).addBuyerWhitelistAddresses(newListingId,allowedBuyers)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L282)
	Event emitted after the call(s):
	- [ListingCreated(s.listingIdCounter,tokenAddress,tokenId,erc1155Quantity,price,s.innovationFee,seller,buyerWhitelistEnabled,partialBuyEnabled,desiredTokenAddress,desiredTokenId,desiredErc1155Quantity)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L288-L301)

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L159-L302


## assembly
Impact: Informational
Confidence: High
 - [ ] ID-8
[IdeationMarketDiamond.fallback()](4naly3er/contracts/src/IdeationMarketDiamond.sol#L36-L59) uses assembly
	- [INLINE ASM](4naly3er/contracts/src/IdeationMarketDiamond.sol#L40-L42)
	- [INLINE ASM](4naly3er/contracts/src/IdeationMarketDiamond.sol#L47-L58)

4naly3er/contracts/src/IdeationMarketDiamond.sol#L36-L59


 - [ ] ID-9
[LibAppStorage.appStorage()](4naly3er/contracts/src/libraries/LibAppStorage.sol#L39-L44) uses assembly
	- [INLINE ASM](4naly3er/contracts/src/libraries/LibAppStorage.sol#L41-L43)

4naly3er/contracts/src/libraries/LibAppStorage.sol#L39-L44


 - [ ] ID-10
[LibDiamond.diamondStorage()](4naly3er/contracts/src/libraries/LibDiamond.sol#L48-L54) uses assembly
	- [INLINE ASM](4naly3er/contracts/src/libraries/LibDiamond.sol#L51-L53)

4naly3er/contracts/src/libraries/LibDiamond.sol#L48-L54


 - [ ] ID-11
[LibDiamond.enforceHasContractCode(address,string)](4naly3er/contracts/src/libraries/LibDiamond.sol#L232-L238) uses assembly
	- [INLINE ASM](4naly3er/contracts/src/libraries/LibDiamond.sol#L234-L236)

4naly3er/contracts/src/libraries/LibDiamond.sol#L232-L238


 - [ ] ID-12
[LibDiamond.initializeDiamondCut(address,bytes)](4naly3er/contracts/src/libraries/LibDiamond.sol#L212-L230) uses assembly
	- [INLINE ASM](4naly3er/contracts/src/libraries/LibDiamond.sol#L222-L225)

4naly3er/contracts/src/libraries/LibDiamond.sol#L212-L230


## cyclomatic-complexity
Impact: Informational
Confidence: High
 - [ ] ID-13
[IdeationMarketFacet.purchaseListing(uint128,uint256,uint256,address,uint256,uint256,uint256,address)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L304-L525) has a high cyclomatic complexity (27).

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L304-L525


 - [ ] ID-14
[IdeationMarketFacet.cancelListing(uint128)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L528-L588) has a high cyclomatic complexity (14).

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L528-L588


 - [ ] ID-15
[IdeationMarketFacet.cleanListing(uint128)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L733-L816) has a high cyclomatic complexity (20).

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L733-L816


 - [ ] ID-16
[IdeationMarketFacet.updateListing(uint128,uint256,address,uint256,uint256,uint256,bool,bool,address[])](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L590-L706) has a high cyclomatic complexity (15).

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L590-L706


 - [ ] ID-17
[IdeationMarketFacet.createListing(address,uint256,address,uint256,address,uint256,uint256,uint256,bool,bool,address[])](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L159-L302) has a high cyclomatic complexity (20).

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L159-L302


## low-level-calls
Impact: Informational
Confidence: High
 - [ ] ID-18
Low level call in [IdeationMarketFacet.withdrawProceeds()](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L708-L722):
	- [(success,None) = address(msg.sender).call{value: proceeds}()](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L717)

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L708-L722


 - [ ] ID-19
Low level call in [LibDiamond.initializeDiamondCut(address,bytes)](4naly3er/contracts/src/libraries/LibDiamond.sol#L212-L230):
	- [(success,error) = _init.delegatecall(_calldata)](4naly3er/contracts/src/libraries/LibDiamond.sol#L217)

4naly3er/contracts/src/libraries/LibDiamond.sol#L212-L230


## naming-convention
Impact: Informational
Confidence: High
 - [ ] ID-20
Parameter [DiamondLoupeFacet.supportsInterface(bytes4)._interfaceId](4naly3er/contracts/src/facets/DiamondLoupeFacet.sol#L63) is not in mixedCase

4naly3er/contracts/src/facets/DiamondLoupeFacet.sol#L63


 - [ ] ID-21
Parameter [LibDiamond.initializeDiamondCut(address,bytes)._init](4naly3er/contracts/src/libraries/LibDiamond.sol#L212) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L212


 - [ ] ID-22
Parameter [DiamondLoupeFacet.facetAddress(bytes4)._functionSelector](4naly3er/contracts/src/facets/DiamondLoupeFacet.sol#L55) is not in mixedCase

4naly3er/contracts/src/facets/DiamondLoupeFacet.sol#L55


 - [ ] ID-23
Parameter [LibDiamond.addFacet(LibDiamond.DiamondStorage,address)._facetAddress](4naly3er/contracts/src/libraries/LibDiamond.sol#L166) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L166


 - [ ] ID-24
Parameter [LibDiamond.addFunctions(address,bytes4[])._facetAddress](4naly3er/contracts/src/libraries/LibDiamond.sol#L99) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L99


 - [ ] ID-25
Parameter [LibDiamond.enforceHasContractCode(address,string)._contract](4naly3er/contracts/src/libraries/LibDiamond.sol#L232) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L232


 - [ ] ID-26
Parameter [LibDiamond.removeFunctions(address,bytes4[])._functionSelectors](4naly3er/contracts/src/libraries/LibDiamond.sol#L148) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L148


 - [ ] ID-27
Parameter [LibDiamond.initializeDiamondCut(address,bytes)._calldata](4naly3er/contracts/src/libraries/LibDiamond.sol#L212) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L212


 - [ ] ID-28
Parameter [LibDiamond.diamondCut(IDiamondCutFacet.FacetCut[],address,bytes)._init](4naly3er/contracts/src/libraries/LibDiamond.sol#L76) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L76


 - [ ] ID-29
Parameter [DiamondCutFacet.diamondCut(IDiamondCutFacet.FacetCut[],address,bytes)._init](4naly3er/contracts/src/facets/DiamondCutFacet.sol#L18) is not in mixedCase

4naly3er/contracts/src/facets/DiamondCutFacet.sol#L18


 - [ ] ID-30
Parameter [LibDiamond.replaceFunctions(address,bytes4[])._functionSelectors](4naly3er/contracts/src/libraries/LibDiamond.sol#L123) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L123


 - [ ] ID-31
Parameter [LibDiamond.addFunction(LibDiamond.DiamondStorage,bytes4,uint96,address)._facetAddress](4naly3er/contracts/src/libraries/LibDiamond.sol#L172) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L172


 - [ ] ID-32
Parameter [LibDiamond.addFunction(LibDiamond.DiamondStorage,bytes4,uint96,address)._selectorPosition](4naly3er/contracts/src/libraries/LibDiamond.sol#L172) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L172


 - [ ] ID-33
Parameter [LibDiamond.enforceHasContractCode(address,string)._errorMessage](4naly3er/contracts/src/libraries/LibDiamond.sol#L232) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L232


 - [ ] ID-34
Parameter [LibDiamond.removeFunction(LibDiamond.DiamondStorage,address,bytes4)._selector](4naly3er/contracts/src/libraries/LibDiamond.sol#L180) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L180


 - [ ] ID-35
Parameter [LibDiamond.replaceFunctions(address,bytes4[])._facetAddress](4naly3er/contracts/src/libraries/LibDiamond.sol#L123) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L123


 - [ ] ID-36
Parameter [DiamondCutFacet.diamondCut(IDiamondCutFacet.FacetCut[],address,bytes)._diamondCut](4naly3er/contracts/src/facets/DiamondCutFacet.sol#L18) is not in mixedCase

4naly3er/contracts/src/facets/DiamondCutFacet.sol#L18


 - [ ] ID-37
Parameter [LibDiamond.setContractOwner(address)._newOwner](4naly3er/contracts/src/libraries/LibDiamond.sol#L58) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L58


 - [ ] ID-38
Parameter [LibDiamond.diamondCut(IDiamondCutFacet.FacetCut[],address,bytes)._calldata](4naly3er/contracts/src/libraries/LibDiamond.sol#L76) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L76


 - [ ] ID-39
Parameter [LibDiamond.removeFunction(LibDiamond.DiamondStorage,address,bytes4)._facetAddress](4naly3er/contracts/src/libraries/LibDiamond.sol#L180) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L180


 - [ ] ID-40
Parameter [DiamondLoupeFacet.facetFunctionSelectors(address)._facet](4naly3er/contracts/src/facets/DiamondLoupeFacet.sol#L34) is not in mixedCase

4naly3er/contracts/src/facets/DiamondLoupeFacet.sol#L34


 - [ ] ID-41
Parameter [LibDiamond.addFunctions(address,bytes4[])._functionSelectors](4naly3er/contracts/src/libraries/LibDiamond.sol#L99) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L99


 - [ ] ID-42
Parameter [DiamondCutFacet.diamondCut(IDiamondCutFacet.FacetCut[],address,bytes)._calldata](4naly3er/contracts/src/facets/DiamondCutFacet.sol#L18) is not in mixedCase

4naly3er/contracts/src/facets/DiamondCutFacet.sol#L18


 - [ ] ID-43
Parameter [LibDiamond.removeFunctions(address,bytes4[])._facetAddress](4naly3er/contracts/src/libraries/LibDiamond.sol#L148) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L148


 - [ ] ID-44
Parameter [LibDiamond.addFunction(LibDiamond.DiamondStorage,bytes4,uint96,address)._selector](4naly3er/contracts/src/libraries/LibDiamond.sol#L172) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L172


 - [ ] ID-45
Parameter [LibDiamond.diamondCut(IDiamondCutFacet.FacetCut[],address,bytes)._diamondCut](4naly3er/contracts/src/libraries/LibDiamond.sol#L76) is not in mixedCase

4naly3er/contracts/src/libraries/LibDiamond.sol#L76


## too-many-digits
Impact: Informational
Confidence: Medium
 - [ ] ID-46
[IdeationMarketFacet.purchaseListing(uint128,uint256,uint256,address,uint256,uint256,uint256,address)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L304-L525) uses literals with too many digits:
	- [innovationProceeds = ((purchasePrice * listedItem.feeRate) / 100000)](4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L381)

4naly3er/contracts/src/facets/IdeationMarketFacet.sol#L304-L525


