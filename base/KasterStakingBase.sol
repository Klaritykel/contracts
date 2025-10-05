// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IKasterStakingConfig.sol";
import "../storage/Types.sol";

error ZeroAddress();
error NotTreasury();
error TreasuryNotSet();
error StakeNotFound();
error NoActiveStakes();

abstract contract KasterStakingBase is Ownable, ReentrancyGuard, Pausable {
    IERC20 public immutable KAST;
    IKasterStakingConfig public config;

    uint256 public immutable programStart;
    uint256 public boostedStakers;           // Count of users with at least one boosted stake
    
    // Multi-stake storage
    mapping(address => Types.UserStakes) public userStakes;
    mapping(address => mapping(uint256 => Types.StakeInfo)) public stakes;
    mapping(address => bool) public hasBoostStake;  // Does user have ANY boosted stake?

    uint256 public totalStaked;
    uint256 public totalRewardsDistributed;
    address public nextStakingContract;

    event Staked(address indexed user, uint256 indexed stakeId, uint256 amount, uint256 lockMonths, bool boost);
    event ExtendedLock(address indexed user, uint256 indexed stakeId, uint256 newLockMonths);
    event Claimed(address indexed user, uint256 indexed stakeId, uint256 reward, uint256 pointsAdded);
    event Restaked(address indexed user, uint256 indexed stakeId, uint256 reward, uint256 pointsCarried);
    event Unstaked(address indexed user, uint256 indexed stakeId, uint256 amount);
    event Migrated(address indexed user, uint256 indexed stakeId, uint256 principal, uint256 rewards, uint256 points, address target);
    event NextContractSet(address target);

    uint256 public totalRewardsAdded;
    uint256 public totalRewardsRecovered;
    address public rewardsTreasury;

    event RewardsAdded(address indexed funder, uint256 amount);
    event RewardsRecovered(address indexed to, uint256 amount);
    event RewardsTreasurySet(address indexed treasury);

    constructor(address _kast, address _config) 
        Ownable(msg.sender)
    {
        if (_kast == address(0) || _config == address(0)) revert ZeroAddress();
        KAST = IERC20(_kast);
        config = IKasterStakingConfig(_config);
        programStart = block.timestamp;
        rewardsTreasury = msg.sender;
        emit RewardsTreasurySet(msg.sender);
    }

    modifier onlyTreasury() {
        if (rewardsTreasury == address(0)) revert TreasuryNotSet();
        if (msg.sender != rewardsTreasury) revert NotTreasury();
        _;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setRewardsTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        rewardsTreasury = _treasury;
        emit RewardsTreasurySet(_treasury);
    }

    function setConfig(address _config) external onlyOwner {
        if (_config == address(0)) revert ZeroAddress();
        config = IKasterStakingConfig(_config);
    }
    
    function setNextContract(address target) external onlyOwner {
        nextStakingContract = target;
        emit NextContractSet(target);
    }

    // Helper functions
    function _lockEnd(Types.StakeInfo memory s) internal pure returns (uint256) {
        return s.lockStart + (s.lockMonths * 30 days);
    }
    
    function _weeksSince(uint256 t0) internal view returns (uint256) {
        if (block.timestamp <= t0) return 0;
        unchecked {
            return (block.timestamp - t0) / (7 days);
        }
    }
    
    function _stakeExists(address user, uint256 stakeId) internal view returns (bool) {
        return stakes[user][stakeId].principal > 0;
    }
    
    function _removeStakeId(address user, uint256 stakeId) internal {
        uint256[] storage ids = userStakes[user].stakeIds;
        for (uint256 i = 0; i < ids.length; i++) {
            if (ids[i] == stakeId) {
                ids[i] = ids[ids.length - 1];
                ids.pop();
                break;
            }
        }
    }
}