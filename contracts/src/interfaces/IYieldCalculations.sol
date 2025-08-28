// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

/**
 * @title IYieldCalculations
 * @dev Interface for yield calculation library functions
 */
interface IYieldCalculations {
    /**
     * @dev Calculate yield based on amount, APY, and time
     * @param amount Principal amount
     * @param apyBasisPoints APY in basis points
     * @param timeInSeconds Time period in seconds
     * @return Calculated yield amount
     */
    function calculateYield(
        uint256 amount,
        uint256 apyBasisPoints,
        uint256 timeInSeconds
    ) external pure returns (uint256);
    
    /**
     * @dev Calculate compound yield
     * @param principal Principal amount
     * @param rate Interest rate per period
     * @param periods Number of compounding periods
     * @return Compound yield amount
     */
    function calculateCompoundYield(
        uint256 principal,
        uint256 rate,
        uint256 periods
    ) external pure returns (uint256);
}