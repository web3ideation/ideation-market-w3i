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
    sources: "../../src", // compile repo contracts (from security-tools/slither)
    artifacts: "artifacts", // ← keep artifacts local to security-tools/slither/
    cache: "cache",
  },
};
