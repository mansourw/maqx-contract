const { ethers } = require("hardhat");
require("dotenv").config();

async function main() {
  const signer = new ethers.Wallet(process.env.PRIVATE_KEY, ethers.getDefaultProvider(process.env.INFURA_URL));

  const contractAddress = "0x1f57Fc18330eDc409897Fe3C399cAF5aa5D1B55c"; // e.g. 0x1f57...
  const contractABI = require("../artifacts/contracts/MAQXToken_v1.1.sol/MAQXToken_v1.1.json").abi;
  const contract = new ethers.Contract(contractAddress, contractABI, signer);

  const tx = await contract.regenAllEligible();
  console.log("Regen batch tx sent:", tx.hash);
  await tx.wait();
  console.log("✅ Regen executed");
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});