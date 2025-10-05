// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Types {
    struct StakeInfo {
        uint256 id;                  // Unique stake ID
        uint256 principal;
        uint256 lockStart;
        uint256 lockMonths;
        uint256 lastClaim;
        uint256 sizeSnapshot;
        uint256 accRewards;
        uint256 points;
        uint256 pointsCheckpoint;
        bool isBoosted;             // Track boost status per stake
    }
    
    struct UserStakes {
        uint256[] stakeIds;         // Array of active stake IDs
        uint256 nextStakeId;        // Counter for generating unique IDs
        uint256 totalPrincipal;     // Sum of all stakes for this user
    }
}