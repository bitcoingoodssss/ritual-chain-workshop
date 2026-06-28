import { defineConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-ethers";
import "dotenv/config";

export default defineConfig({
  solidity: "0.8.24",
  networks: {
    ritualTestnet: {
      type: "http",
      url: "https://rpc.ritualfoundation.org",
      chainId: 1979,
      accounts: process.env.PRIVATE_KEY 
        ? [`0x${process.env.PRIVATE_KEY}`] 
        : [],
    },
  },
});
