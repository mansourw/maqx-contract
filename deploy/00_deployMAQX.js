const path = require("path");
require("dotenv").config({ path: path.resolve(__dirname, "../.env") });

module.exports = async function (hre) {
  const { deployments, getNamedAccounts, ethers, upgrades } = hre;
  const { deploy } = deployments;

  const MAQXToken = await ethers.getContractFactory("MAQXToken");

  console.log("🧪 GLOBAL_MINT_WALLET:", process.env.GLOBAL_MINT_WALLET);
  console.log("📦 PLEDGE_FUND_WALLET:", process.env.PLEDGE_FUND_WALLET);

  if (
    !process.env.GLOBAL_MINT_WALLET ||
    !process.env.FOUNDER_WALLET ||
    !process.env.DEV_POOL_WALLET ||
    !process.env.DAO_TREASURY_WALLET
  ) {
    throw new Error("🚨 Missing one or more required wallet addresses in .env");
  }

  try {
    const proxy = await upgrades.deployProxy(
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

    console.log("✅ Deployment finished. Verifying address...");
    console.log("MAQXToken proxy deployed to:", await proxy.getAddress());
  } catch (error) {
    console.error("❌ Deployment failed:", error);
  }
};

module.exports.tags = ["MAQX"];