// scripts/extractPresaleBuyers.js
const { ethers } = require("ethers");
const fs = require("fs");
require("dotenv").config();

// Ensure .env contains: PRESALE_CONTRACT_ADDRESS=0x... and L1_RPC_URL_SEPOLIA=https://...

// Your presale contract info
const CONTRACT_ADDRESS = process.env.PRESALE_CONTRACT_ADDRESS;
const ABI = [
  "event LogPresaleBuyer(address indexed buyer, uint256 amount)"
];

// Use Infura, Alchemy or other RPC provider
const PROVIDER_URL = process.env.L1_RPC_URL_SEPOLIA;
const provider = new ethers.JsonRpcProvider(PROVIDER_URL);

const contract = new ethers.Contract(CONTRACT_ADDRESS, ABI, provider);

async function main() {
  console.log("Fetching MAQX presale buyers...");

  const events = await contract.queryFilter("LogPresaleBuyer", 0, "latest");

  console.log(`\n📦 Found ${events.length} buyers:\n`);

  const output = [];

  events.forEach((log, i) => {
    const buyer = log.args.buyer;
    const amount = ethers.formatEther(log.args.amount);
    console.log(`${i + 1}. ${buyer} bought ${amount} MAQX`);
    output.push({ buyer, amount });
  });

  // Write to CSV in the contract folder
  const csv = "buyer,amount\n" + output.map(row => `${row.buyer},${row.amount}`).join("\n");
  fs.writeFileSync("./presale-buyers.csv", csv);
  console.log("\n📄 Saved to presale-buyers.csv");
}

main().catch(err => {
  console.error("❌ Error:", err);
});