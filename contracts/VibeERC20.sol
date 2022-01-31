// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract VibeERC20 is Ownable, ERC20Burnable {

    constructor (string memory name, string memory symbol) Ownable() ERC20(name, symbol) {}

    function mint(address account, uint256 amount) external onlyOwner {
        super._mint(account, amount);
    }
}
