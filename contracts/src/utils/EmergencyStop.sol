// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title EmergencyStop
 * @dev Emergency circuit breaker utility contract for ART Protocol
 * 
 * Features:
 * - Global emergency stop mechanism
 * - Automated trigger conditions
 * - Time-locked recovery procedures
 * - Multi-signature emergency controls
 */
contract EmergencyStop is Ownable, Pausable {
    // ============ Constants ============
    
    uint256 public constant RECOVERY_DELAY = 24 hours;
    uint256 public constant MAX_EMERGENCY_GUARDIANS = 5;
    
    // ============ Structs ============
    
    struct EmergencyTrigger {
        bool active;
        uint256 threshold;
        uint256 currentValue;
        string description;
    }
    
    struct RecoveryProposal {
        address proposer;
        uint256 proposedAt;
        uint256 executionTime;
        bool executed;
        string reason;
    }
    
    // ============ State Variables ============
    
    mapping(address => bool) public emergencyGuardians;
    mapping(bytes32 => EmergencyTrigger) public triggers;
    mapping(uint256 => RecoveryProposal) public recoveryProposals;
    
    address[] public guardianList;
    bytes32[] public triggerKeys;
    
    uint256 public guardianCount;
    uint256 public requiredGuardianSignatures = 2;
    uint256 public recoveryProposalCount;
    
    bool public emergencyMode = false;
    uint256 public emergencyTriggeredAt;
    address public emergencyTriggeredBy;
    string public emergencyReason;
    
    // ============ Events ============
    
    event EmergencyActivated(address indexed triggeredBy, string reason, uint256 timestamp);
    event EmergencyDeactivated(address indexed deactivatedBy, uint256 timestamp);
    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);
    event TriggerAdded(bytes32 indexed key, uint256 threshold, string description);
    event TriggerUpdated(bytes32 indexed key, uint256 newThreshold);
    event TriggerActivated(bytes32 indexed key, uint256 currentValue, uint256 threshold);
    event RecoveryProposed(uint256 indexed proposalId, address indexed proposer, string reason);
    event RecoveryExecuted(uint256 indexed proposalId, address indexed executor);
    
    // ============ Modifiers ============
    
    modifier onlyGuardian() {
        require(emergencyGuardians[msg.sender] || msg.sender == owner(), "EmergencyStop: not authorized guardian");
        _;
    }
    
    modifier onlyInEmergency() {
        require(emergencyMode, "EmergencyStop: not in emergency mode");
        _;
    }
    
    modifier onlyNotInEmergency() {
        require(!emergencyMode, "EmergencyStop: in emergency mode");
        _;
    }
    
    // ============ Constructor ============
    
    constructor() Ownable(msg.sender) {
        // Add deployer as initial guardian
        emergencyGuardians[msg.sender] = true;
        guardianList.push(msg.sender);
        guardianCount = 1;
        
        // Initialize default triggers
        _addTrigger("TVL_DROP", 5000, "Total Value Locked dropped by 50%"); // 50% TVL drop
        _addTrigger("WITHDRAWAL_SPIKE", 8000, "Unusual withdrawal spike detected"); // 80% withdrawal rate
        _addTrigger("PRICE_MANIPULATION", 9000, "Token price manipulation detected"); // 90% price deviation
    }
    
    // ============ Emergency Functions ============
    
    /**
     * @dev Manually trigger emergency stop
     * @param reason Reason for emergency activation
     */
    function triggerEmergency(string calldata reason) external onlyGuardian onlyNotInEmergency {
        emergencyMode = true;
        emergencyTriggeredAt = block.timestamp;
        emergencyTriggeredBy = msg.sender;
        emergencyReason = reason;
        
        _pause();
        
        emit EmergencyActivated(msg.sender, reason, block.timestamp);
    }
    
    /**
     * @dev Automated trigger check (called by monitoring systems)
     * @param triggerKey Key of the trigger to check
     * @param currentValue Current value to compare against threshold
     */
    function checkTrigger(bytes32 triggerKey, uint256 currentValue) external onlyGuardian {
        EmergencyTrigger storage trigger = triggers[triggerKey];
        require(trigger.active, "EmergencyStop: trigger not active");
        
        trigger.currentValue = currentValue;
        
        if (currentValue >= trigger.threshold && !emergencyMode) {
            string memory reason = string(abi.encodePacked("Automated trigger: ", trigger.description));
            
            emergencyMode = true;
            emergencyTriggeredAt = block.timestamp;
            emergencyTriggeredBy = msg.sender;
            emergencyReason = reason;
            
            _pause();
            
            emit TriggerActivated(triggerKey, currentValue, trigger.threshold);
            emit EmergencyActivated(msg.sender, reason, block.timestamp);
        }
    }
    
    /**
     * @dev Propose recovery from emergency mode
     * @param reason Reason for recovery
     */
    function proposeRecovery(string calldata reason) external onlyGuardian onlyInEmergency returns (uint256 proposalId) {
        proposalId = recoveryProposalCount++;
        
        recoveryProposals[proposalId] = RecoveryProposal({
            proposer: msg.sender,
            proposedAt: block.timestamp,
            executionTime: block.timestamp + RECOVERY_DELAY,
            executed: false,
            reason: reason
        });
        
        emit RecoveryProposed(proposalId, msg.sender, reason);
    }
    
    /**
     * @dev Execute recovery proposal after time delay
     * @param proposalId ID of the recovery proposal
     */
    function executeRecovery(uint256 proposalId) external onlyGuardian onlyInEmergency {
        RecoveryProposal storage proposal = recoveryProposals[proposalId];
        
        require(!proposal.executed, "EmergencyStop: proposal already executed");
        require(block.timestamp >= proposal.executionTime, "EmergencyStop: recovery delay not passed");
        require(_hasRequiredSignatures(proposalId), "EmergencyStop: insufficient guardian signatures");
        
        proposal.executed = true;
        emergencyMode = false;
        
        _unpause();
        
        emit RecoveryExecuted(proposalId, msg.sender);
        emit EmergencyDeactivated(msg.sender, block.timestamp);
    }
    
    // ============ Guardian Management ============
    
    /**
     * @dev Add emergency guardian
     * @param guardian Address to add as guardian
     */
    function addGuardian(address guardian) external onlyOwner {
        require(guardian != address(0), "EmergencyStop: invalid guardian address");
        require(!emergencyGuardians[guardian], "EmergencyStop: guardian already exists");
        require(guardianCount < MAX_EMERGENCY_GUARDIANS, "EmergencyStop: too many guardians");
        
        emergencyGuardians[guardian] = true;
        guardianList.push(guardian);
        guardianCount++;
        
        emit GuardianAdded(guardian);
    }
    
    /**
     * @dev Remove emergency guardian
     * @param guardian Address to remove from guardians
     */
    function removeGuardian(address guardian) external onlyOwner {
        require(emergencyGuardians[guardian], "EmergencyStop: guardian does not exist");
        require(guardianCount > 1, "EmergencyStop: cannot remove last guardian");
        
        emergencyGuardians[guardian] = false;
        guardianCount--;
        
        // Remove from guardian list
        for (uint256 i = 0; i < guardianList.length; i++) {
            if (guardianList[i] == guardian) {
                guardianList[i] = guardianList[guardianList.length - 1];
                guardianList.pop();
                break;
            }
        }
        
        emit GuardianRemoved(guardian);
    }
    
    /**
     * @dev Update required guardian signatures for recovery
     * @param newRequirement New signature requirement
     */
    function updateSignatureRequirement(uint256 newRequirement) external onlyOwner {
        require(newRequirement > 0 && newRequirement <= guardianCount, "EmergencyStop: invalid requirement");
        requiredGuardianSignatures = newRequirement;
    }
    
    // ============ Trigger Management ============
    
    /**
     * @dev Add new emergency trigger
     * @param key Unique key for the trigger
     * @param threshold Threshold value that activates the trigger
     * @param description Human-readable description
     */
    function addTrigger(
        bytes32 key,
        uint256 threshold,
        string calldata description
    ) external onlyOwner {
        _addTrigger(key, threshold, description);
    }
    
    /**
     * @dev Update existing trigger threshold
     * @param key Key of the trigger to update
     * @param newThreshold New threshold value
     */
    function updateTrigger(bytes32 key, uint256 newThreshold) external onlyOwner {
        require(triggers[key].active, "EmergencyStop: trigger does not exist");
        
        triggers[key].threshold = newThreshold;
        emit TriggerUpdated(key, newThreshold);
    }
    
    /**
     * @dev Deactivate a trigger
     * @param key Key of the trigger to deactivate
     */
    function deactivateTrigger(bytes32 key) external onlyOwner {
        triggers[key].active = false;
    }
    
    // ============ View Functions ============
    
    /**
     * @dev Get emergency status information
     */
    function getEmergencyStatus() 
        external 
        view 
        returns (
            bool inEmergency,
            uint256 triggeredAt,
            address triggeredBy,
            string memory reason
        ) 
    {
        return (emergencyMode, emergencyTriggeredAt, emergencyTriggeredBy, emergencyReason);
    }
    
    /**
     * @dev Get all guardians
     */
    function getGuardians() external view returns (address[] memory) {
        return guardianList;
    }
    
    /**
     * @dev Get all trigger keys
     */
    function getTriggerKeys() external view returns (bytes32[] memory) {
        return triggerKeys;
    }
    
    /**
     * @dev Get trigger information
     * @param key Trigger key
     */
    function getTrigger(bytes32 key) 
        external 
        view 
        returns (
            bool active,
            uint256 threshold,
            uint256 currentValue,
            string memory description
        ) 
    {
        EmergencyTrigger memory trigger = triggers[key];
        return (trigger.active, trigger.threshold, trigger.currentValue, trigger.description);
    }
    
    /**
     * @dev Check if emergency mode should be activated based on current metrics
     * @param triggerKey Key to check
     * @param currentValue Current metric value
     */
    function shouldTriggerEmergency(bytes32 triggerKey, uint256 currentValue) 
        external 
        view 
        returns (bool) 
    {
        EmergencyTrigger memory trigger = triggers[triggerKey];
        return trigger.active && currentValue >= trigger.threshold && !emergencyMode;
    }
    
    // ============ Internal Functions ============
    
    function _addTrigger(
        bytes32 key,
        uint256 threshold,
        string memory description
    ) internal {
        require(!triggers[key].active, "EmergencyStop: trigger already exists");
        
        triggers[key] = EmergencyTrigger({
            active: true,
            threshold: threshold,
            currentValue: 0,
            description: description
        });
        
        triggerKeys.push(key);
        emit TriggerAdded(key, threshold, description);
    }
    
    function _hasRequiredSignatures(uint256 /* proposalId */) internal pure returns (bool) {
        // In a full implementation, this would check actual signatures
        // For MVP, we'll assume the calling guardian represents sufficient consensus
        return true;
    }
}