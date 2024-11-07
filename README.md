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
IdeationMarketDiamond.sol ✅
Migration.sol ✅
LibAppstorage.sol / Appstorage.sol ⬅️ ➡️ ctrl+F "The Foundry implementation you referenced has a more complex approach to AppStorage for compatibility with various OpenZeppelin (OZ) "

read the documentation again for how to deploy my diamond

I cannot just inherit from libraries (that use external storage / statevariables) because that would mess up my diamonds storage layout. Aavegotchi and similar projects handle this issue by manually implementing required functions from external libraries like ERC721 instead of directly inheriting them, and defining all state variables in a centralized AppStorage struct accessed at a fixed slot. This ensures facets don’t conflict over storage slots. They also use library functions to access AppStorage without inheriting external storage directly, preserving compatibility.

do I need to get rid of the constructor? Since I have to store the variables in the Diamond instead of using the constructor of the IdeationMarketFacet I should create a DiamondInit / InitializationFacet with a function that would act as the constructor for the IdeationMarketFacet (and also governance inputs and other initialization stuff)

what are the DiamondLoupe functions actually used for? like ok for stuff like etherscan, but other than that?? I mean would they actually even be called onchain?? 

libDiamond.sol also implements (also storage) governance -> change for dao!

what about using arrays in the appstorage struct, like i cant edit them once impelemnted since that would mess up the storage?

what about using external contracts with storage? that would set my appstorage to something else than position 0?

what about having structs in my appstorage struct? can i add variables to those structs without messing up the whole storage layout? -> yes i can add variables in nested structs ✅

reducing gas costs for executing functions:
Facets can contain few external functions, reducing gas costs. Because it costs more gas to call a function in a contract with many functions than a contract with few functions.
The Solidity optimizer can be set to a high setting causing more bytecode to be generated but the facets will use less gas when executed

check for Function Selector Clash when deploying
verify contract at louper.dev instead of etherscan (if it is still not possible to verify diamond patterns there...)