// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23;

// S=Storage contract
contract Storage {
    // struct Token {
    //     uint128 tokenId;
    //     uint128 liquidity;
    //     address token;
    //     address pool;
    // }

    // mapping(uint id => Token) internal tokens;
    // mapping(uint id => mapping(address user => uint)) internal positionAddedAmount;

    struct TokenInfo {
        uint128 tokenId;
        uint128 liquidity;
        address token;
        address anchorToken;
        uint64 periodFinish;
        address pool;
        uint64 lastUpdateTime;
        //
        uint256 token0RewardRate;
        uint256 token0RewardPerTokenStored;
        uint256 token1RewardRate;
        uint256 token1RewardPerTokenStored;
    }

    struct UserInfo {
        uint addedAmount;
        //
        uint256 token0UserRewardPerTokenPaid;
        uint256 token0rewards;
        uint256 token1UserRewardPerTokenPaid;
        uint256 token1rewards;
    }

    mapping(uint id => TokenInfo) internal tokenInfo;
    mapping(uint id => mapping(address user => UserInfo)) internal userInfo;

    function getTokenInfo(uint id) external view returns(TokenInfo memory) {
        return tokenInfo[id];
    }

    function getUserInfo(uint id, address user) external view returns(UserInfo memory) {
        return userInfo[id][user];
    }
}
