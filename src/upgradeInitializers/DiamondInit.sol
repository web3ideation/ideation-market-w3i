// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * \
 * Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
 * EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
 *
 * Implementation of a diamond.
 * /*****************************************************************************
 */
import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IDiamondLoupeFacet} from "../interfaces/IDiamondLoupeFacet.sol";
import {IDiamondCutFacet} from "../interfaces/IDiamondCutFacet.sol";
import {IERC173} from "../interfaces/IERC173.sol";
import {IERC165} from "../interfaces/IERC165.sol";
import {LibAppStorage, AppStorage} from "../libraries/LibAppStorage.sol";

/// @title DiamondInit (EIP-2535 initializer)
/// @notice Registers ERC-165 interface support and initializes marketplace configuration in shared storage.
/// @dev Must be executed as the `init` call data of `diamondCut` (i.e., via `delegatecall` into the diamond),
/// so that changes persist in the diamond’s storage. Writes to:
/// - `LibDiamond.DiamondStorage.supportedInterfaces` for ERC-165, DiamondCut, DiamondLoupe, and ERC-173.
/// - `LibAppStorage.AppStorage` for `innovationFee` and `buyerWhitelistMaxBatchSize`.
contract DiamondInit {
    /// @notice Initializes ERC-165 flags and marketplace parameters.
    /// @param innovationFee Marketplace fee rate; denominator is **100_000** (e.g., 1_000 = 1%).
    /// @param buyerWhitelistMaxBatchSize Maximum number of addresses accepted per whitelist batch.
    /// @dev Intended to be called once during deployment/upgrade initialization. Idempotent if the same
    /// values are provided again, but repeated calls can overwrite prior configuration.
    function init(uint32 innovationFee, uint16 buyerWhitelistMaxBatchSize) external {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Diamond and ERC165 interfaces
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCutFacet).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupeFacet).interfaceId] = true;
        ds.supportedInterfaces[type(IERC173).interfaceId] = true;

        // Initialize emergency pause state
        ds.paused = false;

        // Initialize marketplace state variables. / Constructor for IdeationMarketFacet.
        AppStorage storage s = LibAppStorage.appStorage();
        s.innovationFee = innovationFee; // Denominator is 100_000 (e.g., 1_000 = 1%). innovation/Marketplace fee (excluding gascosts) for each sale
        s.buyerWhitelistMaxBatchSize = buyerWhitelistMaxBatchSize;

        // Initialize Allowed Currencies
        // All currencies are curated battle-tested tokens: no fee-on-transfer, no rebasing, no pausable by untrusted parties
        // Total: 76 currencies (1 ETH + 75 ERC-20 tokens)

        address[] memory currencies = new address[](76); // 1 ETH + 75 ERC-20 = 76 total

        // ETH (native) - index 0
        currencies[0] = address(0);

        // ETH Wrappers & Liquid Staking (3 tokens)
        currencies[1] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
        currencies[2] = 0xae78736Cd615f374D3085123A210448E74Fc6393; // rETH (Rocket Pool)
        currencies[3] = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; // wstETH (Lido)

        // BTC Wrappers (2 tokens)
        currencies[4] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC
        currencies[5] = 0x18084fbA666a33d37592fA2633fD49a74DD93a88; // tBTC

        // USD Stablecoins (7 tokens)
        currencies[6] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
        currencies[7] = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT
        currencies[8] = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        currencies[9] = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0; // LUSD
        currencies[10] = 0x853d955aCEf822Db058eb8505911ED77F175b99e; // FRAX
        currencies[11] = 0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f; // GHO
        currencies[12] = 0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E; // crvUSD

        // EUR Stablecoins (3 tokens)
        currencies[13] = 0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c; // EURC
        currencies[14] = 0xdB25f211AB05b1c97D595516F45794528a807ad8; // EURS
        currencies[15] = 0xC581b735A1688071A1746c968e0798D642EDE491; // EURT

        // Other Fiat Stablecoins (2 tokens)
        currencies[16] = 0x70e8dE73cE538DA2bEEd35d14187F6959a8ecA96; // XSGD
        currencies[17] = 0x2C537E5624e4af88A7ae4060C022609376C8D0EB; // TRYB (BiLira)

        // DeFi Blue Chips (16 tokens)
        currencies[18] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984; // UNI
        currencies[19] = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9; // AAVE
        currencies[20] = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2; // MKR
        currencies[21] = 0xc00e94Cb662C3520282E6f5717214004A7f26888; // COMP
        currencies[22] = 0xD533a949740bb3306d119CC777fa900bA034cd52; // CRV
        currencies[23] = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B; // CVX
        currencies[24] = 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F; // SNX
        currencies[25] = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e; // YFI
        currencies[26] = 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32; // LDO
        currencies[27] = 0x111111111117dC0aa78b770fA6A738034120C302; // 1INCH
        currencies[28] = 0xba100000625a3754423978a60c9317c58a424e3D; // BAL
        currencies[29] = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2; // SUSHI
        currencies[30] = 0xdeFA4e8a7bcBA345F687a2f1456F5Edd9CE97202; // KNC
        currencies[31] = 0xE41d2489571d322189246DaFA5ebDe1F4699F498; // ZRX
        currencies[32] = 0x6810e776880C02933D47DB1b9fc05908e5386b96; // GNO
        currencies[33] = 0x1a7e4e63778B4f12a199C062f3eFdD288afCBce8; // EURA (was FXS)

        // Infrastructure & Oracles (12 tokens)
        currencies[34] = 0x514910771AF9Ca656af840dff83E8264EcF986CA; // LINK
        currencies[35] = 0xc944E90C64B2c07662A292be6244BDf05Cda44a7; // GRT
        currencies[36] = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF; // BAT
        currencies[37] = 0x967da4048cD07aB37855c090aAF366e4ce1b9F48; // OCEAN
        currencies[38] = 0x6De037ef9aD2725EB40118Bb1702EBb27e4Aeb24; // RENDER
        currencies[39] = 0x58b6A8A3302369DAEc383334672404Ee733aB239; // LPT
        currencies[40] = 0x7DD9c5Cba05E151C895FDe1CF355C9A1D5DA6429; // GLM
        currencies[41] = 0x4a220E6096B25EADb88358cb44068A3248254675; // QNT
        currencies[42] = 0x8290333ceF9e6D528dD5618Fb97a76f268f3EDD4; // ANKR
        currencies[43] = 0xaea46A60368A7bD060eec7DF8CBa43b7EF41Ad85; // FET
        currencies[44] = 0x0b38210ea11411557c13457D4dA7dC6ea731B88a; // API3
        currencies[45] = 0x1776e1F26f98b1A5dF9cD347953a26dd3Cb46671; // NMR
        currencies[46] = 0x163f8C2467924be0ae7B5347228CABF260318753; // WLD (Worldcoin - AI/Identity)

        // NFT & Metaverse (11 tokens)
        currencies[47] = 0x4d224452801ACEd8B2F0aebE155379bb5D594381; // APE
        currencies[48] = 0x3845badAde8e6dFF049820680d1F14bD3903a5d0; // SAND
        currencies[49] = 0x0F5D2fB29fb7d3CFeE444a200298f468908cC942; // MANA
        currencies[50] = 0xBB0E17EF65F82Ab018d8EDd776e8DD940327B28b; // AXS
        currencies[51] = 0xF629cBd94d3791C9250152BD8dfBDF380E2a3B9c; // ENJ
        currencies[52] = 0xF57e7e7C23978C3cAEC3C3548E3D615c346e79fF; // IMX
        currencies[53] = 0x3506424F91fD33084466F402d5D97f05F8e3b4AF; // CHZ
        currencies[54] = 0x5283D291DBCF85356A21bA090E6db59121208b44; // BLUR
        currencies[55] = 0xf4d2888d29D722226FafA5d9B24F9164c092421E; // LOOKS
        currencies[56] = 0xba5BDe662c17e2aDFF1075610382B9B691296350; // RARE
        currencies[57] = 0xFca59Cd816aB1eaD66534D82bc21E7515cE441CF; // RARI
        currencies[58] = 0x767FE9EDC9E0dF98E07454847909b5E959D7ca0E; // ILV

        // L2 & Ecosystem Tokens (10 tokens)
        currencies[59] = 0x455e53CBB86018Ac2B8092FdCd39d8444aFFC3F6; // POL
        currencies[60] = 0xB50721BCf8d664c30412Cfbc6cf7a15145234ad1; // ARB
        currencies[61] = 0x3c3a81e81dc49A522A592e7622A7E711c06bf354; // MNT
        currencies[62] = 0xCa14007Eff0dB1f8135f4C25B34De49AB0d42766; // STRK
        currencies[63] = 0x9E32b13ce7f2E80A01932B42553652E053D6ed8e; // Metis
        currencies[64] = 0xBBbbCA6A901c926F240b89EacB641d8Aec7AEafD; // LRC
        currencies[65] = 0x6985884C4392D348587B19cb9eAAf157F13271cd; // ZRO
        currencies[66] = 0x467719aD09025FcC6cF6F8311755809d45a5E5f3; // AXL
        currencies[67] = 0x66A5cFB2e9c529f14FE6364Ad1075dF3a649C0A5; // ZK
        currencies[68] = 0x4F9254C83EB525f9FCf346490bbb3ed28a81C667; // CELR

        // Additional Liquid Staking & DeFi (7 tokens)
        currencies[69] = 0xa2E3356610840701BDf5611a53974510Ae27E2e1; // WBETH
        currencies[70] = 0x8c1BEd5b9a0928467c9B1341Da1D7BD5e10b6549; // LsETH
        currencies[71] = 0xf1C9acDc66974dFB6dEcB12aA385b9cD01190E38; // osETH
        currencies[72] = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497; // SUSDe
        currencies[73] = 0x68749665FF8D2d112Fa859AA293F07A622782F38; // XAUt (Tether Gold)
        currencies[74] = 0xfAbA6f8e4a5E8Ab82F62fe7C39859FA577269BE3; // ONDO
        currencies[75] = 0x57e114B691Db790C35207b2e685D4A43181e6061; // ENA

        // Initialize allowedCurrencies mapping and array
        for (uint256 i = 0; i < currencies.length; i++) {
            address currency = currencies[i];
            s.allowedCurrencies[currency] = true;
            s.allowedCurrenciesIndex[currency] = i; // Store actual index (same pattern as whitelistedCollectionsIndex)
            s.allowedCurrenciesArray.push(currency);
        }
    }
}
