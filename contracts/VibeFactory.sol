// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "./VibeERC20.sol";
import "./VibeERC721.sol";

contract VibeFactory {

    mapping(VibeERC20 => VibeERC721) public erc20ToErc721;

    mapping(VibeERC721 => VibeERC20) public erc721ToErc20;

    event CreatedERC20ToERC721(address erc20, address erc721);
    event CreatedERC721ToERC20(address erc721, address erc20);
    event RedeemERC20FromERC721(address erc20, address erc721, uint256 amount);
    event RedeemERC721FromERC20(address erc721, address erc20, uint256 amount);

    function createERC20ToERC721(
        string memory name,
        string memory symbol,
        string memory baseURI,
        uint256 amount
    ) external {
        VibeERC20 erc20 = new VibeERC20(name, symbol);
        erc20.mint(msg.sender, amount);

        VibeERC721 erc721 = new VibeERC721(name, symbol, baseURI);

        erc20ToErc721[erc20] = erc721;

        emit CreatedERC20ToERC721(address(erc20), address(erc721));
    }

    function createERC721(
        string memory name,
        string memory symbol,
        string memory baseURI,
        uint256 quantity
    ) external {
        VibeERC721 erc721 = new VibeERC721(name, symbol, baseURI);
        for(uint256 i = 0; i < quantity; i++) {
            erc721.mint(msg.sender);
        }

        VibeERC20 erc20 = new VibeERC20(name, symbol);

        erc721ToErc20[erc721] = erc20;

        emit CreatedERC721ToERC20(address(erc721), address(erc20));
    }

    function redeemERC721FromERC20(VibeERC20 erc20, uint256 amount) external {
        VibeERC721 erc721 = erc20ToErc721[erc20];

        erc20.burnFrom(msg.sender, amount);

        uint256 quantity = amount / erc20.decimals();
        for(uint256 i = 0; i < quantity; i++) {
            erc721.mint(msg.sender);
        }

        emit RedeemERC20FromERC721(address(erc20), address(erc721), amount);
    }

    function redeemERC20FromERC721(VibeERC721 erc721, uint256[] memory tokenIds) external {
        VibeERC20 erc20 = erc721ToErc20[erc721];

        uint256 quantity = tokenIds.length;
        for (uint256 i = 0; i < quantity; i++) {
            erc721.burn(tokenIds[i]);
        }

        uint256 amount = quantity * (10 ** erc20.decimals());
        erc20.mint(msg.sender, amount);

        emit RedeemERC721FromERC20(address(erc721), address(erc20), amount);
    }
}
