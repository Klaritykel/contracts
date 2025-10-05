// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IKasterStakingCore.sol";

/**
 * @title KasterStakingBatch
 * @notice Batch operations for multiple stakes - reduces main contract size
 */
contract KasterStakingBatch {
    IKasterStakingCore public immutable core;

    constructor(address _core) {
        core = IKasterStakingCore(_core);
    }

    /// @notice Claim rewards from all stakes
    function claimAllRewards() external {
        uint256[] memory stakeIds = core.getUserStakeIds(msg.sender);
        require(stakeIds.length > 0, "no stakes");

        for (uint256 i = 0; i < stakeIds.length; i++) {
            try core.claimRewards(stakeIds[i]) {
                // Successfully claimed
            } catch {
                // Skip if not claimable yet
            }
        }
    }

    /// @notice Unstake all unlocked positions
    function unstakeAll() external {
        uint256[] memory stakeIds = core.getUserStakeIds(msg.sender);
        require(stakeIds.length > 0, "no stakes");

        // Iterate in reverse to handle array modifications
        for (uint256 i = stakeIds.length; i > 0; i--) {
            try core.unstake(stakeIds[i - 1]) {
                // Successfully unstaked
            } catch {
                // Skip if still locked
            }
        }
    }

    /// @notice Migrate all unlocked stakes
    function migrateAll() external {
        uint256[] memory stakeIds = core.getUserStakeIds(msg.sender);
        require(stakeIds.length > 0, "no stakes");

        for (uint256 i = stakeIds.length; i > 0; i--) {
            try core.migrate(stakeIds[i - 1]) {
                // Successfully migrated
            } catch {
                // Skip if still locked or no target
            }
        }
    }

    /// @notice Restake rewards from all stakes
    function restakeAllRewards() external {
        uint256[] memory stakeIds = core.getUserStakeIds(msg.sender);
        require(stakeIds.length > 0, "no stakes");

        for (uint256 i = 0; i < stakeIds.length; i++) {
            try core.restakeRewards(stakeIds[i]) {
                // Successfully restaked
            } catch {
                // Skip if no rewards or too soon
            }
        }
    }
}