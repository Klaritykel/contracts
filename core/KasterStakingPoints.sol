// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../base/KasterStakingBase.sol";
import "../libraries/PointsModel.sol";

abstract contract KasterStakingPoints is KasterStakingBase {
    function _previewRewards(Types.StakeInfo memory s, address user)
        internal
        view
        virtual
        returns (uint256);

    function _accrueRewards(address user, Types.StakeInfo storage s) internal {
        uint256 newly = _previewRewards(s, user);
        if (newly > 0) {
            s.accRewards += newly;
        }
    }

    function _settleClaimAndPoints(Types.StakeInfo storage s) internal returns (uint256 reward, uint256 pointsAdd) {
        reward = s.accRewards;
        uint256 tau = _weeksSince(s.pointsCheckpoint);
        pointsAdd = PointsModel.pointsFrom(reward, tau, config.Pmax(), config.k());
        s.points += pointsAdd;

        s.accRewards = 0;
        s.lastClaim = block.timestamp;
        s.pointsCheckpoint = block.timestamp;

        totalRewardsDistributed += reward;
    }
}