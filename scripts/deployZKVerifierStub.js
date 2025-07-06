// scripts/deployZKVerifierStub.js

const hre = require("hardhat");

async function main() {
  const ZKRegenVerifierStub = await hre.ethers.getContractFactory("ZKRegenVerifierStub");
  const verifier = await ZKRegenVerifierStub.deploy();

  await verifier.waitForDeployment();

  console.log(`✅ ZKRegenVerifierStub deployed at: ${await verifier.getAddress()}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});