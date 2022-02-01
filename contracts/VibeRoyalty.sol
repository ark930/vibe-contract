// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract VibeRoyalty is OwnableUpgradeable {
    using SafeMathUpgradeable for uint;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint public maxRoyaltyRate;
    uint public minRoyaltyRate;
    uint public royaltyRate;
    address public royaltyReceiver;

    event ChargeRoyaltyETH(address indexed royaltyReceiver, uint royalty);
    event ChargeRoyaltyERC20(address indexed royaltyReceiver, address indexed token, uint royalty);

    function initialize() public initializer {
        super.__Ownable_init();
        royaltyReceiver = address(this);
        royaltyRate = 0.035 ether; // 3.5%
        maxRoyaltyRate = 1 ether; // 100%
        minRoyaltyRate = 0.001 ether; // 0.1%
    }

    function calculateRoyalty(uint amount) public view returns (uint) {
        return amount.mul(royaltyRate).div(1e18);
    }

    function chargeRoyaltyETH(uint royalty) external payable {
        if (royalty > 0) {
            require(royalty == msg.value, "invalid msg.value");
            if (address(this) != royaltyReceiver) {
                payable(royaltyReceiver).transfer(royalty);
            }
        }

        emit ChargeRoyaltyETH(royaltyReceiver, royalty);
    }

    function chargeRoyaltyERC20(address token, address from, uint royalty) external {
        if (royalty > 0) {
            IERC20Upgradeable(token).safeTransferFrom(from, royaltyReceiver, royalty);
        }

        emit ChargeRoyaltyERC20(royaltyReceiver, token, royalty);
    }

    function setRoyaltyReceiver(address royaltyReceiver_) external onlyOwner {
        royaltyReceiver = royaltyReceiver_;
    }

    function setRoyaltyRate(uint royaltyRate_) external onlyOwner {
        royaltyRate = royaltyRate_;
    }

    function withdrawETH(address payable to, uint amount) external onlyOwner {
        require(address(this).balance >= amount, "INSUFFICIENT AMOUNT");
        to.transfer(amount);
    }

    function withdrawERC20(address token, address to, uint amount) external onlyOwner {
        require(IERC20Upgradeable(token).balanceOf(address(this)) >= amount, "INSUFFICIENT AMOUNT");
        IERC20Upgradeable(token).safeTransfer(to, amount);
    }
}
