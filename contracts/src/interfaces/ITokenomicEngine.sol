// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

/**
 * @title ITokenomicsEngine
 * @dev Interface for the TokenomicsEngine contract
 */
interface ITokenomicsEngine {
    /**
     * @dev Calculate dynamic yield for a user based on multiple factors
     * @param user User address
     * @param baseAmount Base staked amount
     * @return finalYield The calculated yield amount
     */
    function calculateDynamicYield(address user, uint256 baseAmount) 
        external 
        view 
        returns (uint256 finalYield);
    
    /**
     * @dev Update user staking information
     * @param user User address
     * @param amount New staked amount
     * @param tier Staking tier
     */
    function updateUserStake(address user, uint256 amount, uint256 tier) external;
    
    /**
     * @dev Update protocol TVL for health calculations
     * @param newTVL New total value locked
     */
    function updateProtocolTVL(uint256 newTVL) external;
}