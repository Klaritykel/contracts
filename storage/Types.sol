// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Types {
    struct StakeInfo {
        uint256 principal;
        uint256 lockStart;
        uint256 lockMonths;
        uint256 lastClaim;
        uint256 sizeSnapshot;
        uint256 accRewards;
        uint256 points;
        uint256 pointsCheckpoint;
    }
}