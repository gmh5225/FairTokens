// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23 <0.9.0;

import { BaseScript } from "./Base.s.sol";
import { PositionManager } from "../src/PositionManager.sol";
import { IUniswapV3Factory } from "@uniswap-v3/core/contracts/interfaces/IUniswapV3Factory.sol";
import { INonfungiblePositionManager } from "@uniswap-v3/periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { Script } from "forge-std/src/Script.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract DeployProtocol is Script {
    IUniswapV3Factory internal constant factory = IUniswapV3Factory(0x0227628f3F023bb0B980b67D528571c95c6DaC1c);
    INonfungiblePositionManager internal constant NPM =
        INonfungiblePositionManager(0x1238536071E1c677A632429e3655c799b22cDA52);
    address public constant NATIVE = 0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14;
    address configurator = 0xb9b0aF1C311f54377D04e6D3c5A19308dB33B636;
    function run() public returns (PositionManager m) {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        // foo = new Foo();
        m = new PositionManager(factory, NPM, configurator, NATIVE);
        vm.stopBroadcast();
    }
}