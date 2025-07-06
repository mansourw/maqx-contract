// test/test-maqx-core.js

const { expect } = require("chai");
const hre = require("hardhat");
const { ethers, upgrades } = hre;
const parseEther = hre.ethers.parseEther;

describe("MAQXToken – Core Invariant Tests", function () {
  let maqx, owner, user, other;

  // const { upgrades } = require("hardhat");

  beforeEach(async () => {
    [owner, user, other] = await ethers.getSigners();

    const MAQXToken = await ethers.getContractFactory("MAQXToken");
    maqx = await upgrades.deployProxy(MAQXToken, [
      owner.address,       // globalMintWallet
      owner.address,       // founderWallet
      owner.address,       // developerPoolWallet
      owner.address        // daoTreasuryWallet
    ], { initializer: 'initialize' });

  });

  it("should only allow one seed grant per user", async () => {
    await maqx.grantSeed(user.address);
    const bal = await maqx.balanceOf(user.address);
    const lockedBal = await maqx.lockedBalance(user.address);
    console.log("DEBUG: should only allow one seed grant per user - After grantSeed");
    console.log("  total =", bal.toString());
    console.log("  locked =", lockedBal.toString());
    console.log("  unlocked =", (bal - lockedBal).toString());
    await expect(maqx.grantSeed(user.address)).to.be.revertedWith("Seed already granted");
  });

  it("should transfer 1 MAQX to user as seed and mark hasReceivedSeed", async () => {
    await maqx.grantSeed(user.address);
    const bal = await maqx.balanceOf(user.address);
    const lockedBal = await maqx.lockedBalance(user.address);
    console.log("DEBUG: should transfer 1 MAQX to user as seed and mark hasReceivedSeed - After grantSeed");
    console.log("  total =", bal.toString());
    console.log("  locked =", lockedBal.toString());
    console.log("  unlocked =", (bal - lockedBal).toString());
    const balance = await maqx.balanceOf(user.address);
    const received = await maqx.hasReceivedSeed(user.address);
    expect(balance).to.equal(parseEther("1"));
    expect(received).to.be.true;
  });

  it("should prevent transfer of locked seed token", async () => {
    await maqx.grantSeed(user.address);
    
    // Simulate a user receiving additional unlocked tokens
    await maqx.connect(owner).transfer(user.address, parseEther("2"));

    // Transfer within unlocked limit should succeed
    await expect(
      maqx.connect(user).transfer(other.address, parseEther("1"))
    ).to.not.be.reverted;

    let bal = await maqx.balanceOf(user.address);
    let lockedBal = await maqx.lockedBalance(user.address);
    console.log("DEBUG: should prevent transfer of locked seed token - After transfer of 1 MAQX");
    console.log("  total =", bal.toString());
    console.log("  locked =", lockedBal.toString());
    console.log("  unlocked =", (bal - lockedBal).toString());

    // Transfer exceeding unlocked (attempts to use locked seed) should fail
    await expect(
      maqx.connect(user).transfer(other.address, parseEther("2.1"))
    ).to.be.revertedWith("Cannot transfer locked tokens");
  });

  it("should regen 1 MAQX from seed, and lock it", async () => {
    await maqx.grantSeed(user.address);
    // Simulates an off-chain burn — this does NOT reduce user's MAQX balance
    await maqx.connect(user).act({ value: parseEther("1") });

    await network.provider.send("evm_increaseTime", [86400]);
    await network.provider.send("evm_mine");

    await maqx.connect(owner).regenMint(user.address, parseEther("1"));
    const bal = await maqx.balanceOf(user.address);
    const lockedBal = await maqx.lockedBalance(user.address);
    console.log("DEBUG: should regen 1 MAQX from seed, and lock it - After regenMint");
    console.log("  total =", bal.toString());
    console.log("  locked =", lockedBal.toString());
    console.log("  unlocked =", (bal - lockedBal).toString());
    const locked = await maqx.lockedBalance(user.address);
    expect(locked).to.equal(parseEther("1"));
  });

  it("should recursively lock regen from locked MAQX", async () => {
    await maqx.grantSeed(user.address);
    await maqx.connect(owner).regenMint(user.address, parseEther("0.5"));
    await maqx.connect(owner).regenMint(user.address, parseEther("0.5"));
    const bal = await maqx.balanceOf(user.address);
    const lockedBal = await maqx.lockedBalance(user.address);
    console.log("DEBUG: should recursively lock regen from locked MAQX - After two regenMint calls");
    console.log("  total =", bal.toString());
    console.log("  locked =", lockedBal.toString());
    console.log("  unlocked =", (bal - lockedBal).toString());
    const locked = await maqx.lockedBalance(user.address);
    expect(locked).to.equal(parseEther("1"));
  });

  it("should prevent transfer of locked regen", async () => {
    await maqx.grantSeed(user.address);

    // Burn 0.5 MAQX twice to fully consume the 1 MAQX seed token
    await maqx.connect(user).act({ value: parseEther("0.5") });
    await maqx.connect(user).act({ value: parseEther("0.5") });

    // Fast forward to regen eligibility
    await network.provider.send("evm_increaseTime", [86400]);
    await network.provider.send("evm_mine");

    // Regen full 1 MAQX (fully locked)
    await maqx.connect(owner).regenMint(user.address, parseEther("1"));

    // Confirm the user has 1 locked MAQX
    const locked = await maqx.lockedBalance(user.address);
    expect(locked).to.equal(parseEther("1"));

    // Grant user 0.5 MAQX unlocked
    await maqx.connect(owner).transfer(user.address, parseEther("0.5"));

    // Total balance = 1.5 MAQX, of which 1 is locked

    let bal = await maqx.balanceOf(user.address);
    let lockedBal = await maqx.lockedBalance(user.address);
    console.log("DEBUG: should prevent transfer of locked regen - After regenMint and transfer");
    console.log("  total =", bal.toString());
    console.log("  locked =", lockedBal.toString());
    console.log("  unlocked =", (bal - lockedBal).toString());

    // Try to transfer more than unlocked (0.6 > 0.5)
    await expect(
      maqx.connect(user).transfer(other.address, parseEther("1.4"))
    ).to.be.revertedWith("Cannot transfer locked tokens");

    // Transfer within unlocked (0.5) should pass
    //await expect(
      //maqx.connect(user).transfer(other.address, parseEther("0.5"))
    //).to.not.be.reverted;
  });

  it("should mint to pledge fund and track seed-derived amount", async () => {
    await maqx.grantSeed(user.address);
    await maqx.connect(owner).regenMint(user.address, parseEther("1"));
    const bal = await maqx.balanceOf(user.address);
    const lockedBal = await maqx.lockedBalance(user.address);
    console.log("DEBUG: should mint to pledge fund and track seed-derived amount - After regenMint");
    console.log("  total =", bal.toString());
    console.log("  locked =", lockedBal.toString());
    console.log("  unlocked =", (bal - lockedBal).toString());
    const total = await maqx.balanceOf(await maqx.pledgeFundWallet());
    const flagged = await maqx.pledgeFromSeedDerived();
    expect(flagged).to.equal(total);
  });

  it("should reject pledge spend beyond unlocked amount", async () => {
    await maqx.grantSeed(user.address);
    await maqx.connect(owner).grantLockedDevToken(user.address, parseEther("0.1"));

    // Regen from seed
    await maqx.connect(owner).regenMint(user.address, parseEther("1"));

    // Confirm pledge fund received the regen
    const pledgeWallet = await maqx.pledgeFundWallet();
    const total = await maqx.balanceOf(pledgeWallet);
    const flagged = await maqx.pledgeFromSeedDerived();
    const unlocked = total - flagged;

    const bal = await maqx.balanceOf(user.address);
    const lockedBal = await maqx.lockedBalance(user.address);
    console.log("DEBUG: should reject pledge spend beyond unlocked amount - After regenMint and grantLockedDevToken");
    console.log("  total =", bal.toString());
    console.log("  locked =", lockedBal.toString());
    console.log("  unlocked =", (bal - lockedBal).toString());

    expect(flagged).to.equal(total);

    // Try to spend more than unlocked (should be 0 unlocked)
    await expect(
      maqx.spendFromPledgeFund(other.address, parseEther("0.0001"), "test")
    ).to.be.revertedWith("Insufficient unlocked pledge funds");
  });

  // Removed by request: growth check will be verified manually during UI simulation

  it("should mint nothing if burn amount is zero", async () => {
    const bal = await maqx.balanceOf(user.address);
    const lockedBal = await maqx.lockedBalance(user.address);
    console.log("DEBUG: should mint nothing if burn amount is zero - Before regenMint with zero");
    console.log("  total =", bal.toString());
    console.log("  locked =", lockedBal.toString());
    console.log("  unlocked =", (bal - lockedBal).toString());
    await expect(
      maqx.connect(owner).regenMint(user.address, 0)
    ).to.be.revertedWith("Invalid amount");
  });

  it("should allow user to regen pending actions via regenMyPending()", async () => {
    await maqx.grantSeed(user.address);
    const burnAmount = parseEther("0.1");
    // Simulates an off-chain burn — this does NOT reduce user's MAQX balance
    await maqx.connect(user).act({ value: burnAmount });

    // Fast-forward 24 hours (regenInterval)
    await network.provider.send("evm_increaseTime", [86400]);
    await network.provider.send("evm_mine");

    const bal = await maqx.balanceOf(user.address);
    const lockedBal = await maqx.lockedBalance(user.address);
    console.log("DEBUG: should allow user to regen pending actions via regenMyPending() - Before regenMyPending");
    console.log("  total =", bal.toString());
    console.log("  locked =", lockedBal.toString());
    console.log("  unlocked =", (bal - lockedBal).toString());

    await expect(maqx.connect(user).regenMyPending()).to.not.be.reverted;
  });
  // it("should cap seed-based regen at 1 MAQX even if user burns more", async () => {
  //   await maqx.grantSeed(user.address);
  //
  //   // Simulates an off-chain burn on behalf of user — MAQX balance remains unchanged
  //   await maqx.connect(owner).actFor(user.address, parseEther("1"));
  //   // Simulates an off-chain burn on behalf of user — MAQX balance remains unchanged
  //   await maqx.connect(owner).actFor(user.address, parseEther("1"));
  //
  //   // Fast forward to regen eligibility
  //   await network.provider.send("evm_increaseTime", [86400]);
  //   await network.provider.send("evm_mine");
  //
  //   // Attempt to regen
  //   await maqx.connect(owner).regenMint(user.address, parseEther("2"));
  //
  //   // Verify user only received 1 MAQX from seed regen
  //   const locked = await maqx.lockedBalance(user.address);
  //   expect(locked).to.equal(parseEther("1"));
  // });
});