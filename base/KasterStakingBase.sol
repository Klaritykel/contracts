// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IKasterStakingConfig.sol";
import "../storage/Types.sol";

interface IERC20Decimals is IERC20 {
    function decimals() external view returns (uint8);
}

abstract contract KasterStakingBase is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20; // bind SafeERC20 to IERC20, not your custom interface

    IERC20 public immutable KAST; // store as IERC20 for SafeERC20 compatibility
    IKasterStakingConfig public config;

    uint256 public immutable programStart;
    uint256 public boostedStakers;
    mapping(address => bool) public isBoostStaker;

    mapping(address => Types.StakeInfo) internal stakes;

    uint256 public totalStaked;
    uint256 public totalRewardsDistributed;

    address public nextStakingContract;

    event Staked(address indexed user, uint256 amount, uint256 lockMonths, bool boost);
    event ExtendedLock(address indexed user, uint256 newLockMonths);
    event Claimed(address indexed user, uint256 reward, uint256 pointsAdded);
    event Restaked(address indexed user, uint256 reward, uint256 pointsCarried);
    event Unstaked(address indexed user, uint256 amount);
    event Migrated(address indexed user, uint256 principal, uint256 rewards, uint256 points, address target);
    event NextContractSet(address target);

    // Add to state:
    uint256 public totalRewardsAdded;        // sum of all reward funding ever added
    uint256 public totalRewardsRecovered;    // rewards sent back to treasury (if any)

    // OPTIONAL: track a dedicated treasury for recovery
    address public rewardsTreasury;          // set once by owner (optional)

    // Events:
    event RewardsAdded(address indexed funder, uint256 amount);
    event RewardsRecovered(address indexed to, uint256 amount);
    event RewardsTreasurySet(address indexed treasury);


    constructor(address _kast, address _config) 
        Ownable(msg.sender)   // 👈 set initial owner
    {
        require(_kast != address(0) && _config != address(0), "zero");
        KAST = IERC20Decimals(_kast);
        config = IKasterStakingConfig(_config);
        programStart = block.timestamp;
    }

    // --- modifier ---
    modifier onlyTreasury() {
        require(msg.sender == rewardsTreasury, "not treasury");
        _;
    }

    // --- setter ---
    function setRewardsTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "treasury=0");
        rewardsTreasury = _treasury;
        emit RewardsTreasurySet(_treasury);
    }


    function setConfig(address _config) external onlyOwner {
        require(_config != address(0), "zero");
        config = IKasterStakingConfig(_config);
    }
    function setNextContract(address target) external onlyOwner {
        nextStakingContract = target;
        emit NextContractSet(target);
    }

    // helpers
    function _lockEnd(Types.StakeInfo memory s) internal pure returns (uint256) {
        return s.lockStart + (s.lockMonths * 30 days);
    }
    function _weeksSince(uint256 t0) internal view returns (uint256) {
        if (block.timestamp <= t0) return 0;
        return (block.timestamp - t0) / (7 days);
    }
}
