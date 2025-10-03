// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./FixedPoint.sol";
import { UD60x18, ud } from "@prb/math/src/UD60x18.sol";

library AprModel {
    /// @notice Maximum lock duration for normalization (months)
    uint256 private constant MAX_LOCK_MONTHS = 48;
    
    /// @notice Maximum stake ratio for size factor (20x means ~99.999% of max)
    uint256 private constant MAX_STAKE_RATIO = 20e18; // 20x in wad
    
    /// @notice (L/48)^p with p in 1e18 (wad). Returns 1e18.
    /// @param lockMonths Lock duration in months [0, 48]
    /// @param p1e18 Exponent in wad format (e.g., 0.5e18 for square root)
    /// @return Lock factor in wad [0, 1e18]
    function lockPow(uint256 lockMonths, uint256 p1e18) internal pure returns (uint256) {
        if (lockMonths == 0) return 0;
        
        // Clamp to max lock period for safety
        if (lockMonths > MAX_LOCK_MONTHS) {
            lockMonths = MAX_LOCK_MONTHS;
        }
        
        // base = L / 48 (wad) - normalized to [0, 1]
        UD60x18 base = ud((lockMonths * 1e18) / MAX_LOCK_MONTHS);
        
        // exponent p (wad)
        UD60x18 p = ud(p1e18);
        
        // High-precision power using PRB Math
        return base.pow(p).unwrap();  // returns wad in [0, 1e18]
    }

    /// @notice fS = 1 - e^{-S/S0}, S and S0 in token units. Returns 1e18.
    /// @dev Uses exponential decay curve for diminishing returns on stake size.
    ///      Approaches 1.0 asymptotically as S increases.
    /// @param S Stake size in token units
    /// @param S0 Reference stake size (determines curve steepness)
    /// @return Size factor in wad [0, 1e18]
    function sizeFactor(uint256 S, uint256 S0) internal pure returns (uint256) {
        if (S == 0 || S0 == 0) return 0;
        
        // Calculate ratio S/S0 (wad)
        uint256 ratio = (S * 1e18) / S0;
        
        // Clamp to max ratio - beyond 20x, factor is ~99.999% anyway
        // This also maintains accuracy of the exponential approximation
        if (ratio >= MAX_STAKE_RATIO) {
            return 1e18 - 1; // Essentially 1.0 (0.999999...)
        }
        
        // Use custom fixed-point exp for efficiency
        // Accurate within ~1-2% for ratio < 20x
        return FixedPoint.oneMinusExpNeg(S, S0);
    }

    /// @notice APR blend using weighted lock and size factors
    /// @dev Formula: APR = baseAPR + (maxAPR - baseAPR) * (wL*fL + wS*fS)
    /// @param baseAPR Minimum APR in wad (e.g., 5e16 for 5%)
    /// @param maxAPR Maximum APR in wad (e.g., 20e16 for 20%)
    /// @param wL Weight for lock factor in wad [0, 1e18]
    /// @param wS Weight for size factor in wad [0, 1e18]
    /// @param fL Lock factor from lockPow() in wad [0, 1e18]
    /// @param fS Size factor from sizeFactor() in wad [0, 1e18]
    /// @return Final blended APR in wad
    function aprBlend(
        uint256 baseAPR,
        uint256 maxAPR,
        uint256 wL,
        uint256 wS,
        uint256 fL,
        uint256 fS
    ) internal pure returns (uint256) {
        require(maxAPR >= baseAPR, "must be >= baseAPR");
        require(wL + wS <= 1e18, "must sum to <= 1e18");
        
        // B = wL*fL + wS*fS (all wads) -> wad
        // This represents the blended boost factor [0, sum of weights]
        uint256 B = ((wL * fL) / 1e18) + ((wS * fS) / 1e18);
        
        // APR = base + (max-base)*B
        // Linear interpolation between base and max APR
        uint256 delta = ((maxAPR - baseAPR) * B) / 1e18;
        
        return baseAPR + delta;
    }
    
    /// @notice Helper to calculate APR for a stake position
    /// @dev Combines all steps: calculate factors, then blend APR
    /// @param lockMonths Lock duration in months
    /// @param stakeAmount Stake size in token units
    /// @param baseAPR Minimum APR in wad
    /// @param maxAPR Maximum APR in wad
    /// @param lockExp Lock factor exponent in wad
    /// @param wL Weight for lock factor in wad
    /// @param wS Weight for size factor in wad
    /// @param S0 Reference stake size for size factor
    /// @return Final APR in wad
    function calculateAPR(
        uint256 lockMonths,
        uint256 stakeAmount,
        uint256 baseAPR,
        uint256 maxAPR,
        uint256 lockExp,
        uint256 wL,
        uint256 wS,
        uint256 S0
    ) internal pure returns (uint256) {
        uint256 fL = lockPow(lockMonths, lockExp);
        uint256 fS = sizeFactor(stakeAmount, S0);
        
        return aprBlend(baseAPR, maxAPR, wL, wS, fL, fS);
    }
}