// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IKasterStakingConfig.sol";

contract KasterStakingConfig is IKasterStakingConfig, Ownable {
    constructor() Ownable(msg.sender) {} 
    // --- defaults (tune later by DAO multisig) ---
    uint256 public override minBoostStake    = 1_250_000 ether;
    uint256 public override maxBoostStakers  = 100;
    uint256 public override boostDuration    = 180 days;
    uint256 public override baseAPRBoostPhase= 50e16;   // 50%
    uint256 public override maxAPRBoostPhase = 100e16;  // 100%

    uint256 public override baseAPR = 20e16; // 20%
    uint256 public override maxAPR  = 49e16; // 50%

    uint256 public override wL = 70e16; // weights sum to 1e18
    uint256 public override wS = 30e16;
    uint256 public override delta = 120e16; // lock curvature 1.20
    uint256 public override S0 = 50_000 ether; // size scale

    uint256 public override b = 20e16;     // VP floor 0.20
    uint256 public override gamma = 125e16;// VP curvature 1.25

    uint256 public override Pmax = 1e18; // 1 point per 1 KAST reward (1e18 scale)
    uint256 public override k    = 35e16;// 0.35 / week (1e18)

    uint256 public override minLockMonths = 6;
    uint256 public override maxLockMonths = 48;
    uint256 public override claimInterval = 7 days;

    // --- admin setters ---
    function setEarlyBoost(uint256 _min, uint256 _max, uint256 _dur, uint256 _base, uint256 _maxAPR) external onlyOwner {
        minBoostStake=_min; maxBoostStakers=_max; boostDuration=_dur; baseAPRBoostPhase=_base; maxAPRBoostPhase=_maxAPR;
    }
    function setLongTermAPR(uint256 _baseAPR, uint256 _maxAPR) external onlyOwner { baseAPR=_baseAPR; maxAPR=_maxAPR; }
    function setAprShape(uint256 _wL, uint256 _wS, uint256 _delta, uint256 _S0) external onlyOwner {
        require(_wL + _wS == 100e16, "weights!=1");
        wL=_wL; wS=_wS; delta=_delta; S0=_S0;
    }
    function setVotingShape(uint256 _b, uint256 _gamma) external onlyOwner { b=_b; gamma=_gamma; }
    function setPatience(uint256 _Pmax, uint256 _k) external onlyOwner { Pmax=_Pmax; k=_k; }
    function setBounds(uint256 _minM, uint256 _maxM, uint256 _claim) external onlyOwner {
        minLockMonths=_minM; maxLockMonths=_maxM; claimInterval=_claim;
    }
}
