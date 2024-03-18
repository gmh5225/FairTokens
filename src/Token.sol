// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    constructor() ERC20("", "") {
        _mint(msg.sender, 1 ether);
    }

    function mint(address receiver, uint256 amount) external {
        // TODO restrict
        _mint(receiver, amount);
    }

    function burn(uint256 amount) external {
        // TODO restrict
        _burn(msg.sender, amount);
    }
}
