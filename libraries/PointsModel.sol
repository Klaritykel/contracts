// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./FixedPoint.sol";

library PointsModel {
    /// @notice Points = R * Pmax * (1 - e^{-k * weeksTau})
    /// @param reward     Accrued rewards (token units)
    /// @param weeksTau   Time since last checkpoint, in weeks
    /// @param Pmax       Max points per 1 token reward (wad, e.g., 1e18)
    /// @param k          Growth rate per week (wad, e.g., 0.35e18)
    /// @return points    Points units (reward-scaled)
    function pointsFrom(
        uint256 reward,
        uint256 weeksTau,
        uint256 Pmax,
        uint256 k
    ) internal pure returns (uint256 points) {
        if (reward == 0 || weeksTau == 0) return 0;
        // z = k * weeksTau (wad)
        uint256 z = k * weeksTau;
        // factor = 1 - e^{-z} (wad)
        uint256 factor;
        unchecked { factor = 1e18 - FixedPoint.expNeg1e18(z); } // safe
        // reward * (Pmax/1e18) * (factor/1e18)
        return reward * Pmax / 1e18 * factor / 1e18;
    }
}
