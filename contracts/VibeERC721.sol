// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";

contract VibeERC721 is Ownable, ERC721Burnable {

    uint public totalSupply;
    string public baseURI;

    constructor (string memory name, string memory symbol, string memory baseURI_) Ownable() ERC721(name, symbol) {
        baseURI = baseURI_;
    }

    function mint(address to) external onlyOwner {
        super._safeMint(to, totalSupply++);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}
