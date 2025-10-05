// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IKasterStakingConfig.sol";

interface IKasterStakingCore {
    // State variables
    function KAST() external view returns (IERC20);
    function config() external view returns (IKasterStakingConfig);
    function totalStaked() external view returns (uint256);
    function programStart() external view returns (uint256);
    function hasBoostStake(address) external view returns (bool);
    function totalRewardsDistributed() external view returns (uint256);
    function totalRewardsAdded() external view returns (uint256);
    function totalRewardsRecovered() external view returns (uint256);
    
    // Core functions
    function stake(uint256 amount, uint256 lockMonths) external returns (uint256 stakeId);
    function addToStake(uint256 stakeId, uint256 amount) external;
    function extendLock(uint256 stakeId, uint256 newLockMonths) external;
    function claimRewards(uint256 stakeId) external;
    function restakeRewards(uint256 stakeId) external;
    function unstake(uint256 stakeId) external;
    function migrate(uint256 stakeId) external;
    
    // View functions
    function getUserStakeIds(address user) external view returns (uint256[] memory);
    function getUserTotalPrincipal(address user) external view returns (uint256);
    function getStake(address user, uint256 stakeId) external view returns (
        uint256 id,
        uint256 principal,
        uint256 lockStart,
        uint256 lockMonths,
        uint256 lastClaim,
        uint256 sizeSnapshot,
        uint256 accRewards,
        uint256 points,
        uint256 pointsCheckpoint,
        bool isBoosted
    );
}