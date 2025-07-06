const path = require("path");
require("dotenv").config({ path: path.resolve(__dirname, "../.env") });
const { ethers, upgrades } = require("hardhat");

async function main() {
  const MAQXToken = await ethers.getContractFactory("MAQXToken");

  console.log("🧪 GLOBAL_MINT_WALLET:", process.env.GLOBAL_MINT_WALLET);
  console.log("📦 PLEDGE_FUND_WALLET:", process.env.PLEDGE_FUND_WALLET);
  // console.log("📦 PLEDGE_FUND_WALLET:", process.env.PLEDGE_FUND_WALLET);
  // console.log("🔐 ZK_DISTRIBUTION_WALLET:", process.env.ZK_DISTRIBUTION_WALLET);
  // console.log("🔐 ZK_DISTRIBUTION_WALLET:", process.env.ZK_DISTRIBUTION_WALLET);

  const maqx = await upgrades.deployProxy(
    MAQXToken,
    [
      process.env.GLOBAL_MINT_WALLET,
      process.env.FOUNDER_WALLET,
      process.env.DEV_POOL_WALLET,
      process.env.DAO_TREASURY_WALLET,
    ],
    {
      initializer: "initialize",
    }
  );


  console.log("MAQXToken proxy deployed to:", await maqx.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});