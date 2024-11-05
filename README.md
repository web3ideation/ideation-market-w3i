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
compare the .sol files of alexbabits to the ones from nick mudge which i already imported to my repo ⬅️

what are the DiamondLoupe functions actually used for? like ok for stuff like etherscan, but other than that?? I mean would they actually even be called onchain?? 

libDiamond.sol also implements (also storage) governance -> change for dao!


reducing gas costs for executing functions:
Facets can contain few external functions, reducing gas costs. Because it costs more gas to call a function in a contract with many functions than a contract with few functions.
The Solidity optimizer can be set to a high setting causing more bytecode to be generated but the facets will use less gas when executed

check for Function Selector Clash when deploying
verify contract at louper.dev instead of etherscan (if it is still not possible to verify diamond patterns there...)