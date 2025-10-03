// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title FixedPoint (1e18 "wad") math helpers
/// @notice Compact, staking-friendly exp/ln/pow with clamping and signed ln.
///         Designed to be "good enough" for APR/points curves without pulling big deps.
///         Domain: positive reals for ln/pow; signed for exp input.
library FixedPoint {
    int256 internal constant ONE  = 1e18;
    uint256 internal constant ONEU = 1e18;

    // -----------------------
    // Public helpers (wad)
    // -----------------------

    /// @notice Natural exponent: returns e^(x/1e18) in 1e18. Input is signed wad.
    /// @dev Clamps at ~±60 to prevent overflow in polynomial.
    function exp1e18(int256 x) internal pure returns (int256) {
        // Clamp extremes (e^-60 ~ 8e-27 ≈ 0; e^60 ~ 1.1e26 but we just cap)
        if (x <= -60e18) return 0;
        if (x >=  60e18) return type(int256).max; // never used in our flows

        // Range reduction: e^x = (e^(x/2))^2
        if (x > 2e18 || x < -2e18) {
            int256 half = exp1e18(x / 2);
            return (half * half) / ONE;
        }
        // around 0 which is sufficient for |x|<=~1. For bigger |x| we rely on
        // clamp above (APR/points inputs are small in practice).
        // e^x ≈ 1 + x + x^2/2 + x^3/6 + x^4/24 + x^5/120
        int256 x1 = x;
        int256 x2 = (x1 * x1) / ONE;
        int256 x3 = (x2 * x1) / ONE;
        int256 x4 = (x3 * x1) / ONE;
        int256 x5 = (x4 * x1) / ONE;

        return ONE
            + x1
            + (x2 / 2)
            + (x3 / 6)
            + (x4 / 24)
            + (x5 / 120);
    }

    /// @notice e^{-x/1e18} in 1e18 for unsigned wad x. Clamped for safety.
    function expNeg1e18(uint256 x) internal pure returns (uint256) {
        if (x >= 60e18) return 0; // negligible
        return uint256(exp1e18(-int256(x)));
    }

    /// @notice Natural log ln(a/1e18) in 1e18. Returns signed value.
    /// @dev Uses atanh series: ln(a) = 2*(y + y^3/3 + y^5/5 + ...),
    ///      where y = (a-1)/(a+1). Preserves sign for a<1e18.
    function ln1e18(uint256 a) internal pure returns (int256) {
        require(a > 0, "ln(0)");
        int256 ai = int256(a);
        // y in [-1,1)
        int256 y = ( (ai - ONE) * ONE ) / (ai + ONE);

        // Powers of y (wad)
        int256 y2 = (y * y) / ONE;
        int256 y3 = (y2 * y) / ONE;
        int256 y5 = (y3 * y2) / ONE;
        int256 y7 = (y5 * y2) / ONE;
        int256 y9 = (y7 * y2) / ONE;

        // 5-term series is plenty for wad precision
        int256 series = y + (y3 / 3) + (y5 / 5) + (y7 / 7) + (y9 / 9);
        return 2 * series; // signed ln(a)
    }

    /// @notice pow1e18(a, p) ≈ (a/1e18)^(p/1e18) in 1e18.
    /// @dev a>0; p can be fractional (wad). pow = exp( ln(a) * p ).
    function pow1e18(uint256 a, uint256 p1e18) internal pure returns (uint256) {
        require(a > 0, "pow: a=0");
        int256 lnA = ln1e18(a); // signed
        // expIn = ln(a) * p
        int256 expIn = (lnA * int256(p1e18)) / int256(ONE);
        int256 out = exp1e18(expIn);
        require(out >= 0, "pow: exp<0");
        return uint256(out);
    }

    // -----------------------
    // Convenience helpers
    // -----------------------

    /// @notice fS = 1 - e^{-S/S0}, with S,S0 in token units; returns wad.
    function oneMinusExpNeg(uint256 S, uint256 S0) internal pure returns (uint256) {
        if (S == 0 || S0 == 0) return 0;
        uint256 x = (S * ONEU) / S0;     // S/S0 (wad)
        uint256 e = expNeg1e18(x);       // e^{-x} (wad)
        unchecked { return ONEU - e; }   // safe: e ∈ [0, 1e18]
    }
}
