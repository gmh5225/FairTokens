// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.7;

import { console2 } from "forge-std/src/console2.sol";
import "./Storage.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

/// https://github.com/AngleProtocol/angle-core/blob/main/contracts/staking/StakingRewards.sol
/// @title StakingRewards
/// @author Forked form SetProtocol
/// https://github.com/SetProtocol/index-coop-contracts/blob/master/contracts/staking/StakingRewards.sol
/// @notice The `StakingRewards` contracts allows to stake an ERC20 token to receive as reward another ERC20
/// @dev This contracts is managed by the reward distributor and implements the staking interface
abstract contract StakingManager is ERC1155, ReentrancyGuard, Storage {
    using SafeERC20 for IERC20;

    event RewardAdded(uint256 indexed id, uint256 reward0, uint256 reward1);

    event Staked(address indexed user, uint256 amount);

    event Withdrawn(address indexed user, uint256 amount);

    event RewardPaid(address indexed user, uint256 reward0, uint256 reward1);

    event UpdateConfigurator(address indexed _rewardsDistribution);

    // ============================ Staking parameters =============================

    /// @notice Duration of the reward distribution
    uint256 public constant rewardsDuration = 120; // TODO

    uint256 constant BASE = 10 ** 18;
    // ============================ Constructor ====================================

    /// @notice Initializes the staking contract with a first set of parameters
    constructor() ERC1155("") { }

    // ============================ Modifiers ======================================

    /// @notice Checks to see if the calling address is the zero address
    /// @param account Address to check
    modifier zeroCheck(address account) {
        require(account != address(0), "0");
        _;
    }

    /// @notice Called frequently to update the staking parameters associated to an address
    /// @param account Address of the account to update
    modifier updateReward(uint256 id, address account) {
        (uint256 rpt0, uint256 rpt1) = rewardPerToken(id);
        tokenInfo[id].token0RewardPerTokenStored = rpt0;
        tokenInfo[id].token1RewardPerTokenStored = rpt1;
        tokenInfo[id].lastUpdateTime = uint64(lastTimeRewardApplicable(id));
        if (account != address(0)) {
            (uint256 amount0, uint256 amount1) = earned(id, account);
            userInfo[id][account].token0rewards = amount0;
            userInfo[id][account].token1rewards = amount1;
            userInfo[id][account].token0UserRewardPerTokenPaid = rpt0;
            userInfo[id][account].token1UserRewardPerTokenPaid = rpt1;
        }
        _;
    }

    function _updateReward(uint256 id, address account) internal updateReward(id, account) { }

    // ============================ View functions =================================

    /// @notice Accesses the total supply
    /// @dev Used instead of having a public variable to respect the ERC20 standard
    function totalSupply(uint256 id) external view returns (uint256) {
        return tokenInfo[id].liquidity;
    }

    /// @notice Queries the last timestamp at which a reward was distributed
    /// @dev Returns the current timestamp if a reward is being distributed and the end of the staking
    /// period if staking is done
    function lastTimeRewardApplicable(uint256 id) public view returns (uint256) {
        return Math.min(block.timestamp, tokenInfo[id].periodFinish);
    }

    /// @notice Used to actualize the `rewardPerTokenStored`
    /// @dev It adds to the reward per token: the time elapsed since the `rewardPerTokenStored` was
    /// last updated multiplied by the `rewardRate` divided by the number of tokens
    function rewardPerToken(uint256 id) public view returns (uint256 rpt0, uint256 rpt1) {
        uint256 _totalSupply = tokenInfo[id].liquidity;
        if (_totalSupply == 0) {
            return (tokenInfo[id].token0RewardPerTokenStored, tokenInfo[id].token1RewardPerTokenStored);
        }
        rpt0 = tokenInfo[id].token0RewardPerTokenStored;
        rpt1 = tokenInfo[id].token1RewardPerTokenStored;
        uint256 lastTime = lastTimeRewardApplicable(id);
        uint256 _lastUpdateTime = tokenInfo[id].lastUpdateTime;
        return (
            rpt0 + (((lastTime - _lastUpdateTime) * tokenInfo[id].token0RewardRate * BASE) / _totalSupply),
            rpt1 + (((lastTime - _lastUpdateTime) * tokenInfo[id].token1RewardRate * BASE) / _totalSupply)
        );
    }

    /// @notice Returns how much a given account earned rewards
    /// @param id Pool identifier to distribute rewards
    /// @param account Address for which the request is made
    /// @return amount0 amount1 How much a given account earned rewards
    /// @dev It adds to the rewards the amount of reward earned since last time that is the difference
    /// in reward per token from now and last time multiplied by the number of tokens staked by the person
    function earned(uint256 id, address account) public view returns (uint256 amount0, uint256 amount1) {
        (uint256 rpt0, uint256 rpt1) = rewardPerToken(id);
        amount0 = (balanceOf(account, id) * (rpt0 - userInfo[id][account].token0UserRewardPerTokenPaid)) / BASE
            + userInfo[id][account].token0rewards;
        amount1 = (balanceOf(account, id) * (rpt1 - userInfo[id][account].token1UserRewardPerTokenPaid)) / BASE
            + userInfo[id][account].token1rewards;
    }

    // ======================== Mutative functions forked ==========================

    /// @notice Triggers a payment of the reward earned to the msg.sender
    function _getReward(uint256 id) internal updateReward(id, msg.sender) returns (uint256 reward0, uint256 reward1) {
        reward0 = userInfo[id][msg.sender].token0rewards;
        reward1 = userInfo[id][msg.sender].token1rewards;
        address token = tokenInfo[id].token;
        address anchorToken = tokenInfo[id].anchorToken;
        (address t0, address t1) = token < anchorToken ? (token, anchorToken) : (anchorToken, token);
        if (reward0 > 0) {
            userInfo[id][msg.sender].token0rewards = 0;
            IERC20(t0).safeTransfer(msg.sender, reward0);
        }

        if (reward1 > 0) {
            userInfo[id][msg.sender].token1rewards = 0;
            IERC20(t1).safeTransfer(msg.sender, reward1);
        }

        if (reward0 > 0 || reward1 > 0) {
            emit RewardPaid(msg.sender, reward0, reward1);
        }
    }

    /// @notice accounts for a reward claim, without transferring tokens
    function _getRewardWithoutTransfer(uint256 id)
        internal
        updateReward(id, msg.sender)
        returns (uint256 a0, uint256 a1)
    {
        uint256 reward0 = userInfo[id][msg.sender].token0rewards;
        userInfo[id][msg.sender].token0rewards = 0;
        uint256 reward1 = userInfo[id][msg.sender].token1rewards;
        userInfo[id][msg.sender].token1rewards = 0;
        if (reward0 > 0 || reward1 > 0) {
            emit RewardPaid(msg.sender, reward0, reward1);
        }
        return (reward0, reward1);
    }

    function _collectFeesAndDistribute(uint256 id) internal virtual returns (uint256 amount0, uint256 amount1);

    // ====================== Restricted Functions =================================

    /// @notice Adds rewards to be distributed
    /// @param id Pool identifier to distribute rewards
    /// @param amount0reward Amount0 of reward tokens to distribute
    /// @param amount1reward Amount1 of reward tokens to distribute
    function _notifyRewardAmount(uint256 id, uint256 amount0reward, uint256 amount1reward) internal {
        uint256 periodFinish = tokenInfo[id].periodFinish;
        if (block.timestamp >= periodFinish) {
            // If no reward is currently being distributed, the new rate is just `reward / duration`
            tokenInfo[id].token0RewardRate = amount0reward / rewardsDuration;
            tokenInfo[id].token1RewardRate = amount1reward / rewardsDuration;
        } else {
            // Otherwise, cancel the future reward and add the amount left to distribute to reward
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover0 = remaining * tokenInfo[id].token0RewardRate;
            uint256 leftover1 = remaining * tokenInfo[id].token1RewardRate;
            tokenInfo[id].token0RewardRate = (amount0reward + leftover0) / rewardsDuration;
            tokenInfo[id].token1RewardRate = (amount1reward + leftover1) / rewardsDuration;
        }

        // Ensures the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of `rewardRate` in the earned and `rewardsPerToken` functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        address token = tokenInfo[id].token;
        address anchorToken = tokenInfo[id].anchorToken;
        (address t0, address t1) = token < anchorToken ? (token, anchorToken) : (anchorToken, token);

        uint256 balance0 = IERC20(t0).balanceOf(address(this));
        uint256 balance1 = IERC20(t1).balanceOf(address(this));
        require(tokenInfo[id].token0RewardRate <= balance0 / rewardsDuration, "91");
        require(tokenInfo[id].token1RewardRate <= balance1 / rewardsDuration, "91");

        tokenInfo[id].lastUpdateTime = uint64(block.timestamp);
        tokenInfo[id].periodFinish = uint64(block.timestamp + rewardsDuration); // Change the duration
        emit RewardAdded(id, amount0reward, amount1reward);
    }
}
