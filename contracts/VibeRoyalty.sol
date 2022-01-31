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

    uint public maxFeeRate;
    uint public minFeeRate;
    uint public feeRate;
    address public feeReceiver;
    address public signer;

    // collection address => receiver
    mapping(address => address) royaltyReceiver;
    // collection address => rate
    mapping(address => uint) royaltyRate;

    event CollectionConfigSet(
        address indexed sender,
        address indexed collection,
        address indexed royaltyReceiver,
        uint royaltyRate
    );
    event ChargeFeeETH(
        address indexed platformReceiver,
        address indexed royaltyReceiver,
        address indexed collection,
        uint platformFee,
        uint royaltyFee
    );
    event ChargeFeeToken(
        address indexed platformReceiver,
        address indexed royaltyReceiver,
        address indexed collection,
        address token,
        uint platformFee,
        uint royaltyFee
    );

    function initialize() public initializer {
        super.__Ownable_init();
        // TODO
//        signer = signer_;
        feeReceiver = address(this);
        feeRate = 0.035 ether; // 3.5%
        maxFeeRate = 0.065 ether; // 6.5%
        minFeeRate = 0.001 ether; // 0.1%
    }

    function getPlatformFee(uint amount) public view returns (uint) {
        return amount.mul(getPlatformFeeRate()).div(1 ether);
    }

    function getRoyaltyFee(address collection, uint amount) public view returns (uint) {
        return amount.mul(royaltyRate[collection]).div(1 ether);
    }

    function getFeeAndRemaining(address collection, uint amount) public view returns (uint, uint, uint) {
        uint platformFee = getPlatformFee(amount);
        uint royaltyFee = getRoyaltyFee(collection, amount);
        uint remaining = amount.sub(platformFee).sub(royaltyFee);
        return (platformFee, royaltyFee, remaining);
    }

    function chargeFeeETH(address collection, uint platformFee, uint royaltyFee) external payable {
        require(platformFee.add(royaltyFee) == msg.value, "invalid msg.value");

        address platformReceiver = feeETHToPlatform(platformFee);
        address _royaltyReceiver = feeETHToCollection(collection, royaltyFee);

        emit ChargeFeeETH(platformReceiver, _royaltyReceiver, collection, platformFee, royaltyFee);
    }

    function chargeFeeToken(address collection, address token, address from, uint platformFee, uint royaltyFee) external {
        address platformReceiver = feeTokenToPlatform(token, from, platformFee);
        address _royaltyReceiver = feeTokenToCollection(collection, token, from, royaltyFee);

        emit ChargeFeeToken(platformReceiver, _royaltyReceiver, collection, token, platformFee, royaltyFee);
    }

    function feeETHToPlatform(uint fee) internal returns (address) {
        address receiver = getPlatformFeeReceiver();
        if (address(this) != receiver && fee > 0) {
            payable(receiver).transfer(fee);
        }
        return receiver;
    }

    function feeETHToCollection(address collection, uint fee) internal returns (address) {
        if (address(this) != royaltyReceiver[collection] && fee > 0) {
            payable(royaltyReceiver[collection]).transfer(fee);
        }
        return royaltyReceiver[collection];
    }

    function feeTokenToPlatform(address token, address from, uint fee) internal returns (address) {
        address receiver = getPlatformFeeReceiver();
        if (address(this) != receiver && fee > 0) {
            IERC20Upgradeable(token).safeTransferFrom(from, receiver, fee);
        }
        return receiver;
    }

    function feeTokenToCollection(address collection, address token, address from, uint fee) internal returns (address) {
        if (address(this) != royaltyReceiver[collection] && fee > 0) {
            IERC20Upgradeable(token).safeTransferFrom(from, royaltyReceiver[collection], fee);
        }
        return royaltyReceiver[collection];
    }

    function setPlatFormatReceiver(address feeReceiver_) external onlyOwner {
        feeReceiver = feeReceiver_;
    }

    function setPlatformFeeRate(uint feeRate_) external onlyOwner {
        feeRate = feeRate_;
    }

    function setMaxFeeRate(uint maxFeeRate_) external onlyOwner {
        require(maxFeeRate > getMinFeeRate(), "maxFeeRate must larger than minFeeRate");
        minFeeRate = maxFeeRate_;
    }

    function setMinFeeRate(uint minFeeRate_) external onlyOwner {
        require(minFeeRate < getMaxFeeRate(), "minFeeRate must less than maxFeeRate");
        minFeeRate = minFeeRate_;
    }

    function setSigner(address signer_) external onlyOwner {
        signer = signer_;
    }

    function setCollectionConfig(address collection, address _royaltyReceiver, uint _royaltyRate, uint expireTime, bytes calldata sign) external {
        require(block.timestamp <= expireTime, "SIGN EXPIRE");
        bytes32 hash = ECDSAUpgradeable.toEthSignedMessageHash(keccak256(abi.encode(msg.sender, collection, _royaltyReceiver, _royaltyRate, expireTime)));
        require(ECDSAUpgradeable.recover(hash, sign) == signer, "INVALID SIGNER");

        require(_royaltyRate <= getMaxFeeRate(), "_royaltyRate must less than or equal to maxFeeRate");
        require(_royaltyRate >= getMinFeeRate(), "_royaltyRate must larger than or equal to minFeeRate");
        royaltyReceiver[collection] = _royaltyReceiver;
        royaltyRate[collection] = _royaltyRate;

        emit CollectionConfigSet(msg.sender, collection, _royaltyReceiver, _royaltyRate);
    }

    function getMaxFeeRate() public view returns (uint) {
        return maxFeeRate;
    }

    function getMinFeeRate() public view returns (uint) {
        return minFeeRate;
    }

    function getPlatformFeeReceiver() public view returns (address) {
        return feeReceiver;
    }

    function getPlatformFeeRate() public view returns (uint) {
        return feeRate;
    }

    function totalFeeRate(address collection) public view returns (uint) {
        return getPlatformFeeRate().add(royaltyRate[collection]);
    }

    function sendReward(address payable to, uint amount) external onlyOwner {
        require(address(this).balance >= amount, "INSUFFICIENT AMOUNT");
        to.transfer(amount);
    }

    function sendERC20Reward(address token, address to, uint amount) external onlyOwner {
        require(IERC20Upgradeable(token).balanceOf(address(this)) >= amount, "INSUFFICIENT AMOUNT");
        IERC20Upgradeable(token).safeTransfer(to, amount);
    }
}
