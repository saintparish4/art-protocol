// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

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
    function canReceiveTokens(address account, uint256 amount) external view returns (bool);
}