// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

interface IRoyaltyConfig {
    function getFeeAndRemaining(address brand, uint amount) external view returns (uint platformFee, uint royaltyFee, uint remaining);

    function chargeFeeETH(address brand, uint platformFee, uint royaltyFee) external payable;

    function chargeFeeToken(address brand, address token, address from, uint platformFee, uint royaltyFee) external;
}
