// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23;

import { console2 } from "forge-std/src/console2.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { LiquidityAmounts } from "./libraries/LiquidityAmounts.sol";
import { IUniswapV3Pool } from "@uniswap-v3/core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap-v3/core/contracts/interfaces/IUniswapV3Factory.sol";
import { INonfungiblePositionManager } from "@uniswap-v3/periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC20Impl } from "./ERC20Impl.sol";
import { StakingManager } from "./StakingManager.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

// TODO emit events
/// @title Tokens position manager contract
/// @author @codeislight
/// @notice used in managing creation of new tokens, adding and removal liquidity, and collecting trading fees.
contract PositionManager is IERC721Receiver, Ownable2Step, StakingManager {
    using SafeERC20 for IERC20;

    INonfungiblePositionManager public immutable NPM;
    IUniswapV3Factory public immutable factory;
    address immutable ERC20IMPL;
    address public immutable NATIVE;
    int24 constant MIN_TICK = -887200; // 887272;
    int24 constant MAX_TICK = 887200; // 887272;
    uint160 constant sqrtRatioAX96 = 4295128739;
    uint160 constant sqrtRatioBX96 = 1461446703485210103287273052203988822378723970342;
    // uint160 constant public MIN_INIT_SQRTR96 = 7_425_001_144_658_883; // tick -600_000
    // uint160 constant public MAX_INIT_SQRTR96 = 845_400_776_793_423_922_697_130_608_897_531_771_147_615; // tick 600_000
    uint160 constant public MIN_INIT_SQRTR96 = 79224358494714345780; // tick -414487
    uint160 constant public MAX_INIT_SQRTR96 = 79231966716467303967884099512280427189; // tick 414487
    uint256 constant public MAX_FEE_PERCENTAGE = 10_000; // only half of the feePercentage is charged, since it is only charged on anchor token
    uint256 constant public BASE_FEE_PERCENTAGE = 100_000;

    mapping (address token => uint value) public fees;
    mapping (address token => bool whitelisted) public whitelistedAnchorTokens;
    uint256 public protocolFeesPercentage; // only charged from anchor tokens
    uint256 tokenCounter;
    address protocolFeesReceiver;

    constructor(IUniswapV3Factory factory_, INonfungiblePositionManager npm_, address configurator_, address native_) Ownable(configurator_) {
        require(configurator_ != address(0) &&  native_ != address(0));
        ERC20IMPL = address(new ERC20Impl());
        NPM = npm_;
        NATIVE = native_;
        factory = factory_;
        whitelistedAnchorTokens[NATIVE] = true;
        IERC20(NATIVE).approve(address(NPM), type(uint256).max);
    }

    // ====================== external functions =================================

    /// creates a new token, new univ3 pool, and mints a new position
    /// @param name new token's name
    /// @param symbol new token's symbol
    /// @param anchorToken anchor token the created token paired with 
    /// @param sqrtPriceX96 the initial trading price
    function create(string memory name, string memory symbol, address anchorToken, uint160 sqrtPriceX96) external returns(uint id, address token) {
        require(whitelistedAnchorTokens[anchorToken]);
        require(MIN_INIT_SQRTR96 <= sqrtPriceX96 && sqrtPriceX96 <= MAX_INIT_SQRTR96);
        // token = address(new ERC1967Proxy(ERC20IMPL, new bytes(0)));
        token = Clones.clone(ERC20IMPL);
        ERC20Impl(token).init(name, symbol);
        ERC20Impl(token).approve(address(NPM), type(uint256).max);
        (address token0, address token1) = anchorToken < token ? (anchorToken, token) : (token, anchorToken);
        address pool = factory.createPool(token0, token1, 10_000);
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);

        id = ++tokenCounter;

        tokenInfo[id].pool = pool;
        tokenInfo[id].token = token;
        tokenInfo[id].anchorToken = anchorToken;
    }
    
    /// adds LP for token and WETH, and mints needed amount of token to pair it with
    /// @param id Pool identifier to add LP
    /// @param minimumAmount0 minimum amount of token0
    /// @param minimumAmount1 minimum amount of token1
    /// @param amount deposited amount of anchor token
    /// @param receiver added LP receiver
    /// @dev if `receiver` is address(0), the receiver defaults to sender
    function addLiquidity(uint256 id, uint256 minimumAmount0, uint256 minimumAmount1, uint256 amount, address receiver) external payable updateReward(id, receiver) returns(uint128 liquidity) {
        if (receiver == address(0)) receiver = msg.sender;
        address anchorToken = tokenInfo[id].anchorToken;
        require(anchorToken != address(0));
        if (msg.value > 0) {
            require(anchorToken == NATIVE);
            require(amount == msg.value);
            IWETH(NATIVE).deposit{value: msg.value}();
        } else {
            require(amount > 0);
            IERC20(anchorToken).safeTransferFrom(msg.sender, address(this), amount);
        }

        address token = tokenInfo[id].token;
        uint256 amount0;
        uint256 amount1;
        uint minted;
        address token0;
        address token1;
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(tokenInfo[id].pool).slot0();
        if (token < anchorToken) {
            token0 = token;
            token1 = anchorToken;
            (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96,sqrtRatioAX96,sqrtRatioBX96,
                LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96 ,sqrtPriceX96, amount)
            );
            minted = amount0;
        } else {
            token0 = anchorToken;
            token1 = token;
            (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96,sqrtRatioAX96,sqrtRatioBX96,
                LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, sqrtRatioBX96, amount)
            );
            minted = amount1;
        }

        require(amount0 > 0 && amount1 > 0, "insufficient amount");
        ERC20Impl(token).mint(minted);
        uint tokenId = tokenInfo[id].tokenId;
        if (tokenId == 0) {
            (tokenId, liquidity,,) = NPM.mint(
                INonfungiblePositionManager.MintParams({
                    token0: token0,
                    token1: token1,
                    fee: 10_000,
                    tickLower: MIN_TICK,
                    tickUpper: MAX_TICK,
                    amount0Desired: amount0,
                    amount1Desired: amount1,
                    amount0Min: minimumAmount0,
                    amount1Min: minimumAmount1,
                    recipient: address(this),
                    deadline: block.timestamp
                })
            );
            tokenInfo[id].tokenId = uint128(tokenId);
        } else {
            (liquidity,,) = NPM.increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams({
                    tokenId: tokenId,
                    amount0Desired: amount0,
                    amount1Desired: amount1,
                    amount0Min: minimumAmount0,
                    amount1Min: minimumAmount1,
                    deadline: block.timestamp
                })
            );
        }

        userInfo[id][receiver].addedAmount += amount;
        tokenInfo[id].liquidity += liquidity;
        _mint(receiver, id, liquidity, new bytes(0));
    }

    /// removes LP for token and anchorToken, and burns token, and claims deposited anchor token and trading fees
    /// @param id Pool identifier to add LP
    /// @param lpAmount amount of LP tokens to remove
    /// @param minAmount0 minimum of token0 to receive
    /// @param minAmount1 minimum of token1 to receive
    /// @param receiver removed LP and reward receiver
    /// @dev if `receiver` is address(0), the receiver defaults to sender
    function removeLiquidity(uint256 id, uint128 lpAmount, uint256 minAmount0, uint256 minAmount1, address receiver) external updateReward(id, msg.sender) {
        if (receiver == address(0)) receiver = msg.sender;
        address token = tokenInfo[id].token;
        address anchorToken = tokenInfo[id].anchorToken;
        require(token != address(0) && lpAmount > 0, "UninitializedOrZeroAmount");

        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(tokenInfo[id].pool).slot0();
        (uint256 a0, uint256 a1) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, lpAmount);
        uint256 anchorAmount = anchorToken < token ? a0 : a1;
        uint256 addedLP = balanceOf(msg.sender, id);
        uint256 addedAmount = userInfo[id][msg.sender].addedAmount;
        // expected amount according to the time LP was added
        uint256 expectedAmount = lpAmount * addedAmount / addedLP;

        userInfo[id][msg.sender].addedAmount = addedAmount - expectedAmount;
        _burn(msg.sender, id, lpAmount);

        // in case the price is greater, only burn enough LP to get back added anchor tokens
        if (anchorAmount >= expectedAmount) {
            lpAmount = uint128(expectedAmount * addedLP / anchorAmount);
        }

        tokenInfo[id].liquidity -= uint128(lpAmount);

        (removedAmount0, removedAmount1) = NPM.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenInfo[id].tokenId,
                liquidity: lpAmount,
                amount0Min: minAmount0,
                amount1Min: minAmount1,
                deadline: block.timestamp
            })
        );

        // collect and distribute trading fees
        (uint collectedA0, uint collectedA1) = _collect(id);
        collectedA0 -= removedAmount0;
        collectedA1 -= removedAmount1;
        _distribute(id, collectedA0, collectedA1);
    
        (uint256 amount0, uint256 amount1) = _getRewardWithoutTransfer(id);
        if (token < anchorToken) {
            (t0, t1) = (token, anchorToken);
            ERC20Impl(token).burn(removedAmount0);
            amount1 += removedAmount1;
        } else {
            (t0, t1) = (anchorToken, token);
            ERC20Impl(token).burn(removedAmount1);
            amount0 += removedAmount0;
        }

        if (amount0 > 0) IERC20(t0).safeTransfer(receiver, amount0);
        if (amount1 > 0) IERC20(t1).safeTransfer(receiver, amount1);
    }

    /// @notice used to collect trading fees and claim rewards
    /// @param id created token pool ERC1155 id
    /// @param collectFees whether to collect and distribute trading fees
    /// @param claimReward whether to claim trading fees rewards for the caller
    /// @return collectedFees0 collected trading fees for token0
    /// @return collectedFees1 collected trading fees for token1
    /// @return reward0 amount of token rewards for token0
    /// @return reward1 amount of token rewards for token1
    function collectFeesAndclaimRewards(uint256 id, bool collectFees, bool claimReward) external returns(uint collectedFees0, uint collectedFees1, uint reward0, uint reward1) {
        require(tokenInfo[id].token != address(0));
        if(collectFees) (collectedFees0, collectedFees1) = _collectFeesAndDistribute(id);
        if(claimReward) (reward0, reward1) = _getReward(id);
    }


    /// @notice collects protocol fees and sends them to protocolFeesReceiver
    /// @param tokens array of token addresses
    function collectProtocolFees(address[] calldata tokens) external {
        uint len = tokens.length;
        for(uint i; i < len; i++) {
            address token = tokens[i];
            uint collectedFees = fees[token];
            if (collectedFees > 0) {
                fees[token] = 0;
                IERC20(token).safeTransfer(protocolFeesReceiver, collectedFees);
            }
        }
    }

    function onERC721Received(
        address operator,
        address ,
        uint256 ,
        bytes calldata 
    ) external view override returns (bytes4) {
        require(operator == address(this));
        return IERC721Receiver.onERC721Received.selector;
    }

    // ====================== restricted functions =================================

    /// @notice sets percentage for protocol fees charged on trading fees
    /// @param value of protocol fees pip percentage  
    function setProtocolFeesPercentage(uint256 value) external onlyOwner {
        require(value <= MAX_FEE_PERCENTAGE);
        protocolFeesPercentage = value;
    }

    /// @notice sets the protocol fees receiver address
    /// @param receiver address of protocol fees receiver
    function setProtocolFeesReceiver(address receiver) external onlyOwner {
        require(receiver != address(0));
        protocolFeesReceiver = receiver;    
    }

    /// @notice used to whitlist supported anchor tokens
    /// @param token whitelist address
    /// @param isWhitelist whether to whitelist anchor token address
    function whitelistAnchorToken(address token, bool isWhitelist) external onlyOwner {
        require(whitelistedAnchorTokens[token] != isWhitelist);
        require(token != address(0) && token != NATIVE);
        whitelistedAnchorTokens[token] = isWhitelist;
        IERC20(token).approve(address(NPM), isWhitelist ? type(uint256).max : 0); // TODO safeApprove
        
    }

    // ====================== internal functions =================================
    function _updateWithAcceptanceCheck(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    )
        internal
        override
    {
        if (from != address(0) && to != address(0)) {
            for (uint256 i; i < ids.length; i++) {
                uint256 amountLP = values[i];
                if (amountLP > 0) {
                    uint256 id = ids[i];
                    _updateReward(id, from);
                    _updateReward(id, to);

                    uint256 fromAddedAmount = userInfo[id][from].addedAmount;
                    uint256 totalLP = tokenInfo[id].liquidity;
                    uint256 reducedAmount = fromAddedAmount * amountLP / totalLP;
                    userInfo[id][from].addedAmount -= reducedAmount;
                    userInfo[id][to].addedAmount += reducedAmount;
                }
            }
        }
        super._updateWithAcceptanceCheck(from, to, ids, values, data);
    }

    function _collect(uint256 id) internal returns(uint collectedAmount0, uint collectedAmount1) {
        (collectedAmount0,  collectedAmount1) = NPM.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenInfo[id].tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );
    }

    function _distribute(uint id, uint amount0, uint amount1) internal {
        if (amount0 > 0 || amount1 > 0) {
            uint feeAmount;
            address anchorToken = tokenInfo[id].anchorToken;
            if(tokenInfo[id].token < anchorToken) {
                feeAmount = amount1 * protocolFeesPercentage / BASE_FEE_PERCENTAGE; 
                amount1 -= feeAmount;
            } else {
                feeAmount = amount0 * protocolFeesPercentage / BASE_FEE_PERCENTAGE; 
                amount0 -= feeAmount;
            }
            fees[anchorToken] += feeAmount;

            _notifyRewardAmount(id, amount0, amount1);
        }
    }

    function _collectFeesAndDistribute(uint256 id) internal override updateReward(id, address(0)) returns(uint amount0, uint amount1) {
        (amount0, amount1) = _collect(id);
        _distribute(id, amount0, amount1);
    }
}
