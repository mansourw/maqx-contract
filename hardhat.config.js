require("hardhat-deploy");
require("@nomicfoundation/hardhat-toolbox");
require("@matterlabs/hardhat-zksync-deploy");
require("@matterlabs/hardhat-zksync-solc");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config();

const {
  PRIVATE_KEY,
  L1_RPC_URL_SEPOLIA,
  L1_RPC_URL_MAINNET,
  L2_RPC_URL,
  OPTIMISM_RPC_URL,
} = process.env;

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.22",
        settings: {
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 20,
          },
        },
      },
      
    ],
  },
  defaultNetwork: "zkSyncTestnet",
  networks: {
    zkSyncTestnet: {
      url: L2_RPC_URL,
      ethNetwork: "sepolia",
      zksync: true,
      accounts: [PRIVATE_KEY],
    },
    sepolia: {
      url: L1_RPC_URL_SEPOLIA,
      accounts: [PRIVATE_KEY],
    },
    ethereum: {
      url: L1_RPC_URL_MAINNET,
      accounts: [PRIVATE_KEY],
    },
    optimism: {
      url: OPTIMISM_RPC_URL,
      accounts: [PRIVATE_KEY],
    },
  },
  zksolc: {
    version: "1.5.1",
    compilerSource: "binary",
    settings: {
      optimizer: {
        enabled: true,
      },
      viaIR: false, // was true
    },
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
  },
};