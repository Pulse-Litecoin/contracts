import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

import { resolve } from "path";
import { config as dotenvConfig } from "dotenv";

const dotenvConfigPath: string = process.env.DOTENV_CONFIG_PATH || "./.env";
dotenvConfig({ path: resolve(__dirname, dotenvConfigPath) });

const etherscanApiKey: string | undefined = process.env.ETHERSCAN_API_KEY;
if (!etherscanApiKey) {
  throw new Error("Please set your ETHERSCAN_API_KEY in a .env file");
}

const infuraApiKey: string | undefined = process.env.INFURA_API_KEY;
if (!infuraApiKey) {
  throw new Error("Please set your INFURA_API_KEY in a .env file");
}

const coinMarketCapKey: string | undefined = process.env.COIN_MARKET_CAP_API_KEY;
if (!infuraApiKey) {
  throw new Error("Please set your INFURA_API_KEY in a .env file");
}

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.19",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    mainnet: {
      url: "https://eth-mainnet.alchemyapi.io/v2/" + infuraApiKey
    },
    pulse: {
      chainId: 369,
      url: "https://rpc-pulsechain.g4mm4.io",
      gasPrice: 50000000000,
    },
    pulseTestnet: {
      chainId: 943,
      url: "https://rpc.v4.testnet.pulsechain.com",
      gasPrice: 50000000000,
    },
    hardhat: {
      initialBaseFeePerGas: 300_000_000_000,
      forking: {
        url: "https://rpc-pulsechain.g4mm4.io",
        blockNumber: 21151000,
      },
      accounts: {
        count: 20
      }
    },
    'truffle-dashboard': {
      url: "http://localhost:24012/rpc",
      timeout: 100000000
    }
  },
  etherscan: { // needed for contract verification
    apiKey: {
      mainnet: etherscanApiKey,
      pulse: '0',
    },
    customChains: [
      {
        network: 'pulse',
        chainId: 369,
        urls: {
          apiURL: 'https://api.scan.pulsechain.com/api',
          browserURL: 'https://pulsescan.korkey.tech'
        }
      }
    ]
  },
  gasReporter: {
    enabled: true,
    currency: 'USD',
    gasPrice: 305395
  }
};

export default config;
