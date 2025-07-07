const { ethers } = require("hardhat");

module.exports = async ({ deployments }) => {
  const { deploy } = deployments;

  const { address } = await deploy("ZKRegenVerifierStub", {
    from: (await ethers.getSigners())[0].address,
    log: true,
  });

  console.log(`✅ ZKRegenVerifierStub deployed at: ${address}`);
};

module.exports.tags = ["ZKRegenVerifierStub"];