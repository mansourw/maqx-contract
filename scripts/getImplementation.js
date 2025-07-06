const { ethers, upgrades } = require("hardhat");

async function main() {
  const proxyAddress = "0x7544eB20Cf05779898f3C2113010ebeA4e7d957E"; // your deployed proxy
  const implAddress = await upgrades.erc1967.getImplementationAddress(proxyAddress);
  console.log("🛠 Implementation Address:", implAddress);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});