import { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.6.12",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  paths: {
    sources: "./contracts",
    tests: "../test",
    cache: "../cache",
    artifacts: "../artifacts"
  }
};

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more
export default config;
