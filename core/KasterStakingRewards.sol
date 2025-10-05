// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../base/KasterStakingBase.sol";
import "../libraries/AprModel.sol";
import "../libraries/FixedPoint.sol";

abstract contract KasterStakingRewards is KasterStakingBase {
    using FixedPoint for uint256;

    function _currentAPRWindow(address user, uint256 stakeId) internal view returns (uint256 baseAPR_, uint256 maxAPR_) {
        bool boostWindow = block.timestamp <= programStart + config.boostDuration();
        
        // Check if THIS specific stake is boosted
        if (boostWindow && stakes[user][stakeId].isBoosted) {
            return (config.baseAPRBoostPhase(), config.maxAPRBoostPhase());
        }
        return (config.baseAPR(), config.maxAPR());
    }

    function _previewRewards(Types.StakeInfo memory s, address user) internal view virtual returns (uint256) {
        if (s.principal == 0) return 0;
        uint256 dt = block.timestamp - s.lastClaim;
        if (dt == 0) return 0;

        (uint256 baseAPR, uint256 maxAPR) = _currentAPRWindow(user, s.id);
        uint256 fL = AprModel.lockPow(s.lockMonths, config.delta());
        uint256 fS = AprModel.sizeFactor(s.sizeSnapshot, config.S0());

        uint256 apr = AprModel.aprBlend(baseAPR, maxAPR, config.wL(), config.wS(), fL, fS);
        uint256 YEAR = 365 days;
        return s.principal * apr / 1e18 * dt / YEAR;
    }

    function _maybeEnrollBoost(address user, uint256 stakeId, uint256 stakeAmount) internal returns (bool) {
        // Check if this stake is already boosted
        if (stakes[user][stakeId].isBoosted) return true;
        
        // Check if still in boost window
        if (block.timestamp > programStart + config.boostDuration()) return false;
        
        // Check if slots available and stake meets minimum
        if (boostedStakers < config.maxBoostStakers() && stakeAmount >= config.minBoostStake()) {
            stakes[user][stakeId].isBoosted = true;
            
            // Track if user has any boosted stakes
            if (!hasBoostStake[user]) {
                hasBoostStake[user] = true;
                boostedStakers += 1;
            }
            
            return true;
        }
        return false;
    }
}