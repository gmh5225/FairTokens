// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.23;

import "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

contract ERC20Impl is ERC20Upgradeable {
    address immutable owner;

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    constructor() {
        _disableInitializers();
        owner = msg.sender;
    }

    function init(string memory name_, string memory symbol_) external initializer {
        __ERC20_init(name_, symbol_);
    }

    function mint(uint256 amount) external onlyOwner {
        _mint(owner, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
