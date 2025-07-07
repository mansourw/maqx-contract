// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// For debugging output
import "hardhat/console.sol";

interface IZKRegenVerifier {
    function verifyProof(bytes calldata proof, address[] calldata users, uint256[] calldata amounts) external view returns (bool);
}

/**
 * @title MAQXToken
 * @dev Upgradeable ERC20 token with advanced regen and community logic.
 * Inherits OpenZeppelin Initializable, OwnableUpgradeable, UUPSUpgradeable for upgradeability and ownership.
 */
contract MAQXToken is 
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    /**
     * @notice DEX LP pair address for trading and liquidity management.
     */
    address public pair;

    event RegenMinted(
        address indexed user,
        uint256 userAmt,
        uint256 daoAmt,
        uint256 devAmt,
        uint256 founderAmt,
        uint256 pledgeAmt,
        uint256 globalAmt
    );
    // Version: 1.1

    address public founder;
    modifier onlyFounder() {
        require(msg.sender == founder, "Only founder can call this function");
        _;
    }

    // RMR Regen batching/interval logic
    uint256 public rmrInterval; // Regen interval (set extern)
    mapping(address => uint256) public lastRegen; // Last regen time per user
    address[] public eligibleUsers; // List of users eligible for regen

    // Global transfer cooldown logic
    mapping(address => uint256) private _lastTransferTimestamp;
    uint256 public transferDelay;
    mapping(address => bool) private _isExcludedFromLimits;
    uint256 public globalCooldownTime;
    uint256 public maxSellPercent;
    mapping(address => bool) public isExcludedFromLimit;

    /// @notice The zkVerifier contract address (public getter).
    IZKRegenVerifier public zkVerifier;

    // Tracks submitted ZK proof hashes to prevent re-use
    mapping(bytes32 => bool) public usedZKProofs;

    event RMRTierChanged(address indexed user, uint256 newTier);
    event TierRewardClaimed(address indexed user, uint8 tier, uint256 amount);
    event TierRewardAmountChanged(uint256 indexed tier, uint256 amount);
    event EventRegenMint(address indexed user, uint256 baseAmount, uint256 finalAmount);
    // Event multiplier for event-based minting (basis points, 10000 = 1.0x)
    uint256 public eventMultiplier;

    address public pledgeFundWallet;
    uint256 public pledgeRegenShare;

    struct RMRConfig {
        uint256 minDuration; // in days
        uint256 multiplier;  // in percent
    }

    uint256 public constant INITIAL_SUPPLY = 8_500_000_000 * 1e18;
    uint256 public constant FOUNDER_POOL = 85_000_000 * 1e18;
    uint256 public constant DEV_POOL = 85_000_000 * 1e18;
    uint256 public constant MAX_SEED_REGEN = 1e18;

    // New action burn configuration parameters
    uint256 public burnToSeedAmount;
    uint256 public burnToWitnessAmount;
    uint256 public burnToVerifyAmount;

    /// burnToContractAmount: reference parameter for contract-based actions (not yet active in logic)
    uint256 public burnToContractAmount;

    /// burnToActAmount and burnToCommitAmount mirror burnToSeedAmount
    /// Used only for tracking or UI display purposes — no distinct logic
    uint256 public burnToActAmount;
    uint256 public burnToCommitAmount;
    uint256 public minWitnesses;
    uint256 public minVerifiers;

    address public globalMintWallet;
    address public founderWallet;
    address public developerPoolWallet;
    address public daoTreasuryWallet;
    address public zkDistributionWallet;
    mapping(address => uint256) public claimableZKRegen;

    mapping(address => bool) public hasReceivedSeed;
    mapping(address => uint256) public seedBurned;
    mapping(address => uint256) public seedRegenerated;

    // ─────────────────────────────────────────────────────────────
    // OPTION D: FUTURE AUTOMATED REGEN LOGIC (not yet active)
    // These mappings and thresholds enable automatic regenMint()
    // via an off-chain relayer or DAO trigger system.
    //
    // Use Case:
    // - When totalBurnedByUser exceeds regenThreshold,
    //   the system may auto-mint regen MAQX via regenAllEligible()
    //
    // Implementation Required:
    // - Off-chain relayer (e.g. backend or DAO bot) to track eligible users
    // - Relayer calls regenAllEligible() periodically
    // - Full integration not implemented yet
    // ─────────────────────────────────────────────────────────────
    mapping(address => uint256) public totalBurnedByUser;
    mapping(address => uint256) public pendingRegen; // Normal regen pool (from action burns)
    mapping(address => uint256) public pendingEventRegen; // Event regen pool (from eventRegenMint)
    // Regen batching tracking
    mapping(address => bool) private regenUsers;
    address[] private regenUserList;
    uint256 public regenInterval;
    uint256 public lastRegenTimestamp;
    uint256 public regenThreshold;
    // Per-user regen cooldown tracking
    mapping(address => uint256) public lastUserRegen;
    // Bonus multiplier for event-based regen (in percent, e.g. 10 = 10%)
    uint256 public eventRMRBonus;

    mapping(address => uint256) public lockedBalance;
    mapping(address => uint256) public lockedUntil;
    mapping(address => bool) public isDevTokenOrigin;

    uint256 public regenCapPercent;
    uint256 public userRegenShare;
    uint256 public daoRegenShare;
    uint256 public founderRegenShare;
    uint256 public devRegenShare;
    uint256 public regenDecayShare; // % of burned MAQX that disappears (0 = no decay)

    uint256 public maxSeedRegens;

    // Tracks pledge amount that is derived from seed-locked users (lockedBalance > 0)
    uint256 public pledgeFromSeedDerived;

    mapping(address => uint256) public giftedBalance;
    mapping(address => uint256) public giftRewardQuota;
    mapping(address => uint256) public lastGiftTimestamp;

    // ─────────────────────────────────────────────────────────────

    // Added variables for RMR logic
    uint256[] public rmrDurations;
    uint256[] public rmrBonuses;
    uint256[] public rmrMinBalances;
    mapping(address => uint256) public rmrStartTime;
    mapping(address => uint8) public lastClaimedTier;
    mapping(uint256 => uint256) public tierRewards;

    event RegenExecuted(address indexed user, uint256 totalRegen, uint256 userShare, uint256 daoShare, uint256 founderShare, uint256 devShare, uint256 pledgeShare);
    event SeedGranted(address indexed user);
    event GrantLockedDevToken(address indexed to, uint256 amount);
    event LockedTokensUnlocked(address indexed user);
    event Gifted(address indexed from, address indexed to, uint256 amount, uint256 reward);

    // New event for action burns
    event ActionBurned(address indexed user, string actionType, uint256 amount);

    event PopulationIncreaseMint(address indexed by, uint256 amount, uint256 founderBonus, uint256 devBonus);
    event FounderEmergencyMint(address indexed by, uint256 amount, uint256 founderBonus, uint256 devBonus);

    event CommitMade(address indexed user, string commitment);

    // RMR logic
    RMRConfig[6] public rmrTiers;
    mapping(address => uint256) public rmrTier;

    modifier rmrEligible(address user) {
        require(block.timestamp >= lastRegen[user] + rmrInterval, "RMR: interval not met");
        _;
    }

    function _updateRMRTier(address user) internal {
        if (rmrStartTime[user] == 0) {
            rmrStartTime[user] = block.timestamp;
        }
        uint256 heldDuration = (block.timestamp - rmrStartTime[user]) / 1 days;
        uint256 newTier = rmrTier[user];
        for (uint256 i = 5; i >= 1; ) {
            if (heldDuration >= rmrTiers[i].minDuration) {
                newTier = i;
                break;
            }
            unchecked {
                i--;
            }
        }
        if (newTier != rmrTier[user]) {
            rmrTier[user] = newTier;
            emit RMRTierChanged(user, newTier);
        }
    }

    // Updated getRMRMultiplier function with safety guard to prevent out-of-bounds errors
    function getRMRMultiplier(address user) public view returns (uint256) {
        uint256 len = rmrDurations.length;
        if (len == 0 || rmrBonuses.length != len || rmrMinBalances.length != len) {
            return 0;
        }
        uint256 userBalance = balanceOf(user);
        uint256 heldTime = block.timestamp - rmrStartTime[user];

        unchecked {
            for (uint256 i = len - 1; i > 0; i--) {
                if (heldTime >= rmrDurations[i] && userBalance >= rmrMinBalances[i]) {
                    return rmrBonuses[i];
                }
            }
        }
        return rmrBonuses[0];
    }

    function setRMRTierConfig(uint256 tier, uint256 minDurationDays, uint256 multiplier) external onlyOwner {
        require(tier >= 1 && tier <= 5, "Tier must be 1-5");
        require(multiplier <= 25, "Max multiplier is 25%");
        rmrTiers[tier] = RMRConfig(minDurationDays, multiplier);
    }

    function claimTierReward() external {
        uint256 currentTier = rmrTier[msg.sender];
        require(currentTier > lastClaimedTier[msg.sender], "Already claimed or no new tier");

        for (uint256 tier = lastClaimedTier[msg.sender] + 1; tier <= currentTier; tier++) {
            uint256 reward = tierRewards[tier];
            if (reward > 0) {
                _transfer(globalMintWallet, msg.sender, reward);
                emit TierRewardClaimed(msg.sender, uint8(tier), reward);
            }
        }

        lastClaimedTier[msg.sender] = uint8(currentTier);
    }
    function setTierReward(uint256 tier, uint256 amount) external onlyOwner {
        tierRewards[tier] = amount;
        emit TierRewardAmountChanged(tier, amount);
    }

    /**
     * @dev Initializes the upgradeable contract, including ownership and UUPS modules.
     */
    function initialize(
        address _globalMintWallet,
        address _founderWallet,
        address _developerPoolWallet,
        address _daoTreasuryWallet
    ) public initializer {
        __ERC20_init("MAQX", "MAQX");
        __ERC20Burnable_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        founder = msg.sender;
        globalMintWallet = _globalMintWallet;
        founderWallet = _founderWallet;
        developerPoolWallet = _developerPoolWallet;
        daoTreasuryWallet = _daoTreasuryWallet;

        _mint(globalMintWallet, INITIAL_SUPPLY);
        _mint(founderWallet, FOUNDER_POOL);
        _mint(developerPoolWallet, DEV_POOL);

        regenCapPercent = 60;
        userRegenShare = 50;
        daoRegenShare = 4;
        founderRegenShare = 4;
        devRegenShare = 2;
        maxSeedRegens = 1; // Default: allow 1 full regen for seed token
        regenDecayShare = 0;

        rmrTiers[0] = RMRConfig(0, 0);
        rmrTiers[1] = RMRConfig(30, 5);
        rmrTiers[2] = RMRConfig(90, 10);
        rmrTiers[3] = RMRConfig(180, 15);
        rmrTiers[4] = RMRConfig(270, 20);
        rmrTiers[5] = RMRConfig(365, 25);

        // Initialize tier rewards
        tierRewards[1] = 1e18;
        tierRewards[2] = 1e18;
        tierRewards[3] = 1e18;
        tierRewards[4] = 1e18;
        tierRewards[5] = 1e18;

        // Set configurable parameters previously initialized at declaration
        eventMultiplier = 10000;
        burnToSeedAmount = 0.1 ether;
        burnToWitnessAmount = 0.01 ether;
        burnToVerifyAmount = 0.1 ether;
        burnToContractAmount = 0.1 ether;
        burnToActAmount = 0.1 ether;
        burnToCommitAmount = 0.1 ether;
        minWitnesses = 2;
        minVerifiers = 1;
        regenInterval = 1 days;
        regenThreshold = 0.2 ether;
        eventRMRBonus = 10;
        rmrDurations = [0, 30 days, 90 days, 180 days, 270 days, 365 days];
        rmrBonuses = [0, 5, 10, 15, 20, 25];
        rmrMinBalances = [0, 4 ether, 12 ether, 30 ether, 60 ether, 100 ether];

        pledgeFundWallet = 0x95Bc0be1892c9B040880A90D4Ef94BD33BCFAEe2;
        pledgeRegenShare = 10;
        zkDistributionWallet = 0x5543332C405A3Cbbf7EeeAe91b410FD06213135b;

        // Initialize sellCooldown to 72 hours (was previously 48 hours)
        sellCooldown = 72 hours;

        // Exclude deployer and Global Mint Wallet from LP sell limit
        isExcludedFromLimit[msg.sender] = true;
        isExcludedFromLimit[0xa321c7F2F64e4Ca75C72Ce4Cd79De2bd19eec0CD] = true;

        // Exclude founder and global mint wallet from global transfer cooldown
        _isExcludedFromLimits[owner()] = true;
        _isExcludedFromLimits[globalMintWallet] = true;

        // Assign values for variables
        transferDelay = 5 minutes;
        globalCooldownTime = 300;
        maxSellPercent = 10;
    }

    /**
     * @notice Set the LP pair address for DEX liquidity.
     * Only the contract owner can set this.
     * @param _pair The LP pair address.
     */
    function setPair(address _pair) external onlyOwner {
        pair = _pair;
    }

    /**
     * @dev Authorize contract upgrades. Only the owner can upgrade.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function grantSeed(address user) external onlyOwner {
        require(!hasReceivedSeed[user], "Seed already granted");
        hasReceivedSeed[user] = true;
        _transfer(globalMintWallet, user, 1e18);
        // lockedBalance[user] += 1e18; // Removed to prevent premature locking of the seed
        rmrStartTime[user] = block.timestamp;
        emit SeedGranted(user);
    }

    function grantEarlyAdoptionToken(address to, uint256 amount) external onlyOwner {
        _transfer(developerPoolWallet, to, amount);
    }

    function setMaxSellPercent(uint256 _percent) external onlyOwner {
        maxSellPercent = _percent;
    }

    function setExcludedFromLimit(address account, bool excluded) external onlyOwner {
        isExcludedFromLimit[account] = excluded;
    }

    function grantLockedDevToken(address to, uint256 amount) external onlyOwner {
        _transfer(developerPoolWallet, to, amount);
        lockedBalance[to] += amount;
        isDevTokenOrigin[to] = true;
        emit GrantLockedDevToken(to, amount);
    }

    function unlockAndClearDevTokens(address user) external onlyOwner {
        lockedBalance[user] = 0;
        isDevTokenOrigin[user] = false;
        emit LockedTokensUnlocked(user);
    }

    function regenMint(address user, uint256 amountBurned) external onlyOwner {
        require(amountBurned > 0, "Invalid amount");

        _updateRMRTier(user);

        uint256 decayedAmt = (amountBurned * regenDecayShare) / 100;
        uint256 regenAmount = amountBurned - decayedAmt;

        // Debug: Output regen computation info
        console.log("REGEN_DEBUG");
        console.log("user", user);
        console.log("burned", amountBurned);
        console.log("seedBurned", seedBurned[user]);
        console.log("seedRegenerated", seedRegenerated[user]);
        console.log("regenAmount", regenAmount);

        if (hasReceivedSeed[user] && seedRegenerated[user] < maxSeedRegens * 1e18) {
            seedBurned[user] += amountBurned;
            uint256 remaining = (maxSeedRegens * 1e18) - seedRegenerated[user];
            uint256 toRegen = seedBurned[user] > remaining ? remaining : seedBurned[user];
            seedBurned[user] -= toRegen;
            seedRegenerated[user] += toRegen;
            _mint(user, toRegen);
            lockedBalance[user] += toRegen;
            // DEBUG: seed-only mint
            console.log("DEBUG: seed-only mint %s to %s", toRegen, user);
            return;
        }

        uint256 baseUserAmt = (regenAmount * 50) / 100;
        uint256 rmrBonus = (baseUserAmt * getRMRMultiplier(user)) / 100;
        uint256 userAmt = baseUserAmt + rmrBonus;
        uint256 daoAmt = (regenAmount * 4) / 100;
        uint256 founderAmt = (regenAmount * 4) / 100;
        uint256 devAmt = (regenAmount * 2) / 100;
        uint256 pledgeAmt = (regenAmount * pledgeRegenShare) / 100;
        uint256 globalAmt = regenAmount - userAmt - daoAmt - founderAmt - devAmt - pledgeAmt;

        // Debug: Output regen split info
        console.log("REGEN_SPLIT");
        console.log("userAmt", userAmt);
        console.log("daoAmt", daoAmt);
        console.log("founderAmt", founderAmt);
        console.log("devAmt", devAmt);
        console.log("pledgeAmt", pledgeAmt);
        console.log("globalAmt", globalAmt);

        _mint(user, userAmt);
        if (lockedBalance[user] > 0) {
            lockedBalance[user] += userAmt;
        }
        _mint(daoTreasuryWallet, daoAmt);
        _mint(founderWallet, founderAmt);
        _mint(developerPoolWallet, devAmt);
        _mint(pledgeFundWallet, pledgeAmt);
        if (lockedBalance[user] > 0) {
            pledgeFromSeedDerived += pledgeAmt;
        }
        _mint(globalMintWallet, globalAmt);

        emit RegenExecuted(user, amountBurned, userAmt, daoAmt, founderAmt, devAmt, pledgeAmt);
    }

    function updateWallets(address _dev, address _founder, address _dao) external onlyOwner {
        developerPoolWallet = _dev;
        founderWallet = _founder;
        daoTreasuryWallet = _dao;
    }

    function updateRegenShares(uint256 userShare, uint256 daoShare, uint256 founderShare, uint256 devShare, uint256 pledgeShare) external onlyOwner {
        require(userShare + daoShare + founderShare + devShare + pledgeShare == 100, "Invalid shares");
        userRegenShare = userShare;
        daoRegenShare = daoShare;
        founderRegenShare = founderShare;
        devRegenShare = devShare;
        pledgeRegenShare = pledgeShare;
    }

    function updateMaxSeedRegens(uint256 newMax) external onlyOwner {
        maxSeedRegens = newMax;
    }

    function updateRegenDecayShare(uint256 newDecay) external onlyOwner {
        require(newDecay <= 100, "Invalid percentage");
        regenDecayShare = newDecay;
    }

    // Option D: Track pending regen - logic would go inside burn function in full implementation
    function getPendingRegen(address user) external view returns (uint256) {
        return pendingRegen[user];
    }

    // ─────────────────────────────────────────────────────────────
    // Regen batching logic
    modifier onlyAfterRegenInterval() {
        require(block.timestamp >= lastRegenTimestamp + regenInterval, "Regen not yet available");
        _;
    }
    // Per-user regen interval modifier
    modifier onlyUserRegenInterval(address user) {
        require(block.timestamp >= lastUserRegen[user] + regenInterval, "User regen not yet available");
        _;
    }

    /**
     * @dev Internal: accumulate burned amount for regen, track user for batch mint.
     */
    function seedRegenMint(address user, uint256 amountBurned) internal {
        if (amountBurned == 0) return;
        if (!regenUsers[user]) {
            regenUsers[user] = true;
            regenUserList.push(user);
        }
        pendingRegen[user] += amountBurned;
    }

    /**
     * @dev Event-based regen: accumulate for batch instead of minting directly.
     * Uses a separate pendingEventRegen pool.
     */
    function eventRegenMint(address user, uint256 baseAmount) external onlyOwner {
        require(baseAmount > 0, "Invalid amount");
        uint256 finalAmount = (baseAmount * eventMultiplier) / 10000;
        if (!regenUsers[user]) {
            regenUsers[user] = true;
            regenUserList.push(user);
        }
        pendingEventRegen[user] += finalAmount; // Separate event pool
        emit EventRegenMint(user, baseAmount, finalAmount);
    }

    function _handleSeedRegen(address user, uint256 totalBurned) internal {
        seedBurned[user] += totalBurned;
        uint256 remaining = (maxSeedRegens * 1e18) - seedRegenerated[user];
        uint256 toRegen = seedBurned[user] > remaining ? remaining : seedBurned[user];
        seedBurned[user] -= toRegen;
        seedRegenerated[user] += toRegen;
        _mint(user, toRegen);
        lockedBalance[user] += toRegen;
    }

    function _calculateUserReward(address user, uint256 normalAmt, uint256 eventAmt) internal view returns (uint256) {
        uint256 baseNormal = (normalAmt * 50) / 100;
        uint256 normalBonus = (baseNormal * getRMRMultiplier(user)) / 100;
        uint256 baseEvent = (eventAmt * 50) / 100;
        uint256 eventBonus = (baseEvent * eventRMRBonus) / 100;
        return baseNormal + normalBonus + baseEvent + eventBonus;
    }

    function _mintRegenShares(address user, uint256 userAmt, uint256 regenAmount) internal {
        uint256 daoAmt = (regenAmount * 4) / 100;
        uint256 founderAmt = (regenAmount * 4) / 100;
        uint256 devAmt = (regenAmount * 2) / 100;
        uint256 pledgeAmt = (regenAmount * pledgeRegenShare) / 100;
        uint256 globalAmt = regenAmount - userAmt - daoAmt - founderAmt - devAmt - pledgeAmt;

        _mint(user, userAmt);
        if (lockedBalance[user] > 0) {
            lockedBalance[user] += userAmt;
        }
        _mint(daoTreasuryWallet, daoAmt);
        _mint(founderWallet, founderAmt);
        _mint(developerPoolWallet, devAmt);
        _mint(pledgeFundWallet, pledgeAmt);
        if (lockedBalance[user] > 0) {
            pledgeFromSeedDerived += pledgeAmt;
        }
        _mint(globalMintWallet, globalAmt);

        emit RegenExecuted(user, userAmt + daoAmt + founderAmt + devAmt + pledgeAmt + globalAmt, userAmt, daoAmt, founderAmt, devAmt, pledgeAmt);
    }

    function _finalizeRegenBatch(address user) internal {
        pendingRegen[user] = 0;
        pendingEventRegen[user] = 0;
        regenUsers[user] = false;
    }

    /**
     * @dev Allows a user to trigger their own regen if they have pending burns.
     * Enforces per-user cooldown via onlyUserRegenInterval.
     */
    function regenMyPending() external onlyUserRegenInterval(msg.sender) {
        address user = msg.sender;
        uint256 normalAmt = pendingRegen[user];
        uint256 eventAmt = pendingEventRegen[user];
        uint256 totalBurned = normalAmt + eventAmt;
        require(totalBurned > 0, "No pending regen");

        _updateRMRTier(user);

        if (hasReceivedSeed[user] && seedRegenerated[user] < maxSeedRegens * 1e18) {
            _handleSeedRegen(user, totalBurned);
        } else {
            uint256 decayedAmt = (totalBurned * regenDecayShare) / 100;
            uint256 regenAmount = totalBurned - decayedAmt;
            uint256 userAmt = _calculateUserReward(user, normalAmt, eventAmt);
            _mintRegenShares(user, userAmt, regenAmount);
        }

        _finalizeRegenBatch(user);
        lastUserRegen[user] = block.timestamp;
    }

    // _processUserRegen is no longer used by batch logic, but may remain for internal use if needed.

    function transferWithOptionalLock(address to, uint256 amount, bool lock, uint256 lockDurationDays) external {
        _transfer(msg.sender, to, amount);
        if (lock && lockDurationDays > 0) {
            lockedUntil[to] = block.timestamp + (lockDurationDays * 1 days);
        }
    }

    function _update(address from, address to, uint256 value) internal override {
        // ─────────────────────────────────────────────────────────────
        // Global transfer cooldown: enforce delay between transfers unless excluded
        if (from != address(0) && !_isExcludedFromLimits[from]) {
            require(block.timestamp - _lastTransferTimestamp[from] >= globalCooldownTime, "Global cooldown: wait before next transfer");
            _lastTransferTimestamp[from] = block.timestamp;
        }
        // ─────────────────────────────────────────────────────────────
        // SELL COOLDOWN and LP SELL LIMIT: Exclude owner from these rules
        if (from != owner()) {
            if (uniswapV2Pair != address(0)) {
                if (to == uniswapV2Pair && from != address(0)) {
                    require(block.timestamp > lastBuyTimestamp[from] + sellCooldown, "Sell cooldown active");
                    uint256 pairBalance = balanceOf(uniswapV2Pair);
                    uint256 maxSellAmount = (pairBalance * 10) / 100;
                    require(value <= maxSellAmount, "Exceeds max sell amount");
                }
            } else {
                require(uniswapV2Pair != address(0), "Pair not set");
            }
        }

        if (from != address(0)) {
            uint256 unlocked = balanceOf(from) - lockedBalance[from];
            // DEBUG: transfer lock check
            console.log("DEBUG: balance", balanceOf(from));
            console.log("DEBUG: locked", lockedBalance[from]);
            console.log("DEBUG: unlocked", balanceOf(from) - lockedBalance[from]);
            console.log("DEBUG: attempting transfer", value);
            require(value <= unlocked, "Cannot transfer locked tokens");
        }

        super._update(from, to, value);

        // ─────────────────────────────────────────────────────────────
        // If buying from LP, set lastBuyTimestamp
        if (from == uniswapV2Pair && to != address(0)) {
            lastBuyTimestamp[to] = block.timestamp;
        }

        uint256 len = rmrDurations.length;
        if (len == 0 || rmrBonuses.length != len || rmrMinBalances.length != len) {
            return;
        }

        uint256 newBalance = balanceOf(to);
        uint256 currentTier = getRMRMultiplier(to);

        if (currentTier < rmrMinBalances.length && newBalance < rmrMinBalances[currentTier]) {
            rmrStartTime[to] = block.timestamp;
        }
    }



    function gift(address to, uint256 amount) external {
        _transfer(msg.sender, to, amount);

        // Restore quota if a new day has passed
        if (block.timestamp > lastGiftTimestamp[msg.sender] + 1 days) {
            giftRewardQuota[msg.sender] += 10 ether; // 10 MAQX daily cap
            lastGiftTimestamp[msg.sender] = block.timestamp;
        }

        // Reward is 2% of gifted amount
        uint256 reward = (amount * 2) / 100;
        uint256 allowedReward = reward <= giftRewardQuota[msg.sender] ? reward : giftRewardQuota[msg.sender];

        if (allowedReward > 0) {
            _transfer(globalMintWallet, msg.sender, allowedReward);
            giftRewardQuota[msg.sender] -= allowedReward;
        }

        giftedBalance[msg.sender] += amount;
        emit Gifted(msg.sender, to, amount, allowedReward);
    }

    // New functions for action burns with events

    /**
     * @notice Burn tokens to perform a seed action.
     */
    function burnToSeed() external {
        _burn(msg.sender, burnToSeedAmount);
        emit ActionBurned(msg.sender, "burnToSeed", burnToSeedAmount);
    }

    /**
     * @notice Burn tokens to perform an act action.
     */
    function act() external payable {
        _burn(msg.sender, burnToActAmount);
        seedRegenMint(msg.sender, burnToActAmount);
        emit ActionBurned(msg.sender, "act", burnToActAmount);
    }

    /**
     * @notice Burn tokens to perform a contract action.
     */
    function contractAction() external {
        _burn(msg.sender, burnToContractAmount);
        seedRegenMint(msg.sender, burnToContractAmount);
        emit ActionBurned(msg.sender, "contract", burnToContractAmount);
    }

    /**
     * @notice Burn tokens to perform a witness action.
     */
    function witnessAction() external {
        _burn(msg.sender, burnToWitnessAmount);
        seedRegenMint(msg.sender, burnToWitnessAmount);
        emit ActionBurned(msg.sender, "witnessAction", burnToWitnessAmount);
    }

    /**
     * @notice Burn tokens to perform a verify action.
     */
    function verifyAction() external {
        _burn(msg.sender, burnToVerifyAmount);
        seedRegenMint(msg.sender, burnToVerifyAmount);
        emit ActionBurned(msg.sender, "verifyAction", burnToVerifyAmount);
    }

    /**
     * @notice Commit a statement or action, burning tokens and regenerating seed.
     * @param commitment The commitment string.
     */
    function commit(string memory commitment) external {
        require(msg.sender != address(0), "Invalid sender");
        _burn(msg.sender, burnToSeedAmount);
        seedRegenMint(msg.sender, burnToSeedAmount);
        emit CommitMade(msg.sender, commitment);
    }

    /**
     * @notice Mint new MAQX based on verified population increase.
     * @param totalAmount The amount to mint for global allocation.
     * Founder and Dev each get 1% extra on top.
     */
    function mintForPopulationIncrease(uint256 totalAmount) external onlyFounder {
        uint256 founderBonus = (totalAmount * 1) / 100;
        uint256 devBonus = (totalAmount * 1) / 100;

        _mint(globalMintWallet, totalAmount);
        _mint(founderWallet, founderBonus);
        _mint(developerPoolWallet, devBonus);

        emit PopulationIncreaseMint(msg.sender, totalAmount, founderBonus, devBonus);
    }

    /**
     * @notice Emergency minting for liquidity restoration or recovery.
     * @param totalAmount The amount to mint for global allocation.
     * Founder and Dev each get 1% extra on top.
     */
    function mintFounderEmergency(uint256 totalAmount) external onlyFounder {
        uint256 founderBonus = (totalAmount * 1) / 100;
        uint256 devBonus = (totalAmount * 1) / 100;

        _mint(globalMintWallet, totalAmount);
        _mint(founderWallet, founderBonus);
        _mint(developerPoolWallet, devBonus);

        emit FounderEmergencyMint(msg.sender, totalAmount, founderBonus, devBonus);
    }

    // Optional future modules:
    // - zk-witnessing
    // - DAO-controlled upgrades
    // - Population-based minting
    // - Dust mode
    // - Delegated regen authority
    // - LP-based unlock logic
    // - beginMigrationTo(address newChainBridge)

    /// @notice Sends MAQX from the Global Pledge Fund Wallet to a specified recipient.
    /// This allows the founder to fund approved community or impact projects manually.
    function spendFromPledgeFund(address to, uint256 amount, string calldata reason) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        uint256 pledgeBalance = balanceOf(pledgeFundWallet);
        uint256 unlocked = pledgeBalance > pledgeFromSeedDerived ? pledgeBalance - pledgeFromSeedDerived : 0;
        require(unlocked >= amount, "Insufficient unlocked pledge funds");
        _transfer(pledgeFundWallet, to, amount);
        emit PledgeFundSpent(to, amount, reason);
    }

    /// @notice Emitted when MAQX is spent from the Global Pledge Fund Wallet for a cause or project.
    event PledgeFundSpent(address indexed to, uint256 amount, string reason);

    /// @notice Returns the amount of pledge funds that are not derived from locked/seed users and are available to spend.
    function getSpendablePledgeFunds() public view returns (uint256) {
        return balanceOf(pledgeFundWallet) - pledgeFromSeedDerived;
    }
    /**
     * @notice Sets the event multiplier (in basis points, e.g. 15000 = 1.5x).
     * Only callable by the contract owner (founder).
     */
    function setEventMultiplier(uint256 newMultiplier) external onlyOwner {
        eventMultiplier = newMultiplier;
    }

    // eventRegenMint moved and refactored above for batch logic
    /**
     * @notice Sets the ZK regen verifier contract address.
     * Only callable by the contract owner (founder).
     */
    function setZKVerifier(address verifier) external onlyOwner {
        zkVerifier = IZKRegenVerifier(verifier);
    }

    /**
     * @notice ZK-based regen minting (batch): Mints total user share to zkDistributionWallet.
     * Users must later claim their regen using claimZKRegen().
     * Other ecosystem shares (DAO, founder, dev, pledge) are minted directly.
     * @param proof The zk-proof bytes.
     * @param users The list of user addresses to mint to.
     * @param amounts The corresponding regen amounts per user.
     */
    function mintFromZKProof(bytes calldata proof, address[] calldata users, uint256[] calldata amounts) external onlyOwner {
        require(users.length == amounts.length, "Mismatched input lengths");
        require(zkVerifier != IZKRegenVerifier(address(0)), "Verifier not set");

        // Compute hash of proof, users, and amounts to checkpoint against re-use
        bytes32 proofHash = keccak256(abi.encodePacked(proof, users, amounts));
        require(!usedZKProofs[proofHash], "ZK proof already used");
        usedZKProofs[proofHash] = true;

        bool isValid = zkVerifier.verifyProof(proof, users, amounts);
        require(isValid, "Invalid zk proof");

        uint256 totalUserRegen = 0;
        uint256 totalFounderRegen = 0;
        uint256 totalDAORegen = 0;
        uint256 totalDevRegen = 0;
        uint256 totalPledgeRegen = 0;
        uint256 totalGlobalMintRegen = 0;

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 amountBurned = amounts[i];
            require(amountBurned > 0, "Invalid amount");

            _updateRMRTier(user);

            if (hasReceivedSeed[user] && seedRegenerated[user] < maxSeedRegens * 1e18) {
                // Seed user with remaining regen: handle locked minting and update tracking
                _handleSeedRegen(user, amountBurned);
                // For seed users, emit RegenExecuted event with only the amount minted to user (locked), others are zero
                emit RegenExecuted(user, amountBurned, amountBurned, 0, 0, 0, 0);
            } else {
                // Normal user: apply decay, calculate split, accumulate for batch minting
                uint256 decayedAmt = (amountBurned * regenDecayShare) / 100;
                uint256 totalRegenAmount = amountBurned - decayedAmt;

                // 50% to user, with RMR multiplier applied
                uint256 userRegenAmount = (totalRegenAmount * 50) / 100;
                // RMR multiplier: between 5% to 25% (placeholder: not applied yet)
                // uint256 rmrMultiplier = getRMRMultiplier(user); // returns percent (e.g., 5, 10, 15, 20, 25)
                // userRegenAmount = userRegenAmount + (userRegenAmount * rmrMultiplier) / 100;
                // TODO: Apply RMR multiplier to userRegenAmount above if not already handled

                // Accumulate for batch mint to zkDistributionWallet
                claimableZKRegen[user] += userRegenAmount;
                totalUserRegen += userRegenAmount;

                // 4% to founder
                uint256 founderRegenAmount = (totalRegenAmount * 4) / 100;
                totalFounderRegen += founderRegenAmount;
                // 4% to DAO Treasury
                uint256 daoRegenAmount = (totalRegenAmount * 4) / 100;
                totalDAORegen += daoRegenAmount;
                // 2% to Dev Pool
                uint256 devRegenAmount = (totalRegenAmount * 2) / 100;
                totalDevRegen += devRegenAmount;
                // 10% to Global Pledge Fund
                uint256 pledgeRegenAmount = (totalRegenAmount * 10) / 100;
                totalPledgeRegen += pledgeRegenAmount;
                // Remaining to Global Mint Wallet
                uint256 allocated = userRegenAmount + founderRegenAmount + daoRegenAmount + devRegenAmount + pledgeRegenAmount;
                uint256 globalMintRegenAmount = totalRegenAmount > allocated ? totalRegenAmount - allocated : 0;
                totalGlobalMintRegen += globalMintRegenAmount;

                emit RegenExecuted(
                    user,
                    totalRegenAmount,
                    userRegenAmount,
                    daoRegenAmount,
                    founderRegenAmount,
                    devRegenAmount,
                    pledgeRegenAmount
                );
            }

            pendingRegen[user] = 0;
            pendingEventRegen[user] = 0;
            regenUsers[user] = false;
            lastUserRegen[user] = block.timestamp;
        }
        // Mint accumulated shares
        if (totalUserRegen > 0) _mint(zkDistributionWallet, totalUserRegen);
        if (totalFounderRegen > 0) _mint(founderWallet, totalFounderRegen);
        if (totalDAORegen > 0) _mint(daoTreasuryWallet, totalDAORegen);
        if (totalDevRegen > 0) _mint(developerPoolWallet, totalDevRegen);
        if (totalPledgeRegen > 0) _mint(pledgeFundWallet, totalPledgeRegen);
        if (totalGlobalMintRegen > 0) _mint(globalMintWallet, totalGlobalMintRegen);

        lastRegenTimestamp = block.timestamp;
    }

    function claimZKRegen() external {
        uint256 amount = claimableZKRegen[msg.sender];
        require(amount > 0, "No claimable regen");
        claimableZKRegen[msg.sender] = 0;
        _transfer(zkDistributionWallet, msg.sender, amount);
    }
    /**
     * @notice Set the UniswapV2Pair address for LP trading. Only owner can set.
     */
    function setUniswapV2Pair(address _pair) external onlyOwner {
        uniswapV2Pair = _pair;
    }

    /**
     * @notice Set the sell cooldown period (in seconds). Only owner can set.
     */
    function setSellCooldown(uint256 _cooldown) external onlyOwner {
        sellCooldown = _cooldown;
    }

    /// @notice Sets the global cooldown duration between transfers
    /// @param _cooldown New cooldown time in seconds
    function setGlobalCooldownTime(uint256 _cooldown) external onlyOwner {
        globalCooldownTime = _cooldown;
    }
    /// @notice Cooldown period (in seconds) after buying from LP before selling is allowed.
    uint256 public sellCooldown;
    /// @notice Mapping to track the last buy timestamp for each address (from LP).
    mapping(address => uint256) public lastBuyTimestamp;
    /// @notice UniswapV2Pair address for MAQX/ETH (or relevant pair).
    address public uniswapV2Pair;
    // ─────────────────────────────────────────────────────────────
    // Regen cap calculation helper
    /*
    function _calculateRegenCap(address user) internal view returns (uint256) {
        // Placeholder logic for regen cap
        return 1000 ether; // Example cap
    }
    */

    // Regen share calculation helper for batch regen (internal modularization)
    function _calculateRegenShares(address user)
        internal
        view
        returns (
            uint256 daoAmt,
            uint256 devAmt,
            uint256 founderAmt,
            uint256 pledgeAmt,
            uint256 globalAmt
        )
    {
        uint256 regenAmt = pendingRegen[user];
        // uint256 regenCap = _calculateRegenCap(user);
        //
        // if (regenAmt > regenCap) {
        //     regenAmt = regenCap;
        // }

        daoAmt     = (regenAmt * daoRegenShare) / 100;
        devAmt     = (regenAmt * devRegenShare) / 100;
        founderAmt = (regenAmt * founderRegenShare) / 100;
        pledgeAmt  = (regenAmt * pledgeRegenShare) / 100;
        globalAmt  = regenAmt - (daoAmt + devAmt + founderAmt + pledgeAmt);
    }

    function regenAllEligible() external onlyOwner onlyAfterRegenInterval {
        for (uint256 i = 0; i < eligibleUsers.length; i++) {
            address user = eligibleUsers[i];
            (
                uint256 daoAmt,
                uint256 devAmt,
                uint256 founderAmt,
                uint256 pledgeAmt,
                uint256 globalAmt
            ) = _calculateRegenShares(user);
            uint256 regenAmt = pendingRegen[user];
            // uint256 regenCap = _calculateRegenCap(user);
            // if (regenAmt > regenCap) {
            //     regenAmt = regenCap;
            // }
            uint256 userAmt = regenAmt - (daoAmt + devAmt + founderAmt + pledgeAmt + globalAmt);
            if (userAmt > 0) _mint(user, userAmt);
            if (daoAmt > 0) _mint(daoTreasuryWallet, daoAmt);
            if (devAmt > 0) _mint(developerPoolWallet, devAmt);
            if (founderAmt > 0) _mint(founderWallet, founderAmt);
            if (pledgeAmt > 0) _mint(pledgeFundWallet, pledgeAmt);
            if (globalAmt > 0) _mint(globalMintWallet, globalAmt);

            emit RegenMinted(user, userAmt, daoAmt, devAmt, founderAmt, pledgeAmt, globalAmt);

            pendingRegen[user] = 0;
        }

        lastRegenTimestamp = block.timestamp;
    }

}