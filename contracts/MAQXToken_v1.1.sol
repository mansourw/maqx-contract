// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract MAQXToken is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, OwnableUpgradeable {
    // Version: 1.1

    event RMRTierChanged(address indexed user, uint256 newTier);
    event TierRewardClaimed(address indexed user, uint8 tier);
    event TierRewardAmountChanged(uint256 indexed tier, uint256 amount);
    event EventRegenMint(address indexed user, uint256 baseAmount, uint256 finalAmount);
    // Event multiplier for event-based minting (basis points, 10000 = 1.0x)
    uint256 public eventMultiplier = 10000; // 10000 = 1.0x

    struct RMRConfig {
        uint256 minDuration; // in days
        uint256 multiplier;  // in percent
    }

    uint256 public constant INITIAL_SUPPLY = 8_500_000_000 * 1e18;
    uint256 public constant FOUNDER_POOL = 85_000_000 * 1e18;
    uint256 public constant DEV_POOL = 85_000_000 * 1e18;
    uint256 public constant MAX_SEED_REGEN = 1e18;

    // New action burn configuration parameters
    uint256 public burnToSeedAmount = 0.1 ether;
    uint256 public burnToWitnessAmount = 0.01 ether;
    uint256 public burnToVerifyAmount = 0.1 ether;

    /// burnToContractAmount: reference parameter for contract-based actions (not yet active in logic)
    uint256 public burnToContractAmount = 0.1 ether;

    /// burnToActAmount and burnToCommitAmount mirror burnToSeedAmount
    /// Used only for tracking or UI display purposes — no distinct logic
    uint256 public burnToActAmount = 0.1 ether;
    uint256 public burnToCommitAmount = 0.1 ether;
    uint256 public minWitnesses = 2;
    uint256 public minVerifiers = 1;

    address public globalMintWallet;
    address public founderWallet;
    address public developerPoolWallet;
    address public daoTreasuryWallet;

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
    uint256 public regenInterval = 1 days;
    uint256 public lastRegenTimestamp;
    uint256 public regenThreshold = 0.2 ether;
    // Bonus multiplier for event-based regen (in percent, e.g. 10 = 10%)
    uint256 public eventRMRBonus = 10; // Default: +10% bonus on event regen

    mapping(address => uint256) public lockedBalance;
    mapping(address => uint256) public lockedUntil;
    mapping(address => bool) public isDevTokenOrigin;

    uint256 public regenCapPercent;
    uint256 public userRegenShare;
    uint256 public daoRegenShare;
    uint256 public founderRegenShare;
    uint256 public regenDecayShare; // % of burned MAQX that disappears (0 = no decay)

    uint256 public maxSeedRegens;

    mapping(address => uint256) public giftedBalance;
    mapping(address => uint256) public giftRewardQuota;
    mapping(address => uint256) public lastGiftTimestamp;

    // Added variables for RMR logic
    uint256[] public rmrDurations = [0, 30 days, 90 days, 180 days, 270 days, 365 days];
    uint256[] public rmrBonuses = [0, 5, 10, 15, 20, 25];
    uint256[] public rmrMinBalances = [0, 4 ether, 12 ether, 30 ether, 60 ether, 100 ether];
    mapping(address => uint256) public rmrStartTime;
    mapping(address => uint8) public lastClaimedTier;
    mapping(uint256 => uint256) public tierRewards;

    event RegenExecuted(address indexed user, uint256 totalRegen, uint256 userShare, uint256 daoShare, uint256 founderShare);
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

    function _updateRMRTier(address user) internal {
        if (rmrStartTime[user] == 0) {
            rmrStartTime[user] = block.timestamp;
        }
        uint256 heldDuration = (block.timestamp - rmrStartTime[user]) / 1 days;
        uint256 newTier = rmrTier[user];
        for (uint256 i = 5; i >= 1; i--) {
            if (heldDuration >= rmrTiers[i].minDuration) {
                newTier = i;
                break;
            }
        }
        if (newTier != rmrTier[user]) {
            rmrTier[user] = newTier;
            emit RMRTierChanged(user, newTier);
        }
    }

    // Updated getRMRMultiplier function to compute tier automatically
    function getRMRMultiplier(address user) public view returns (uint256) {
        uint256 userBalance = balanceOf(user);
        uint256 heldTime = block.timestamp - rmrStartTime[user];

        for (uint256 i = rmrDurations.length - 1; i > 0; i--) {
            if (heldTime >= rmrDurations[i] && userBalance >= rmrMinBalances[i]) {
                return rmrBonuses[i];
            }
        }
        return rmrBonuses[0];
    }

    function setRMRTierConfig(uint256 tier, uint256 minDurationDays, uint256 multiplier) external onlyOwner {
        require(tier >= 1 && tier <= 5, "Tier must be 1–5");
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
                emit TierRewardClaimed(msg.sender, tier, reward);
            }
        }

        lastClaimedTier[msg.sender] = uint8(currentTier);
    }
    function setTierReward(uint256 tier, uint256 amount) external onlyOwner {
        tierRewards[tier] = amount;
        emit TierRewardAmountChanged(tier, amount);
    }

    function initialize(
        address _globalMintWallet,
        address _founderWallet,
        address _developerPoolWallet,
        address _daoTreasuryWallet
    ) public initializer {
        __ERC20_init("MAQX", "MAQX");
        __ERC20Burnable_init();
        __Ownable_init(msg.sender);

        globalMintWallet = _globalMintWallet;
        founderWallet = _founderWallet;
        developerPoolWallet = _developerPoolWallet;
        daoTreasuryWallet = _daoTreasuryWallet;

        _mint(globalMintWallet, INITIAL_SUPPLY);
        _mint(founderWallet, FOUNDER_POOL);
        _mint(developerPoolWallet, DEV_POOL);

        regenCapPercent = 60;
        userRegenShare = 80;
        daoRegenShare = 10;
        founderRegenShare = 10;
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
    }

    function grantSeed(address user) external onlyOwner {
        require(!hasReceivedSeed[user], "Seed already granted");
        hasReceivedSeed[user] = true;
        _transfer(globalMintWallet, user, 1e18);
        rmrStartTime[user] = block.timestamp;
        emit SeedGranted(user);
    }

    function grantEarlyAdoptionToken(address to, uint256 amount) external onlyOwner {
        _transfer(developerPoolWallet, to, amount);
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

        if (hasReceivedSeed[user] && seedRegenerated[user] < maxSeedRegens * 1e18) {
            seedBurned[user] += amountBurned;
            uint256 remaining = (maxSeedRegens * 1e18) - seedRegenerated[user];
            uint256 toRegen = seedBurned[user] > remaining ? remaining : seedBurned[user];
            seedBurned[user] -= toRegen;
            seedRegenerated[user] += toRegen;
            _mint(user, toRegen);
            return;
        }

        uint256 baseUserAmt = (regenAmount * 50) / 100;
        uint256 rmrBonus = (baseUserAmt * getRMRMultiplier(user)) / 100;
        uint256 userAmt = baseUserAmt + rmrBonus;
        uint256 daoAmt = (regenAmount * 10) / 100;
        uint256 founderAmt = (regenAmount * 10) / 100;
        uint256 globalAmt = regenAmount - userAmt - daoAmt - founderAmt;

        _mint(user, userAmt);
        _mint(daoTreasuryWallet, daoAmt);
        _mint(founderWallet, founderAmt);
        _mint(globalMintWallet, globalAmt);

        emit RegenExecuted(user, amountBurned, userAmt, daoAmt, founderAmt);
    }

    function updateWallets(address _dev, address _founder, address _dao) external onlyOwner {
        developerPoolWallet = _dev;
        founderWallet = _founder;
        daoTreasuryWallet = _dao;
    }

    function updateRegenShares(uint256 userShare, uint256 daoShare, uint256 founderShare) external onlyOwner {
        require(userShare + daoShare + founderShare == 100, "Invalid shares");
        userRegenShare = userShare;
        daoRegenShare = daoShare;
        founderRegenShare = founderShare;
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

    /**
     * @dev Batch mint regen for all users with pending amounts (normal and event).
     * Applies different RMR multipliers for normal and event pools.
     * Can only be called once per regenInterval.
     */
    function regenAllEligible() external onlyOwner onlyAfterRegenInterval {
        for (uint256 i = 0; i < regenUserList.length; i++) {
            address user = regenUserList[i];
            uint256 normalAmt = pendingRegen[user];
            uint256 eventAmt = pendingEventRegen[user];
            uint256 totalBurned = normalAmt + eventAmt;
            if (totalBurned == 0) continue;

            _updateRMRTier(user);

            // Apply decay to the combined total
            uint256 decayedAmt = (totalBurned * regenDecayShare) / 100;
            uint256 regenAmount = totalBurned - decayedAmt;

            // If user is in seed mode, handle legacy regen (does not use event pool logic)
            if (hasReceivedSeed[user] && seedRegenerated[user] < maxSeedRegens * 1e18) {
                seedBurned[user] += totalBurned;
                uint256 remaining = (maxSeedRegens * 1e18) - seedRegenerated[user];
                uint256 toRegen = seedBurned[user] > remaining ? remaining : seedBurned[user];
                seedBurned[user] -= toRegen;
                seedRegenerated[user] += toRegen;
                _mint(user, toRegen);
            } else {
                // Compute user shares with different multipliers for normal/event
                // 50% of each pool is base, then apply RMR bonus (normal) and eventRMRBonus (event)
                uint256 baseNormal = (normalAmt * 50) / 100;
                uint256 normalBonus = (baseNormal * getRMRMultiplier(user)) / 100;
                uint256 baseEvent = (eventAmt * 50) / 100;
                uint256 eventBonus = (baseEvent * eventRMRBonus) / 100;
                uint256 userAmt = baseNormal + normalBonus + baseEvent + eventBonus;

                // DAO / Founder / Global shares from full decayed regenAmount
                uint256 daoAmt = (regenAmount * 10) / 100;
                uint256 founderAmt = (regenAmount * 10) / 100;
                uint256 globalAmt = regenAmount - userAmt - daoAmt - founderAmt;

                _mint(user, userAmt);
                _mint(daoTreasuryWallet, daoAmt);
                _mint(founderWallet, founderAmt);
                _mint(globalMintWallet, globalAmt);

                emit RegenExecuted(user, totalBurned, userAmt, daoAmt, founderAmt);
            }
            // Clear both pools and user flag
            pendingRegen[user] = 0;
            pendingEventRegen[user] = 0;
            regenUsers[user] = false;
        }
        delete regenUserList;
        lastRegenTimestamp = block.timestamp;
    }

    function transferWithOptionalLock(address to, uint256 amount, bool lock, uint256 lockDurationDays) external {
        _transfer(msg.sender, to, amount);
        if (lock && lockDurationDays > 0) {
            lockedUntil[to] = block.timestamp + (lockDurationDays * 1 days);
        }
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0)) {
            require(
                balanceOf(from) - lockedBalance[from] >= value &&
                block.timestamp >= lockedUntil[from],
                "Attempting to transfer locked or time-locked tokens"
            );
        }
        super._update(from, to, value);

        uint256 newBalance = balanceOf(to);
        uint256 currentTier = getRMRMultiplier(to);

        if (newBalance < rmrMinBalances[currentTier]) {
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
    function act() external {
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
    function mintForPopulationIncrease(uint256 totalAmount) external onlyOwner {
        require(totalAmount > 0, "Invalid mint amount");

        uint256 founderBonus = (totalAmount * 1) / 100;
        uint256 devBonus = (totalAmount * 1) / 100;
        uint256 totalToMint = totalAmount + founderBonus + devBonus;

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
    function mintFounderEmergency(uint256 totalAmount) external onlyOwner {
        require(totalAmount > 0, "Invalid mint amount");

        uint256 founderBonus = (totalAmount * 1) / 100;
        uint256 devBonus = (totalAmount * 1) / 100;
        uint256 totalToMint = totalAmount + founderBonus + devBonus;

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
}

    /**
     * @notice Sets the event multiplier (in basis points, e.g. 15000 = 1.5x).
     * Only callable by the contract owner (founder).
     */
    function setEventMultiplier(uint256 newMultiplier) external onlyOwner {
        eventMultiplier = newMultiplier;
    }

    // eventRegenMint moved and refactored above for batch logic