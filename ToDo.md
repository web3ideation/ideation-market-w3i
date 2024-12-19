how do i set a (hash) storage location in the diamond for the facets?
whats the LibDiamondCut.sol for?

read
https://eip2535diamonds.substack.com/p/introduction-to-the-diamond-standard ✅
https://eips.ethereum.org/EIPS/eip-2535 ✅
https://github.com/mudgen/diamond-3?tab=readme-ov-file ✅


https://github.com/mudgen/diamond ✅
https://github.com/alexbabits/diamond-3-foundry ✅
and what about appstorage - seems to be an alternative to diamond storage - but which one should i use? Understand AppStorage and check alexbabits impelementation since he seems to use both -> I rather use Diamon Storage since there are not clashes if importing external contracts that also use storage ✅
decide which implementation to base on (what about mudgens foundry implementation? on which 1 2 or 3 is it based on?) -> diamond 3 -> but which foundry implementation?? ✅
compare the .sol files of alexbabits to the ones from nick mudge which i already imported to my repo - use cGPT to compare the implementations -> 
continue reading the last cGPT message ✅
and then scroll back up to ctrl+F "Here’s a detailed comparison between the original and Foundry implementations of diamond.sol, highlighting all changes, deletions, and additions:" and continue with comparing the files:
import the dieamond-3-hardhat files since they are newer and recompare the files ✅
IdeationMarketDiamond.sol ✅
Migration.sol ✅
LibAppstorage.sol / Appstorage.sol ✅
LibDiamond.sol ✅
DiamondInit.sol ✅
DiamondCutFacet.sol ✅ 
DiamondLoupeFacet.sol ✅
ERC20Facet.sol ✅ (not necessary but take them as examples of how to change the storage to appstorage)
ERC1155Facet.sol ✅ (not necessary but take them as examples of how to change the storage to appstorage)
OwnershipFacet.sol ✅
IDiamondCutFacet.sol ✅
IDiamondLoupeFacet.sol ✅
IERC20Facet.sol (not necessary) ✅
IERC165.sol ✅
IERC173.sol ✅
IERC1155Facet.sol (not necessary) ✅
deployDiamond.s.sol <-> mudgen's diamond-3-hardhat/scripts/deploy.js --> check if there are documentations for how to deploy my diamond
differs in  the constructor of the diamond.sol and which facets are getting deployed from the getgo -> so adapt alexabits script to fit my setup of the different diamond and deploying ALL facets i want - then show cGPT my repo and check again if the depolymentscript is vollständig ✅

check the constructor arguments for the code that deploys the IdeationMarketDiamond.sol and why that diamond needs the facetcut infos tho alexabits didnt need those ✅

the IdeationMarketFacet had a constructor, which should somehow be implemented through the diamond now... ✅

check all the exclamationmarks ✅

ask cGPT with the context of the whole repo, if the diamond is correctly set up and the deploymentscript would be correct ✅

libDiamond.sol also implements (also storage) governance -> change for dao! ✅

whats the owner in ideationMarket.sol for? make sure it doesnt derivate from the owner of the diamond ✅

research again if that storage problem only happens when inheriting, not when just importing ✅
change the way IdeationMarketFacet uses openzeppelin - since i cant use that dependencies external storage as is.
I cannot just inherit from libraries (that use external storage / statevariables) because that would mess up my diamonds storage layout. Aavegotchi and similar projects handle this issue by manually implementing required functions from external libraries like ERC721 instead of directly inheriting them, and defining all state variables in a centralized AppStorage struct accessed at a fixed slot. This ensures facets don’t conflict over storage slots. They also use library functions to access AppStorage without inheriting external storage directly, preserving compatibility. ✅

what about using arrays in the appstorage struct, like i cant edit them once impelemnted since that would mess up the storage? -> no only use mappings ✅

what about having structs in my appstorage struct? can i add variables to those structs without messing up the whole storage layout? -> yes i can add variables in nested structs ✅

Have my dev wallet the deployer seperated from the multisigwallet the owner (governance) ✅

check if the deployer and the owner are definetly seperated in my diamond structure - so that as soon as deployed only the owner has the controll like upgrading over it ✅

stack to deep error bei s.listings[nftAddress][tokenId] = listedItem; ✅
nochmal selbst mit forge built checken ✅

appstorage slot zu keccak256 setzen statt 0 ✅ 

add a function to transfer ownership (?) already in ownershipfacet ✅

check if sourcecontroll is syncing all the changes ✅ 

ToDos for the IdeationMarketFacet: 
islisted als status enum - no, this is just expensive overhead in the smartcontract that can be handled by the graph or the frontend ✅
define listings by listingId, not nft ⬅️

all the !!!
google keep notes


do i have to adapt the graph?
add graph queries for listed, updated, canceled, bought, swapped - also fee updated and proceeds withdrawn

reducing gas costs for executing functions:
Facets can contain few external functions, reducing gas costs. Because it costs more gas to call a function in a contract with many functions than a contract with few functions.
The Solidity optimizer can be set to a high setting causing more bytecode to be generated but the facets will use less gas when executed

check for Function Selector Clash when deploying
verify contract at louper.dev instead of etherscan (if it is still not possible to verify diamond patterns there...)

do "Struct Packing" -> storage optimization for gas savings (in appstorage)

do I need getter functions for all the state variables or is it automatically possible to read the storage struct out in a whole?

activate optimizer in the foundry.toml optimizer = true, optimizer_runs = 5000 (10 for cheaper deployment, 5000 for cheaper executions)
