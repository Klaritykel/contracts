// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./core/KasterStakingRewards.sol";
import "./core/KasterStakingPoints.sol";
import "./libraries/VotingModel.sol";

contract KasterStaking is KasterStakingRewards, KasterStakingPoints {
    constructor(address _kast, address _config) KasterStakingBase(_kast, _config) {}


    struct StakerView {
        uint256 principal;
        uint256 lockStart;
        uint256 lockMonths;
        uint256 lockEnd;
        uint256 lastClaim;
        uint256 sizeSnapshot;

        uint256 accRewards;       // stored (unclaimed)
        uint256 pendingRewards;   // computed now

        uint256 points;           // stored
        uint256 projectedPoints;  // includes pendingRewards over tau

        bool    isBoosted;
        uint256 currentAPR;       // 1e18 (e.g., 0.6906e18 = 69.06%)
    }



    function _previewRewards(Types.StakeInfo memory s, address user)
        internal
        view
        override(KasterStakingPoints, KasterStakingRewards)
        returns (uint256)
    {
        return KasterStakingRewards._previewRewards(s, user);
    }

    // --------- User actions ---------
    function stake(uint256 amount, uint256 lockMonths) external nonReentrant {
        require(amount > 0, "amount=0");
        require(lockMonths >= config.minLockMonths() && lockMonths <= config.maxLockMonths(), "bad lock");

        KAST.transferFrom(msg.sender, address(this), amount);

        Types.StakeInfo storage s = stakes[msg.sender];
        _accrueRewards(msg.sender, s);

        s.principal += amount;
        if (s.lockStart == 0) {
            s.lockStart = block.timestamp;
            s.lastClaim = block.timestamp;
            s.pointsCheckpoint = block.timestamp;
        }
        if (lockMonths > s.lockMonths) {
            s.lockMonths = lockMonths;
            emit ExtendedLock(msg.sender, s.lockMonths);
        }
        s.sizeSnapshot = s.principal;

        bool boost = _maybeEnrollBoost(msg.sender, s.principal);
        totalStaked += amount;
        emit Staked(msg.sender, amount, s.lockMonths, boost);
    }

    function restakeRewards() external nonReentrant {
        Types.StakeInfo storage s = stakes[msg.sender];
        require(s.principal > 0, "no stake");
        _accrueRewards(msg.sender, s);
        require(block.timestamp >= s.lastClaim + config.claimInterval(), "too soon");

        (uint256 reward, uint256 pointsAdd) = _settleClaimAndPoints(s);
        s.principal += reward;                 // compound
        totalStaked += reward;
        s.sizeSnapshot = s.principal;

        emit Restaked(msg.sender, reward, pointsAdd);
    }

    function claimRewards() external nonReentrant {
        Types.StakeInfo storage s = stakes[msg.sender];
        require(s.principal > 0, "no stake");
        _accrueRewards(msg.sender, s);
        require(block.timestamp >= s.lastClaim + config.claimInterval(), "too soon");

        (uint256 reward, uint256 pointsAdd) = _settleClaimAndPoints(s);
        if (reward > 0) KAST.transfer(msg.sender, reward);
        emit Claimed(msg.sender, reward, pointsAdd);
    }

    function unstake() external nonReentrant {
        Types.StakeInfo storage s = stakes[msg.sender];
        require(s.principal > 0, "no stake");
        require(block.timestamp >= _lockEnd(s), "locked");

        _accrueRewards(msg.sender, s);
        if (s.accRewards > 0 && block.timestamp >= s.lastClaim + config.claimInterval()) {
            (uint256 reward, ) = _settleClaimAndPoints(s);
            if (reward > 0) KAST.transfer(msg.sender, reward);
        }

        uint256 amt = s.principal;
        totalStaked -= amt;
        delete stakes[msg.sender];

        KAST.transfer(msg.sender, amt);
        emit Unstaked(msg.sender, amt);
    }

    /**
    * @notice Funder must `approve` this contract first. Contract pulls tokens in.
    */
    function fundRewards(uint256 amount) external nonReentrant onlyTreasury {    
        require(amount > 0, "amount=0");
        KAST.transferFrom(msg.sender, address(this), amount);
        totalRewardsAdded += amount;
        emit RewardsAdded(msg.sender, amount);
    }

    /**
    * @notice Call this after you have already transferred KAST to the contract to sync accounting.
    */
    function notifyRewards(uint256 amount) external nonReentrant onlyTreasury {
        require(amount > 0, "amount=0");
        // Trust that owner only notifies what actually arrived; optionally sanity-check:
        // require(KAST.balanceOf(address(this)) >= totalStaked + rewardsAvailable() + amount, "bad notify");
        totalRewardsAdded += amount;
        emit RewardsAdded(msg.sender, amount);
    }

    function recoverExcessRewards(uint256 amount, address to) external onlyTreasury nonReentrant {
        require(to != address(0), "zero to");
        uint256 avail = rewardsAvailable();
        require(amount > 0 && amount <= avail, "exceeds avail");
        KAST.transfer(to, amount);
        totalRewardsRecovered += amount;
        emit RewardsRecovered(to, amount);
    }



    // --------- Views ---------
    function pending(address user) external view returns (uint256 reward, uint256 points) {
        Types.StakeInfo memory s = stakes[user];
        if (s.principal == 0 || s.lastClaim == 0) return (0, s.points);

        uint256 rNow = _previewRewards(s, user);
        reward = s.accRewards + rNow;

        uint256 tau = (s.pointsCheckpoint == 0) ? 0 : _weeksSince(s.pointsCheckpoint);
        if (reward == 0 || tau == 0) return (reward, s.points);

        // patience points (uses clamped expNeg now)
        uint256 eTerm = FixedPoint.expNeg1e18(config.k() * tau);
        uint256 add = reward * config.Pmax() / 1e18 * (1e18 - eTerm) / 1e18;
        points = s.points + add;
    }


    function votingPower(address user) external view returns (uint256) {
        Types.StakeInfo memory s = stakes[user];
        return VotingModel.votingPower(s.principal, s.lockMonths, config.b(), config.gamma());
    }

    function currentApr(address user) public view returns (uint256 apr1e18) {
        Types.StakeInfo memory s = stakes[user];
        if (s.principal == 0) return 0;

        (uint256 baseAPR, uint256 maxAPR) = _currentAPRWindow(user);

        return AprModel.calculateAPR(s.lockMonths, s.principal, baseAPR, maxAPR, config.delta(), config.wL(), config.wS(), config.S0()); // 1e18
    }

    /// @notice Raw contract balance of KAST.
    function contractBalance() public view returns (uint256) {
        return KAST.balanceOf(address(this));
    }

    /// @notice Rewards available right now: contract balance minus principal backing.
    /// @dev This is the hard lower-bound of what can be paid as rewards without touching principal.
    function rewardsAvailable() public view returns (uint256) {
        uint256 bal = contractBalance();
        return (bal > totalStaked) ? (bal - totalStaked) : 0;
    }

    /// @notice Accounting-based remaining rewards (tracks via notify/fund/claims/recover).
    function rewardsRemainingAccounted() public view returns (uint256) {
        // May differ slightly from rewardsAvailable() if someone sent tokens without notify/fund.
        uint256 spent = totalRewardsDistributed + totalRewardsRecovered;
        return (totalRewardsAdded > spent) ? (totalRewardsAdded - spent) : 0;
    }

    /// @notice Global rewards stats handy for UIs.
    struct RewardsStats {
        uint256 contractBal;
        uint256 principalBacking;          // totalStaked
        uint256 liquidRewards;             // rewardsAvailable()
        uint256 totalAdded;                // totalRewardsAdded
        uint256 totalPaidOut;              // totalRewardsDistributed
        uint256 totalRecovered;            // totalRewardsRecovered
        uint256 remainingAccounted;        // totalAdded - paidOut - recovered
    }
    function getRewardsStats() external view returns (RewardsStats memory r) {
        r.contractBal        = contractBalance();
        r.principalBacking   = totalStaked;
        r.liquidRewards      = rewardsAvailable();
        r.totalAdded         = totalRewardsAdded;
        r.totalPaidOut       = totalRewardsDistributed;
        r.totalRecovered     = totalRewardsRecovered;
        r.remainingAccounted = rewardsRemainingAccounted();
    }


    function getStakerInfo(address user) external view returns (StakerView memory v) {
        Types.StakeInfo memory s = stakes[user];

        // base fields
        v.principal    = s.principal;
        v.lockStart    = s.lockStart;
        v.lockMonths   = s.lockMonths;
        v.lockEnd      = (s.lockStart == 0) ? 0 : (s.lockStart + s.lockMonths * 30 days);
        v.lastClaim    = s.lastClaim;
        v.sizeSnapshot = s.sizeSnapshot;

        // rewards
        uint256 pendingNow = _previewRewards(s, user); // uses APR (wad) under the hood
        v.accRewards      = s.accRewards;
        v.pendingRewards  = pendingNow;

        // points (projected = stored + new from total unclaimed over tau weeks)
        // Points = R * Pmax * (1 - e^{-k * tau})
        uint256 tauWeeks = (s.pointsCheckpoint == 0)
            ? 0
            : ((block.timestamp - s.pointsCheckpoint) / (7 days));

        uint256 rewardTotal = s.accRewards + pendingNow;
        if (rewardTotal == 0 || tauWeeks == 0) {
            v.points          = s.points;
            v.projectedPoints = s.points;
        } else {
            // factor = 1 - e^{-k * tau}  (wad)
            uint256 eTerm  = FixedPoint.expNeg1e18(config.k() * tauWeeks);
            uint256 factor = 1e18 - eTerm;

            // addPts = rewardTotal * Pmax/1e18 * factor/1e18
            uint256 addPts = rewardTotal * config.Pmax() / 1e18 * factor / 1e18;

            v.points          = s.points;
            v.projectedPoints = s.points + addPts;
        }

        // cohort / apr
        v.isBoosted  = isBoostStaker[user];
        v.currentAPR = currentApr(user); // returns wad (1e18)
    }



    function claimableNow(address user) external view returns (bool) {
        Types.StakeInfo memory s = stakes[user];
        if (s.principal == 0) return false;
        return block.timestamp >= s.lastClaim + config.claimInterval();
    }

    function lockEnded(address user) external view returns (bool) {
        Types.StakeInfo memory s = stakes[user];
        if (s.lockStart == 0) return false;
        return block.timestamp >= (s.lockStart + s.lockMonths * 30 days);
    }




    // --------- Migration ---------
    function migrate() external nonReentrant {
        require(nextStakingContract != address(0), "no target");
        Types.StakeInfo storage s = stakes[msg.sender];
        require(s.principal > 0, "no stake");
        _accrueRewards(msg.sender, s);

        uint256 principal = s.principal;
        uint256 rewards = s.accRewards;
        uint256 tau = _weeksSince(s.pointsCheckpoint);
        uint256 pointsAll = s.points + (rewards == 0 ? 0 : (rewards * (config.Pmax()) / 1e18 * (1e18 - FixedPoint.expNeg1e18(config.k() * tau)) / 1e18));

        totalStaked -= principal;
        delete stakes[msg.sender];

        KAST.transfer(nextStakingContract, principal + rewards);
        totalRewardsDistributed += rewards;
        emit Migrated(msg.sender, principal, rewards, pointsAll, nextStakingContract);
        // NOTE: next contract should have an importer to credit user balances.
    }
}
