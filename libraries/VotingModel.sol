// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./FixedPoint.sol";
import "./AprModel.sol";  // <-- add this

library VotingModel {
    /// VP = S * ( b + (1-b) * (L/48)^gamma )
    function votingPower(
        uint256 principal,
        uint256 lockMonths,
        uint256 b1e18,
        uint256 gamma1e18
    ) internal pure returns (uint256 vp) {
        if (principal == 0) return 0;

        // Use the same, precise lock power as APR (PRB pow under the hood)
        uint256 Lpow = AprModel.lockPow(lockMonths, gamma1e18); // 0..1e18

        uint256 term = b1e18 + ((1e18 - b1e18) * Lpow) / 1e18;  // wad
        return (principal * term) / 1e18;
    }
}
