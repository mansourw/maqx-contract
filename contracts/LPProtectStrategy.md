# MAQX LP Protection Strategy

## ✅ Implemented in Contract

- **Buy Cooldown:** Prevents immediate sell after a buy (48h).
- **Max Sell Amount:** Capped at 10% of total LP per transaction.
- **Global Transfer Cooldown:** 5-minute delay between any transfers from the same wallet.
- **Excluded Addresses:** Founder and Global Mint Wallet are excluded from above limits.

## 🔜 For Future Implementation

- Dynamic LP-based price floor logic.
- Vesting-based sell schedule for large holders.
- Auto-detect and mitigate sandwich attacks / MEV bots.
- DAO-governed cooldowns and caps.

- LP Protection Bot: Monitors price, LP ratio, and volume; can auto-add MAQX liquidity or trigger alerts based on predefined thresholds.

### 🔧 LP Bot Strategy Rules (Draft)

The MAQX LP Bot will follow a conservative liquidity management strategy:

- ✅ Monitor:
  - MAQX/ETH price in LP
  - Total LP depth (MAQX and ETH)
  - Daily and hourly volume changes
  - Slippage on recent swaps

- 🚨 React:
  - Auto-add liquidity if:
    - MAQX price drops more than 5% in an hour
    - LP depth is <50% of weekly average
  - Trigger alerts if:
    - Price impact of any swap >10%
    - Unusual sell patterns detected
  - Optional: Buy back MAQX from LP in crash events

- 🧠 Source:
  - Operates from Global Mint Wallet only
  - LP additions are visible and verifiable
  - DAO may later control parameters

This logic will be implemented in a standalone `liqBot.js` stub.