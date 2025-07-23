require("@nomicfoundation/hardhat-ethers");

module.exports = {
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      viaIR: true,
    },
  },
  paths: {
    sources: "./4naly3er/contracts", // ← compile your main code
    artifacts: "./artifacts", // ← keep artifacts local to audit/
    cache: "./cache",
  },
};
