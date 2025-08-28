// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/ITokenomicEngine.sol";
import "../libraries/YieldCalculations.sol";

/**
 * @title TokenomicEngine
 * @dev Core tokenomics and dynamic yield calculation for ART protocol
 *
 * Features:
 * - Dynamic Yield Amplification (DYA) system
 * - Tiered staking multipliers
 * - Market condition adaptive yields
 * - Protocol health metrics integration
 */
contract TokenomicsEngine is
    ITokenomicEngine,
    Ownable,
    Pausable,
    ReentrancyGuard
{
    using YieldCalculations for uint256;

    // ===== Constants =====

    uint256 public constant BASE_APY = 500; // 5% APY base APY (in basis points)
    uint256 public constant MAX_MULTIPLIER = 300; // 3.0x maximum multiplier
    uint256 public constant BASIS_POINTS = 10000;

    // ===== Structs =====

    struct StakingTier {
        uint256 lockPeriod; // Lock period in seconds
        uint256 multiplier; // Yield multiplier (in basis points, 100 = 1.0x)
        bool active; // Whether the tier is active
    }

    struct MarketCondition {
        uint256 volatilityIndex; // Market volatility (0-10000)
        uint256 tvlGrowthRate; // TVL growth rate (in basis points)
        uint256 timestamp; // Last update timestamp
    }

    struct UserStakeInfo {
        uint256 amount; // Staked amount
        uint256 startTime; // Stake start time
        uint256 tier; // Staking tier
        uint256 lastClaimed; // Last claimed timestamp
    }

    // ===== State Variables =====

    mapping(uint256 => StakingTier) public stakingTiers;
    mapping(address => UserStakeInfo) public userStakes;

    MarketCondition public currentMarketCondition;

    uint256 public totalStaked;
    uint256 public protocolTVL;
    uint256 public lastProtocolUpdate;

    // Dynamic parameters
    uint256 public volatilityThreshold = 2000; // 20% volatility threshold
    uint256 public growthBonus = 150; // 1.5x bonus for high growth
    uint256 public stabilityBonus = 120; // 1.2x bonus for low volatility

    address public masterFarm;

    // ===== Events =====

    event TierAdded(
        uint256 indexed tierId,
        uint256 lockPeriod,
        uint256 multiplier
    );
    event TierUpdated(uint256 indexed tierId, uint256 multiplier, bool active);
    event MarketConditionUpdated(uint256 volatility, uint256 growth);
    event YieldCalculated(
        address indexed user,
        uint256 baseYield,
        uint256 finalYield
    );
    event ParametersUpdated(
        uint256 volatilityThreshold,
        uint256 growthBonus,
        uint256 stabilityBonus
    );

    // ===== Modifiers =====

    modifier onlyMasterFarm() {
        require(
            msg.sender == masterFarm,
            "TokenomicsEngine: caller not master farm"
        );
        _;
    }

    modifier validTier(uint256 tierId) {
        require(
            stakingTiers[tierId].active,
            "TokenomicsEngine: invalid or inactive tier"
        );
        _;
    }

    // ===== Constructor =====

    constructor() {
        _initializeDefaultTiers();
        currentMarketCondition = MarketCondition({
            volatilityIndex: 1000, // 10% default volatility
            tvlGrowthRate: 0,
            timestamp: block.timestamp
        });
    }

    // ===== External Functions =====

    /**
     * @dev Calculate dynamic yield for a user based on multiple factors
     * @param user User address
     * @param baseAmount Base staked amount
     * @return finalYield The calculated yield amount
     */
    function calculateDynamicYield(
        address user,
        uint256 baseAmount
    ) external view override returns (uint256 finalYield) {
        if (baseAmount == 0 || user == address(0)) return 0;

        UserStakeInfo memory userStake = userStakes[user];
        uint256 stakeDuration = block.timestamp - userStake.startTime;

        // Base yield calculation
        uint256 baseYield = baseAmount.calculateYield(BASE_APY, stakeDuration);

        // Apply tier multiplier
        uint256 tierMultiplier = _getTierMultiplier(
            userStake.tier,
            stakeDuration
        );
        uint256 yieldWithTier = (baseYield * tierMultiplier) / BASIS_POINTS;

        // Apply market condition multiplier
        uint256 marketMultiplier = _getMarketMultiplier();
        finalYield = (yieldWithTier * marketMultiplier) / BASIS_POINTS;

        // Apply protocol health bonus
        uint256 protocolBonus = _getProtocolHealthBonus();
        finalYield = (finalYield * protocolBonus) / BASIS_POINTS;

        // Ensure maximum multiplier cap
        uint256 maxYield = (baseYield * MAX_MULTIPLIER) / 100;
        if (finalYield > maxYield) {
            finalYield = maxYield;
        }
    }

    /**
     * @dev Update user staking information
     * @param user User address
     * @param amount New staked amount
     * @param tier Staking tier
     */
    function updateUserStake(
        address user,
        uint256 amount,
        uint256 tier
    ) external override onlyMasterFarm validTier(tier) whenNotPaused {
        require(user != address(0), "TokenomicsEngine: invalid user address");
        UserStakeInfo storage userStake = userStakes[user];

        // Update total staked amount
        totalStaked = totalStaked - userStake.amount + amount;

        userStake.amount = amount;
        userStake.tier = tier;

        // Set start time only for new stakes
        if (userStake.startTime == 0) {
            userStake.startTime = block.timestamp;
        }

        userStake.lastClaimed = block.timestamp;
    }

    /**
     * @dev Update market conditions (called by oracle or admin)
     * @param volatility Market volatility (0-10000)
     * @param growth TVL growth rate in basis points
     */
    function updateMarketConditions(
        uint256 volatility,
        uint256 growth
    ) external onlyOwner whenNotPaused {
        require(
            volatility <= BASIS_POINTS,
            "TokenomicsEngine: invalid volatility"
        );

        currentMarketCondition = MarketCondition({
            volatilityIndex: volatility,
            tvlGrowthRate: growth,
            timestamp: block.timestamp
        });

        emit MarketConditionUpdated(volatility, growth);
    }

    /**
     * @dev Update protocol TVL for health calculations
     * @param newTVL New total value locked
     */
    function updateProtocolTVL(uint256 newTVL) external onlyMasterFarm {
        protocolTVL = newTVL;
        lastProtocolUpdate = block.timestamp;
    }

    // ===== Admin Functions =====

    /**
     * @dev Add new staking tier
     */
    function addStakingTier(
        uint256 tierId,
        uint256 lockPeriod,
        uint256 multiplier
    ) external onlyOwner {
        require(
            multiplier >= 100 && multiplier <= MAX_MULTIPLIER * 100,
            "TokenomicsEngine: invalid multiplier"
        );
        require(
            !stakingTiers[tierId].active,
            "TokenomicsEngine: tier already exists"
        );

        stakingTiers[tierId] = StakingTier({
            lockPeriod: lockPeriod,
            multiplier: multiplier,
            active: true
        });

        emit TierAdded(tierId, lockPeriod, multiplier);
    }

    /**
     * @dev Update existing staking tier
     */
    function updateStakingTier(
        uint256 tierId,
        uint256 multiplier,
        bool active
    ) external onlyOwner {
        require(
            stakingTiers[tierId].lockPeriod > 0,
            "TokenomicsEngine: tier does not exist"
        );
        require(
            multiplier >= 100 && multiplier <= MAX_MULTIPLIER * 100,
            "TokenomicsEngine: invalid multiplier"
        );

        stakingTiers[tierId].multiplier = multiplier;
        stakingTiers[tierId].active = active;

        emit TierUpdated(tierId, multiplier, active);
    }

    /**
     * @dev Update tokenomics parameters
     */
    function updateParameters(
        uint256 _volatilityThreshold,
        uint256 _growthBonus,
        uint256 _stabilityBonus
    ) external onlyOwner {
        require(_growthBonus <= 200, "TokenomicsEngine: growth bonus too high"); // Max 2x bonus
        require(
            _stabilityBonus <= 200,
            "TokenomicsEngine: stability bonus too high"
        ); // Max 2x bonus

        volatilityThreshold = _volatilityThreshold;
        growthBonus = _growthBonus;
        stabilityBonus = _stabilityBonus;

        emit ParametersUpdated(_volatilityThreshold, _growthBonus, _stabilityBonus);
    }

    /**
     * @dev Set master farm contract address 
     */
    function setMasterFarm(address _masterFarm) external onlyOwner {
        require(_masterFarm != address(0), "TokenomicsEngine: invalid master farm");
        masterFarm = _masterFarm; 
    }

    /**
     * @dev Emergency pause 
     */
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();  
    }

    // ===== View Functions =====

    /**
     * @dev Get user's current yield info 
     */
    function getUserYieldInfo(address user)
        external
        view
        returns (
            uint256 currentYield,
            uint256 tierMultiplier,
            uint256 marketMultiplier,
            uint256 timeInTier 
        )
    {
        UserStakeInfo memory userStake = userStakes[user];

        if (userStake.amount == 0) {
            return (0, 0, 0, 0); 
        }

        timeInTier = block.timestamp - userStake.startTime;
        tierMultiplier = _getTierMultiplier(userStake.tier, timeInTier);
        marketMultiplier = _getMarketMultiplier();
        currentYield = calculateDynamicYield(user, userStake.amount); 
    }

    /**
     * @dev Get market condition multiplier 
     */
    function getMarketMultiplier() external view returns (uint256) {
        return _getMarketMultiplier(); 
    }

    /**
     * @dev Get protocol health bonus  
     */

    function getProtocolHealthBonus() external view returns (uint256) {
        return _getProtocolHealthBonus();  
    }

    // ===== Internal Functions =====

    function _initializeDefaultTiers() internal {
        // Bronze: 7 days, 1.2x
        stakingTiers[0] = StakingTier(7 days, 120, true);

        // Silver: 30 days, 1.5x
        stakingTiers[1] = StakingTier(30 days, 150, true);

        // Gold: 90 days, 2.0x
        stakingTiers[2] = StakingTier(90 days, 200, true);

        // Diamond: 365 days, 3.0x
        stakingTiers[3] = StakingTier(365 days, 300, true); 
    }

    function _getTierMultiplier(uint256 tier, uint256 stakeDuration) 
        internal
        view
        returns (uint256)
    {
        StakingTier memory stakingTier = stakingTiers[tier];

        if (!stakingTier.active || stakeDuration < stakingTier.lockPeriod) {
            return 100; // 1.0x base multiplier if tier not unlocked
        }

        return stakingTier.multiplier;
    }

    function _getMarketMultiplier() internal view returns (uint256) {
        uint256 baseMultiplier = 100; // 1.0x

        // Low volatility bonus 
        if (currentMarketCondition.volatilityIndex < volatilityThreshold) {
            baseMultiplier = (baseMultiplier * stabilityBonus) / 100; 
        }

        // High growth bonus 
        if (currentMarketCondition.tvlGrowthRate > 1000) { // 10% growth 
            baseMultiplier = (baseMultiplier * growthBonus) / 100;  
        }

        return baseMultiplier;
    }

    function _getProtocolHealthBonus() internal view returns (uint256) {
        // Simple protocol health based on TVL growth
        if (protocolTVL > 0 && totalStaked > 0) {
            uint256 stakingRatio = (totalStaked * BASIS_POINTS) / protocolTVL;

            // Bonus for healthy staking ratio (20-80%)
            if (stakingRatio >= 2000 && stakingRatio <= 8000) {
                return 110; // 1.1x bonus  
            }
        }

        return 100; // 1.0x no bonus  
    }
}
