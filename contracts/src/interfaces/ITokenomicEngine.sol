// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

/**
 * @title ITokenomicEngine
 * @dev Interface for the tokenomicsEngine contract
 */
interface ITokenomicEngine {
    /**
     * @dev Calculate dynamic yield for a user based on multiple factors
     * @param user User address
     * @param baseAmount Base staked amount
     * @return finalYield The calculated yield amount
     */
    function calculateDynamicYield(
        address user,
        uint256 baseAmount
    ) external view returns (uint256 finalYield);

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
    ) external;

    /**
     * @dev Update protocol TVL for health calculations
     * @param newTVL New total value locked
     */
    function updateProtocolTVL(uint256 newTVL) external;
}

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
    function pendingART(
        uint256 pid,
        address user
    ) external view returns (uint256);
}

/**
 * @title IARTToken
 * @dev Interface for the ART token contract
 */
interface IARTToken {
    /**
     * @dev Mint tokens to specified address
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external;

    /**
     * @dev Calculate and mint emission rewards
     * @param to Address to mint emission rewards to
     */
    function mintEmission(address to) external;

    /**
     * @dev Get remaining tokens that can be minted
     */
    function remainingSupply() external view returns (uint256);

    /**
     * @dev Get current emission rate
     */
    function emissionRate() external view returns (uint256);

    /**
     * @dev Check if address can receive additional tokens without hitting limit
     */
    function canReceiveTokens(
        address account,
        uint256 amount
    ) external view returns (bool);
}

/**
 * @title IYieldCalculations
 * @dev Interface for yield calculation library functions
 */
interface IYieldCalculations {
    /**
     * @dev Calculate yield based on amount, APY, and time
     * @param amount Principal amount
     * @param apyBasisPoints APU in basis points
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
