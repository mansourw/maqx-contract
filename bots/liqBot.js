// liqBot.js
// Monitors Uniswap LP and injects MAQX when price spikes due to large buys
// Strategy: dampen upward spikes by injecting just enough MAQX to slow price climb

const { ethers } = require("ethers");
require("dotenv").config();

// ---- CONFIG ----
const MAQX_ADDRESS = process.env.MAQX_TOKEN;
const UNISWAP_PAIR_ADDRESS = process.env.UNISWAP_PAIR;
const GLOBAL_WALLET_PRIVATE_KEY = process.env.GLOBAL_WALLET_PK;
const RPC_URL = process.env.RPC_URL; // Infura/Alchemy
const DAMPENING_THRESHOLD = 1.03; // Trigger if price rises more than 3%

// ---- SETUP ----
const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(GLOBAL_WALLET_PRIVATE_KEY, provider);

// UniswapV2Pair ABI snippet to fetch reserves
const UNISWAP_PAIR_ABI = [
  "function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)",
  "function token0() view returns (address)",
  "function token1() view returns (address)"
];

// ---- CORE FUNCTION ----
async function monitorAndInject() {
  const pair = new ethers.Contract(UNISWAP_PAIR_ADDRESS, UNISWAP_PAIR_ABI, provider);

  const [reserve0, reserve1] = await pair.getReserves();
  const token0 = await pair.token0();
  const token1 = await pair.token1();

  // Determine which reserve is MAQX
  const isMAQXToken0 = token0.toLowerCase() === MAQX_ADDRESS.toLowerCase();
  const maqxReserve = isMAQXToken0 ? reserve0 : reserve1;
  const otherReserve = isMAQXToken0 ? reserve1 : reserve0;

  const priceBefore = otherReserve / maqxReserve;

  // PATCH: Track previous reserves for delta computation
  const prevReserves = { maqx: maqxReserve, other: otherReserve };
  await new Promise(resolve => setTimeout(resolve, 3000)); // wait 3s to observe potential spike
  const [newReserve0, newReserve1] = await pair.getReserves();
  const newMaqxReserveLive = isMAQXToken0 ? newReserve0 : newReserve1;
  const newOtherReserveLive = isMAQXToken0 ? newReserve1 : newReserve0;
  const priceAfter = newOtherReserveLive / newMaqxReserveLive;

  // const assumedBuyEth = 1; // 1 ETH bought worth of MAQX (example)  // removed as per instructions

  const newMaqxReserve = newMaqxReserveLive;

  const increaseFactor = priceAfter / priceBefore;
  const deltaMAQX = prevReserves.maqx - newMaqxReserveLive;

  if (increaseFactor >= DAMPENING_THRESHOLD) {
    // Adaptive dampening: stronger reaction for larger spikes
    const dampeningFactor = Math.min(0.3, 0.1 + (increaseFactor - 1) * 2); // 10–30%

    const targetPrice = priceBefore + dampeningFactor * (priceAfter - priceBefore);
    const targetMaqxReserve = otherReserve / targetPrice;
    const maqxToInject = targetMaqxReserve - maqxReserve;
    // 3-phase multiplier system for injection
    let INJECTION_MULTIPLIER;
    if (maqxReserve < 500_000_000) {
      INJECTION_MULTIPLIER = 3.0; // Phase 1
    } else if (maqxReserve < 1_000_000_000) {
      INJECTION_MULTIPLIER = 2.0; // Phase 2
    } else if (maqxReserve < 1_500_000_000) {
      INJECTION_MULTIPLIER = 1.0; // Phase 3
    } else {
      INJECTION_MULTIPLIER = 0.0; // Beyond phase range, do not inject
    }
    const maxReplenish = deltaMAQX * INJECTION_MULTIPLIER;
    const safeInject = Math.min(maqxToInject, maxReplenish);

    console.log(`Spike detected: price moved from ${priceBefore.toFixed(4)} to ${priceAfter.toFixed(4)}.`);
    console.log(`Injecting ${safeInject.toFixed(4)} MAQX to target price ${targetPrice.toFixed(4)}.`);
    console.log(`Bot Injection Ratio: ${safeInject.toFixed(4)} / ${deltaMAQX.toFixed(4)} = ${(safeInject / deltaMAQX).toFixed(2)}x`);
    if (maqxToInject > maxReplenish) {
      console.log(`Injection clipped: desired ${maqxToInject.toFixed(4)} MAQX exceeds safe cap of ${maxReplenish.toFixed(4)}.`);
    }

    // --- TODO ---
    // Add MAQX to LP using router (addLiquidity)
    // Requires token approval and Uniswap interaction
  } else {
    console.log("No spike detected.");
    console.log(`Price change within threshold: ${increaseFactor.toFixed(4)}x`);
  }
}

// ---- RUN LOOP ----
monitorAndInject().catch(console.error);