// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IMasterFarm.sol";
import "../interfaces/ITokenomicEngine.sol";
import "./ARTToken.sol";

/**
 * @title MasterFarm
 * @dev Main farming contract for ART Protocol with dynamic yield distribution
 * 
 * Features:
 * - Multi-pool farming with different reward rates
 * - Integration with TokenomicsEngine for dynamic yields
 * - Tiered staking system
 * - Emergency withdrawal capabilities
 * - Fee collection and distribution
 */
contract MasterFarm is IMasterFarm, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // ============ Constants ============
    
    uint256 public constant PRECISION_FACTOR = 1e18;
    uint256 public constant MAX_WITHDRAWAL_FEE = 500; // 5% max withdrawal fee
    uint256 public constant MAX_POOLS = 50; // Maximum number of pools
    
    // ============ Structs ============
    
    struct PoolInfo {
        IERC20 lpToken;           // LP token contract
        uint256 allocPoint;       // Allocation points for this pool
        uint256 lastRewardBlock;  // Last block number that ART distribution occurred
        uint256 accARTPerShare;   // Accumulated ART per share, times PRECISION_FACTOR
        uint256 totalStaked;      // Total amount staked in this pool
        uint256 withdrawalFee;    // Withdrawal fee in basis points (0-500)
        bool active;              // Whether pool is active
    }
    
    struct UserInfo {
        uint256 amount;           // How many LP tokens the user has provided
        uint256 rewardDebt;       // Reward debt for ART calculations
        uint256 stakingTier;      // User's chosen staking tier
        uint256 lastDepositTime;  // Last deposit timestamp for withdrawal fee calculation
        uint256 totalRewarded;    // Total ART rewards claimed
    }
    
    // ============ State Variables ============
    
    ARTToken public artToken;
    ITokenomicsEngine public tokenomicsEngine;
    
    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    
    uint256 public totalAllocPoint = 0;
    uint256 public startBlock;
    
    // Protocol fees
    uint256 public protocolFeeRate = 300; // 3% protocol fee
    address public feeCollector;
    uint256 public collectedFees;
    
    // Early withdrawal penalty period (24 hours)
    uint256 public constant PENALTY_PERIOD = 24 hours;
    uint256 public earlyWithdrawalPenalty = 200; // 2% additional penalty
    
    // ============ Events ============
    
    event PoolAdded(uint256 indexed pid, address indexed lpToken, uint256 allocPoint);
    event PoolUpdated(uint256 indexed pid, uint256 allocPoint, uint256 withdrawalFee);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, uint256 tier);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event FeeCollected(uint256 amount);
    event ParametersUpdated(uint256 protocolFeeRate, uint256 earlyWithdrawalPenalty);
    
    // ============ Modifiers ============
    
    modifier validPool(uint256 _pid) {
        require(_pid < poolInfo.length, "MasterFarm: invalid pool ID");
        require(poolInfo[_pid].active, "MasterFarm: pool not active");
        _;
    }
    
    modifier validTier(uint256 _tier) {
        require(_tier <= 3, "MasterFarm: invalid staking tier");
        _;
    }
    
    // ============ Constructor ============
    
    constructor(
        ARTToken _artToken,
        ITokenomicsEngine _tokenomicsEngine,
        uint256 _startBlock,
        address _feeCollector
    ) Ownable(msg.sender) {
        require(address(_artToken) != address(0), "MasterFarm: invalid ART token");
        require(address(_tokenomicsEngine) != address(0), "MasterFarm: invalid tokenomics engine");
        require(_feeCollector != address(0), "MasterFarm: invalid fee collector");
        
        artToken = _artToken;
        tokenomicsEngine = _tokenomicsEngine;
        startBlock = _startBlock;
        feeCollector = _feeCollector;
    }
    
    // ============ External Functions ============
    
    /**
     * @dev Add a new farming pool
     */
    function addPool(
        IERC20 _lpToken,
        uint256 _allocPoint,
        uint256 _withdrawalFee
    ) external onlyOwner {
        require(address(_lpToken) != address(0), "MasterFarm: invalid LP token");
        require(_withdrawalFee <= MAX_WITHDRAWAL_FEE, "MasterFarm: withdrawal fee too high");
        require(poolInfo.length < MAX_POOLS, "MasterFarm: too many pools");
        
        // Check for duplicate pools
        for (uint256 i = 0; i < poolInfo.length; i++) {
            require(address(poolInfo[i].lpToken) != address(_lpToken), "MasterFarm: pool already exists");
        }
        
        massUpdatePools();
        
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint += _allocPoint;
        
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accARTPerShare: 0,
            totalStaked: 0,
            withdrawalFee: _withdrawalFee,
            active: true
        }));
        
        emit PoolAdded(poolInfo.length - 1, address(_lpToken), _allocPoint);
    }
    
    /**
     * @dev Update pool allocation and parameters
     */
    function updatePool(
        uint256 _pid,
        uint256 _allocPoint,
        uint256 _withdrawalFee
    ) external onlyOwner validPool(_pid) {
        require(_withdrawalFee <= MAX_WITHDRAWAL_FEE, "MasterFarm: withdrawal fee too high");
        
        massUpdatePools();
        
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].withdrawalFee = _withdrawalFee;
        
        emit PoolUpdated(_pid, _allocPoint, _withdrawalFee);
    }
    
    /**
     * @dev Deposit LP tokens to farm for ART rewards
     */
    function deposit(
        uint256 _pid,
        uint256 _amount,
        uint256 _tier
    ) external override validPool(_pid) validTier(_tier) whenNotPaused nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        
        updatePoolRewards(_pid);
        
        // Harvest pending rewards before deposit
        if (user.amount > 0) {
            _harvestRewards(_pid, msg.sender);
        }
        
        if (_amount > 0) {
            // Transfer LP tokens from user
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            
            user.amount += _amount;
            user.stakingTier = _tier;
            user.lastDepositTime = block.timestamp;
            pool.totalStaked += _amount;
            
            // Update tokenomics engine with new stake info
            tokenomicsEngine.updateUserStake(msg.sender, user.amount, _tier);
            
            // Update protocol TVL
            uint256 totalTVL = _calculateTotalTVL();
            tokenomicsEngine.updateProtocolTVL(totalTVL);
        }
        
        user.rewardDebt = (user.amount * pool.accARTPerShare) / PRECISION_FACTOR;
        
        emit Deposit(msg.sender, _pid, _amount, _tier);
    }
    
    /**
     * @dev Withdraw LP tokens and harvest rewards
     */
    function withdraw(uint256 _pid, uint256 _amount) 
        external 
        override 
        validPool(_pid) 
        nonReentrant 
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        
        require(user.amount >= _amount, "MasterFarm: insufficient balance");
        
        updatePoolRewards(_pid);
        
        // Harvest pending rewards
        _harvestRewards(_pid, msg.sender);
        
        if (_amount > 0) {
            user.amount -= _amount;
            pool.totalStaked -= _amount;
            
            // Calculate withdrawal fees
            uint256 feeAmount = _calculateWithdrawalFee(_pid, _amount, user.lastDepositTime);
            uint256 withdrawAmount = _amount - feeAmount;
            
            // Collect fees
            if (feeAmount > 0) {
                collectedFees += feeAmount;
                pool.lpToken.safeTransfer(feeCollector, feeAmount);
                emit FeeCollected(feeAmount);
            }
            
            // Transfer tokens back to user
            pool.lpToken.safeTransfer(msg.sender, withdrawAmount);
            
            // Update tokenomics engine
            tokenomicsEngine.updateUserStake(msg.sender, user.amount, user.stakingTier);
            
            // Update protocol TVL
            uint256 totalTVL = _calculateTotalTVL();
            tokenomicsEngine.updateProtocolTVL(totalTVL);
        }
        
        user.rewardDebt = (user.amount * pool.accARTPerShare) / PRECISION_FACTOR;
        
        emit Withdraw(msg.sender, _pid, _amount);
    }
    
    /**
     * @dev Harvest ART rewards from a pool
     */
    function harvest(uint256 _pid) external override validPool(_pid) nonReentrant {
        updatePoolRewards(_pid);
        _harvestRewards(_pid, msg.sender);
    }
    
    /**
     * @dev Emergency withdraw without caring about rewards (no fees)
     */
    function emergencyWithdraw(uint256 _pid) external validPool(_pid) nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        
        uint256 amount = user.amount;
        require(amount > 0, "MasterFarm: no balance to withdraw");
        
        user.amount = 0;
        user.rewardDebt = 0;
        pool.totalStaked -= amount;
        
        pool.lpToken.safeTransfer(msg.sender, amount);
        
        // Update tokenomics engine
        tokenomicsEngine.updateUserStake(msg.sender, 0, 0);
        
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }
    
    /**
     * @dev Update reward variables for all pools
     */
    function massUpdatePools() public {
        for (uint256 pid = 0; pid < poolInfo.length; pid++) {
            updatePoolRewards(pid);
        }
    }
    
    /**
     * @dev Update reward variables for a specific pool
     */
    function updatePoolRewards(uint256 _pid) public validPool(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        
        uint256 lpSupply = pool.totalStaked;
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        
        uint256 multiplier = block.number - pool.lastRewardBlock;
        uint256 artReward = (multiplier * getARTPerBlock() * pool.allocPoint) / totalAllocPoint;
        
        // Mint ART rewards to this contract
        artToken.mint(address(this), artReward);
        
        pool.accARTPerShare += (artReward * PRECISION_FACTOR) / lpSupply;
        pool.lastRewardBlock = block.number;
    }
    
    // ============ Admin Functions ============
    
    /**
     * @dev Set pool active/inactive status
     */
    function setPoolActive(uint256 _pid, bool _active) external onlyOwner {
        require(_pid < poolInfo.length, "MasterFarm: invalid pool ID");
        poolInfo[_pid].active = _active;
    }
    
    /**
     * @dev Update protocol parameters
     */
    function updateParameters(
        uint256 _protocolFeeRate,
        uint256 _earlyWithdrawalPenalty
    ) external onlyOwner {
        require(_protocolFeeRate <= 1000, "MasterFarm: protocol fee too high"); // Max 10%
        require(_earlyWithdrawalPenalty <= 1000, "MasterFarm: penalty too high"); // Max 10%
        
        protocolFeeRate = _protocolFeeRate;
        earlyWithdrawalPenalty = _earlyWithdrawalPenalty;
        
        emit ParametersUpdated(_protocolFeeRate, _earlyWithdrawalPenalty);
    }
    
    /**
     * @dev Update fee collector address
     */
    function setFeeCollector(address _feeCollector) external onlyOwner {
        require(_feeCollector != address(0), "MasterFarm: invalid fee collector");
        feeCollector = _feeCollector;
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
    
    // ============ View Functions ============
    
    /**
     * @dev Get number of pools
     */
    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }
    
    /**
     * @dev Get ART tokens generated per block
     */
    function getARTPerBlock() public view returns (uint256) {
        // Simple emission rate for MVP - can be made more complex later
        return artToken.emissionRate();
    }
    
    /**
     * @dev Get pending ART rewards for a user
     */
    function pendingART(uint256 _pid, address _user) 
        external 
        view 
        override 
        returns (uint256) 
    {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        
        uint256 accARTPerShare = pool.accARTPerShare;
        uint256 lpSupply = pool.totalStaked;
        
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = block.number - pool.lastRewardBlock;
            uint256 artReward = (multiplier * getARTPerBlock() * pool.allocPoint) / totalAllocPoint;
            accARTPerShare += (artReward * PRECISION_FACTOR) / lpSupply;
        }
        
        uint256 baseReward = (user.amount * accARTPerShare) / PRECISION_FACTOR - user.rewardDebt;
        
        // Apply dynamic yield multiplier from tokenomics engine
        if (baseReward > 0) {
            return tokenomicsEngine.calculateDynamicYield(_user, baseReward);
        }
        
        return 0;
    }
    
    /**
     * @dev Get user info for a specific pool
     */
    function getUserInfo(uint256 _pid, address _user) 
        external 
        view 
        returns (
            uint256 amount,
            uint256 rewardDebt,
            uint256 stakingTier,
            uint256 lastDepositTime,
            uint256 totalRewarded
        ) 
    {
        UserInfo memory user = userInfo[_pid][_user];
        return (
            user.amount,
            user.rewardDebt,
            user.stakingTier,
            user.lastDepositTime,
            user.totalRewarded
        );
    }
    
    /**
     * @dev Get pool info
     */
    function getPoolInfo(uint256 _pid) 
        external 
        view 
        returns (
            address lpToken,
            uint256 allocPoint,
            uint256 lastRewardBlock,
            uint256 accARTPerShare,
            uint256 totalStaked,
            uint256 withdrawalFee,
            bool active
        ) 
    {
        PoolInfo memory pool = poolInfo[_pid];
        return (
            address(pool.lpToken),
            pool.allocPoint,
            pool.lastRewardBlock,
            pool.accARTPerShare,
            pool.totalStaked,
            pool.withdrawalFee,
            pool.active
        );
    }
    
    // ============ Internal Functions ============
    
    function _harvestRewards(uint256 _pid, address _user) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        
        uint256 pending = (user.amount * pool.accARTPerShare) / PRECISION_FACTOR - user.rewardDebt;
        
        if (pending > 0) {
            // Apply dynamic yield multiplier
            uint256 finalReward = tokenomicsEngine.calculateDynamicYield(_user, pending);
            
            // Apply protocol fee
            uint256 protocolFee = (finalReward * protocolFeeRate) / 10000;
            uint256 userReward = finalReward - protocolFee;
            
            // Transfer rewards
            artToken.transfer(_user, userReward);
            artToken.transfer(feeCollector, protocolFee);
            
            user.totalRewarded += userReward;
            collectedFees += protocolFee;
            
            emit Harvest(_user, _pid, userReward);
            emit FeeCollected(protocolFee);
        }
    }
    
    function _calculateWithdrawalFee(
        uint256 _pid,
        uint256 _amount,
        uint256 _lastDepositTime
    ) internal view returns (uint256) {
        PoolInfo memory pool = poolInfo[_pid];
        uint256 fee = (pool.withdrawalFee * _amount) / 10000;
        
        // Apply early withdrawal penalty if within penalty period
        if (block.timestamp < _lastDepositTime + PENALTY_PERIOD) {
            uint256 earlyFee = (earlyWithdrawalPenalty * _amount) / 10000;
            fee += earlyFee;
        }
        
        return fee;
    }
    
    function _calculateTotalTVL() internal view returns (uint256) {
        uint256 totalTVL = 0;
        for (uint256 i = 0; i < poolInfo.length; i++) {
            totalTVL += poolInfo[i].totalStaked;
        }
        return totalTVL;
    }
}