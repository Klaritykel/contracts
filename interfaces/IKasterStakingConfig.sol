// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IKasterStakingConfig {
    // Early adopter cohort
    function minBoostStake() external view returns (uint256);
    function maxBoostStakers() external view returns (uint256);
    function boostDuration() external view returns (uint256);
    function baseAPRBoostPhase() external view returns (uint256); // 1e18 = 100%
    function maxAPRBoostPhase() external view returns (uint256);  // 1e18 = 100%

    // Long-term APR band
    function baseAPR() external view returns (uint256);
    function maxAPR() external view returns (uint256);

    // APR blend shape
    function wL() external view returns (uint256);
    function wS() external view returns (uint256);
    function delta() external view returns (uint256);
    function S0() external view returns (uint256);

    // Voting power shape
    function b() external view returns (uint256);
    function gamma() external view returns (uint256);

    // Patience points
    function Pmax() external view returns (uint256);
    function k() external view returns (uint256);

    // Bounds & intervals
    function minLockMonths() external view returns (uint256);
    function maxLockMonths() external view returns (uint256);
    function claimInterval() external view returns (uint256);
}
