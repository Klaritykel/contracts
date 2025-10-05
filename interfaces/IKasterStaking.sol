// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IKasterStakingConfig.sol";

interface IKasterStaking {
    // State variables
    function config() external view returns (IKasterStakingConfig);
    function totalStaked() external view returns (uint256);
    function totalRewardsDistributed() external view returns (uint256);
    function totalRewardsAdded() external view returns (uint256);
    function totalRewardsRecovered() external view returns (uint256);
    function hasBoostStake(address) external view returns (bool);
    function isBoostStaker(address) external view returns (bool);  // Backwards compatibility
    
    // Multi-stake storage accessor
    function stakes(address user, uint256 stakeId) external view returns (
        uint256 principal,
        uint256 lockStart,
        uint256 lockMonths,
        uint256 lastClaim,
        uint256 sizeSnapshot,
        uint256 accRewards,
        uint256 points,
        uint256 pointsCheckpoint
    );
    
    // User stake management
    function getUserStakeIds(address user) external view returns (uint256[] memory);
    function getUserStakeCount(address user) external view returns (uint256);
    function getUserTotalPrincipal(address user) external view returns (uint256);
    
    // View functions
    function pending(address user, uint256 stakeId) external view returns (uint256 reward, uint256 points);
    function currentApr(address user, uint256 stakeId) external view returns (uint256);
    function contractBalance() external view returns (uint256);
    function rewardsAvailable() external view returns (uint256);
    function rewardsRemainingAccounted() external view returns (uint256);
    function votingPower(address user) external view returns (uint256);
    function claimableNow(address user, uint256 stakeId) external view returns (bool);
    function lockEnded(address user, uint256 stakeId) external view returns (bool);
}