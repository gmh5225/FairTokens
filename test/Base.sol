// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import { PRBTest } from "@prb/test/src/PRBTest.sol";
import { console2 } from "forge-std/src/console2.sol";
import { StdCheats } from "forge-std/src/StdCheats.sol";
import { Test } from "forge-std/src/Test.sol";
import { PositionManager } from "../src/PositionManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV3Factory } from "@uniswap-v3/core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap-v3/core/contracts/interfaces/IUniswapV3Pool.sol";
import { INonfungiblePositionManager } from "@uniswap-v3/periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IERC1155Receiver } from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import { LiquidityAmounts } from "../src/libraries/LiquidityAmounts.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IUniswapV3SwapCallback } from "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
/// @dev If this is your first time with Forge, read this tutorial in the Foundry Book:
/// https://book.getfoundry.sh/forge/writing-tests

abstract contract Base is IUniswapV3SwapCallback, IERC1155Receiver, Test {
    address bob_t = address(66);
    address tim_t = address(67);
    address alice_lp = address(68);
    address internal configurator = address(404);
    address internal protocolFeesReceiver = address(420);
    // address bob = address(69);
    PositionManager internal m;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint160 constant sqrtRatioAX96 = 4_295_128_739;
    uint160 constant sqrtRatioEqual = 2 ** 96;
    uint160 constant sqrtRatioBX96 = 1_461_446_703_485_210_103_287_273_052_203_988_822_378_723_970_342;
    address public constant NATIVE = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    ISwapRouter public constant router = ISwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    // IUniswapV2Factory constant factory = IUniswapV2Factory(0x9Ad6C38BE94206cA50bb0d90783181662f0Cfa10);
    IUniswapV3Factory internal constant factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    INonfungiblePositionManager internal constant NPM =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    string internal name = "Obama supersonic inu";
    string internal symbol = "BITCOIN";
    uint160 internal initSqrtPrice160 = 79_228_162_514_264_337_593_543_950_336;
    uint256 internal id;
    uint24 internal poolFee = 10_000;

    modifier create(uint256 amount) {
        uint160 initSqrt = uint160(bound(amount, m.MIN_INIT_SQRTR96(), m.MAX_INIT_SQRTR96()));
        (id,) = m.create(name, symbol, NATIVE, initSqrt);
        _;
    }

    modifier createWithSqrt(uint256 amount, uint160 initSqrt) {
        (id,) = m.create(name, symbol, NATIVE, initSqrt);
        _;
    }

    function _addLiquidity(uint256 amount) internal returns (uint256 liquidity) {
        deal(address(this), amount);
        uint128 preLiq = getLiquidity();
        liquidity = m.addLiquidity{value: amount}(id, 0, 0, amount, address(this));
        assertEq(liquidity, getLiquidity() - preLiq);
        assertEq(liquidity, m.balanceOf(address(this), id));
        assertEq(amount, m.getUserInfo(id, address(this)).addedAmount);
    }

    function _addLiquidity(address user, uint256 amount) internal returns (uint256 liquidity) {
        deal(user, amount);
        uint128 preLiq = getLiquidity();
        vm.prank(user);
        liquidity = m.addLiquidity{value: amount}(id, 0, 0, amount, user);
        assertEq(liquidity, getLiquidity() - preLiq);
        assertEq(liquidity, m.balanceOf(user, id));
        assertEq(amount, m.getUserInfo(id, user).addedAmount);
    }

    function _removeLiquidity(uint128 lpAmount) internal {
        uint256 preLP = m.balanceOf(address(this), id);
        m.removeLiquidity(id, lpAmount, 0, 0, address(this));
        assertEq(lpAmount, preLP - m.balanceOf(address(this), id));
    }

    function _removeLiquidity(address user, uint128 lpAmount) internal {
        uint256 preLP = m.balanceOf(user, id);
        vm.prank(user);
        m.removeLiquidity(id, lpAmount, 0, 0, user);
        assertEq(lpAmount, preLP - m.balanceOf(user, id));
    }

    function _swap(bool isBuy, address user, uint256 amount) internal returns (uint256 amountOut) {
        address tokenIn = isBuy ? NATIVE : m.getTokenInfo(id).token;
        address tokenOut = isBuy ? m.getTokenInfo(id).token : NATIVE;
        deal(tokenIn, address(this), amount);
        bool isZeroForOne = tokenIn < tokenOut;
        console2.log("amt", amount);
        (int256 amount0, int256 amount1) = IUniswapV3Pool(m.getTokenInfo(id).pool).swap(
            user, isZeroForOne, int256(amount), isZeroForOne ? sqrtRatioAX96 + 1 : sqrtRatioBX96 - 1, new bytes(0)
        );
        console2.logInt(amount0);
        console2.logInt(amount1);
        amountOut = uint256(isZeroForOne ? -amount1 : -amount0);
    }

    function getAmount0(uint256 amount) internal returns (uint256 amount_) {
        (amount_,) = getAmounts(amount);
    }

    function getAmount1(uint256 amount) internal returns (uint256 amount_) {
        (, amount_) = getAmounts(amount);
    }

    function getLiquidity() internal returns (uint128 liquidity) {
        uint256 tokenId = m.getTokenInfo(id).tokenId;
        if (tokenId == 0) return 0;
        (,,,,,,, liquidity,,,,) = NPM.positions(tokenId);
    }

    function getAmounts(uint256 amount) internal returns (uint256 amount0, uint256 amount1) {
        PositionManager.TokenInfo memory t = m.getTokenInfo(id);
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(t.pool).slot0();
        console2.log("-");
        uint128 liquidity;
        if (t.token < t.anchorToken) {
            console2.log("values", amount, 2 ** 96, sqrtPriceX96 - sqrtRatioAX96);
            liquidity = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96, sqrtPriceX96, amount);
            console2.log("--");
            (amount0, amount1) =
                LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, liquidity);
        } else {
            liquidity = LiquidityAmounts.getLiquidityForAmount0(sqrtPriceX96, sqrtRatioBX96, amount);
            console2.log("--");
            (amount0, amount1) =
                LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, liquidity);
        }
        console2.log("---");
    }

    function onERC1155Received(
        address ,
        address ,
        uint256 ,
        uint256 ,
        bytes calldata
    )
        external
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    )
        external
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return interfaceId == IERC1155Receiver.onERC1155Received.selector
            || interfaceId == IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        address token = m.getTokenInfo(id).token;
        (address t0, address t1) = token < NATIVE ? (token, NATIVE) : (NATIVE, token);
        if (amount0Delta > 0) {
            IERC20(t0).transfer(msg.sender, uint256(amount0Delta));
        }

        if (amount1Delta > 0) {
            IERC20(t1).transfer(msg.sender, uint256(amount1Delta));
        }
    }
}
