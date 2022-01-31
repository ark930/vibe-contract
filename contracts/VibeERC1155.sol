// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";

contract VibeERC1155 is Ownable, ERC1155Burnable {
    constructor(string memory uri) Ownable() ERC1155(uri) {}

    function mint(address account, uint256 id, uint256 amount, bytes memory data) external onlyOwner {
        super._mint(account, id, amount, data);
    }

    function batchMint(address to, uint256 fromId, uint256 toId, uint256 amount, bytes memory data) external onlyOwner {
        for (uint256 id = fromId; id <= toId; id++) {
            super._mint(to, id, amount, data);
        }
    }
}
