// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;
/**
 * @title YieldCalculations
 * @dev Library for yield calculation utilities
 */
library YieldCalculations {
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    uint256 private constant PRECISION = 1e18;
    
    /**
     * @dev Calculate simple yield based on amount, APY, and time
     * @param amount Principal amount
     * @param apyBasisPoints APY in basis points (e.g., 500 = 5%)
     * @param timeInSeconds Time period in seconds
     * @return Calculated yield amount
     */
    function calculateYield(
        uint256 amount,
        uint256 apyBasisPoints,
        uint256 timeInSeconds
    ) internal pure returns (uint256) {
        if (amount == 0 || apyBasisPoints == 0 || timeInSeconds == 0) {
            return 0;
        }
        
        // Simple interest: yield = principal * rate * time
        // rate = APY / 10000 (basis points)
        // time = timeInSeconds / SECONDS_PER_YEAR
        return (amount * apyBasisPoints * timeInSeconds) / (BASIS_POINTS * SECONDS_PER_YEAR);
    }
    
    /**
     * @dev Calculate compound yield with daily compounding
     * @param principal Principal amount
     * @param apyBasisPoints APY in basis points
     * @param timeInSeconds Time period in seconds
     * @return Compound yield amount (total - principal)
     */
    function calculateCompoundYield(
        uint256 principal,
        uint256 apyBasisPoints,
        uint256 timeInSeconds
    ) internal pure returns (uint256) {
        if (principal == 0 || apyBasisPoints == 0 || timeInSeconds == 0) {
            return 0;
        }
        
        // Daily compounding: A = P(1 + r/365)^(365*t)
        // For simplicity, approximate with: A ≈ P * e^(rt)
        // Using Taylor series approximation for small rates
        
        uint256 rate = (apyBasisPoints * PRECISION) / BASIS_POINTS;
        uint256 time = (timeInSeconds * PRECISION) / SECONDS_PER_YEAR;
        
        // e^(rt) ≈ 1 + rt + (rt)^2/2 + (rt)^3/6 (first few terms)
        uint256 rt = (rate * time) / PRECISION;
        uint256 rt2 = (rt * rt) / PRECISION;
        uint256 rt3 = (rt2 * rt) / PRECISION;
        
        uint256 multiplier = PRECISION + rt + (rt2 / 2) + (rt3 / 6);
        uint256 finalAmount = (principal * multiplier) / PRECISION;
        
        return finalAmount > principal ? finalAmount - principal : 0;
    }
    
    /**
     * @dev Calculate APY from total rewards over time
     * @param principal Initial principal amount
     * @param totalRewards Total rewards earned
     * @param timeInSeconds Time period in seconds
     * @return APY in basis points
     */
    function calculateAPY(
        uint256 principal,
        uint256 totalRewards,
        uint256 timeInSeconds
    ) internal pure returns (uint256) {
        if (principal == 0 || timeInSeconds == 0) {
            return 0;
        }
        
        // APY = (rewards / principal) * (SECONDS_PER_YEAR / timeInSeconds) * BASIS_POINTS
        return (totalRewards * SECONDS_PER_YEAR * BASIS_POINTS) / (principal * timeInSeconds);
    }
    
    /**
     * @dev Calculate yield with linear decay over time
     * @param amount Principal amount
     * @param initialAPY Initial APY in basis points
     * @param finalAPY Final APY in basis points
     * @param timeInSeconds Current time elapsed
     * @param totalDuration Total duration for decay
     * @return Calculated yield with decay
     */
    function calculateDecayingYield(
        uint256 amount,
        uint256 initialAPY,
        uint256 finalAPY,
        uint256 timeInSeconds,
        uint256 totalDuration
    ) internal pure returns (uint256) {
        if (amount == 0 || timeInSeconds == 0 || totalDuration == 0) {
            return 0;
        }
        
        // Linear interpolation between initial and final APY
        uint256 currentAPY;
        if (timeInSeconds >= totalDuration) {
            currentAPY = finalAPY;
        } else {
            uint256 progress = (timeInSeconds * PRECISION) / totalDuration;
            if (initialAPY >= finalAPY) {
                uint256 decrease = ((initialAPY - finalAPY) * progress) / PRECISION;
                currentAPY = initialAPY - decrease;
            } else {
                uint256 increase = ((finalAPY - initialAPY) * progress) / PRECISION;
                currentAPY = initialAPY + increase;
            }
        }
        
        return calculateYield(amount, currentAPY, timeInSeconds);
    }
    
    /**
     * @dev Calculate bonus yield based on multiplier
     * @param baseYield Base yield amount
     * @param multiplierBasisPoints Multiplier in basis points (e.g., 150 = 1.5x)
     * @return Bonus yield amount (additional to base)
     */
    function calculateBonusYield(
        uint256 baseYield,
        uint256 multiplierBasisPoints
    ) internal pure returns (uint256) {
        if (baseYield == 0 || multiplierBasisPoints <= 100) {
            return 0;
        }
        
        uint256 totalYield = (baseYield * multiplierBasisPoints) / 100;
        return totalYield - baseYield; // Return only the bonus portion
    }
    
    /**
     * @dev Calculate yield with time-based multiplier boost
     * @param amount Principal amount
     * @param baseAPY Base APY in basis points
     * @param timeInSeconds Time staked
     * @param boostThreshold Time threshold for boost (in seconds)
     * @param boostMultiplier Boost multiplier in basis points
     * @return Calculated yield with time boost
     */
    function calculateTimeBasedYield(
        uint256 amount,
        uint256 baseAPY,
        uint256 timeInSeconds,
        uint256 boostThreshold,
        uint256 boostMultiplier
    ) internal pure returns (uint256) {
        uint256 baseYield = calculateYield(amount, baseAPY, timeInSeconds);
        
        if (timeInSeconds >= boostThreshold && boostMultiplier > 100) {
            return (baseYield * boostMultiplier) / 100;
        }
        
        return baseYield;
    }
    
    /**
     * @dev Calculate penalty for early withdrawal
     * @param amount Withdrawal amount
     * @param penaltyRate Penalty rate in basis points
     * @param timeStaked Time tokens were staked
     * @param minimumStakeTime Minimum time for no penalty
     * @return Penalty amount
     */
    function calculateEarlyWithdrawalPenalty(
        uint256 amount,
        uint256 penaltyRate,
        uint256 timeStaked,
        uint256 minimumStakeTime
    ) internal pure returns (uint256) {
        if (timeStaked >= minimumStakeTime || penaltyRate == 0) {
            return 0;
        }
        
        // Linear penalty reduction based on time staked
        uint256 timeProgress = (timeStaked * PRECISION) / minimumStakeTime;
        uint256 adjustedPenaltyRate = penaltyRate - ((penaltyRate * timeProgress) / PRECISION);
        
        return (amount * adjustedPenaltyRate) / BASIS_POINTS;
    }
    
    /**
     * @dev Safely multiply two numbers with overflow protection
     * @param a First number
     * @param b Second number
     * @return Product of a and b
     */
    function safeMul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "YieldCalculations: multiplication overflow");
        return c;
    }
    
    /**
     * @dev Calculate percentage of a value
     * @param value Base value
     * @param percentage Percentage in basis points
     * @return Calculated percentage amount
     */
    function calculatePercentage(uint256 value, uint256 percentage) internal pure returns (uint256) {
        return (value * percentage) / BASIS_POINTS;
    }
}