const { getNamedAccounts, deployments } = require("hardhat");
require("dotenv").config();

module.exports = async ({ getNamedAccounts, deployments }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const maqxToken = process.env.MAQX_TOKEN_ADDRESS;
  const usdtToken = process.env.USDT_TOKEN_ADDRESS;
  const priceFeed = process.env.ETH_USD_PRICE_FEED || "0x694AA1769357215DE4FAC081bf1f309aDC325306"; // Sepolia default

  if (!maqxToken || !usdtToken || !priceFeed) {
    throw new Error("❌ Missing MAQX_TOKEN_ADDRESS, USDT_TOKEN_ADDRESS, or ETH_USD_PRICE_FEED in .env");
  }

  console.log("🚀 Deploying MaqxPresale...");
  console.log("🧠 Using ETH/USD Price Feed:", priceFeed);

  await deploy("MaqxPresale", {
    from: deployer,
    args: [maqxToken, usdtToken, priceFeed],
    log: true,
  });

  const deployedContract = await deployments.get("MaqxPresale");
  console.log("✅ MaqxPresale deployed at:", deployedContract.address);
};

module.exports.tags = ["Presale"];