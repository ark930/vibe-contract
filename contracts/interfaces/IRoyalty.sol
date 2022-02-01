// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

interface IRoyalty {
    function calculateRoyalty(uint amount) external view returns (uint);

    function chargeRoyaltyETH(uint royalty) external payable;

    function chargeRoyaltyERC20(address token, address from, uint royalty) external;
}
