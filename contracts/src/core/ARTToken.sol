// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3; // solidity version (Watch out for this)

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ARTToken
 * @dev The governance and utility token for ART Protocol
 *
 * Features:
 * - ERC20 with voting capabilities
 * - Controlled minting with emission schedule
 * - Burning mechanism
 * - Pausable for emergency stops
 * - Anti-whale mechanisms
 */

contract ARTToken is
    ERC20,
    ERC20Permit,
    ERC20Burnable,
    ERC20Votes,
    Ownable,
    Pausable,
    ReentrancyGuard
{
    // === Constants ===

    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18; // 1 billion tokens
    uint256 public constant INITIAL_SUPPLY = 150_000_000 * 1e18; // 15% initial (Treasury + DEX)

    // Anti-whale: Maximum wallet holding (2% of total supply)
    uint256 public constant MAX_WALLET_HOLDING = 20_000_000 * 1e18; // 2% of total supply

    // === State Variables ===

    uint256 public totalMinted;
    uint256 public emissionRate = 1000 * 1e18; // Initial emission per block
    uint256 public lastEmissionBlock;

    mapping(address => bool) public minters;
    mapping(address => bool) public excludedFromLimit;

    // === Events ===
    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
    event EmissionRateUpdated(uint256 newRate);
    event TokensBurned(address indexed burner, uint256 amount);

    // === Constructor ===

    constructor()
        ERC20("ART Protocol Token", "ART")
        ERC20Permit("ART Protocol Token")
        Ownable(msg.sender)
    {
        // Mint initial supply to deployer (Treasury allocation)
        _mint(msg.sender, INITIAL_SUPPLY);
        totalMinted = INITIAL_SUPPLY;
        lastEmissionBlock = block.number;

        // Exclude contract addresses from wallet limits
        excludedFromLimit[address(this)] = true;
        excludedFromLimit[msg.sender] = true;
    }

    // === Modifiers ===

    modifier onlyMinter() {
        require(minters[msg.sender], "ARTToken: caller is not a minter");
        _;
    }

    modifier validAmount(uint256 amount) {
        require(amount > 0, "ARTToken: amount must be positive");
        _;
    }

    // === Minting Functions ===

    /**
     * @dev Mint tokens to specified address with supply and anti-whale checks
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(
        address to,
        uint256 amount
    ) external onlyMinter validAmount(amount) whenNotPaused nonReentrant {
        require(
            totalMinted + amount <= MAX_SUPPLY,
            "ARTToken: exceeds max supply"
        );

        // Check wallet holding limit (unless excluded)
        if (!excludedFromLimit[to]) {
            require(
                balanceOf(to) + amount <= MAX_WALLET_HOLDING,
                "ARTToken: exceeds max wallet holding"
            );
        }

        totalMinted += amount;
        _mint(to, amount);
    }

    /**
     * @dev Calculate and mint emission rewards based on blocks passed
     * @param to Address to mint emission rewards to
     */
    function mintEmission(
        address to
    ) external onlyMinter whenNotPaused nonReentrant {
        uint256 blocksPassed = block.number - lastEmissionBlock;
        require(blocksPassed > 0, "ARTToken: no blocks passed");

        uint256 emissionAmount = blocksPassed * emissionRate;

        if (totalMinted + emissionAmount > MAX_SUPPLY) {
            emissionAmount = MAX_SUPPLY - totalMinted;
        }

        if (emissionAmount > 0) {
            totalMinted += emissionAmount;
            lastEmissionBlock = block.number;
            _mint(to, emissionAmount);
        }
    }

    // === Admin Functions ===

    /**
     * @dev Add minter role to address
     */
    function addMinter(address minter) external onlyOwner {
        require(minter != address(0), "ARTToken: invalid minter address");
        minters[minter] = true;
        excludedFromLimit[minter] = true;
        emit MinterAdded(minter);
    }

    /**
     * @dev Remove minter role from address
     */
    function removeMinter(address minter) external onlyOwner {
        minters[minter] = false;
        emit MinterRemoved(minter);
    }

    /**
     * @dev Update emission rate (for tokenomics adjustment)
     */
    function updateEmissionRate(uint256 newRate) external onlyOwner {
        require(newRate <= 10000 * 1e18, "ARTToken: emission rate too high");
        emissionRate = newRate;
        emit EmissionRateUpdated(newRate);
    }

    /**
     * @dev Add address to wallet limit exclusion
     */
    function exlcudeFromLimit(
        address account,
        bool excluded
    ) external onlyOwner {
        excludedFromLimit[account] = excluded;
    }

    /**
     * @dev Emergency pause function
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause function
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // === View Functions ===

    /**
     * @dev Get remaining tokens that can be minted
     */
    function remainingSupply() external view returns (uint256) {
        return MAX_SUPPLY - totalMinted;
    }

    /**
     * @dev Get current emission amount for current block
     */
    function getCurrentEmissionAmount() external view returns (uint256) {
        uint256 blocksPassed = block.number - lastEmissionBlock;
        uint256 emissionAmount = blocksPassed * emissionRate;

        if (totalMinted + emissionAmount > MAX_SUPPLY) {
            emissionAmount = MAX_SUPPLY - totalMinted;
        }

        return emissionAmount;
    }

    /**
     * @dev Check if address can receive additional tokens without hitting limit
     */
    function canReceiveTokens(
        address account,
        uint256 amount
    ) external view returns (bool) {
        if (excludedFromLimit[account]) {
            return true;
        }
        return balanceOf(account) + amount <= MAX_WALLET_HOLDING;
    }

    // ==  Overrides ==

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        // Check wallet holding limit for regular transfers (not minting)
        if (from != address(0) && to != address(0) && !excludedFromLimit[to]) {
            require(
                balanceOf(to) + amount <= MAX_WALLET_HOLDING,
                "ARTToken: transfer exceed max wallet holding"
            );
        }

        super._update(from, to, amount);
    }

    function _mint(
        address to,
        uint256 amount
    ) internal override {
        super._mint(to, amount);
    }

    function _burn(
        address account,
        uint256 amount
    ) internal override {
        super._burn(account, amount);
        emit TokensBurned(account, amount);
    }
}
