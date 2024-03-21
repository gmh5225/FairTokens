// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import { PRBTest } from "@prb/test/src/PRBTest.sol";
import { console2 } from "forge-std/src/console2.sol";
import { Vm } from "forge-std/src/Vm.sol";
import { StdCheats } from "forge-std/src/StdCheats.sol";
import { PositionManager } from "../src/PositionManager.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV3Factory } from "@uniswap-v3/core/contracts/interfaces/IUniswapV3Factory.sol";
import { INonfungiblePositionManager } from "@uniswap-v3/periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IERC1155Receiver } from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
/// @dev If this is your first time with Forge, read this tutorial in the Foundry Book:
/// https://book.getfoundry.sh/forge/writing-tests
import "./Base.sol";

contract ManagerTest is Base {
    receive() external payable { }

    /// @dev A function invoked before each test case is run.
    function setUp() public virtual {
        // Otherwise, run the test against the mainnet fork.
        vm.createSelectFork({urlOrAlias: "main", blockNumber: 19_425_183});
        // Instantiate the contract-under-test.

        // deal(NATIVE, address(lp), amount);

        m = new PositionManager(factory, NPM, configurator, NATIVE);
        vm.prank(configurator);
        m.setProtocolFeesReceiver(protocolFeesReceiver);

        // id = m.create(name, symbol, NATIVE, initSqrtPrice160);
    }

    /// @dev Basic test. Run it with `forge test -vvv` to see the console log.
    function test_add_LP(uint256 amount) external create(amount) {
        amount = bound(amount, 0, 10_000 ether);
        vm.assume(getAmount0(amount) > 0 && getAmount1(amount) > 0);
        _addLiquidity(amount);
    }

    function test_removeLP_abovePrice(uint256 amount) external create(amount) {
        //
        amount = bound(amount, 1000, 10_000 ether);
        vm.assume(getAmount0(amount) > 0 && getAmount1(amount) > 0);
        uint128 liquidity = uint128(_addLiquidity(alice_lp, amount));
        //
        uint256 buyAmount = bound(amount, amount / 3, amount / 2);
        uint256 amountOut = _swap(true, bob_t, buyAmount);
        address anchorToken = m.getTokenInfo(id).anchorToken;
        uint256 pre = IERC20(anchorToken).balanceOf(alice_lp);
        _removeLiquidity(alice_lp, liquidity);
        assertApproxEqRel(IERC20(anchorToken).balanceOf(alice_lp) - pre, amount, 1 ether / 10**8);
        assertEq(m.balanceOf(alice_lp, id), 0);
        assertEq(m.getUserInfo(id, alice_lp).addedAmount, 0);
        
    }

    function test_removeLP(uint256 amount) external create(amount) {
        amount = bound(amount, 1000, 10_000 ether);
        vm.assume(getAmount0(amount) > 0 && getAmount1(amount) > 0);
        uint128 liquidity = uint128(_addLiquidity(amount));
        _removeLiquidity(liquidity);
    }

    function test_createPool(uint256 amount) external {
        // unwhitelisted token
        vm.expectRevert();
        m.create(name, symbol, address(0), sqrtRatioEqual);
        // lower bound
        uint160 sqrtX96 = uint160(bound(amount, 0, m.MIN_INIT_SQRTR96()));
        vm.expectRevert();
        m.create(name, symbol, address(0), sqrtX96);
        sqrtX96 = uint160(bound(amount, m.MAX_INIT_SQRTR96(), type(uint160).max));
        // upper bound
        sqrtX96 = uint160(bound(amount, m.MAX_INIT_SQRTR96(), type(uint160).max));
        vm.expectRevert();
        m.create(name, symbol, address(0), sqrtX96);
        // success
        sqrtX96 = uint160(bound(amount, m.MIN_INIT_SQRTR96(), m.MAX_INIT_SQRTR96()));
        (uint256 id, address token) = m.create(name, symbol, NATIVE, sqrtX96);
        assertEq(m.getTokenInfo(id).token, token);
        assertEq(m.getTokenInfo(id).anchorToken, NATIVE);
        assertEq(m.getTokenInfo(id).pool, factory.getPool(token, NATIVE, poolFee));
    }

    function test_owner_setProtocolFeesPercentage(uint256 amount) external {
        // access
        vm.expectRevert();
        m.setProtocolFeesPercentage(0);
        // invalid amount
        amount = bound(amount, m.MAX_FEE_PERCENTAGE() + 1, type(uint256).max);
        vm.expectRevert();
        vm.prank(configurator);
        m.setProtocolFeesPercentage(amount);
        // success
        amount = bound(amount, 0, m.MAX_FEE_PERCENTAGE());
        vm.prank(configurator);
        m.setProtocolFeesPercentage(amount);
    }

    function test_owner_setProtocolFeesReceiver() external {
        address addr = address(1234);
        // access
        vm.expectRevert();
        m.setProtocolFeesReceiver(addr);
        // receiver = address(0)
        vm.expectRevert();
        vm.prank(configurator);
        m.setProtocolFeesReceiver(address(0));
        // success
        vm.prank(configurator);
        m.setProtocolFeesReceiver(addr);
    }

    function test_owner_whitelistAnchorToken() external {
        // access
        vm.expectRevert();
        m.whitelistAnchorToken(USDC, true);
        // token = NATIVE
        vm.expectRevert();
        vm.prank(configurator);
        m.whitelistAnchorToken(NATIVE, false);
        // token = address(0)
        vm.expectRevert();
        vm.prank(configurator);
        m.whitelistAnchorToken(address(0), true);
        // set same value
        vm.expectRevert();
        vm.prank(configurator);
        m.whitelistAnchorToken(USDC, false);
        // success
        vm.prank(configurator);
        m.whitelistAnchorToken(USDC, true);
        assertTrue(m.whitelistedAnchorTokens(USDC));
        assertEq(IERC20(USDC).allowance(address(m), address(NPM)), type(uint256).max);

        vm.prank(configurator);
        m.whitelistAnchorToken(USDC, false);
        assertFalse(m.whitelistedAnchorTokens(USDC));
        assertEq(IERC20(USDC).allowance(address(m), address(NPM)), 0);
    }

    function test_transferLiquidityTokens(uint256 amount) external create(amount) {
        amount = bound(amount, 1000, 10_000 ether);
        vm.assume(getAmount0(amount) > 0 && getAmount1(amount) > 0);
        uint256 liquidity = _addLiquidity(amount);
        liquidity = bound(liquidity, 0, liquidity);
        uint256 addedAmount = m.getUserInfo(id, address(this)).addedAmount;
        m.safeTransferFrom(address(this), bob_t, id, liquidity, new bytes(0));
        assertEq(m.getUserInfo(id, address(this)).addedAmount, 0);
        assertEq(m.getUserInfo(id, bob_t).addedAmount, addedAmount);
        assertEq(m.balanceOf(bob_t, id), liquidity);
    }

    function test_collectFeesAndclaimRewards(uint256 amount) external create(amount) {
        //
        address token = m.getTokenInfo(id).token;
        address anchorToken = m.getTokenInfo(id).anchorToken;

        amount = bound(amount, 1000, 10_000 ether);
        vm.assume(getAmount0(amount) > 0 && getAmount1(amount) > 0);
        uint256 liquidity = _addLiquidity(alice_lp, amount);
        assertGt(liquidity, 0);
        uint256 buyAmount = bound(amount, amount / 3, amount / 2);
        uint256 amountOut = _swap(true, bob_t, buyAmount);
        console2.log("amountOut", amountOut);
        // _swap(false, bob_t, amountOut);
        (uint256 collected0, uint256 collected1,,) = m.collectFeesAndclaimRewards(id, true, false);
        console2.log("collected", collected0, collected1);
        if (anchorToken < token) {
            assertGt(collected0, 0);
        } else {
            assertGt(collected1, 0);
        }
        skip(m.rewardsDuration());
 
        (address t0, address t1) = token < anchorToken ? (token, anchorToken) : (anchorToken, token);
        uint256 pre0 = IERC20(t0).balanceOf(alice_lp);
        uint256 pre1 = IERC20(t1).balanceOf(alice_lp);
        vm.prank(alice_lp);
        (,, uint256 reward0, uint256 reward1) = m.collectFeesAndclaimRewards(id, false, true);
        if (reward0 > 0) {
            console2.log("r0", IERC20(t0).balanceOf(alice_lp), pre0);
            assertTrue(IERC20(t0).balanceOf(alice_lp) > pre0);
        }
        if (reward1 > 0) {
            assertTrue(IERC20(t1).balanceOf(alice_lp) > pre1);
        }
    }
}
