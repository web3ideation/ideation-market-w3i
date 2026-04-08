// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {MockAXIE} from "../src/mocks/MockAXIE.sol";

/// @title DeployAxieMock
/// @notice Deploys MockAXIE and seeds a few real-looking Axie IDs for Sepolia POC.
contract DeployAxieMock is Script {
    address internal constant RONIN_MAIN_AXIE = 0x32950db2a7164aE833121501C797D79E7B79d74C;
    string internal constant AXIE_BASE_URI = "https://metadata.axieinfinity.com/axie/";

    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        require(deployer != address(0), "DEPLOYER_ADDRESS not set");

        vm.startBroadcast();

        MockAXIE axie = new MockAXIE();

        axie.grantRole(axie.MINTER_ROLE(), deployer);
        axie.grantRole(axie.SEEDER_ROLE(), deployer);
        axie.setBaseTokenURI(AXIE_BASE_URI);

        MockAXIE.AxieData memory d27 = MockAXIE.AxieData({
            sireId: 0,
            matronId: 0,
            birthDate: 1521001390,
            genes: MockAXIE.Gene({
                x: 4820857114582492907591948997336919297038119854941980382495492,
                y: 5300975133944756922121709900192707377810136563002416291881364447383569666
            }),
            breedCount: 3,
            level: 60
        });

        MockAXIE.AxieData memory d29 = MockAXIE.AxieData({
            sireId: 0,
            matronId: 0,
            birthDate: 1521001401,
            genes: MockAXIE.Gene({
                x: 10855508365998398141786268695694610390510491098382546684414504806036652704002,
                y: 1767171440114137971612780573571528246763261168815173281775360364756632580
            }),
            breedCount: 3,
            level: 30
        });

        MockAXIE.AxieData memory d3270162 = MockAXIE.AxieData({
            sireId: 2873779,
            matronId: 2873787,
            birthDate: 1627906689,
            genes: MockAXIE.Gene({
                x: 10855508365998394927910084349603529190859416743163757142831925635828569686786,
                y: 1766851330340799475867436122228031043277947372330264682745471096630379270
            }),
            breedCount: 3,
            level: 0
        });

        MockAXIE.AxieData memory d4200042 = MockAXIE.AxieData({
            sireId: 1290011,
            matronId: 1290088,
            birthDate: 1631022333,
            genes: MockAXIE.Gene({x: 7777000000000000000000000000000000000042, y: 8800112233445566778899001122334455667788}),
            breedCount: 1,
            level: 12
        });

        MockAXIE.AxieData memory d9000001 = MockAXIE.AxieData({
            sireId: 0,
            matronId: 0,
            birthDate: 1640995200,
            genes: MockAXIE.Gene({x: 9000001000000000000000000000000000000001, y: 1234567890123456789012345678901234567890}),
            breedCount: 0,
            level: 1
        });

        axie.mintAxieWithId(deployer, 27, d27);
        axie.mintAxieWithId(deployer, 29, d29);
        axie.mintAxieWithId(deployer, 3270162, d3270162);
        axie.mintAxieWithId(deployer, 4200042, d4200042);
        axie.mintAxieWithId(deployer, 9000001, d9000001);

        console.log("Live Ronin Axie collection:", RONIN_MAIN_AXIE);
        console.log("Deployed MockAXIE:", address(axie));
        console.log("Minted to deployer:", deployer);
        console.log("Seeded IDs: 27, 29, 3270162, 4200042, 9000001");

        vm.stopBroadcast();
    }
}
