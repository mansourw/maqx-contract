const fs = require("fs");
const traceFilePath = "./traceFeed.json";

let traceFeed = [];
if (fs.existsSync(traceFilePath)) {
  const raw = fs.readFileSync(traceFilePath);
  try {
    traceFeed = JSON.parse(raw);
  } catch (e) {
    console.error("Failed to parse traceFeed.json, starting with empty array.");
    traceFeed = [];
  }
}

function writeTrace(entry) {
  traceFeed.push(entry);
  fs.writeFileSync(traceFilePath, JSON.stringify(traceFeed, null, 2));
}

require("dotenv").config();
const { ethers } = require("ethers");

const provider = new ethers.JsonRpcProvider(process.env.SEPOLIA_RPC_URL);
const contractAddress = "0x1f57Fc18330eDc409897Fe3C399cAF5aa5D1B55c"; // Replace with current contract if redeployed

const abi = [
  "event Transfer(address indexed from, address indexed to, uint256 value)",
  "event Approval(address indexed owner, address indexed spender, uint256 value)",
  "event SeedGranted(address indexed user)",
  "event LockedTokensUnlocked(address indexed user)",
  "event ActionBurned(address indexed user, uint8 actionType, uint256 amount)",
  "event Gifted(address indexed from, address indexed to, uint256 amount, uint256 reward)",
  "event RegenExecuted(address indexed user, uint256 totalRegen, uint256 userShare, uint256 daoShare, uint256 founderShare)",
  "event RMRTierChanged(address indexed user, uint8 newTier)"
];

const contract = new ethers.Contract(contractAddress, abi, provider);

contract.on("SeedGranted", (user, event) => {
  console.log(`🌱 Seed granted to: ${user}`);
  writeTrace({
    type: "SeedGranted",
    user,
    timestamp: Date.now(),
    blockNumber: event.blockNumber
  });
});

contract.on("LockedTokensUnlocked", (user, event) => {
  console.log(`🔓 Dev tokens unlocked for: ${user}`);
  writeTrace({
    type: "LockedTokensUnlocked",
    user,
    timestamp: Date.now(),
    blockNumber: event.blockNumber
  });
});

contract.on("ActionBurned", (user, actionType, amount, event) => {
  console.log(`[TraceFeed] 🔥 ActionBurned - ${user} | Type: ${actionType} | Amount: ${ethers.formatEther(amount)} MAQX | Block: ${event.blockNumber}`);
  writeTrace({
    type: "ActionBurned",
    user,
    actionType,
    amount: ethers.formatEther(amount),
    timestamp: Date.now(),
    blockNumber: event.blockNumber
  });
});

contract.on("Gifted", (from, to, amount, reward, event) => {
  console.log(`[Leaderboard] 🎁 Gifted - From: ${from} → To: ${to} | Amount: ${ethers.formatEther(amount)} MAQX | Reward: ${ethers.formatEther(reward)} MAQX | Block: ${event.blockNumber}`);
  writeTrace({
    type: "Gifted",
    from,
    to,
    amount: ethers.formatEther(amount),
    reward: ethers.formatEther(reward),
    timestamp: Date.now(),
    blockNumber: event.blockNumber
  });
});

contract.on("RegenExecuted", (user, total, userShare, daoShare, founderShare, event) => {
  console.log(`[Regen] 🌱 RegenExecuted - ${user} | Regen: ${ethers.formatEther(total)} MAQX | User: ${ethers.formatEther(userShare)}, DAO: ${ethers.formatEther(daoShare)}, Founder: ${ethers.formatEther(founderShare)} | Block: ${event.blockNumber}`);
  writeTrace({
    type: "RegenExecuted",
    user,
    total: ethers.formatEther(total),
    userShare: ethers.formatEther(userShare),
    daoShare: ethers.formatEther(daoShare),
    founderShare: ethers.formatEther(founderShare),
    timestamp: Date.now(),
    blockNumber: event.blockNumber
  });
});

contract.on("RMRTierChanged", (user, newTier, event) => {
  console.log(`[RMR] 🌀 Tier Changed - ${user} is now Tier ${newTier} | Block: ${event.blockNumber}`);
  writeTrace({
    type: "RMRTierChanged",
    user,
    newTier,
    timestamp: Date.now(),
    blockNumber: event.blockNumber
  });
});