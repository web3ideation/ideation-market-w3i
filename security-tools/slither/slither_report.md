**THIS CHECKLIST IS NOT COMPLETE**. Use `--show-ignored-findings` to show all the results.
Summary
 - [arbitrary-send-eth](#arbitrary-send-eth) (1 results) (High)
 - [controlled-delegatecall](#controlled-delegatecall) (1 results) (High)
 - [boolean-cst](#boolean-cst) (1 results) (Medium)
 - [divide-before-multiply](#divide-before-multiply) (1 results) (Medium)
 - [erc20-interface](#erc20-interface) (3 results) (Medium)
 - [locked-ether](#locked-ether) (1 results) (Medium)
 - [uninitialized-local](#uninitialized-local) (2 results) (Medium)
 - [calls-loop](#calls-loop) (5 results) (Low)
 - [reentrancy-events](#reentrancy-events) (3 results) (Low)
 - [assembly](#assembly) (7 results) (Informational)
 - [cyclomatic-complexity](#cyclomatic-complexity) (5 results) (Informational)
 - [low-level-calls](#low-level-calls) (4 results) (Informational)
 - [naming-convention](#naming-convention) (31 results) (Informational)
 - [too-many-digits](#too-many-digits) (1 results) (Informational)
## arbitrary-send-eth
Impact: High
Confidence: Medium
 - [ ] ID-0
[IdeationMarketFacet._distributePayments(address,address,uint256,address,uint256,address,address,uint256,uint128)](../../src/facets/IdeationMarketFacet.sol#L998-L1048) sends eth to arbitrary user
	Dangerous calls:
	- [(successRoyalty,None) = address(royaltyReceiver).call{value: royaltyAmount}()](../../src/facets/IdeationMarketFacet.sol#L1020)

../../src/facets/IdeationMarketFacet.sol#L998-L1048


## controlled-delegatecall
Impact: High
Confidence: Medium
 - [ ] ID-1
[DiamondUpgradeFacet.upgradeDiamond(IDiamondUpgradeFacet.FacetFunctions[],IDiamondUpgradeFacet.FacetFunctions[],bytes4[],address,bytes,bytes32,bytes)](../../src/facets/DiamondUpgradeFacet.sol#L10-L94) uses delegatecall to a input-controlled function id
	- [(success,returndata) = _delegate.delegatecall(_functionCall)](../../src/facets/DiamondUpgradeFacet.sol#L79)

../../src/facets/DiamondUpgradeFacet.sol#L10-L94


## boolean-cst
Impact: Medium
Confidence: Medium
 - [ ] ID-2
[IdeationMarketFacet.cleanListing(uint128)](../../src/facets/IdeationMarketFacet.sol#L766-L852) uses a Boolean constant improperly:
	-[false](../../src/facets/IdeationMarketFacet.sol#L839)

../../src/facets/IdeationMarketFacet.sol#L766-L852


## divide-before-multiply
Impact: Medium
Confidence: Medium
 - [ ] ID-3
[IdeationMarketFacet.purchaseListing(uint128,uint256,address,uint256,address,uint256,uint256,uint256,address)](../../src/facets/IdeationMarketFacet.sol#L346-L559) performs a multiplication on the result of a division:
	- [unitPrice = listedItem.price / listedItem.erc1155Quantity](../../src/facets/IdeationMarketFacet.sol#L397)
	- [purchasePrice = unitPrice * erc1155PurchaseQuantity](../../src/facets/IdeationMarketFacet.sol#L398)

../../src/facets/IdeationMarketFacet.sol#L346-L559


## erc20-interface
Impact: Medium
Confidence: High
 - [ ] ID-4
[MockUSDTLike_6](../../src/mocks/MockUSDTLike_6.sol#L10-L60) has incorrect ERC20 function interface:[MockUSDTLike_6.approve(address,uint256)](../../src/mocks/MockUSDTLike_6.sol#L29-L34)

../../src/mocks/MockUSDTLike_6.sol#L10-L60


 - [ ] ID-5
[MockUSDTLike_6](../../src/mocks/MockUSDTLike_6.sol#L10-L60) has incorrect ERC20 function interface:[MockUSDTLike_6.transfer(address,uint256)](../../src/mocks/MockUSDTLike_6.sol#L36-L38)

../../src/mocks/MockUSDTLike_6.sol#L10-L60


 - [ ] ID-6
[MockUSDTLike_6](../../src/mocks/MockUSDTLike_6.sol#L10-L60) has incorrect ERC20 function interface:[MockUSDTLike_6.transferFrom(address,address,uint256)](../../src/mocks/MockUSDTLike_6.sol#L40-L48)

../../src/mocks/MockUSDTLike_6.sol#L10-L60


## locked-ether
Impact: Medium
Confidence: High
 - [ ] ID-7
Contract locking ether found:
	Contract [IdeationMarketDiamond](../../src/IdeationMarketDiamond.sol#L16-L57) has payable functions:
	 - [IdeationMarketDiamond.constructor(address,address)](../../src/IdeationMarketDiamond.sol#L20-L27)
	 - [IdeationMarketDiamond.fallback()](../../src/IdeationMarketDiamond.sol#L33-L56)
	But does not have a function to withdraw the ether

../../src/IdeationMarketDiamond.sol#L16-L57


## uninitialized-local
Impact: Medium
Confidence: Medium
 - [ ] ID-8
[DiamondLoupeFacet.functionFacetPairs().totalSelectors](../../src/facets/DiamondLoupeFacet.sol#L74) is a local variable never initialized

../../src/facets/DiamondLoupeFacet.sol#L74


 - [ ] ID-9
[DiamondLoupeFacet.functionFacetPairs().k](../../src/facets/DiamondLoupeFacet.sol#L83) is a local variable never initialized

../../src/facets/DiamondLoupeFacet.sol#L83


## calls-loop
Impact: Low
Confidence: Medium
 - [ ] ID-10
[IdeationMarketFacet.cleanListing(uint128)](../../src/facets/IdeationMarketFacet.sol#L766-L852) has external calls inside a loop: [currOwner = token_scope_0.ownerOf(listedItem.tokenId)](../../src/facets/IdeationMarketFacet.sol#L806-L814)

../../src/facets/IdeationMarketFacet.sol#L766-L852


 - [ ] ID-11
[IdeationMarketFacet.cleanListing(uint128)](../../src/facets/IdeationMarketFacet.sol#L766-L852) has external calls inside a loop: [approvedForAll = token_scope_0.isApprovedForAll(listedItem.seller,address(this))](../../src/facets/IdeationMarketFacet.sol#L820-L828)

../../src/facets/IdeationMarketFacet.sol#L766-L852


 - [ ] ID-12
[IdeationMarketFacet.cleanListing(uint128)](../../src/facets/IdeationMarketFacet.sol#L766-L852) has external calls inside a loop: [approved = token.isApprovedForAll(listedItem.seller,address(this))](../../src/facets/IdeationMarketFacet.sol#L793-L801)

../../src/facets/IdeationMarketFacet.sol#L766-L852


 - [ ] ID-13
[IdeationMarketFacet.cleanListing(uint128)](../../src/facets/IdeationMarketFacet.sol#L766-L852) has external calls inside a loop: [approved_scope_1 = token_scope_0.getApproved(listedItem.tokenId)](../../src/facets/IdeationMarketFacet.sol#L817-L833)

../../src/facets/IdeationMarketFacet.sol#L766-L852


 - [ ] ID-14
[IdeationMarketFacet.cleanListing(uint128)](../../src/facets/IdeationMarketFacet.sol#L766-L852) has external calls inside a loop: [balance = token.balanceOf(listedItem.seller,listedItem.tokenId)](../../src/facets/IdeationMarketFacet.sol#L782-L790)

../../src/facets/IdeationMarketFacet.sol#L766-L852


## reentrancy-events
Impact: Low
Confidence: Medium
 - [ ] ID-15
Reentrancy in [DiamondUpgradeFacet.upgradeDiamond(IDiamondUpgradeFacet.FacetFunctions[],IDiamondUpgradeFacet.FacetFunctions[],bytes4[],address,bytes,bytes32,bytes)](../../src/facets/DiamondUpgradeFacet.sol#L10-L94):
	External calls:
	- [(success,returndata) = _delegate.delegatecall(_functionCall)](../../src/facets/DiamondUpgradeFacet.sol#L79)
	Event emitted after the call(s):
	- [DiamondDelegateCall(_delegate,_functionCall)](../../src/facets/DiamondUpgradeFacet.sol#L87)
	- [DiamondMetadata(_tag,_metadata)](../../src/facets/DiamondUpgradeFacet.sol#L92)

../../src/facets/DiamondUpgradeFacet.sol#L10-L94


 - [ ] ID-16
Reentrancy in [IdeationMarketFacet.createListing(address,uint256,address,uint256,address,address,uint256,uint256,uint256,bool,bool,address[])](../../src/facets/IdeationMarketFacet.sol#L197-L325):
	External calls:
	- [_applyBuyerWhitelist(newListingId,buyerWhitelistEnabled,allowedBuyers)](../../src/facets/IdeationMarketFacet.sol#L308)
		- [IBuyerWhitelistFacet(address(this)).addBuyerWhitelistAddresses(listingId,allowedBuyers)](../../src/facets/IdeationMarketFacet.sol#L904)
	Event emitted after the call(s):
	- [ListingCreated(s.listingIdCounter,tokenAddress,tokenId,erc1155Quantity,price,currency,s.innovationFee,seller,buyerWhitelistEnabled,partialBuyEnabled,desiredTokenAddress,desiredTokenId,desiredErc1155Quantity)](../../src/facets/IdeationMarketFacet.sol#L310-L324)

../../src/facets/IdeationMarketFacet.sol#L197-L325


 - [ ] ID-17
Reentrancy in [IdeationMarketFacet.updateListing(uint128,uint256,address,address,uint256,uint256,uint256,bool,bool,address[])](../../src/facets/IdeationMarketFacet.sol#L647-L747):
	External calls:
	- [_applyBuyerWhitelist(listingId,newBuyerWhitelistEnabled,newAllowedBuyers)](../../src/facets/IdeationMarketFacet.sol#L730)
		- [IBuyerWhitelistFacet(address(this)).addBuyerWhitelistAddresses(listingId,allowedBuyers)](../../src/facets/IdeationMarketFacet.sol#L904)
	Event emitted after the call(s):
	- [ListingUpdated(listedItem.listingId,listedItem.tokenAddress,listedItem.tokenId,newErc1155Quantity,newPrice,newCurrency,listedItem.feeRate,listedItem.seller,newBuyerWhitelistEnabled,newPartialBuyEnabled,newDesiredTokenAddress,newDesiredTokenId,newDesiredErc1155Quantity)](../../src/facets/IdeationMarketFacet.sol#L732-L746)

../../src/facets/IdeationMarketFacet.sol#L647-L747


## assembly
Impact: Informational
Confidence: High
 - [ ] ID-18
[LibDiamond.diamondStorage()](../../src/libraries/LibDiamond.sol#L61-L66) uses assembly
	- [INLINE ASM](../../src/libraries/LibDiamond.sol#L63-L65)

../../src/libraries/LibDiamond.sol#L61-L66


 - [ ] ID-19
[IdeationMarketDiamond.fallback()](../../src/IdeationMarketDiamond.sol#L33-L56) uses assembly
	- [INLINE ASM](../../src/IdeationMarketDiamond.sol#L37-L39)
	- [INLINE ASM](../../src/IdeationMarketDiamond.sol#L44-L55)

../../src/IdeationMarketDiamond.sol#L33-L56


 - [ ] ID-20
[LibDiamond.initializeDiamondCut(address,bytes)](../../src/libraries/LibDiamond.sol#L240-L256) uses assembly
	- [INLINE ASM](../../src/libraries/LibDiamond.sol#L248-L251)

../../src/libraries/LibDiamond.sol#L240-L256


 - [ ] ID-21
[LibAppStorage.appStorage()](../../src/libraries/LibAppStorage.sol#L93-L98) uses assembly
	- [INLINE ASM](../../src/libraries/LibAppStorage.sol#L95-L97)

../../src/libraries/LibAppStorage.sol#L93-L98


 - [ ] ID-22
[LibDiamond.enforceHasContractCode(address,string)](../../src/libraries/LibDiamond.sol#L260-L266) uses assembly
	- [INLINE ASM](../../src/libraries/LibDiamond.sol#L262-L264)

../../src/libraries/LibDiamond.sol#L260-L266


 - [ ] ID-23
[DiamondUpgradeFacet._revertWith(bytes)](../../src/facets/DiamondUpgradeFacet.sol#L104-L108) uses assembly
	- [INLINE ASM](../../src/facets/DiamondUpgradeFacet.sol#L105-L107)

../../src/facets/DiamondUpgradeFacet.sol#L104-L108


 - [ ] ID-24
[DiamondUpgradeFacet._hasCode(address)](../../src/facets/DiamondUpgradeFacet.sol#L96-L102) uses assembly
	- [INLINE ASM](../../src/facets/DiamondUpgradeFacet.sol#L98-L100)

../../src/facets/DiamondUpgradeFacet.sol#L96-L102


## cyclomatic-complexity
Impact: Informational
Confidence: High
 - [ ] ID-25
[IdeationMarketFacet.createListing(address,uint256,address,uint256,address,address,uint256,uint256,uint256,bool,bool,address[])](../../src/facets/IdeationMarketFacet.sol#L197-L325) has a high cyclomatic complexity (13).

../../src/facets/IdeationMarketFacet.sol#L197-L325


 - [ ] ID-26
[IdeationMarketFacet.cancelListing(uint128)](../../src/facets/IdeationMarketFacet.sol#L565-L629) has a high cyclomatic complexity (14).

../../src/facets/IdeationMarketFacet.sol#L565-L629


 - [ ] ID-27
[IdeationMarketFacet.purchaseListing(uint128,uint256,address,uint256,address,uint256,uint256,uint256,address)](../../src/facets/IdeationMarketFacet.sol#L346-L559) has a high cyclomatic complexity (27).

../../src/facets/IdeationMarketFacet.sol#L346-L559


 - [ ] ID-28
[IdeationMarketFacet.cleanListing(uint128)](../../src/facets/IdeationMarketFacet.sol#L766-L852) has a high cyclomatic complexity (20).

../../src/facets/IdeationMarketFacet.sol#L766-L852


 - [ ] ID-29
[DiamondUpgradeFacet.upgradeDiamond(IDiamondUpgradeFacet.FacetFunctions[],IDiamondUpgradeFacet.FacetFunctions[],bytes4[],address,bytes,bytes32,bytes)](../../src/facets/DiamondUpgradeFacet.sol#L10-L94) has a high cyclomatic complexity (22).

../../src/facets/DiamondUpgradeFacet.sol#L10-L94


## low-level-calls
Impact: Informational
Confidence: High
 - [ ] ID-30
Low level call in [IdeationMarketFacet._distributePayments(address,address,uint256,address,uint256,address,address,uint256,uint128)](../../src/facets/IdeationMarketFacet.sol#L998-L1048):
	- [(successFee,None) = address(marketplaceOwner).call{value: innovationFee}()](../../src/facets/IdeationMarketFacet.sol#L1014)
	- [(successRoyalty,None) = address(royaltyReceiver).call{value: royaltyAmount}()](../../src/facets/IdeationMarketFacet.sol#L1020)
	- [(successSeller,None) = address(seller).call{value: sellerProceeds}()](../../src/facets/IdeationMarketFacet.sol#L1026)

../../src/facets/IdeationMarketFacet.sol#L998-L1048


 - [ ] ID-31
Low level call in [DiamondUpgradeFacet.upgradeDiamond(IDiamondUpgradeFacet.FacetFunctions[],IDiamondUpgradeFacet.FacetFunctions[],bytes4[],address,bytes,bytes32,bytes)](../../src/facets/DiamondUpgradeFacet.sol#L10-L94):
	- [(success,returndata) = _delegate.delegatecall(_functionCall)](../../src/facets/DiamondUpgradeFacet.sol#L79)

../../src/facets/DiamondUpgradeFacet.sol#L10-L94


 - [ ] ID-32
Low level call in [LibDiamond.initializeDiamondCut(address,bytes)](../../src/libraries/LibDiamond.sol#L240-L256):
	- [(success,error) = _init.delegatecall(_calldata)](../../src/libraries/LibDiamond.sol#L245)

../../src/libraries/LibDiamond.sol#L240-L256


 - [ ] ID-33
Low level call in [IdeationMarketFacet._safeTransferFrom(address,address,address,uint256)](../../src/facets/IdeationMarketFacet.sol#L1057-L1074):
	- [(success,returndata) = token.call(data)](../../src/facets/IdeationMarketFacet.sol#L1065)

../../src/facets/IdeationMarketFacet.sol#L1057-L1074


## naming-convention
Impact: Informational
Confidence: High
 - [ ] ID-34
Parameter [DiamondLoupeFacet.supportsInterface(bytes4)._interfaceId](../../src/facets/DiamondLoupeFacet.sol#L104) is not in mixedCase

../../src/facets/DiamondLoupeFacet.sol#L104


 - [ ] ID-35
Parameter [LibDiamond.initializeDiamondCut(address,bytes)._init](../../src/libraries/LibDiamond.sol#L240) is not in mixedCase

../../src/libraries/LibDiamond.sol#L240


 - [ ] ID-36
Parameter [DiamondLoupeFacet.facetAddress(bytes4)._functionSelector](../../src/facets/DiamondLoupeFacet.sol#L58) is not in mixedCase

../../src/facets/DiamondLoupeFacet.sol#L58


 - [ ] ID-37
Parameter [DiamondUpgradeFacet.upgradeDiamond(IDiamondUpgradeFacet.FacetFunctions[],IDiamondUpgradeFacet.FacetFunctions[],bytes4[],address,bytes,bytes32,bytes)._delegate](../../src/facets/DiamondUpgradeFacet.sol#L14) is not in mixedCase

../../src/facets/DiamondUpgradeFacet.sol#L14


 - [ ] ID-38
Contract [MockWBTC_8](../../src/mocks/MockWBTC_8.sol#L7-L9) is not in CapWords

../../src/mocks/MockWBTC_8.sol#L7-L9


 - [ ] ID-39
Parameter [DiamondUpgradeFacet.upgradeDiamond(IDiamondUpgradeFacet.FacetFunctions[],IDiamondUpgradeFacet.FacetFunctions[],bytes4[],address,bytes,bytes32,bytes)._addFunctions](../../src/facets/DiamondUpgradeFacet.sol#L11) is not in mixedCase

../../src/facets/DiamondUpgradeFacet.sol#L11


 - [ ] ID-40
Parameter [LibDiamond.addFacet(LibDiamond.DiamondStorage,address)._facetAddress](../../src/libraries/LibDiamond.sol#L188) is not in mixedCase

../../src/libraries/LibDiamond.sol#L188


 - [ ] ID-41
Contract [MockUSDTLike_6](../../src/mocks/MockUSDTLike_6.sol#L10-L60) is not in CapWords

../../src/mocks/MockUSDTLike_6.sol#L10-L60


 - [ ] ID-42
Parameter [LibDiamond.addFunctions(address,bytes4[])._facetAddress](../../src/libraries/LibDiamond.sol#L114) is not in mixedCase

../../src/libraries/LibDiamond.sol#L114


 - [ ] ID-43
Parameter [LibDiamond.enforceHasContractCode(address,string)._contract](../../src/libraries/LibDiamond.sol#L260) is not in mixedCase

../../src/libraries/LibDiamond.sol#L260


 - [ ] ID-44
Parameter [LibDiamond.initializeDiamondCut(address,bytes)._calldata](../../src/libraries/LibDiamond.sol#L240) is not in mixedCase

../../src/libraries/LibDiamond.sol#L240


 - [ ] ID-45
Parameter [LibDiamond.replaceFunctions(address,bytes4[])._functionSelectors](../../src/libraries/LibDiamond.sol#L141) is not in mixedCase

../../src/libraries/LibDiamond.sol#L141


 - [ ] ID-46
Parameter [LibDiamond.addFunction(LibDiamond.DiamondStorage,bytes4,uint96,address)._facetAddress](../../src/libraries/LibDiamond.sol#L196) is not in mixedCase

../../src/libraries/LibDiamond.sol#L196


 - [ ] ID-47
Parameter [LibDiamond.addFunction(LibDiamond.DiamondStorage,bytes4,uint96,address)._selectorPosition](../../src/libraries/LibDiamond.sol#L196) is not in mixedCase

../../src/libraries/LibDiamond.sol#L196


 - [ ] ID-48
Contract [MockERC20_18](../../src/mocks/MockERC20_18.sol#L7-L9) is not in CapWords

../../src/mocks/MockERC20_18.sol#L7-L9


 - [ ] ID-49
Parameter [LibDiamond.enforceHasContractCode(address,string)._errorMessage](../../src/libraries/LibDiamond.sol#L260) is not in mixedCase

../../src/libraries/LibDiamond.sol#L260


 - [ ] ID-50
Parameter [LibDiamond.removeFunction(LibDiamond.DiamondStorage,address,bytes4)._selector](../../src/libraries/LibDiamond.sol#L206) is not in mixedCase

../../src/libraries/LibDiamond.sol#L206


 - [ ] ID-51
Parameter [DiamondUpgradeFacet.upgradeDiamond(IDiamondUpgradeFacet.FacetFunctions[],IDiamondUpgradeFacet.FacetFunctions[],bytes4[],address,bytes,bytes32,bytes)._metadata](../../src/facets/DiamondUpgradeFacet.sol#L17) is not in mixedCase

../../src/facets/DiamondUpgradeFacet.sol#L17


 - [ ] ID-52
Parameter [LibDiamond.replaceFunctions(address,bytes4[])._facetAddress](../../src/libraries/LibDiamond.sol#L141) is not in mixedCase

../../src/libraries/LibDiamond.sol#L141


 - [ ] ID-53
Contract [MockUSDC_6](../../src/mocks/MockUSDC_6.sol#L7-L9) is not in CapWords

../../src/mocks/MockUSDC_6.sol#L7-L9


 - [ ] ID-54
Parameter [LibDiamond.setContractOwner(address)._newOwner](../../src/libraries/LibDiamond.sol#L95) is not in mixedCase

../../src/libraries/LibDiamond.sol#L95


 - [ ] ID-55
Parameter [DiamondUpgradeFacet.upgradeDiamond(IDiamondUpgradeFacet.FacetFunctions[],IDiamondUpgradeFacet.FacetFunctions[],bytes4[],address,bytes,bytes32,bytes)._tag](../../src/facets/DiamondUpgradeFacet.sol#L16) is not in mixedCase

../../src/facets/DiamondUpgradeFacet.sol#L16


 - [ ] ID-56
Parameter [DiamondUpgradeFacet.upgradeDiamond(IDiamondUpgradeFacet.FacetFunctions[],IDiamondUpgradeFacet.FacetFunctions[],bytes4[],address,bytes,bytes32,bytes)._replaceFunctions](../../src/facets/DiamondUpgradeFacet.sol#L12) is not in mixedCase

../../src/facets/DiamondUpgradeFacet.sol#L12


 - [ ] ID-57
Parameter [LibDiamond.removeFunction(LibDiamond.DiamondStorage,address,bytes4)._facetAddress](../../src/libraries/LibDiamond.sol#L206) is not in mixedCase

../../src/libraries/LibDiamond.sol#L206


 - [ ] ID-58
Parameter [DiamondLoupeFacet.facetFunctionSelectors(address)._facet](../../src/facets/DiamondLoupeFacet.sol#L36) is not in mixedCase

../../src/facets/DiamondLoupeFacet.sol#L36


 - [ ] ID-59
Parameter [LibDiamond.addFunctions(address,bytes4[])._functionSelectors](../../src/libraries/LibDiamond.sol#L114) is not in mixedCase

../../src/libraries/LibDiamond.sol#L114


 - [ ] ID-60
Parameter [DiamondUpgradeFacet.upgradeDiamond(IDiamondUpgradeFacet.FacetFunctions[],IDiamondUpgradeFacet.FacetFunctions[],bytes4[],address,bytes,bytes32,bytes)._functionCall](../../src/facets/DiamondUpgradeFacet.sol#L15) is not in mixedCase

../../src/facets/DiamondUpgradeFacet.sol#L15


 - [ ] ID-61
Parameter [LibDiamond.addFunction(LibDiamond.DiamondStorage,bytes4,uint96,address)._selector](../../src/libraries/LibDiamond.sol#L196) is not in mixedCase

../../src/libraries/LibDiamond.sol#L196


 - [ ] ID-62
Parameter [DiamondUpgradeFacet.upgradeDiamond(IDiamondUpgradeFacet.FacetFunctions[],IDiamondUpgradeFacet.FacetFunctions[],bytes4[],address,bytes,bytes32,bytes)._removeFunctions](../../src/facets/DiamondUpgradeFacet.sol#L13) is not in mixedCase

../../src/facets/DiamondUpgradeFacet.sol#L13


 - [ ] ID-63
Parameter [LibDiamond.removeSelectors(bytes4[])._functionSelectors](../../src/libraries/LibDiamond.sol#L170) is not in mixedCase

../../src/libraries/LibDiamond.sol#L170


 - [ ] ID-64
Contract [MockEURS_2](../../src/mocks/MockEURS_2.sol#L7-L9) is not in CapWords

../../src/mocks/MockEURS_2.sol#L7-L9


## too-many-digits
Impact: Informational
Confidence: Medium
 - [ ] ID-65
[IdeationMarketFacet.purchaseListing(uint128,uint256,address,uint256,address,uint256,uint256,uint256,address)](../../src/facets/IdeationMarketFacet.sol#L346-L559) uses literals with too many digits:
	- [innovationFee = ((purchasePrice * listedItem.feeRate) / 100000)](../../src/facets/IdeationMarketFacet.sol#L439)

../../src/facets/IdeationMarketFacet.sol#L346-L559


