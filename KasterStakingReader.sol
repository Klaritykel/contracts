// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IKasterStakingCore.sol";
import "./interfaces/IKasterStakingConfig.sol";
import "./libraries/FixedPoint.sol";
import "./libraries/AprModel.sol";
import "./libraries/VotingModel.sol";

/**
 * @title KasterStakingReader
 * @notice All view functions - separate from core to reduce main contract size
 * @dev Optimized to avoid stack too deep errors
 */
contract KasterStakingReader {
    IKasterStakingCore public immutable core;
    IKasterStakingConfig public immutable config;

    struct StakeView {
        uint256 id;
        uint256 principal;
        uint256 lockStart;
        uint256 lockMonths;
        uint256 lockEnd;
        uint256 lastClaim;
        uint256 sizeSnapshot;
        uint256 accRewards;
        uint256 pendingRewards;
        uint256 points;
        uint256 projectedPoints;
        bool isBoosted;
        uint256 currentAPR;
    }

    // Struct to pass stake data and avoid stack too deep
    struct StakeData {
        uint256 principal;
        uint256 lockMonths;
        uint256 sizeSnapshot;
        uint256 lastClaim;
        bool isBoosted;
    }

    // Struct for APR calculation parameters
    struct APRParams {
        uint256 baseAPR;
        uint256 maxAPR;
        uint256 lockMonths;
        uint256 sizeSnapshot;
    }

    constructor(address _core) {
        core = IKasterStakingCore(_core);
        config = IKasterStakingConfig(core.config());
    }

    /// @notice Get detailed info for one stake
    function getStakeInfo(address user, uint256 stakeId) external view returns (StakeView memory v) {
        v = _getBasicStakeInfo(user, stakeId);
        
        // Pack data into struct to avoid stack too deep
        StakeData memory data = StakeData({
            principal: v.principal,
            lockMonths: v.lockMonths,
            sizeSnapshot: v.sizeSnapshot,
            lastClaim: v.lastClaim,
            isBoosted: v.isBoosted
        });
        
        v.pendingRewards = _calculatePendingRewards(user, stakeId, data);
        v.projectedPoints = _calculateProjectedPoints(v.accRewards, v.pendingRewards, v.points, v.lastClaim);
        v.currentAPR = _calculateAPR(user, stakeId, data);
    }

    /// @notice Get all stakes for user
    function getAllStakesInfo(address user) external view returns (StakeView[] memory) {
        uint256[] memory stakeIds = core.getUserStakeIds(user);
        StakeView[] memory views = new StakeView[](stakeIds.length);
        
        for (uint256 i = 0; i < stakeIds.length; i++) {
            views[i] = this.getStakeInfo(user, stakeIds[i]);
        }
        
        return views;
    }

    /// @notice Get total voting power across all stakes
    function votingPower(address user) external view returns (uint256 totalVP) {
        uint256[] memory stakeIds = core.getUserStakeIds(user);
        
        for (uint256 i = 0; i < stakeIds.length; i++) {
            (, uint256 principal,, uint256 lockMonths,,,,,, ) = core.getStake(user, stakeIds[i]);
            totalVP += VotingModel.votingPower(principal, lockMonths, config.b(), config.gamma());
        }
    }

    /// @notice Get pending rewards for stake
    function pending(address user, uint256 stakeId) external view returns (uint256 reward, uint256 projectedPoints) {
        // Use a separate function to get stake data and avoid stack issues
        (StakeData memory data, uint256 accRewards, uint256 storedPoints, uint256 pointsCheckpoint) = _getStakeDataForPending(user, stakeId);
        
        if (data.principal == 0) return (0, 0);

        // Calculate pending rewards
        uint256 pendingNow = _calculatePendingRewards(user, stakeId, data);
        reward = accRewards + pendingNow;
        
        // Calculate projected points in a separate function
        projectedPoints = _computeProjectedPoints(reward, storedPoints, pointsCheckpoint);
    }
    
    /// @notice Helper to get stake data for pending calculation
    function _getStakeDataForPending(address user, uint256 stakeId) 
        internal view 
        returns (StakeData memory data, uint256 accRewards, uint256 storedPoints, uint256 pointsCheckpoint) 
    {
        (
            ,
            uint256 principal,
            ,
            uint256 lockMonths,
            uint256 lastClaim,
            uint256 sizeSnapshot,
            uint256 _accRewards,
            uint256 _storedPoints,
            uint256 _pointsCheckpoint,
            bool isBoosted
        ) = core.getStake(user, stakeId);
        
        data = StakeData({
            principal: principal,
            lockMonths: lockMonths,
            sizeSnapshot: sizeSnapshot,
            lastClaim: lastClaim,
            isBoosted: isBoosted
        });
        
        accRewards = _accRewards;
        storedPoints = _storedPoints;
        pointsCheckpoint = _pointsCheckpoint;
    }
    
    /// @notice Compute projected points
    function _computeProjectedPoints(uint256 reward, uint256 storedPoints, uint256 pointsCheckpoint) 
        internal view 
        returns (uint256) 
    {
        uint256 tau = (pointsCheckpoint == 0) ? 0 : ((block.timestamp - pointsCheckpoint) / 7 days);
        
        if (reward == 0 || tau == 0) {
            return storedPoints;
        }
        
        uint256 eTerm = FixedPoint.expNeg1e18(config.k() * tau);
        if (eTerm > 1e18) eTerm = 1e18;
        
        uint256 factor;
        unchecked { factor = 1e18 - eTerm; }
        
        return storedPoints + (reward * config.Pmax() * factor) / 1e36;
    }

    /// @notice Get current APR for stake
    function currentApr(address user, uint256 stakeId) external view returns (uint256) {
        (, uint256 principal,, uint256 lockMonths,, uint256 sizeSnapshot,,,, bool isBoosted) = 
            core.getStake(user, stakeId);
        
        if (principal == 0) return 0;
        
        StakeData memory data = StakeData({
            principal: principal,
            lockMonths: lockMonths,
            sizeSnapshot: sizeSnapshot,
            lastClaim: 0, // Not needed for APR calculation
            isBoosted: isBoosted
        });
        
        return _calculateAPR(user, stakeId, data);
    }

    /// @notice Check if stake is claimable
    function claimableNow(address user, uint256 stakeId) external view returns (bool) {
        (,uint256 principal,,, uint256 lastClaim,,,,, ) = core.getStake(user, stakeId);
        if (principal == 0) return false;
        return block.timestamp >= lastClaim + config.claimInterval();
    }

    /// @notice Check if stake is unlocked
    function lockEnded(address user, uint256 stakeId) external view returns (bool) {
        (,, uint256 lockStart, uint256 lockMonths,,,,,,) = core.getStake(user, stakeId);
        if (lockStart == 0) return false;
        return block.timestamp >= (lockStart + lockMonths * 30 days);
    }

    /// @notice Get contract balance
    function contractBalance() external view returns (uint256) {
        return core.KAST().balanceOf(address(core));
    }

    /// @notice Get available rewards
    function rewardsAvailable() external view returns (uint256) {
        uint256 bal = core.KAST().balanceOf(address(core));
        uint256 staked = core.totalStaked();
        return bal > staked ? bal - staked : 0;
    }

    // ===== INTERNAL HELPER FUNCTIONS (to avoid stack too deep) =====

    /// @notice Get basic stake information
    function _getBasicStakeInfo(address user, uint256 stakeId) internal view returns (StakeView memory v) {
        (
            uint256 id,
            uint256 principal,
            uint256 lockStart,
            uint256 lockMonths,
            uint256 lastClaim,
            uint256 sizeSnapshot,
            uint256 accRewards,
            uint256 points,
            , // pointsCheckpoint - not needed here
            bool isBoosted
        ) = core.getStake(user, stakeId);

        require(principal > 0, "stake not found");

        v.id = id;
        v.principal = principal;
        v.lockStart = lockStart;
        v.lockMonths = lockMonths;
        v.lockEnd = lockStart + lockMonths * 30 days;
        v.lastClaim = lastClaim;
        v.sizeSnapshot = sizeSnapshot;
        v.accRewards = accRewards;
        v.points = points;
        v.isBoosted = isBoosted;
    }

    /// @notice Calculate pending rewards for a stake using packed data
    function _calculatePendingRewards(
        address user,
        uint256 stakeId,
        StakeData memory data
    ) internal view returns (uint256) {
        uint256 dt = block.timestamp - data.lastClaim;
        if (dt == 0) return 0;

        (uint256 baseAPR, uint256 maxAPR) = _getAPRWindow(user, stakeId, data.isBoosted);
        
        APRParams memory params = APRParams({
            baseAPR: baseAPR,
            maxAPR: maxAPR,
            lockMonths: data.lockMonths,
            sizeSnapshot: data.sizeSnapshot
        });
        
        uint256 apr = _computeAPR(params);
        
        return data.principal * apr / 1e18 * dt / 365 days;
    }

    /// @notice Compute APR from parameters
    function _computeAPR(APRParams memory params) internal view returns (uint256) {
        uint256 fL = AprModel.lockPow(params.lockMonths, config.delta());
        uint256 fS = AprModel.sizeFactor(params.sizeSnapshot, config.S0());
        return AprModel.aprBlend(params.baseAPR, params.maxAPR, config.wL(), config.wS(), fL, fS);
    }

    /// @notice Calculate projected points
    function _calculateProjectedPoints(
        uint256 accRewards,
        uint256 pendingRewards,
        uint256 currentPoints,
        uint256 pointsCheckpoint
    ) internal view returns (uint256) {
        uint256 tauWeeks = (pointsCheckpoint == 0) ? 0 : ((block.timestamp - pointsCheckpoint) / 7 days);
        uint256 rewardTotal = accRewards + pendingRewards;
        
        if (rewardTotal == 0 || tauWeeks == 0) {
            return currentPoints;
        }

        uint256 eTerm = FixedPoint.expNeg1e18(config.k() * tauWeeks);
        if (eTerm > 1e18) eTerm = 1e18;
        
        uint256 factor;
        unchecked { factor = 1e18 - eTerm; }
        
        uint256 addPts = (rewardTotal * config.Pmax() * factor) / 1e36;
        return currentPoints + addPts;
    }

    /// @notice Get APR window based on boost status
    function _getAPRWindow(address /*user*/, uint256 /*stakeId*/, bool isBoosted) internal view returns (uint256 baseAPR, uint256 maxAPR) {
        bool boostWindow = block.timestamp <= core.programStart() + config.boostDuration();
        
        if (boostWindow && isBoosted) {
            return (config.baseAPRBoostPhase(), config.maxAPRBoostPhase());
        }
        return (config.baseAPR(), config.maxAPR());
    }

    /// @notice Calculate APR for a stake using packed data
    function _calculateAPR(
        address user,
        uint256 stakeId,
        StakeData memory data
    ) internal view returns (uint256) {
        if (data.principal == 0) return 0;
        
        (uint256 baseAPR, uint256 maxAPR) = _getAPRWindow(user, stakeId, data.isBoosted);
        
        return AprModel.calculateAPR(
            data.lockMonths,
            data.sizeSnapshot,
            baseAPR,
            maxAPR,
            config.delta(),
            config.wL(),
            config.wS(),
            config.S0()
        );
    }
}