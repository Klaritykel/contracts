// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./core/KasterStakingRewards.sol";
import "./core/KasterStakingPoints.sol";
import "./libraries/FixedPoint.sol"; // ✅ FIXED: Added import

// ✅ FIXED: Added all missing custom errors
error ZeroAmount();
error BadLock();
error NoStake();
error StillLocked();
error TooSoon();
error NoRewards();
error NoTarget();
error ExceedsAvailable();
error CannotRecoverToSelf();
error InsufficientBalance();

/**
 * @title KasterStakingCore
 * @notice Minimal core staking contract - all view functions in separate Reader contract
 * @dev Deploys under 24KB by moving non-essential functions to external contracts
 */
contract KasterStakingCore is KasterStakingRewards, KasterStakingPoints {
    
    constructor(address _kast, address _config) KasterStakingBase(_kast, _config) {}

    function _previewRewards(Types.StakeInfo memory s, address user)
        internal
        view
        override(KasterStakingPoints, KasterStakingRewards)
        returns (uint256)
    {
        return KasterStakingRewards._previewRewards(s, user);
    }

    // ===== CORE STAKING FUNCTIONS =====

    /// @notice Create new stake position
    /// @param amount Amount to stake
    /// @param lockMonths Lock duration in months
    /// @return stakeId Unique ID for the created stake
    function stake(uint256 amount, uint256 lockMonths) 
        external 
        nonReentrant 
        whenNotPaused 
        returns (uint256 stakeId) 
    {
        if (amount == 0) revert ZeroAmount();
        if (lockMonths < config.minLockMonths() || lockMonths > config.maxLockMonths()) {
            revert BadLock();
        }

        KAST.transferFrom(msg.sender, address(this), amount);

        Types.UserStakes storage userInfo = userStakes[msg.sender];
        stakeId = userInfo.nextStakeId++;
        
        Types.StakeInfo storage s = stakes[msg.sender][stakeId];
        s.id = stakeId;
        s.principal = amount;
        s.lockStart = block.timestamp;
        s.lockMonths = lockMonths;
        s.lastClaim = block.timestamp;
        s.pointsCheckpoint = block.timestamp;
        s.sizeSnapshot = amount;

        userInfo.stakeIds.push(stakeId);
        userInfo.totalPrincipal += amount;

        bool boost = _maybeEnrollBoost(msg.sender, stakeId, amount);
        
        totalStaked += amount;
        
        emit Staked(msg.sender, stakeId, amount, lockMonths, boost);
    }

    /// @notice Add more tokens to existing stake
    /// @param stakeId The stake to add to
    /// @param amount Amount to add
    function addToStake(uint256 stakeId, uint256 amount) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        if (amount == 0) revert ZeroAmount();
        if (!_stakeExists(msg.sender, stakeId)) revert StakeNotFound();

        Types.StakeInfo storage s = stakes[msg.sender][stakeId];
        
        KAST.transferFrom(msg.sender, address(this), amount);
        _accrueRewards(msg.sender, s);

        s.principal += amount;
        s.sizeSnapshot = s.principal;
        
        userStakes[msg.sender].totalPrincipal += amount;

        bool boost = _maybeEnrollBoost(msg.sender, stakeId, s.principal);
        
        totalStaked += amount;
        
        emit Staked(msg.sender, stakeId, amount, s.lockMonths, boost);
    }

    /// @notice Extend lock period of a stake
    /// @param stakeId The stake to extend
    /// @param newLockMonths New lock duration (must be longer than current)
    function extendLock(uint256 stakeId, uint256 newLockMonths) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        if (!_stakeExists(msg.sender, stakeId)) revert StakeNotFound();
        if (newLockMonths > config.maxLockMonths()) revert BadLock();

        Types.StakeInfo storage s = stakes[msg.sender][stakeId];
        if (newLockMonths <= s.lockMonths) revert BadLock();

        _accrueRewards(msg.sender, s);
        s.lockMonths = newLockMonths;
        
        emit ExtendedLock(msg.sender, stakeId, newLockMonths);
    }

    /// @notice Claim rewards from a stake
    /// @param stakeId The stake to claim from
    function claimRewards(uint256 stakeId) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        if (!_stakeExists(msg.sender, stakeId)) revert StakeNotFound();
        
        Types.StakeInfo storage s = stakes[msg.sender][stakeId];
        _accrueRewards(msg.sender, s);
        if (block.timestamp < s.lastClaim + config.claimInterval()) revert TooSoon();

        (uint256 reward, uint256 pointsAdd) = _settleClaimAndPoints(s);
        
        emit Claimed(msg.sender, stakeId, reward, pointsAdd);
        
        if (reward > 0) KAST.transfer(msg.sender, reward);
    }

    /// @notice Restake rewards back into the same stake
    /// @param stakeId The stake to restake into
    function restakeRewards(uint256 stakeId) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        if (!_stakeExists(msg.sender, stakeId)) revert StakeNotFound();
        
        Types.StakeInfo storage s = stakes[msg.sender][stakeId];
        _accrueRewards(msg.sender, s);
        if (block.timestamp < s.lastClaim + config.claimInterval()) revert TooSoon();

        (uint256 reward, uint256 pointsAdd) = _settleClaimAndPoints(s);
        if (reward == 0) revert NoRewards();
        
        s.principal += reward;
        totalStaked += reward;
        s.sizeSnapshot = s.principal;
        
        userStakes[msg.sender].totalPrincipal += reward;

        emit Restaked(msg.sender, stakeId, reward, pointsAdd);
    }

    /// @notice Unstake a specific position (after lock period)
    /// @param stakeId The stake to unstake
    function unstake(uint256 stakeId) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        if (!_stakeExists(msg.sender, stakeId)) revert StakeNotFound();
        
        Types.StakeInfo storage s = stakes[msg.sender][stakeId];
        if (block.timestamp < _lockEnd(s)) revert StillLocked();

        _accrueRewards(msg.sender, s);
        
        uint256 finalReward = 0;
        if (s.accRewards > 0 && block.timestamp >= s.lastClaim + config.claimInterval()) {
            (uint256 reward, ) = _settleClaimAndPoints(s);
            finalReward = reward;
        }

        uint256 amt = s.principal;
        totalStaked -= amt;
        
        userStakes[msg.sender].totalPrincipal -= amt;
        _removeStakeId(msg.sender, stakeId);
        
        delete stakes[msg.sender][stakeId];

        emit Unstaked(msg.sender, stakeId, amt);
        
        if (finalReward > 0) KAST.transfer(msg.sender, finalReward);
        KAST.transfer(msg.sender, amt);
    }

    // ===== ADMIN FUNCTIONS =====
    
    /// @notice Fund rewards by transferring tokens
    /// @param amount Amount of tokens to fund
    function fundRewards(uint256 amount) 
        external 
        nonReentrant 
        onlyTreasury 
    {    
        if (amount == 0) revert ZeroAmount();
        
        emit RewardsAdded(msg.sender, amount);
        
        KAST.transferFrom(msg.sender, address(this), amount);
        totalRewardsAdded += amount;
    }

    /// @notice Notify that rewards were sent (without transferFrom)
    /// @param amount Amount that was sent
    /// @dev ✅ FIXED: Added balance validation
    function notifyRewards(uint256 amount) 
        external 
        nonReentrant 
        onlyTreasury 
    {
        if (amount == 0) revert ZeroAmount();
        
        // ✅ FIXED: Validate tokens actually exist
        uint256 currentBalance = KAST.balanceOf(address(this));
        uint256 expectedBalance = totalStaked + totalRewardsAdded + amount - totalRewardsDistributed - totalRewardsRecovered;
        
        if (currentBalance < expectedBalance) revert InsufficientBalance();
        
        totalRewardsAdded += amount;
        emit RewardsAdded(msg.sender, amount);
    }

    /// @notice Recover excess rewards
    /// @param amount Amount to recover
    /// @param to Address to send recovered tokens
    function recoverExcessRewards(uint256 amount, address to) 
        external 
        onlyTreasury 
        nonReentrant 
    {
        if (to == address(0)) revert ZeroAddress();
        if (to == address(this)) revert CannotRecoverToSelf();
        
        uint256 bal = KAST.balanceOf(address(this));
        uint256 avail = bal > totalStaked ? bal - totalStaked : 0;
        
        if (amount == 0 || amount > avail) revert ExceedsAvailable();
        
        totalRewardsRecovered += amount;
        
        emit RewardsRecovered(to, amount);
        
        KAST.transfer(to, amount);
    }

    /// @notice Migrate a specific stake to new contract (after lock ends)
    /// @param stakeId The stake to migrate
    function migrate(uint256 stakeId) 
        external 
        nonReentrant 
    {
        if (nextStakingContract == address(0)) revert NoTarget();
        if (!_stakeExists(msg.sender, stakeId)) revert StakeNotFound();
        
        Types.StakeInfo storage s = stakes[msg.sender][stakeId];
        if (block.timestamp < _lockEnd(s)) revert StillLocked();
        
        _accrueRewards(msg.sender, s);

        uint256 principal = s.principal;
        uint256 rewards = s.accRewards;
        uint256 tau = _weeksSince(s.pointsCheckpoint);
        
        uint256 pointsAll = s.points;
        if (rewards > 0 && tau > 0) {
            uint256 eTerm = FixedPoint.expNeg1e18(config.k() * tau);
            if (eTerm > 1e18) eTerm = 1e18;
            
            uint256 factor;
            unchecked { 
                factor = 1e18 - eTerm; 
            }
            
            pointsAll += (rewards * config.Pmax() * factor) / 1e36;
        }

        totalStaked -= principal;
        totalRewardsDistributed += rewards;
        
        userStakes[msg.sender].totalPrincipal -= principal;
        _removeStakeId(msg.sender, stakeId);
        
        delete stakes[msg.sender][stakeId];

        emit Migrated(msg.sender, stakeId, principal, rewards, pointsAll, nextStakingContract);
        
        KAST.transfer(nextStakingContract, principal + rewards);
    }

    // ===== MINIMAL VIEW FUNCTIONS =====
    // (Complex views are in Reader contract)
    
    /// @notice Get user's stake IDs
    /// @param user Address to query
    /// @return Array of stake IDs
    function getUserStakeIds(address user) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return userStakes[user].stakeIds;
    }

    /// @notice Get user's total principal across all stakes
    /// @param user Address to query
    /// @return Total principal amount
    function getUserTotalPrincipal(address user) 
        external 
        view 
        returns (uint256) 
    {
        return userStakes[user].totalPrincipal;
    }

    /// @notice Get raw stake data (for Reader contract)
    /// @param user Stake owner
    /// @param stakeId Stake ID
    function getStake(address user, uint256 stakeId) 
        external 
        view 
        returns (
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
        ) 
    {
        Types.StakeInfo memory s = stakes[user][stakeId];
        return (
            s.id,
            s.principal,
            s.lockStart,
            s.lockMonths,
            s.lastClaim,
            s.sizeSnapshot,
            s.accRewards,
            s.points,
            s.pointsCheckpoint,
            s.isBoosted
        );
    }
}