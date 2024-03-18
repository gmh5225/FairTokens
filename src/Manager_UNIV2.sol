// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23;

import { console2 } from "forge-std/src/console2.sol";
import { Token } from "./Token.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV2Factory } from "@uniswap-v2/core/contracts/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Pair } from "@uniswap-v2/core/contracts/interfaces/IUniswapV2Pair.sol";

contract Manager {
    struct Position {
        uint256 addedAmount;
        uint256 addedLP;
    }

    address public constant NATIVE = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    IUniswapV2Factory public immutable factory;
    Token public immutable token;
    IUniswapV2Pair public immutable lp;
    mapping(address => Position) public positions;
    // ensure that token0 = token and token1 = native

    constructor(Token token_, IUniswapV2Factory factory_, IUniswapV2Pair lp_) {
        token = token_;
        factory = factory_;
        lp = lp_;
    }

    function addLP() external payable {
        IWETH(NATIVE).deposit{value: msg.value}();
        _addLP(msg.value);
    }

    function addLP(uint256 amount) external {
        IERC20(NATIVE).transferFrom(msg.sender, address(this), amount);
        _addLP(amount);
    }

    function getPosition(address user) external view returns (uint256 amount, uint256 lp) {
        return (positions[user].addedAmount, positions[user].addedLP);
    }

    function removeLP(uint256 lpAmount, uint256 minAmount, bool unwrap) external {
        uint256 amount = lpAmount * IERC20(NATIVE).balanceOf(address(lp)) / lp.totalSupply();
        Position memory pos = positions[msg.sender];
        uint256 expectedAmount = lpAmount * pos.addedAmount / pos.addedLP;
        positions[msg.sender].addedLP = pos.addedLP - lpAmount;
        if (amount >= expectedAmount) {
            amount = expectedAmount;
            lpAmount = amount * pos.addedLP / pos.addedAmount;
        }
        positions[msg.sender].addedAmount = pos.addedAmount - amount;
        lp.transfer(address(lp), lpAmount);
        (uint256 a0, uint256 a1) = lp.burn(address(this));
        require(a1 >= minAmount);
        // (uint112 r0, uint112 r1,) = lp.getReserves();
        // uint256 tokenAmount = UniswapV2Library.quote(amount, r1, r0);
        token.burn(a0);
        if (unwrap) {
            IWETH(NATIVE).withdraw(a1);
            (bool success,) = msg.sender.call{gas: 3000, value: a1}("");
            require(success);
        } else {
            IERC20(NATIVE).transfer(msg.sender, a1);
        }
    }

    function _addLP(uint256 amount) internal {
        (uint112 r0, uint112 r1,) = lp.getReserves();
        uint256 tokenAmount = amount * r1 / r0;
        require(tokenAmount > 0);
        token.mint(address(lp), tokenAmount);
        IERC20(NATIVE).transfer(address(lp), amount);
        uint256 liquidity = lp.mint(address(this));

        // TODO add minimumAmount
        positions[msg.sender].addedAmount += amount;
        positions[msg.sender].addedLP += liquidity;
    }
}
