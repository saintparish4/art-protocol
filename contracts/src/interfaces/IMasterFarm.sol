// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

/**
 * @title IMasterFarm
 * @dev Interface for the MasterFarm contract
 */
interface IMasterFarm {
    /**
     * @dev Deposit LP tokens to farm for ART rewards
     * @param pid Pool ID
     * @param amount Amount to deposit
     * @param tier Staking tier
     */
    function deposit(uint256 pid, uint256 amount, uint256 tier) external;
    
    /**
     * @dev Withdraw LP tokens and harvest rewards
     * @param pid Pool ID
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 pid, uint256 amount) external;
    
    /**
     * @dev Harvest ART rewards from a pool
     * @param pid Pool ID
     */
    function harvest(uint256 pid) external;
    
    /**
     * @dev Get pending ART rewards for a user
     * @param pid Pool ID
     * @param user User address
     * @return Pending ART amount
     */
    function pendingART(uint256 pid, address user) external view returns (uint256);
}