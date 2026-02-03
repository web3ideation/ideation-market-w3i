# Report


## Gas Optimizations


| |Issue|Instances|
|-|:-|:-:|
| [GAS-1](#GAS-1) | `a = a + b` is more gas effective than `a += b` for state variables (excluding arrays and mappings) | 4 |
| [GAS-2](#GAS-2) | Using bools for storage incurs overhead | 6 |
| [GAS-3](#GAS-3) | Cache array length outside of loop | 8 |
| [GAS-4](#GAS-4) | For Operations that will not overflow, you could use unchecked | 188 |
| [GAS-5](#GAS-5) | Use Custom Errors instead of Revert Strings to save Gas | 14 |
| [GAS-6](#GAS-6) | Avoid contract existence checks by using low level calls | 8 |
| [GAS-7](#GAS-7) | Functions guaranteed to revert when called by normal users can be marked `payable` | 4 |
| [GAS-8](#GAS-8) | `++i` costs less gas compared to `i++` or `i += 1` (same for `--i` vs `i--` or `i -= 1`) | 28 |
| [GAS-9](#GAS-9) | Using `private` rather than `public` for constants, saves gas | 3 |
| [GAS-10](#GAS-10) | Superfluous event fields | 2 |
| [GAS-11](#GAS-11) | Increments/decrements can be unchecked in for-loops | 13 |
| [GAS-12](#GAS-12) | Use != 0 instead of > 0 for unsigned integer comparison | 31 |
### <a name="GAS-1"></a>[GAS-1] `a = a + b` is more gas effective than `a += b` for state variables (excluding arrays and mappings)
This saves **16 gas per instance.**

*Instances (4)*:
```solidity
File: src/facets/DiamondLoupeFacet.sol

76:             totalSelectors += ds.facetFunctionSelectors[ds.facetAddresses[i]].functionSelectors.length;

```

```solidity
File: src/mocks/MockUSDTLike_6.sol

24:         balanceOf[to] += amount;

25:         totalSupply += amount;

56:             balanceOf[to] += value;

```

### <a name="GAS-2"></a>[GAS-2] Using bools for storage incurs overhead
Use uint256(1) and uint256(2) for true/false to avoid a Gwarmaccess (100 gas), and to avoid Gsset (20000 gas) when changing from ‘false’ to ‘true’, after having been ‘true’ in the past. See [source](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/58f635312aa21f947cae5f8578638a85aa2519f5/contracts/security/ReentrancyGuard.sol#L23-L27).

*Instances (6)*:
```solidity
File: src/facets/BuyerWhitelistFacet.sol

36:         mapping(address buyer => bool isWhitelisted) storage listingWhitelist =

63:         mapping(address buyer => bool isWhitelisted) storage listingWhitelist =

```

```solidity
File: src/libraries/LibAppStorage.sol

60:     mapping(address currency => bool allowed) allowedCurrencies;

67:     mapping(address collection => bool isWhitelisted) whitelistedCollections;

73:     mapping(uint128 listingId => mapping(address buyer => bool isWhitelisted)) whitelistedBuyersByListingId;

```

```solidity
File: src/libraries/LibDiamond.sol

38:         mapping(bytes4 interfaceId => bool isSupported) supportedInterfaces;

```

### <a name="GAS-3"></a>[GAS-3] Cache array length outside of loop
If not cached, the solidity compiler will always read the length of the array during each iteration. That is, if it is a storage array, this is an extra sload operation (100 additional extra gas for each iteration except for the first) and if it is a memory array, this is an extra mload operation (3 additional gas for each iteration except for the first).

*Instances (8)*:
```solidity
File: src/facets/DiamondUpgradeFacet.sol

24:         for (uint256 i = 0; i < _addFunctions.length; i++) {

31:             for (uint256 j = 0; j < selectors.length; j++) {

43:         for (uint256 i = 0; i < _replaceFunctions.length; i++) {

50:             for (uint256 j = 0; j < selectors.length; j++) {

64:             for (uint256 i = 0; i < _removeFunctions.length; i++) {

112:         for (uint256 i = 0; i < arr.length; i++) {

```

```solidity
File: src/upgradeInitializers/DiamondInit.sol

149:         for (uint256 i = 0; i < currencies.length; i++) {

```

```solidity
File: src/upgradeInitializers/DummyUpgradeInit.sol

56:         for (uint256 i = 0; i < facetAddresses.length; i++) {

```

### <a name="GAS-4"></a>[GAS-4] For Operations that will not overflow, you could use unchecked

*Instances (188)*:
```solidity
File: src/IdeationMarketDiamond.sol

5: import {LibDiamond} from "./libraries/LibDiamond.sol";

6: import {IDiamondUpgradeFacet} from "./interfaces/IDiamondUpgradeFacet.sol";

37:         assembly ("memory-safe") {

44:         assembly ("memory-safe") {

```

```solidity
File: src/facets/BuyerWhitelistFacet.sol

4: import "../libraries/LibAppStorage.sol";

5: import "../interfaces/IERC721.sol";

6: import "../interfaces/IERC1155.sol";

7: import "../interfaces/IBuyerWhitelistFacet.sol";

48:                 i++;

75:                 i++;

```

```solidity
File: src/facets/CollectionWhitelistFacet.sol

4: import "../libraries/LibAppStorage.sol";

5: import "../libraries/LibDiamond.sol";

53:         uint256 lastIndex = s.whitelistedCollectionsArray.length - 1;

92:                 i++;

113:                 uint256 lastIndex = arr.length - 1;

131:                 i++;

```

```solidity
File: src/facets/CurrencyWhitelistFacet.sol

4: import "../libraries/LibAppStorage.sol";

5: import "../libraries/LibDiamond.sol";

59:         uint256 lastIndex = s.allowedCurrenciesArray.length - 1;

```

```solidity
File: src/facets/DiamondLoupeFacet.sol

6: import {LibDiamond} from "../libraries/LibDiamond.sol";

7: import {IDiamondLoupeFacet} from "../interfaces/IDiamondLoupeFacet.sol";

8: import {IDiamondInspectFacet} from "../interfaces/IDiamondInspectFacet.sol";

9: import {IERC165} from "../interfaces/IERC165.sol";

27:                 i++;

76:             totalSelectors += ds.facetFunctionSelectors[ds.facetAddresses[i]].functionSelectors.length;

78:                 i++;

91:                     k++;

92:                     j++;

96:                 i++;

```

```solidity
File: src/facets/DiamondUpgradeFacet.sol

4: import {LibDiamond} from "../libraries/LibDiamond.sol";

5: import {IDiamondUpgradeFacet} from "../interfaces/IDiamondUpgradeFacet.sol";

24:         for (uint256 i = 0; i < _addFunctions.length; i++) {

31:             for (uint256 j = 0; j < selectors.length; j++) {

43:         for (uint256 i = 0; i < _replaceFunctions.length; i++) {

50:             for (uint256 j = 0; j < selectors.length; j++) {

64:             for (uint256 i = 0; i < _removeFunctions.length; i++) {

98:         assembly ("memory-safe") {

105:         assembly ("memory-safe") {

112:         for (uint256 i = 0; i < arr.length; i++) {

```

```solidity
File: src/facets/DummyUpgradeFacet.sol

4: import {LibDiamond} from "../libraries/LibDiamond.sol";

5: import {LibAppStorage, AppStorage} from "../libraries/LibAppStorage.sol";

```

```solidity
File: src/facets/GetterFacet.sol

4: import "../libraries/LibAppStorage.sol";

5: import "../libraries/LibDiamond.sol";

49:         return s.listingIdCounter + 1;

```

```solidity
File: src/facets/IdeationMarketFacet.sol

4: import "../libraries/LibAppStorage.sol";

5: import "../libraries/LibDiamond.sol";

6: import "../interfaces/IERC721.sol";

7: import "../interfaces/IERC165.sol";

8: import "../interfaces/IERC2981.sol";

9: import "../interfaces/IERC1155.sol";

10: import "../interfaces/IBuyerWhitelistFacet.sol";

205:         uint256 desiredErc1155Quantity, // >0 for swap ERC1155, 0 for only swap ERC721 or non swap

206:         uint256 erc1155Quantity, // >0 for ERC1155, 0 for only ERC721

209:         address[] calldata allowedBuyers // whitelisted Buyers

284:         s.listingIdCounter++;

397:             uint256 unitPrice = listedItem.price / listedItem.erc1155Quantity;

398:             purchasePrice = unitPrice * erc1155PurchaseQuantity;

439:         uint256 innovationFee = ((purchasePrice * listedItem.feeRate) / 100000);

440:         uint256 remainingProceeds = purchasePrice - innovationFee;

452:                 remainingProceeds -= royaltyAmount;

517:             s.listings[listingId].erc1155Quantity -= erc1155PurchaseQuantity;

518:             s.listings[listingId].price -= purchasePrice;

594:                 } catch { /* ignore */ }

603:                 } catch { /* ignore */ }

616:                 } catch { /* ignore */ }

```

```solidity
File: src/facets/OwnershipFacet.sol

4: import {LibDiamond} from "../libraries/LibDiamond.sol";

5: import {IERC173} from "../interfaces/IERC173.sol";

```

```solidity
File: src/facets/PauseFacet.sol

4: import {LibDiamond} from "../libraries/LibDiamond.sol";

```

```solidity
File: src/facets/VersionFacet.sol

4: import {LibDiamond} from "../libraries/LibDiamond.sol";

```

```solidity
File: src/interfaces/IERC1155.sol

6: import {IERC165} from "./IERC165.sol";

```

```solidity
File: src/interfaces/IERC2981.sol

6: import {IERC165} from "./IERC165.sol";

```

```solidity
File: src/interfaces/IERC4907.sol

5: import {IERC721} from "./IERC721.sol";

```

```solidity
File: src/interfaces/IERC721.sol

6: import {IERC165} from "./IERC165.sol";

```

```solidity
File: src/libraries/LibAppStorage.sol

95:         assembly ("memory-safe") {

```

```solidity
File: src/libraries/LibDiamond.sol

63:         assembly ("memory-safe") {

132:             selectorPosition++;

134:                 selectorIndex++;

160:             selectorPosition++;

162:                 selectorIndex++;

181:                 selectorIndex++;

212:         uint256 lastSelectorPosition = ds.facetFunctionSelectors[_facetAddress].functionSelectors.length - 1;

226:             uint256 lastFacetAddressPosition = ds.facetAddresses.length - 1;

248:                 assembly ("memory-safe") {

262:         assembly ("memory-safe") {

```

```solidity
File: src/mocks/MockERC20_18.sol

4: import {MockMintableERC20} from "./MockMintableERC20.sol";

```

```solidity
File: src/mocks/MockEURS_2.sol

4: import {MockMintableERC20} from "./MockMintableERC20.sol";

```

```solidity
File: src/mocks/MockMintableERC20.sol

4: import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

```

```solidity
File: src/mocks/MockUSDC_6.sol

4: import {MockMintableERC20} from "./MockMintableERC20.sol";

```

```solidity
File: src/mocks/MockUSDTLike_6.sol

24:         balanceOf[to] += amount;

25:         totalSupply += amount;

44:             allowance[from][msg.sender] = allowed - value;

55:             balanceOf[from] = bal - value;

56:             balanceOf[to] += value;

```

```solidity
File: src/mocks/MockWBTC_8.sol

4: import {MockMintableERC20} from "./MockMintableERC20.sol";

```

```solidity
File: src/upgradeInitializers/DiamondInit.sol

5: import {LibDiamond} from "../libraries/LibDiamond.sol";

6: import {IDiamondLoupeFacet} from "../interfaces/IDiamondLoupeFacet.sol";

7: import {IDiamondInspectFacet} from "../interfaces/IDiamondInspectFacet.sol";

8: import {IDiamondUpgradeFacet} from "../interfaces/IDiamondUpgradeFacet.sol";

9: import {IERC173} from "../interfaces/IERC173.sol";

10: import {IERC165} from "../interfaces/IERC165.sol";

11: import {LibAppStorage, AppStorage} from "../libraries/LibAppStorage.sol";

41:         s.innovationFee = innovationFee; // Denominator is 100_000 (e.g., 1_000 = 1%). innovation/Marketplace fee (excluding gascosts) for each sale

48:         address[] memory currencies = new address[](76); // 1 ETH + 75 ERC-20 = 76 total

54:         currencies[1] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH

55:         currencies[2] = 0xae78736Cd615f374D3085123A210448E74Fc6393; // rETH (Rocket Pool)

56:         currencies[3] = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; // wstETH (Lido)

59:         currencies[4] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC

60:         currencies[5] = 0x18084fbA666a33d37592fA2633fD49a74DD93a88; // tBTC

63:         currencies[6] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC

64:         currencies[7] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT

65:         currencies[8] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI

66:         currencies[9] = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0; // LUSD

67:         currencies[10] = 0x853d955aCEf822Db058eb8505911ED77F175b99e; // FRAX

68:         currencies[11] = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f; // GHO

69:         currencies[12] = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E; // crvUSD

72:         currencies[13] = 0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c; // EURC

73:         currencies[14] = 0xdB25f211AB05b1c97D595516F45794528a807ad8; // EURS

74:         currencies[15] = 0xC581b735A1688071A1746c968e0798D642EDE491; // EURT

77:         currencies[16] = 0x70e8dE73cE538DA2bEEd35d14187F6959a8ecA96; // XSGD

78:         currencies[17] = 0x2C537E5624e4af88A7ae4060C022609376C8D0EB; // TRYB (BiLira)

81:         currencies[18] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // UNI

82:         currencies[19] = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9; // AAVE

83:         currencies[20] = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2; // MKR

84:         currencies[21] = 0xc00e94Cb662C3520282E6f5717214004A7f26888; // COMP

85:         currencies[22] = 0xD533a949740bb3306d119CC777fa900bA034cd52; // CRV

86:         currencies[23] = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B; // CVX

87:         currencies[24] = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F; // SNX

88:         currencies[25] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e; // YFI

89:         currencies[26] = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32; // LDO

90:         currencies[27] = 0x111111111117dC0aa78b770fA6A738034120C302; // 1INCH

91:         currencies[28] = 0xba100000625a3754423978a60c9317c58a424e3D; // BAL

92:         currencies[29] = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2; // SUSHI

93:         currencies[30] = 0xdeFA4e8a7bcBA345F687a2f1456F5Edd9CE97202; // KNC

94:         currencies[31] = 0xE41d2489571d322189246DaFA5ebDe1F4699F498; // ZRX

95:         currencies[32] = 0x6810e776880C02933D47DB1b9fc05908e5386b96; // GNO

96:         currencies[33] = 0x1a7e4e63778B4f12a199C062f3eFdD288afCBce8; // EURA (was FXS)

99:         currencies[34] = 0x514910771AF9Ca656af840dff83E8264EcF986CA; // LINK

100:         currencies[35] = 0xc944E90C64B2c07662A292be6244BDf05Cda44a7; // GRT

101:         currencies[36] = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF; // BAT

102:         currencies[37] = 0x967da4048cD07aB37855c090aAF366e4ce1b9F48; // OCEAN

103:         currencies[38] = 0x6De037ef9aD2725EB40118Bb1702EBb27e4Aeb24; // RENDER

104:         currencies[39] = 0x58b6A8A3302369DAEc383334672404Ee733aB239; // LPT

105:         currencies[40] = 0x7DD9c5Cba05E151C895FDe1CF355C9A1D5DA6429; // GLM

106:         currencies[41] = 0x4a220E6096B25EADb88358cb44068A3248254675; // QNT

107:         currencies[42] = 0x8290333ceF9e6D528dD5618Fb97a76f268f3EDD4; // ANKR

108:         currencies[43] = 0xaea46A60368A7bD060eec7DF8CBa43b7EF41Ad85; // FET

109:         currencies[44] = 0x0b38210ea11411557c13457D4dA7dC6ea731B88a; // API3

110:         currencies[45] = 0x1776e1F26f98b1A5dF9cD347953a26dd3Cb46671; // NMR

111:         currencies[46] = 0x163f8C2467924be0ae7B5347228CABF260318753; // WLD (Worldcoin - AI/Identity)

114:         currencies[47] = 0x4d224452801ACEd8B2F0aebE155379bb5D594381; // APE

115:         currencies[48] = 0x3845badAde8e6dFF049820680d1F14bD3903a5d0; // SAND

116:         currencies[49] = 0x0F5D2fB29fb7d3CFeE444a200298f468908cC942; // MANA

117:         currencies[50] = 0xBB0E17EF65F82Ab018d8EDd776e8DD940327B28b; // AXS

118:         currencies[51] = 0xF629cBd94d3791C9250152BD8dfBDF380E2a3B9c; // ENJ

119:         currencies[52] = 0xF57e7e7C23978C3cAEC3C3548E3D615c346e79fF; // IMX

120:         currencies[53] = 0x3506424F91fD33084466F402d5D97f05F8e3b4AF; // CHZ

121:         currencies[54] = 0x5283D291DBCF85356A21bA090E6db59121208b44; // BLUR

122:         currencies[55] = 0xf4d2888d29D722226FafA5d9B24F9164c092421E; // LOOKS

123:         currencies[56] = 0xba5BDe662c17e2aDFF1075610382B9B691296350; // RARE

124:         currencies[57] = 0xFca59Cd816aB1eaD66534D82bc21E7515cE441CF; // RARI

125:         currencies[58] = 0x767FE9EDC9E0dF98E07454847909b5E959D7ca0E; // ILV

128:         currencies[59] = 0x455e53CBB86018Ac2B8092FdCd39d8444aFFC3F6; // POL

129:         currencies[60] = 0xB50721BCf8d664c30412Cfbc6cf7a15145234ad1; // ARB

130:         currencies[61] = 0x3c3a81e81dc49A522A592e7622A7E711c06bf354; // MNT

131:         currencies[62] = 0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766; // STRK

132:         currencies[63] = 0x9E32b13ce7f2E80A01932B42553652E053D6ed8e; // Metis

133:         currencies[64] = 0xBBbbCA6A901c926F240b89EacB641d8Aec7AEafD; // LRC

134:         currencies[65] = 0x6985884C4392D348587B19cb9eAAf157F13271cd; // ZRO

135:         currencies[66] = 0x467719aD09025FcC6cF6F8311755809d45a5E5f3; // AXL

136:         currencies[67] = 0x66A5cFB2e9c529f14FE6364Ad1075dF3a649C0A5; // ZK

137:         currencies[68] = 0x4F9254C83EB525f9FCf346490bbb3ed28a81C667; // CELR

140:         currencies[69] = 0xa2E3356610840701BDf5611a53974510Ae27E2e1; // WBETH

141:         currencies[70] = 0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549; // LsETH

142:         currencies[71] = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38; // osETH

143:         currencies[72] = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497; // SUSDe

144:         currencies[73] = 0x68749665FF8D2d112Fa859AA293F07A622782F38; // XAUt (Tether Gold)

145:         currencies[74] = 0xfAbA6f8e4a5E8Ab82F62fe7C39859FA577269BE3; // ONDO

146:         currencies[75] = 0x57e114B691Db790C35207b2e685D4A43181e6061; // ENA

149:         for (uint256 i = 0; i < currencies.length; i++) {

152:             s.allowedCurrenciesIndex[currency] = i; // Store actual index (same pattern as whitelistedCollectionsIndex)

```

```solidity
File: src/upgradeInitializers/DummyUpgradeInit.sol

4: import {LibAppStorage, AppStorage} from "../libraries/LibAppStorage.sol";

5: import {LibDiamond} from "../libraries/LibDiamond.sol";

56:         for (uint256 i = 0; i < facetAddresses.length; i++) {

67:         for (uint256 i = 0; i < length; i++) {

68:             for (uint256 j = i + 1; j < length; j++) {

79:         for (uint256 i = 0; i < length; i++) {

83:         for (uint256 i = 0; i < length; i++) {

84:             for (uint256 j = i + 1; j < length; j++) {

```

### <a name="GAS-5"></a>[GAS-5] Use Custom Errors instead of Revert Strings to save Gas
Custom errors are available from solidity version 0.8.4. Custom errors save [**~50 gas**](https://gist.github.com/IllIllI000/ad1bd0d29a0101b25e57c293b4b0c746) each time they're hit by [avoiding having to allocate and store the revert string](https://blog.soliditylang.org/2021/04/21/custom-errors/#errors-in-depth). Not defining the strings also save deployment gas

Additionally, custom errors can be used inside and outside of contracts (including interfaces and libraries).

Source: <https://blog.soliditylang.org/2021/04/21/custom-errors/>:

> Starting from [Solidity v0.8.4](https://github.com/ethereum/solidity/releases/tag/v0.8.4), there is a convenient and gas-efficient way to explain to users why an operation failed through the use of custom errors. Until now, you could already use strings to give more information about failures (e.g., `revert("Insufficient funds.");`), but they are rather expensive, especially when it comes to deploy cost, and it is difficult to use dynamic information in them.

Consider replacing **all revert strings** with custom errors in the solution, and particularly those that have multiple occurrences:

*Instances (14)*:
```solidity
File: src/libraries/LibDiamond.sol

109:         require(msg.sender == diamondStorage().contractOwner, "LibDiamond: Must be contract owner");

115:         require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");

117:         require(_facetAddress != address(0), "LibDiamondCut: Add facet can't be address(0)");

129:             require(oldFacetAddress == address(0), "LibDiamondCut: Can't add function that already exists");

142:         require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");

144:         require(_facetAddress != address(0), "LibDiamondCut: Replace facet can't be address(0)");

156:             require(oldFacetAddress != _facetAddress, "LibDiamondCut: Can't replace function with same function");

171:         require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");

207:         require(_facetAddress != address(0), "LibDiamondCut: Can't remove function that doesn't exist");

209:         require(_facetAddress != address(this), "LibDiamondCut: Can't remove immutable function");

```

```solidity
File: src/mocks/MockUSDTLike_6.sol

31:         if (value != 0 && current != 0) revert("USDTLike: must reset allowance to 0");

43:             if (allowed < value) revert("USDTLike: insufficient allowance");

51:         if (to == address(0)) revert("USDTLike: transfer to zero");

53:         if (bal < value) revert("USDTLike: insufficient balance");

```

### <a name="GAS-6"></a>[GAS-6] Avoid contract existence checks by using low level calls
Prior to 0.8.10 the compiler inserted extra code, including `EXTCODESIZE` (**100 gas**), to check for contract existence for external function calls. In more recent solidity versions, the compiler will not insert these checks if the external call has a return value. Similar behavior can be achieved in earlier versions by using low-level calls, since low level calls never check for contract existence

*Instances (8)*:
```solidity
File: src/facets/BuyerWhitelistFacet.sol

98:             if (token.balanceOf(seller, tokenId) < erc1155Quantity) {

```

```solidity
File: src/facets/DiamondUpgradeFacet.sol

79:             (bool success, bytes memory returndata) = _delegate.delegatecall(_functionCall);

```

```solidity
File: src/facets/IdeationMarketFacet.sol

237:             uint256 balance = token.balanceOf(erc1155Holder, tokenId);

425:             uint256 balance = IERC1155(listedItem.tokenAddress).balanceOf(listedItem.seller, listedItem.tokenId);

466:                 uint256 swapBalance = desiredToken.balanceOf(desiredErc1155Holder, listedItem.desiredTokenId);

680:             uint256 balance = token.balanceOf(listedItem.seller, listedItem.tokenId);

782:                     try token.balanceOf(listedItem.seller, listedItem.tokenId) returns (uint256 balance) {

```

```solidity
File: src/libraries/LibDiamond.sol

245:         (bool success, bytes memory error) = _init.delegatecall(_calldata);

```

### <a name="GAS-7"></a>[GAS-7] Functions guaranteed to revert when called by normal users can be marked `payable`
If a function modifier such as `onlyOwner` is used, the function will revert if a normal user tries to pay the function. Marking the function as `payable` will lower the gas cost for legitimate callers because the compiler will not include checks for whether a payment was provided.

*Instances (4)*:
```solidity
File: src/facets/CollectionWhitelistFacet.sol

31:     function addWhitelistedCollection(address tokenAddress) external onlyOwner {

47:     function removeWhitelistedCollection(address tokenAddress) external onlyOwner {

73:     function batchAddWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {

101:     function batchRemoveWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {

```

### <a name="GAS-8"></a>[GAS-8] `++i` costs less gas compared to `i++` or `i += 1` (same for `--i` vs `i--` or `i -= 1`)
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

*Instances (28)*:
```solidity
File: src/facets/BuyerWhitelistFacet.sol

48:                 i++;

75:                 i++;

```

```solidity
File: src/facets/CollectionWhitelistFacet.sol

92:                 i++;

131:                 i++;

```

```solidity
File: src/facets/DiamondLoupeFacet.sol

27:                 i++;

78:                 i++;

91:                     k++;

92:                     j++;

96:                 i++;

```

```solidity
File: src/facets/DiamondUpgradeFacet.sol

24:         for (uint256 i = 0; i < _addFunctions.length; i++) {

31:             for (uint256 j = 0; j < selectors.length; j++) {

43:         for (uint256 i = 0; i < _replaceFunctions.length; i++) {

50:             for (uint256 j = 0; j < selectors.length; j++) {

64:             for (uint256 i = 0; i < _removeFunctions.length; i++) {

112:         for (uint256 i = 0; i < arr.length; i++) {

```

```solidity
File: src/facets/IdeationMarketFacet.sol

284:         s.listingIdCounter++;

```

```solidity
File: src/libraries/LibDiamond.sol

132:             selectorPosition++;

134:                 selectorIndex++;

160:             selectorPosition++;

162:                 selectorIndex++;

181:                 selectorIndex++;

```

```solidity
File: src/upgradeInitializers/DiamondInit.sol

149:         for (uint256 i = 0; i < currencies.length; i++) {

```

```solidity
File: src/upgradeInitializers/DummyUpgradeInit.sol

56:         for (uint256 i = 0; i < facetAddresses.length; i++) {

67:         for (uint256 i = 0; i < length; i++) {

68:             for (uint256 j = i + 1; j < length; j++) {

79:         for (uint256 i = 0; i < length; i++) {

83:         for (uint256 i = 0; i < length; i++) {

84:             for (uint256 j = i + 1; j < length; j++) {

```

### <a name="GAS-9"></a>[GAS-9] Using `private` rather than `public` for constants, saves gas
If needed, the values can be read from the verified contract source code, or if there are multiple values there can be a single getter function that [returns a tuple](https://github.com/code-423n4/2022-08-frax/blob/90f55a9ce4e25bceed3a74290b854341d8de6afa/src/contracts/FraxlendPair.sol#L156-L178) of the values of all currently-public constants. Saves **3406-3606 gas** in deployment gas due to the compiler not having to create non-payable getter functions for deployment calldata, not having to store the bytes of the value outside of where it's used, and not adding another entry to the method ID table

*Instances (3)*:
```solidity
File: src/mocks/MockUSDTLike_6.sol

11:     string public constant name = "Mock USDT";

12:     string public constant symbol = "mUSDT";

13:     uint8 public constant decimals = 6;

```

### <a name="GAS-10"></a>[GAS-10] Superfluous event fields
`block.timestamp` and `block.number` are added to event information by default so adding them manually wastes gas

*Instances (2)*:
```solidity
File: src/facets/VersionFacet.sol

13:     event VersionUpdated(string version, bytes32 indexed implementationId, uint256 timestamp);

```

```solidity
File: src/upgradeInitializers/DummyUpgradeInit.sol

12:     event DummyUpgradeVersionInitialized(string version, bytes32 implementationId, uint256 timestamp);

```

### <a name="GAS-11"></a>[GAS-11] Increments/decrements can be unchecked in for-loops
In Solidity 0.8+, there's a default overflow check on unsigned integers. It's possible to uncheck this in for-loops and save some gas at each iteration, but at the cost of some code readability, as this uncheck cannot be made inline.

[ethereum/solidity#10695](https://github.com/ethereum/solidity/issues/10695)

The change would be:

```diff
- for (uint256 i; i < numIterations; i++) {
+ for (uint256 i; i < numIterations;) {
 // ...  
+   unchecked { ++i; }
}  
```

These save around **25 gas saved** per instance.

The same can be applied with decrements (which should use `break` when `i == 0`).

The risk of overflow is non-existent for `uint256`.

*Instances (13)*:
```solidity
File: src/facets/DiamondUpgradeFacet.sol

24:         for (uint256 i = 0; i < _addFunctions.length; i++) {

31:             for (uint256 j = 0; j < selectors.length; j++) {

43:         for (uint256 i = 0; i < _replaceFunctions.length; i++) {

50:             for (uint256 j = 0; j < selectors.length; j++) {

64:             for (uint256 i = 0; i < _removeFunctions.length; i++) {

112:         for (uint256 i = 0; i < arr.length; i++) {

```

```solidity
File: src/upgradeInitializers/DiamondInit.sol

149:         for (uint256 i = 0; i < currencies.length; i++) {

```

```solidity
File: src/upgradeInitializers/DummyUpgradeInit.sol

56:         for (uint256 i = 0; i < facetAddresses.length; i++) {

67:         for (uint256 i = 0; i < length; i++) {

68:             for (uint256 j = i + 1; j < length; j++) {

79:         for (uint256 i = 0; i < length; i++) {

83:         for (uint256 i = 0; i < length; i++) {

84:             for (uint256 j = i + 1; j < length; j++) {

```

### <a name="GAS-12"></a>[GAS-12] Use != 0 instead of > 0 for unsigned integer comparison

*Instances (31)*:
```solidity
File: src/facets/BuyerWhitelistFacet.sol

95:         if (erc1155Quantity > 0) {

```

```solidity
File: src/facets/DiamondUpgradeFacet.sol

63:         if (_removeFunctions.length > 0) {

81:                 if (returndata.length > 0) {

91:         if (_tag != bytes32(0) || _metadata.length > 0) {

101:         return size > 0;

```

```solidity
File: src/facets/IdeationMarketFacet.sol

205:         uint256 desiredErc1155Quantity, // >0 for swap ERC1155, 0 for only swap ERC721 or non swap

206:         uint256 erc1155Quantity, // >0 for ERC1155, 0 for only ERC721

222:         if (erc1155Quantity > 0) {

278:         if (erc1155Quantity > 0) {

396:         if (erc1155PurchaseQuantity > 0 && erc1155PurchaseQuantity != listedItem.erc1155Quantity) {

410:             if (msg.value > 0) {

415:         if (listedItem.desiredErc1155Quantity > 0 && desiredErc1155Holder == address(0)) {

424:         if (listedItem.erc1155Quantity > 0) {

450:             if (royaltyReceiver != address(0) && royaltyAmount > 0) {

463:             if (listedItem.desiredErc1155Quantity > 0) {

523:         if (erc1155PurchaseQuantity > 0) {

663:         if (newErc1155Quantity > 0) {

668:             if (listedItem.erc1155Quantity > 0) {

674:         if (newErc1155Quantity > 0) {

778:                 if (listedItem.erc1155Quantity > 0) {

903:             if (allowedBuyers.length > 0) {

907:             if (allowedBuyers.length > 0) revert IdeationMarket__WhitelistDisabled();

953:             if (desiredErc1155Quantity > 0) {

1019:             if (royaltyAmount > 0 && royaltyReceiver != address(0)) {

1039:             if (royaltyAmount > 0 && royaltyReceiver != address(0)) {

1071:         if (!success || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {

```

```solidity
File: src/libraries/LibDiamond.sol

115:         require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");

142:         require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");

171:         require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");

247:             if (error.length > 0) {

265:         require(contractSize > 0, _errorMessage);

```


## Non Critical Issues


| |Issue|Instances|
|-|:-|:-:|
| [NC-1](#NC-1) | Replace `abi.encodeWithSignature` and `abi.encodeWithSelector` with `abi.encodeCall` which keeps the code typo/type safe | 1 |
| [NC-2](#NC-2) | Constants should be in CONSTANT_CASE | 3 |
| [NC-3](#NC-3) | `constant`s should be defined rather than using magic numbers | 6 |
| [NC-4](#NC-4) | Control structures do not follow the Solidity Style Guide | 50 |
| [NC-5](#NC-5) | Critical Changes Should Use Two-step Procedure | 1 |
| [NC-6](#NC-6) | Default Visibility for constants | 2 |
| [NC-7](#NC-7) | Functions should not be longer than 50 lines | 132 |
| [NC-8](#NC-8) | Use a `modifier` instead of a `require/if` statement for a special `msg.sender` actor | 9 |
| [NC-9](#NC-9) | Consider using named mappings | 2 |
| [NC-10](#NC-10) | `address`s shouldn't be hard-coded | 75 |
| [NC-11](#NC-11) | Take advantage of Custom Error's return value property | 57 |
| [NC-12](#NC-12) | Use scientific notation for readability reasons for large multiples of ten | 1 |
| [NC-13](#NC-13) | Avoid the use of sensitive terms | 131 |
| [NC-14](#NC-14) | Strings should use double quotes rather than single quotes | 1 |
| [NC-15](#NC-15) | Use Underscores for Number Literals (add an underscore every 3 digits) | 1 |
| [NC-16](#NC-16) | Constants should be defined rather than using magic numbers | 1 |
| [NC-17](#NC-17) | Variables need not be initialized to zero | 23 |
### <a name="NC-1"></a>[NC-1] Replace `abi.encodeWithSignature` and `abi.encodeWithSelector` with `abi.encodeCall` which keeps the code typo/type safe
When using `abi.encodeWithSignature`, it is possible to include a typo for the correct function signature.
When using `abi.encodeWithSignature` or `abi.encodeWithSelector`, it is also possible to provide parameters that are not of the correct type for the function.

To avoid these pitfalls, it would be best to use [`abi.encodeCall`](https://solidity-by-example.org/abi-encode/) instead.

*Instances (1)*:
```solidity
File: src/facets/IdeationMarketFacet.sol

1062:         bytes memory data = abi.encodeWithSelector(0x23b872dd, from, to, amount);

```

### <a name="NC-2"></a>[NC-2] Constants should be in CONSTANT_CASE
For `constant` variable names, each word should use all capital letters, with underscores separating each word (CONSTANT_CASE)

*Instances (3)*:
```solidity
File: src/mocks/MockUSDTLike_6.sol

11:     string public constant name = "Mock USDT";

12:     string public constant symbol = "mUSDT";

13:     uint8 public constant decimals = 6;

```

### <a name="NC-3"></a>[NC-3] `constant`s should be defined rather than using magic numbers
Even [assembly](https://github.com/code-423n4/2022-05-opensea-seaport/blob/9d7ce4d08bf3c3010304a0476a785c70c0e90ae7/contracts/lib/TokenTransferrer.sol#L35-L39) can benefit from using readable constants instead of hex/numeric literals

*Instances (6)*:
```solidity
File: src/facets/DiamondUpgradeFacet.sol

106:             revert(add(revertData, 32), mload(revertData))

```

```solidity
File: src/facets/IdeationMarketFacet.sol

439:         uint256 innovationFee = ((purchasePrice * listedItem.feeRate) / 100000);

```

```solidity
File: src/mocks/MockERC20_18.sol

8:     constructor() MockMintableERC20("Mock ERC20 18", "mERC20", 18) {}

```

```solidity
File: src/mocks/MockEURS_2.sol

8:     constructor() MockMintableERC20("Mock EURS", "mEURS", 2) {}

```

```solidity
File: src/mocks/MockUSDC_6.sol

8:     constructor() MockMintableERC20("Mock USDC", "mUSDC", 6) {}

```

```solidity
File: src/mocks/MockWBTC_8.sol

8:     constructor() MockMintableERC20("Mock WBTC", "mWBTC", 8) {}

```

### <a name="NC-4"></a>[NC-4] Control structures do not follow the Solidity Style Guide
See the [control structures](https://docs.soliditylang.org/en/latest/style-guide.html#control-structures) section of the Solidity Style Guide

*Instances (50)*:
```solidity
File: src/IdeationMarketDiamond.sol

42:         if (facet == address(0)) revert Diamond__FunctionDoesNotExist();

```

```solidity
File: src/facets/BuyerWhitelistFacet.sol

41:             if (allowedBuyer == address(0)) revert BuyerWhitelist__ZeroAddress();

68:             if (disallowedBuyer == address(0)) revert BuyerWhitelist__ZeroAddress();

84:         if (batchSize == 0) revert BuyerWhitelist__EmptyCalldata();

90:         if (seller == address(0)) revert BuyerWhitelist__ListingDoesNotExist();

109:             if (tokenHolder != seller) revert BuyerWhitelist__SellerIsNotERC721Owner(seller, tokenHolder);

111:             if (

```

```solidity
File: src/facets/CollectionWhitelistFacet.sol

33:         if (s.whitelistedCollections[tokenAddress]) revert CollectionWhitelist__AlreadyWhitelisted();

34:         if (tokenAddress == address(0)) revert CollectionWhitelist__ZeroAddress();

49:         if (!s.whitelistedCollections[tokenAddress]) revert CollectionWhitelist__NotWhitelisted();

81:             if (addr == address(0)) revert CollectionWhitelist__ZeroAddress();

```

```solidity
File: src/facets/CurrencyWhitelistFacet.sol

36:         if (s.allowedCurrencies[currency]) revert CurrencyWhitelist__AlreadyAllowed();

53:         if (!s.allowedCurrencies[currency]) revert CurrencyWhitelist__NotAllowed();

```

```solidity
File: src/facets/DiamondUpgradeFacet.sol

28:             if (selectors.length == 0) revert NoSelectorsProvidedForFacet(facet);

29:             if (!_hasCode(facet)) revert NoBytecodeAtAddress(facet);

47:             if (selectors.length == 0) revert NoSelectorsProvidedForFacet(facet);

48:             if (!_hasCode(facet)) revert NoBytecodeAtAddress(facet);

53:                 if (oldFacet == address(0)) revert CannotReplaceFunctionThatDoesNotExist(selector);

54:                 if (oldFacet == address(this)) revert CannotReplaceImmutableFunction(selector);

55:                 if (oldFacet == facet) revert CannotReplaceFunctionWithTheSameFacet(selector);

67:                 if (oldFacet == address(0)) revert CannotRemoveFunctionThatDoesNotExist(selector);

68:                 if (oldFacet == address(this)) revert CannotRemoveImmutableFunction(selector);

77:             if (!_hasCode(_delegate)) revert NoBytecodeAtAddress(_delegate);

```

```solidity
File: src/facets/IdeationMarketFacet.sol

158:         if (LibDiamond.diamondStorage().paused) revert IdeationMarket__ContractPaused();

165:         if (LibAppStorage.appStorage().listings[listingId].seller == address(0)) revert IdeationMarket__NotListed();

173:         if (s.reentrancyLock) revert IdeationMarket__Reentrant();

256:             if (

371:         if (

382:         if (

451:                 if (remainingProceeds < royaltyAmount) revert IdeationMarket__RoyaltyFeeExceedsProceeds();

467:                 if (swapBalance == 0) revert IdeationMarket__WrongErc1155HolderParameter();

468:                 if (

493:                 if (

688:             if (

882:         if (!partialBuyEnabled) return;

907:             if (allowedBuyers.length > 0) revert IdeationMarket__WhitelistDisabled();

916:         if (

949:             if (desiredTokenId != 0) revert IdeationMarket__InvalidNoSwapParameters();

950:             if (desiredErc1155Quantity != 0) revert IdeationMarket__InvalidNoSwapParameters();

951:             if (price == 0) revert IdeationMarket__FreeListingsNotSupported();

1015:             if (!successFee) revert IdeationMarket__EthTransferFailed(marketplaceOwner);

1021:                 if (!successRoyalty) revert IdeationMarket__EthTransferFailed(royaltyReceiver);

1027:             if (!successSeller) revert IdeationMarket__EthTransferFailed(seller);

1058:         if (token.code.length == 0) revert IdeationMarket__ERC20TokenAddressIsNotAContract(token);

```

```solidity
File: src/facets/PauseFacet.sol

32:         if (ds.paused) revert Pause__AlreadyPaused();

42:         if (!ds.paused) revert Pause__NotPaused();

```

```solidity
File: src/mocks/MockUSDTLike_6.sol

31:         if (value != 0 && current != 0) revert("USDTLike: must reset allowance to 0");

43:             if (allowed < value) revert("USDTLike: insufficient allowance");

51:         if (to == address(0)) revert("USDTLike: transfer to zero");

53:         if (bal < value) revert("USDTLike: insufficient balance");

```

### <a name="NC-5"></a>[NC-5] Critical Changes Should Use Two-step Procedure
The critical procedures should be two step process.

See similar findings in previous Code4rena contests for reference: <https://code4rena.com/reports/2022-06-illuminate/#2-critical-changes-should-use-two-step-procedure>

**Recommended Mitigation Steps**

Lack of two-step procedure for critical operations leaves them error-prone. Consider adding two step procedure on the critical functions.

*Instances (1)*:
```solidity
File: src/libraries/LibDiamond.sol

95:     function setContractOwner(address _newOwner) internal {

```

### <a name="NC-6"></a>[NC-6] Default Visibility for constants
Some constants are using the default visibility. For readability, consider explicitly declaring them as `internal`.

*Instances (2)*:
```solidity
File: src/libraries/LibAppStorage.sol

89:     bytes32 constant APP_STORAGE_POSITION = keccak256("diamond.standard.app.storage");

```

```solidity
File: src/libraries/LibDiamond.sol

13:     bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

```

### <a name="NC-7"></a>[NC-7] Functions should not be longer than 50 lines
Overly complex code can make understanding functionality more difficult, try to further modularize your code to ensure readability 

*Instances (132)*:
```solidity
File: src/IdeationMarketDiamond.sol

24:         functionSelectors[0] = IDiamondUpgradeFacet.upgradeDiamond.selector;

26:         LibDiamond.addFunctions(_diamondUpgradeFacet, functionSelectors);

```

```solidity
File: src/facets/BuyerWhitelistFacet.sol

30:     function addBuyerWhitelistAddresses(uint128 listingId, address[] calldata allowedBuyers) external override {

57:     function removeBuyerWhitelistAddresses(uint128 listingId, address[] calldata disallowedBuyers) external override {

83:     function validateWhitelistBatch(AppStorage storage s, uint128 listingId, uint256 batchSize) internal view {

```

```solidity
File: src/facets/CollectionWhitelistFacet.sol

31:     function addWhitelistedCollection(address tokenAddress) external onlyOwner {

47:     function removeWhitelistedCollection(address tokenAddress) external onlyOwner {

73:     function batchAddWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {

101:     function batchRemoveWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {

```

```solidity
File: src/facets/CurrencyWhitelistFacet.sol

32:     function addAllowedCurrency(address currency) external {

49:     function removeAllowedCurrency(address currency) external {

```

```solidity
File: src/facets/DiamondLoupeFacet.sol

18:     function facets() external view override returns (Facet[] memory facets_) {

25:             facets_[i].functionSelectors = ds.facetFunctionSelectors[facetAddress_].functionSelectors;

43:         facetFunctionSelectors_ = ds.facetFunctionSelectors[_facet].functionSelectors;

49:     function facetAddresses() external view override returns (address[] memory facetAddresses_) {

70:     function functionFacetPairs() external view override returns (FunctionFacetPair[] memory pairs) {

76:             totalSelectors += ds.facetFunctionSelectors[ds.facetAddresses[i]].functionSelectors.length;

89:                 pairs[k] = FunctionFacetPair({selector: selectors[j], facet: facet});

104:     function supportsInterface(bytes4 _interfaceId) external view override returns (bool) {

```

```solidity
File: src/facets/DiamondUpgradeFacet.sol

96:     function _hasCode(address _addr) internal view returns (bool) {

104:     function _revertWith(bytes memory revertData) internal pure {

110:     function _toMemory(bytes4[] calldata arr) internal pure returns (bytes4[] memory out) {

```

```solidity
File: src/facets/DummyUpgradeFacet.sol

13:     function getDummyUpgradeValue() external view returns (uint256) {

20:     function setDummyUpgradeValue(uint256 value) external {

```

```solidity
File: src/facets/GetterFacet.sol

15:     function getActiveListingIdByERC721(address tokenAddress, uint256 tokenId) external view returns (uint128) {

23:     function getListingByListingId(uint128 listingId) external view returns (Listing memory listing) {

34:     function getBalance() external view returns (uint256) {

40:     function getInnovationFee() external view returns (uint32 innovationFee) {

47:     function getNextListingId() external view returns (uint128) {

55:     function isCollectionWhitelisted(address collection) external view returns (bool) {

63:     function getWhitelistedCollections() external view returns (address[] memory) {

70:     function getContractOwner() external view returns (address) {

79:     function isBuyerWhitelisted(uint128 listingId, address buyer) external view returns (bool) {

89:     function getBuyerWhitelistMaxBatchSize() external view returns (uint16 maxBatchSize) {

95:     function getPendingOwner() external view returns (address) {

104:     function isCurrencyAllowed(address currency) external view returns (bool) {

111:     function getAllowedCurrencies() external view returns (address[] memory currencies) {

122:     function getVersion() external view returns (string memory version, bytes32 implementationId, uint256 timestamp) {

142:     function getVersionString() external view returns (string memory) {

148:     function getImplementationId() external view returns (bytes32) {

154:     function isPaused() external view returns (bool) {

```

```solidity
File: src/facets/IdeationMarketFacet.sol

565:     function cancelListing(uint128 listingId) public listingExists(listingId) {

752:     function setInnovationFee(uint32 newFee) external {

766:     function cleanListing(uint128 listingId) external listingExists(listingId) {

860:     function _enforceCurrencyAllowed(AppStorage storage s, address currency) private view {

868:     function _enforceCollectionWhitelisted(AppStorage storage s, address tokenAddress) private view {

899:     function _applyBuyerWhitelist(uint128 listingId, bool buyerWhitelistEnabled, address[] calldata allowedBuyers)

914:     function _requireERC721Approval(address tokenAddress, uint256 tokenId) internal view {

929:     function _requireERC1155Approval(address tokenAddress, address tokenOwner) internal view {

1057:     function _safeTransferFrom(address token, address from, address to, uint256 amount) private {

```

```solidity
File: src/facets/OwnershipFacet.sol

21:     function transferOwnership(address newOwner) external override {

40:     function owner() external view override returns (address) {

```

```solidity
File: src/facets/VersionFacet.sol

21:     function setVersion(string calldata newVersion, bytes32 newImplementationId) external {

```

```solidity
File: src/interfaces/IBuyerWhitelistFacet.sol

10:     function addBuyerWhitelistAddresses(uint128 listingId, address[] calldata allowedBuyers) external;

15:     function removeBuyerWhitelistAddresses(uint128 listingId, address[] calldata disallowedBuyers) external;

```

```solidity
File: src/interfaces/IDiamondInspectFacet.sol

13:     function facetAddress(bytes4 _functionSelector) external view returns (address);

24:     function functionFacetPairs() external view returns (FunctionFacetPair[] memory pairs);

```

```solidity
File: src/interfaces/IDiamondLoupeFacet.sol

13:     function facets() external view returns (Facet[] memory facets_);

18:     function facetFunctionSelectors(address _facet) external view returns (bytes4[] memory facetFunctionSelectors_);

22:     function facetAddresses() external view returns (address[] memory facetAddresses_);

28:     function facetAddress(bytes4 _functionSelector) external view returns (address facetAddress_);

```

```solidity
File: src/interfaces/IDiamondUpgradeFacet.sol

12:     error CannotAddFunctionToDiamondThatAlreadyExists(bytes4 _selector);

```

```solidity
File: src/interfaces/IERC1155.sol

44:     function balanceOf(address account, uint256 id) external view returns (uint256);

53:     function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)

67:     function setApprovalForAll(address operator, bool approved) external;

74:     function isApprovedForAll(address account, address operator) external view returns (bool);

94:     function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes calldata data) external;

```

```solidity
File: src/interfaces/IERC165.sol

11:     function supportsInterface(bytes4 interfaceId) external view returns (bool);

```

```solidity
File: src/interfaces/IERC173.sol

13:     function owner() external view returns (address owner_);

19:     function transferOwnership(address _newOwner) external;

```

```solidity
File: src/interfaces/IERC2981.sol

22:     function royaltyInfo(uint256 tokenId, uint256 salePrice)

```

```solidity
File: src/interfaces/IERC4907.sol

22:     function setUser(uint256 tokenId, address user, uint64 expires) external;

28:     function userOf(uint256 tokenId) external view returns (address);

34:     function userExpires(uint256 tokenId) external view returns (uint256);

```

```solidity
File: src/interfaces/IERC721.sol

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

```solidity
File: src/libraries/LibAppStorage.sol

93:     function appStorage() internal pure returns (AppStorage storage s) {

```

```solidity
File: src/libraries/LibDiamond.sol

6: error InitializationFunctionReverted(address _initializationContractAddress, bytes _calldata);

34:         mapping(address facetAddress => FacetFunctionSelectors selectors) facetFunctionSelectors;

61:     function diamondStorage() internal pure returns (DiamondStorage storage ds) {

76:     event DiamondFunctionAdded(bytes4 indexed _selector, address indexed _facet);

84:     event DiamondFunctionReplaced(bytes4 indexed _selector, address indexed _oldFacet, address indexed _newFacet);

91:     event DiamondFunctionRemoved(bytes4 indexed _selector, address indexed _oldFacet);

95:     function setContractOwner(address _newOwner) internal {

103:     function contractOwner() internal view returns (address contractOwner_) {

114:     function addFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {

115:         require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");

118:         uint96 selectorPosition = uint96(ds.facetFunctionSelectors[_facetAddress].functionSelectors.length);

130:             addFunction(ds, selector, selectorPosition, _facetAddress);

141:     function replaceFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {

142:         require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");

145:         uint96 selectorPosition = uint96(ds.facetFunctionSelectors[_facetAddress].functionSelectors.length);

158:             addFunction(ds, selector, selectorPosition, _facetAddress);

159:             emit DiamondFunctionReplaced(selector, oldFacetAddress, _facetAddress);

170:     function removeSelectors(bytes4[] memory _functionSelectors) internal {

171:         require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");

188:     function addFacet(DiamondStorage storage ds, address _facetAddress) internal {

190:         ds.facetFunctionSelectors[_facetAddress].facetAddressPosition = ds.facetAddresses.length;

196:     function addFunction(DiamondStorage storage ds, bytes4 _selector, uint96 _selectorPosition, address _facetAddress)

200:         ds.facetFunctionSelectors[_facetAddress].functionSelectors.push(_selector);

206:     function removeFunction(DiamondStorage storage ds, address _facetAddress, bytes4 _selector) internal {

212:         uint256 lastSelectorPosition = ds.facetFunctionSelectors[_facetAddress].functionSelectors.length - 1;

215:             bytes4 lastSelector = ds.facetFunctionSelectors[_facetAddress].functionSelectors[lastSelectorPosition];

216:             ds.facetFunctionSelectors[_facetAddress].functionSelectors[selectorPosition] = lastSelector;

217:             ds.selectorToFacetAndPosition[lastSelector].functionSelectorPosition = uint96(selectorPosition);

220:         ds.facetFunctionSelectors[_facetAddress].functionSelectors.pop();

227:             uint256 facetAddressPosition = ds.facetFunctionSelectors[_facetAddress].facetAddressPosition;

231:                 ds.facetFunctionSelectors[lastFacetAddress].facetAddressPosition = facetAddressPosition;

234:             delete ds.facetFunctionSelectors[_facetAddress].facetAddressPosition;

240:     function initializeDiamondCut(address _init, bytes memory _calldata) internal {

260:     function enforceHasContractCode(address _contract, string memory _errorMessage) internal view {

```

```solidity
File: src/mocks/MockMintableERC20.sol

16:     function decimals() public view override returns (uint8) {

21:     function mint(address to, uint256 amount) external {

```

```solidity
File: src/mocks/MockUSDTLike_6.sol

23:     function mint(address to, uint256 amount) external {

29:     function approve(address spender, uint256 value) external {

36:     function transfer(address to, uint256 value) external {

40:     function transferFrom(address from, address to, uint256 value) external {

50:     function _transfer(address from, address to, uint256 value) internal {

```

```solidity
File: src/upgradeInitializers/DiamondInit.sol

26:     function init(uint32 innovationFee, uint16 buyerWhitelistMaxBatchSize) external {

```

```solidity
File: src/upgradeInitializers/DummyUpgradeInit.sol

14:     function initDummyUpgrade(uint256 value) external {

23:     function initDummyUpgradeAndVersion(uint256 value, string calldata newVersion) external {

47:     function _computeImplementationIdFromDiamondStorage(LibDiamond.DiamondStorage storage ds)

57:             bytes4[] memory selectors = ds.facetFunctionSelectors[facetAddresses[i]].functionSelectors;

65:     function _sortAddresses(address[] memory arr) internal pure {

76:     function _sortSelectors(bytes4[] memory selectors) internal pure returns (bytes4[] memory) {

```

### <a name="NC-8"></a>[NC-8] Use a `modifier` instead of a `require/if` statement for a special `msg.sender` actor
If a function is supposed to be access-controlled, a `modifier` should be used instead of a `require/if` statement for more readability.

*Instances (9)*:
```solidity
File: src/facets/BuyerWhitelistFacet.sol

102:             if (msg.sender != seller && !token.isApprovedForAll(seller, msg.sender)) {

```

```solidity
File: src/facets/IdeationMarketFacet.sol

233:             if (msg.sender != erc1155Holder && !token.isApprovedForAll(erc1155Holder, msg.sender)) {

365:             if (!s.whitelistedBuyersByListingId[listingId][msg.sender]) {

419:         if (msg.sender == listedItem.seller) {

571:         if (msg.sender == diamondOwner) {

591:                     if (approvedAddress == msg.sender) {

677:             if (msg.sender != listedItem.seller && !token.isApprovedForAll(listedItem.seller, msg.sender)) {

```

```solidity
File: src/facets/OwnershipFacet.sol

32:         if (msg.sender != ds.pendingContractOwner) {

```

```solidity
File: src/libraries/LibDiamond.sol

109:         require(msg.sender == diamondStorage().contractOwner, "LibDiamond: Must be contract owner");

```

### <a name="NC-9"></a>[NC-9] Consider using named mappings
Consider moving to solidity version 0.8.18 or later, and using [named mappings](https://ethereum.stackexchange.com/questions/51629/how-to-name-the-arguments-in-mapping/145555#145555) to make it easier to understand the purpose of each mapping

*Instances (2)*:
```solidity
File: src/mocks/MockUSDTLike_6.sol

17:     mapping(address => uint256) public balanceOf;

18:     mapping(address => mapping(address => uint256)) public allowance;

```

### <a name="NC-10"></a>[NC-10] `address`s shouldn't be hard-coded
It is often better to declare `address`es as `immutable`, and assign them via constructor arguments. This allows the code to remain the same across deployments on different networks, and avoids recompilation when addresses need to change.

*Instances (75)*:
```solidity
File: src/upgradeInitializers/DiamondInit.sol

54:         currencies[1] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH

55:         currencies[2] = 0xae78736Cd615f374D3085123A210448E74Fc6393; // rETH (Rocket Pool)

56:         currencies[3] = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; // wstETH (Lido)

59:         currencies[4] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC

60:         currencies[5] = 0x18084fbA666a33d37592fA2633fD49a74DD93a88; // tBTC

63:         currencies[6] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC

64:         currencies[7] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT

65:         currencies[8] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI

66:         currencies[9] = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0; // LUSD

67:         currencies[10] = 0x853d955aCEf822Db058eb8505911ED77F175b99e; // FRAX

68:         currencies[11] = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f; // GHO

69:         currencies[12] = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E; // crvUSD

72:         currencies[13] = 0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c; // EURC

73:         currencies[14] = 0xdB25f211AB05b1c97D595516F45794528a807ad8; // EURS

74:         currencies[15] = 0xC581b735A1688071A1746c968e0798D642EDE491; // EURT

77:         currencies[16] = 0x70e8dE73cE538DA2bEEd35d14187F6959a8ecA96; // XSGD

78:         currencies[17] = 0x2C537E5624e4af88A7ae4060C022609376C8D0EB; // TRYB (BiLira)

81:         currencies[18] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // UNI

82:         currencies[19] = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9; // AAVE

83:         currencies[20] = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2; // MKR

84:         currencies[21] = 0xc00e94Cb662C3520282E6f5717214004A7f26888; // COMP

85:         currencies[22] = 0xD533a949740bb3306d119CC777fa900bA034cd52; // CRV

86:         currencies[23] = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B; // CVX

87:         currencies[24] = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F; // SNX

88:         currencies[25] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e; // YFI

89:         currencies[26] = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32; // LDO

90:         currencies[27] = 0x111111111117dC0aa78b770fA6A738034120C302; // 1INCH

91:         currencies[28] = 0xba100000625a3754423978a60c9317c58a424e3D; // BAL

92:         currencies[29] = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2; // SUSHI

93:         currencies[30] = 0xdeFA4e8a7bcBA345F687a2f1456F5Edd9CE97202; // KNC

94:         currencies[31] = 0xE41d2489571d322189246DaFA5ebDe1F4699F498; // ZRX

95:         currencies[32] = 0x6810e776880C02933D47DB1b9fc05908e5386b96; // GNO

96:         currencies[33] = 0x1a7e4e63778B4f12a199C062f3eFdD288afCBce8; // EURA (was FXS)

99:         currencies[34] = 0x514910771AF9Ca656af840dff83E8264EcF986CA; // LINK

100:         currencies[35] = 0xc944E90C64B2c07662A292be6244BDf05Cda44a7; // GRT

101:         currencies[36] = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF; // BAT

102:         currencies[37] = 0x967da4048cD07aB37855c090aAF366e4ce1b9F48; // OCEAN

103:         currencies[38] = 0x6De037ef9aD2725EB40118Bb1702EBb27e4Aeb24; // RENDER

104:         currencies[39] = 0x58b6A8A3302369DAEc383334672404Ee733aB239; // LPT

105:         currencies[40] = 0x7DD9c5Cba05E151C895FDe1CF355C9A1D5DA6429; // GLM

106:         currencies[41] = 0x4a220E6096B25EADb88358cb44068A3248254675; // QNT

107:         currencies[42] = 0x8290333ceF9e6D528dD5618Fb97a76f268f3EDD4; // ANKR

108:         currencies[43] = 0xaea46A60368A7bD060eec7DF8CBa43b7EF41Ad85; // FET

109:         currencies[44] = 0x0b38210ea11411557c13457D4dA7dC6ea731B88a; // API3

110:         currencies[45] = 0x1776e1F26f98b1A5dF9cD347953a26dd3Cb46671; // NMR

111:         currencies[46] = 0x163f8C2467924be0ae7B5347228CABF260318753; // WLD (Worldcoin - AI/Identity)

114:         currencies[47] = 0x4d224452801ACEd8B2F0aebE155379bb5D594381; // APE

115:         currencies[48] = 0x3845badAde8e6dFF049820680d1F14bD3903a5d0; // SAND

116:         currencies[49] = 0x0F5D2fB29fb7d3CFeE444a200298f468908cC942; // MANA

117:         currencies[50] = 0xBB0E17EF65F82Ab018d8EDd776e8DD940327B28b; // AXS

118:         currencies[51] = 0xF629cBd94d3791C9250152BD8dfBDF380E2a3B9c; // ENJ

119:         currencies[52] = 0xF57e7e7C23978C3cAEC3C3548E3D615c346e79fF; // IMX

120:         currencies[53] = 0x3506424F91fD33084466F402d5D97f05F8e3b4AF; // CHZ

121:         currencies[54] = 0x5283D291DBCF85356A21bA090E6db59121208b44; // BLUR

122:         currencies[55] = 0xf4d2888d29D722226FafA5d9B24F9164c092421E; // LOOKS

123:         currencies[56] = 0xba5BDe662c17e2aDFF1075610382B9B691296350; // RARE

124:         currencies[57] = 0xFca59Cd816aB1eaD66534D82bc21E7515cE441CF; // RARI

125:         currencies[58] = 0x767FE9EDC9E0dF98E07454847909b5E959D7ca0E; // ILV

128:         currencies[59] = 0x455e53CBB86018Ac2B8092FdCd39d8444aFFC3F6; // POL

129:         currencies[60] = 0xB50721BCf8d664c30412Cfbc6cf7a15145234ad1; // ARB

130:         currencies[61] = 0x3c3a81e81dc49A522A592e7622A7E711c06bf354; // MNT

131:         currencies[62] = 0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766; // STRK

132:         currencies[63] = 0x9E32b13ce7f2E80A01932B42553652E053D6ed8e; // Metis

133:         currencies[64] = 0xBBbbCA6A901c926F240b89EacB641d8Aec7AEafD; // LRC

134:         currencies[65] = 0x6985884C4392D348587B19cb9eAAf157F13271cd; // ZRO

135:         currencies[66] = 0x467719aD09025FcC6cF6F8311755809d45a5E5f3; // AXL

136:         currencies[67] = 0x66A5cFB2e9c529f14FE6364Ad1075dF3a649C0A5; // ZK

137:         currencies[68] = 0x4F9254C83EB525f9FCf346490bbb3ed28a81C667; // CELR

140:         currencies[69] = 0xa2E3356610840701BDf5611a53974510Ae27E2e1; // WBETH

141:         currencies[70] = 0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549; // LsETH

142:         currencies[71] = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38; // osETH

143:         currencies[72] = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497; // SUSDe

144:         currencies[73] = 0x68749665FF8D2d112Fa859AA293F07A622782F38; // XAUt (Tether Gold)

145:         currencies[74] = 0xfAbA6f8e4a5E8Ab82F62fe7C39859FA577269BE3; // ONDO

146:         currencies[75] = 0x57e114B691Db790C35207b2e685D4A43181e6061; // ENA

```

### <a name="NC-11"></a>[NC-11] Take advantage of Custom Error's return value property
An important feature of Custom Error is that values such as address, tokenID, msg.value can be written inside the () sign, this kind of approach provides a serious advantage in debugging and examining the revert details of dapps such as tenderly.

*Instances (57)*:
```solidity
File: src/IdeationMarketDiamond.sol

42:         if (facet == address(0)) revert Diamond__FunctionDoesNotExist();

53:             case 0 { revert(0, returndatasize()) }

```

```solidity
File: src/facets/BuyerWhitelistFacet.sol

41:             if (allowedBuyer == address(0)) revert BuyerWhitelist__ZeroAddress();

68:             if (disallowedBuyer == address(0)) revert BuyerWhitelist__ZeroAddress();

84:         if (batchSize == 0) revert BuyerWhitelist__EmptyCalldata();

90:         if (seller == address(0)) revert BuyerWhitelist__ListingDoesNotExist();

103:                 revert BuyerWhitelist__NotAuthorizedOperator();

114:             ) revert BuyerWhitelist__NotAuthorizedOperator();

```

```solidity
File: src/facets/CollectionWhitelistFacet.sol

33:         if (s.whitelistedCollections[tokenAddress]) revert CollectionWhitelist__AlreadyWhitelisted();

34:         if (tokenAddress == address(0)) revert CollectionWhitelist__ZeroAddress();

49:         if (!s.whitelistedCollections[tokenAddress]) revert CollectionWhitelist__NotWhitelisted();

81:             if (addr == address(0)) revert CollectionWhitelist__ZeroAddress();

```

```solidity
File: src/facets/CurrencyWhitelistFacet.sol

36:         if (s.allowedCurrencies[currency]) revert CurrencyWhitelist__AlreadyAllowed();

53:         if (!s.allowedCurrencies[currency]) revert CurrencyWhitelist__NotAllowed();

```

```solidity
File: src/facets/IdeationMarketFacet.sol

158:         if (LibDiamond.diamondStorage().paused) revert IdeationMarket__ContractPaused();

165:         if (LibAppStorage.appStorage().listings[listingId].seller == address(0)) revert IdeationMarket__NotListed();

173:         if (s.reentrancyLock) revert IdeationMarket__Reentrant();

226:                     revert IdeationMarket__NotSupportedTokenStandard();

228:                     revert IdeationMarket__WrongQuantityParameter();

234:                 revert IdeationMarket__NotAuthorizedOperator();

239:                 revert IdeationMarket__WrongErc1155HolderParameter();

249:                     revert IdeationMarket__NotSupportedTokenStandard();

251:                     revert IdeationMarket__WrongQuantityParameter();

260:                 revert IdeationMarket__NotAuthorizedOperator();

269:             revert IdeationMarket__AlreadyListed();

378:             revert IdeationMarket__ListingTermsChanged();

387:             revert IdeationMarket__InvalidPurchaseQuantity();

390:             revert IdeationMarket__PartialBuyNotPossible();

411:                 revert IdeationMarket__WrongPaymentCurrency();

416:             revert IdeationMarket__WrongErc1155HolderParameter();

420:             revert IdeationMarket__SameBuyerAsSeller();

451:                 if (remainingProceeds < royaltyAmount) revert IdeationMarket__RoyaltyFeeExceedsProceeds();

467:                 if (swapBalance == 0) revert IdeationMarket__WrongErc1155HolderParameter();

472:                     revert IdeationMarket__NotAuthorizedOperator();

497:                     revert IdeationMarket__NotAuthorizedOperator();

628:         revert IdeationMarket__NotAuthorizedToCancel();

665:                 revert IdeationMarket__WrongQuantityParameter();

669:                 revert IdeationMarket__WrongQuantityParameter();

678:                 revert IdeationMarket__NotAuthorizedOperator();

692:                 revert IdeationMarket__NotAuthorizedOperator();

851:         revert IdeationMarket__StillApproved();

862:             revert IdeationMarket__CurrencyNotAllowed();

885:             revert IdeationMarket__PartialBuyNotPossible();

889:             revert IdeationMarket__InvalidUnitPrice();

893:             revert IdeationMarket__PartialBuyNotPossible();

907:             if (allowedBuyers.length > 0) revert IdeationMarket__WhitelistDisabled();

922:             revert IdeationMarket__NotApprovedForMarketplace();

931:             revert IdeationMarket__NotApprovedForMarketplace();

949:             if (desiredTokenId != 0) revert IdeationMarket__InvalidNoSwapParameters();

950:             if (desiredErc1155Quantity != 0) revert IdeationMarket__InvalidNoSwapParameters();

951:             if (price == 0) revert IdeationMarket__FreeListingsNotSupported();

955:                     revert IdeationMarket__NotSupportedTokenStandard();

960:                     revert IdeationMarket__NotSupportedTokenStandard();

964:                 revert IdeationMarket__NoSwapForSameToken();

```

```solidity
File: src/facets/OwnershipFacet.sol

33:             revert Ownership__CallerIsNotThePendingOwner();

```

```solidity
File: src/facets/PauseFacet.sol

32:         if (ds.paused) revert Pause__AlreadyPaused();

42:         if (!ds.paused) revert Pause__NotPaused();

```

### <a name="NC-12"></a>[NC-12] Use scientific notation for readability reasons for large multiples of ten
The more a number has zeros, the harder it becomes to see with the eyes if it's the intended value. To ease auditing and bug bounty hunting, consider using the scientific notation

*Instances (1)*:
```solidity
File: src/facets/IdeationMarketFacet.sol

439:         uint256 innovationFee = ((purchasePrice * listedItem.feeRate) / 100000);

```

### <a name="NC-13"></a>[NC-13] Avoid the use of sensitive terms
Use [alternative variants](https://www.zdnet.com/article/mysql-drops-master-slave-and-blacklist-whitelist-terminology/), e.g. allowlist/denylist instead of whitelist/blacklist

*Instances (131)*:
```solidity
File: src/facets/BuyerWhitelistFacet.sol

7: import "../interfaces/IBuyerWhitelistFacet.sol";

9: error BuyerWhitelist__ListingDoesNotExist();

10: error BuyerWhitelist__NotAuthorizedOperator();

11: error BuyerWhitelist__ExceedsMaxBatchSize(uint256 batchSize);

12: error BuyerWhitelist__ZeroAddress();

13: error BuyerWhitelist__EmptyCalldata();

14: error BuyerWhitelist__SellerIsNotERC1155Owner(address seller);

15: error BuyerWhitelist__SellerIsNotERC721Owner(address seller, address owner);

21: contract BuyerWhitelistFacet is IBuyerWhitelistFacet {

22:     event BuyerWhitelisted(uint128 indexed listingId, address indexed buyer);

23:     event BuyerRemovedFromWhitelist(uint128 indexed listingId, address indexed buyer);

30:     function addBuyerWhitelistAddresses(uint128 listingId, address[] calldata allowedBuyers) external override {

34:         validateWhitelistBatch(s, listingId, len);

36:         mapping(address buyer => bool isWhitelisted) storage listingWhitelist =

37:             s.whitelistedBuyersByListingId[listingId];

41:             if (allowedBuyer == address(0)) revert BuyerWhitelist__ZeroAddress();

43:             if (!listingWhitelist[allowedBuyer]) {

44:                 listingWhitelist[allowedBuyer] = true;

45:                 emit BuyerWhitelisted(listingId, allowedBuyer);

57:     function removeBuyerWhitelistAddresses(uint128 listingId, address[] calldata disallowedBuyers) external override {

61:         validateWhitelistBatch(s, listingId, len);

63:         mapping(address buyer => bool isWhitelisted) storage listingWhitelist =

64:             s.whitelistedBuyersByListingId[listingId];

68:             if (disallowedBuyer == address(0)) revert BuyerWhitelist__ZeroAddress();

70:             if (listingWhitelist[disallowedBuyer]) {

71:                 listingWhitelist[disallowedBuyer] = false;

72:                 emit BuyerRemovedFromWhitelist(listingId, disallowedBuyer);

83:     function validateWhitelistBatch(AppStorage storage s, uint128 listingId, uint256 batchSize) internal view {

84:         if (batchSize == 0) revert BuyerWhitelist__EmptyCalldata();

85:         if (batchSize > s.buyerWhitelistMaxBatchSize) {

86:             revert BuyerWhitelist__ExceedsMaxBatchSize(batchSize);

90:         if (seller == address(0)) revert BuyerWhitelist__ListingDoesNotExist();

99:                 revert BuyerWhitelist__SellerIsNotERC1155Owner(seller);

103:                 revert BuyerWhitelist__NotAuthorizedOperator();

109:             if (tokenHolder != seller) revert BuyerWhitelist__SellerIsNotERC721Owner(seller, tokenHolder);

114:             ) revert BuyerWhitelist__NotAuthorizedOperator();

```

```solidity
File: src/facets/CollectionWhitelistFacet.sol

7: error CollectionWhitelist__AlreadyWhitelisted();

8: error CollectionWhitelist__NotWhitelisted();

9: error CollectionWhitelist__ZeroAddress();

15: contract CollectionWhitelistFacet {

17:     event CollectionAddedToWhitelist(address indexed tokenAddress);

20:     event CollectionRemovedFromWhitelist(address indexed tokenAddress);

31:     function addWhitelistedCollection(address tokenAddress) external onlyOwner {

33:         if (s.whitelistedCollections[tokenAddress]) revert CollectionWhitelist__AlreadyWhitelisted();

34:         if (tokenAddress == address(0)) revert CollectionWhitelist__ZeroAddress();

36:         s.whitelistedCollections[tokenAddress] = true;

37:         s.whitelistedCollectionsIndex[tokenAddress] = s.whitelistedCollectionsArray.length;

38:         s.whitelistedCollectionsArray.push(tokenAddress);

40:         emit CollectionAddedToWhitelist(tokenAddress);

47:     function removeWhitelistedCollection(address tokenAddress) external onlyOwner {

49:         if (!s.whitelistedCollections[tokenAddress]) revert CollectionWhitelist__NotWhitelisted();

52:         uint256 index = s.whitelistedCollectionsIndex[tokenAddress];

53:         uint256 lastIndex = s.whitelistedCollectionsArray.length - 1;

54:         address lastAddress = s.whitelistedCollectionsArray[lastIndex];

58:             s.whitelistedCollectionsArray[index] = lastAddress;

59:             s.whitelistedCollectionsIndex[lastAddress] = index;

63:         s.whitelistedCollectionsArray.pop();

64:         delete s.whitelistedCollectionsIndex[tokenAddress];

65:         s.whitelistedCollections[tokenAddress] = false;

67:         emit CollectionRemovedFromWhitelist(tokenAddress);

73:     function batchAddWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {

75:         address[] storage arr = s.whitelistedCollectionsArray;

81:             if (addr == address(0)) revert CollectionWhitelist__ZeroAddress();

83:             if (!s.whitelistedCollections[addr]) {

84:                 s.whitelistedCollections[addr] = true;

85:                 s.whitelistedCollectionsIndex[addr] = arr.length;

88:                 emit CollectionAddedToWhitelist(addr);

101:     function batchRemoveWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {

103:         address[] storage arr = s.whitelistedCollectionsArray;

110:             if (s.whitelistedCollections[addr]) {

112:                 uint256 index = s.whitelistedCollectionsIndex[addr];

119:                     s.whitelistedCollectionsIndex[lastAddress] = index;

124:                 delete s.whitelistedCollectionsIndex[addr];

125:                 s.whitelistedCollections[addr] = false;

127:                 emit CollectionRemovedFromWhitelist(addr);

```

```solidity
File: src/facets/CurrencyWhitelistFacet.sol

7: error CurrencyWhitelist__AlreadyAllowed();

8: error CurrencyWhitelist__NotAllowed();

15: contract CurrencyWhitelistFacet {

36:         if (s.allowedCurrencies[currency]) revert CurrencyWhitelist__AlreadyAllowed();

53:         if (!s.allowedCurrencies[currency]) revert CurrencyWhitelist__NotAllowed();

```

```solidity
File: src/facets/GetterFacet.sol

55:     function isCollectionWhitelisted(address collection) external view returns (bool) {

57:         return s.whitelistedCollections[collection];

63:     function getWhitelistedCollections() external view returns (address[] memory) {

65:         return s.whitelistedCollectionsArray;

79:     function isBuyerWhitelisted(uint128 listingId, address buyer) external view returns (bool) {

84:         return s.whitelistedBuyersByListingId[listingId][buyer];

89:     function getBuyerWhitelistMaxBatchSize() external view returns (uint16 maxBatchSize) {

90:         return LibAppStorage.appStorage().buyerWhitelistMaxBatchSize;

```

```solidity
File: src/facets/IdeationMarketFacet.sol

10: import "../interfaces/IBuyerWhitelistFacet.sol";

24: error IdeationMarket__CollectionNotWhitelisted(address tokenAddress);

25: error IdeationMarket__BuyerNotWhitelisted(uint128 listingId, address buyer);

31: error IdeationMarket__WhitelistDisabled();

80:         bool buyerWhitelistEnabled,

120:         bool buyerWhitelistEnabled,

149:     event CollectionWhitelistRevokedCancelTriggered(uint128 indexed listingId, address indexed tokenAddress);

207:         bool buyerWhitelistEnabled,

209:         address[] calldata allowedBuyers // whitelisted Buyers

218:         _enforceCollectionWhitelisted(s, tokenAddress);

297:             buyerWhitelistEnabled: buyerWhitelistEnabled,

308:         _applyBuyerWhitelist(newListingId, buyerWhitelistEnabled, allowedBuyers);

319:             buyerWhitelistEnabled,

361:         _enforceCollectionWhitelisted(s, listedItem.tokenAddress);

364:         if (listedItem.buyerWhitelistEnabled) {

365:             if (!s.whitelistedBuyersByListingId[listingId][msg.sender]) {

366:                 revert IdeationMarket__BuyerNotWhitelisted(listingId, msg.sender);

655:         bool newBuyerWhitelistEnabled,

699:         if (!s.whitelistedCollections[listedItem.tokenAddress]) {

701:             emit CollectionWhitelistRevokedCancelTriggered(listingId, listedItem.tokenAddress);

727:         listedItem.buyerWhitelistEnabled = newBuyerWhitelistEnabled;

730:         _applyBuyerWhitelist(listingId, newBuyerWhitelistEnabled, newAllowedBuyers);

741:             newBuyerWhitelistEnabled,

776:             if (s.whitelistedCollections[listedItem.tokenAddress]) {

868:     function _enforceCollectionWhitelisted(AppStorage storage s, address tokenAddress) private view {

869:         if (!s.whitelistedCollections[tokenAddress]) {

870:             revert IdeationMarket__CollectionNotWhitelisted(tokenAddress);

899:     function _applyBuyerWhitelist(uint128 listingId, bool buyerWhitelistEnabled, address[] calldata allowedBuyers)

902:         if (buyerWhitelistEnabled) {

904:                 IBuyerWhitelistFacet(address(this)).addBuyerWhitelistAddresses(listingId, allowedBuyers);

907:             if (allowedBuyers.length > 0) revert IdeationMarket__WhitelistDisabled();

```

```solidity
File: src/interfaces/IBuyerWhitelistFacet.sol

6: interface IBuyerWhitelistFacet {

10:     function addBuyerWhitelistAddresses(uint128 listingId, address[] calldata allowedBuyers) external;

15:     function removeBuyerWhitelistAddresses(uint128 listingId, address[] calldata disallowedBuyers) external;

```

```solidity
File: src/libraries/LibAppStorage.sol

14:     bool buyerWhitelistEnabled;

48:     uint16 buyerWhitelistMaxBatchSize;

67:     mapping(address collection => bool isWhitelisted) whitelistedCollections;

69:     address[] whitelistedCollectionsArray;

71:     mapping(address collection => uint256 index) whitelistedCollectionsIndex;

73:     mapping(uint128 listingId => mapping(address buyer => bool isWhitelisted)) whitelistedBuyersByListingId;

```

```solidity
File: src/upgradeInitializers/DiamondInit.sol

26:     function init(uint32 innovationFee, uint16 buyerWhitelistMaxBatchSize) external {

42:         s.buyerWhitelistMaxBatchSize = buyerWhitelistMaxBatchSize;

152:             s.allowedCurrenciesIndex[currency] = i; // Store actual index (same pattern as whitelistedCollectionsIndex)

```

### <a name="NC-14"></a>[NC-14] Strings should use double quotes rather than single quotes
See the Solidity Style Guide: https://docs.soliditylang.org/en/v0.8.20/style-guide.html#other-recommendations

*Instances (1)*:
```solidity
File: src/libraries/LibDiamond.sol

207:         require(_facetAddress != address(0), "LibDiamondCut: Can't remove function that doesn't exist");

```

### <a name="NC-15"></a>[NC-15] Use Underscores for Number Literals (add an underscore every 3 digits)

*Instances (1)*:
```solidity
File: src/facets/IdeationMarketFacet.sol

439:         uint256 innovationFee = ((purchasePrice * listedItem.feeRate) / 100000);

```

### <a name="NC-16"></a>[NC-16] Constants should be defined rather than using magic numbers

*Instances (1)*:
```solidity
File: src/upgradeInitializers/DiamondInit.sol

48:         address[] memory currencies = new address[](76); // 1 ETH + 75 ERC-20 = 76 total

```

### <a name="NC-17"></a>[NC-17] Variables need not be initialized to zero
The default value for variables is zero, so initializing them to zero is superfluous.

*Instances (23)*:
```solidity
File: src/facets/BuyerWhitelistFacet.sol

39:         for (uint256 i = 0; i < len;) {

66:         for (uint256 i = 0; i < len;) {

```

```solidity
File: src/facets/CollectionWhitelistFacet.sol

79:         for (uint256 i = 0; i < len;) {

107:         for (uint256 i = 0; i < len;) {

```

```solidity
File: src/facets/DiamondLoupeFacet.sol

22:         for (uint256 i = 0; i < numFacets;) {

75:         for (uint256 i = 0; i < facetCount;) {

84:         for (uint256 i = 0; i < facetCount;) {

88:             for (uint256 j = 0; j < selLen;) {

```

```solidity
File: src/facets/DiamondUpgradeFacet.sol

24:         for (uint256 i = 0; i < _addFunctions.length; i++) {

31:             for (uint256 j = 0; j < selectors.length; j++) {

43:         for (uint256 i = 0; i < _replaceFunctions.length; i++) {

50:             for (uint256 j = 0; j < selectors.length; j++) {

64:             for (uint256 i = 0; i < _removeFunctions.length; i++) {

112:         for (uint256 i = 0; i < arr.length; i++) {

```

```solidity
File: src/facets/IdeationMarketFacet.sol

221:         address seller = address(0);

442:         address royaltyReceiver = address(0);

443:         uint256 royaltyAmount = 0;

```

```solidity
File: src/libraries/LibDiamond.sol

126:         for (uint256 selectorIndex = 0; selectorIndex < selLen;) {

```

```solidity
File: src/upgradeInitializers/DiamondInit.sol

149:         for (uint256 i = 0; i < currencies.length; i++) {

```

```solidity
File: src/upgradeInitializers/DummyUpgradeInit.sol

56:         for (uint256 i = 0; i < facetAddresses.length; i++) {

67:         for (uint256 i = 0; i < length; i++) {

79:         for (uint256 i = 0; i < length; i++) {

83:         for (uint256 i = 0; i < length; i++) {

```


## Low Issues


| |Issue|Instances|
|-|:-|:-:|
| [L-1](#L-1) | Division by zero not prevented | 1 |
| [L-2](#L-2) | External call recipient may consume all transaction gas | 4 |
| [L-3](#L-3) | Initializers could be front-run | 1 |
| [L-4](#L-4) | Use `Ownable2Step.transferOwnership` instead of `Ownable.transferOwnership` | 2 |
| [L-5](#L-5) | Unsafe solidity low-level call can cause gas grief attack | 1 |
| [L-6](#L-6) | Upgradeable contract not initialized | 6 |
### <a name="L-1"></a>[L-1] Division by zero not prevented
The divisions below take an input parameter which does not have any zero-value checks, which may lead to the functions reverting when zero is passed.

*Instances (1)*:
```solidity
File: src/facets/IdeationMarketFacet.sol

397:             uint256 unitPrice = listedItem.price / listedItem.erc1155Quantity;

```

### <a name="L-2"></a>[L-2] External call recipient may consume all transaction gas
There is no limit specified on the amount of gas used, so the recipient can use up all of the transaction's gas, causing it to revert. Use `addr.call{gas: <amount>}("")` or [this](https://github.com/nomad-xyz/ExcessivelySafeCall) library instead.

*Instances (4)*:
```solidity
File: src/facets/IdeationMarketFacet.sol

1014:             (bool successFee,) = payable(marketplaceOwner).call{value: innovationFee}("");

1020:                 (bool successRoyalty,) = payable(royaltyReceiver).call{value: royaltyAmount}("");

1026:             (bool successSeller,) = payable(seller).call{value: sellerProceeds}("");

1065:         (bool success, bytes memory returndata) = token.call(data);

```

### <a name="L-3"></a>[L-3] Initializers could be front-run
Initializers could be front-run, allowing an attacker to either set their own values, take ownership of the contract, and in the best case forcing a re-deployment

*Instances (1)*:
```solidity
File: src/upgradeInitializers/DiamondInit.sol

26:     function init(uint32 innovationFee, uint16 buyerWhitelistMaxBatchSize) external {

```

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
File: src/facets/OwnershipFacet.sol

21:     function transferOwnership(address newOwner) external override {

```

```solidity
File: src/interfaces/IERC173.sol

19:     function transferOwnership(address _newOwner) external;

```

### <a name="L-5"></a>[L-5] Unsafe solidity low-level call can cause gas grief attack
Using the low-level calls of a solidity address can leave the contract open to gas grief attacks. These attacks occur when the called contract returns a large amount of data.

So when calling an external contract, it is necessary to check the length of the return data before reading/copying it (using `returndatasize()`).

*Instances (1)*:
```solidity
File: src/facets/IdeationMarketFacet.sol

1065:         (bool success, bytes memory returndata) = token.call(data);

```

### <a name="L-6"></a>[L-6] Upgradeable contract not initialized
Upgradeable contracts are initialized via an initializer function rather than by a constructor. Leaving such a contract uninitialized may lead to it being taken over by a malicious user

*Instances (6)*:
```solidity
File: src/libraries/LibDiamond.sol

240:     function initializeDiamondCut(address _init, bytes memory _calldata) internal {

```

```solidity
File: src/upgradeInitializers/DummyUpgradeInit.sol

11:     event DummyUpgradeInitialized(uint256 value);

12:     event DummyUpgradeVersionInitialized(string version, bytes32 implementationId, uint256 timestamp);

17:         emit DummyUpgradeInitialized(value);

41:         emit DummyUpgradeInitialized(value);

42:         emit DummyUpgradeVersionInitialized(newVersion, ds.currentImplementationId, block.timestamp);

```


## Medium Issues


| |Issue|Instances|
|-|:-|:-:|
| [M-1](#M-1) | Centralization Risk for trusted owners | 4 |
| [M-2](#M-2) | Direct `supportsInterface()` calls may cause caller to revert | 7 |
### <a name="M-1"></a>[M-1] Centralization Risk for trusted owners

#### Impact:
Contracts have owners with privileged rights to perform admin tasks and need to be trusted to not perform malicious updates or drain funds.

*Instances (4)*:
```solidity
File: src/facets/CollectionWhitelistFacet.sol

31:     function addWhitelistedCollection(address tokenAddress) external onlyOwner {

47:     function removeWhitelistedCollection(address tokenAddress) external onlyOwner {

73:     function batchAddWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {

101:     function batchRemoveWhitelistedCollections(address[] calldata tokenAddresses) external onlyOwner {

```

### <a name="M-2"></a>[M-2] Direct `supportsInterface()` calls may cause caller to revert
Calling `supportsInterface()` on a contract that doesn't implement the ERC-165 standard will result in the call reverting. Even if the caller does support the function, the contract may be malicious and consume all of the transaction's available gas. Call it via a low-level [staticcall()](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/f959d7e4e6ee0b022b41e5b644c79369869d8411/contracts/utils/introspection/ERC165Checker.sol#L119), with a fixed amount of gas, and check the return code, or use OpenZeppelin's [`ERC165Checker.supportsInterface()`](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/f959d7e4e6ee0b022b41e5b644c79369869d8411/contracts/utils/introspection/ERC165Checker.sol#L36-L39).

*Instances (7)*:
```solidity
File: src/facets/IdeationMarketFacet.sol

224:             if (!IERC165(tokenAddress).supportsInterface(type(IERC1155).interfaceId)) {

225:                 if (!IERC165(tokenAddress).supportsInterface(type(IERC721).interfaceId)) {

247:             if (!IERC165(tokenAddress).supportsInterface(type(IERC721).interfaceId)) {

248:                 if (!IERC165(tokenAddress).supportsInterface(type(IERC1155).interfaceId)) {

446:         if (IERC165(listedItem.tokenAddress).supportsInterface(type(IERC2981).interfaceId)) {

954:                 if (!IERC165(desiredTokenAddress).supportsInterface(type(IERC1155).interfaceId)) {

959:                 if (!IERC165(desiredTokenAddress).supportsInterface(type(IERC721).interfaceId)) {

```

