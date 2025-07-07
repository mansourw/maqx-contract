const { ethers, upgrades } = require("hardhat");

async function main() {
  const MAQXToken = await ethers.getContractFactory("MAQXToken");
  console.log("Upgrading MAQXToken...");

  const proxyAddress = "0x7544eB20Cf05779898f3C2113010ebeA4e7d957E";
  await upgrades.upgradeProxy(proxyAddress, MAQXToken);

  console.log("✅ Upgrade complete.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});