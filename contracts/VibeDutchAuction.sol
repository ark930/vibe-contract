// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "./interfaces/IRoyalty.sol";

contract VibeDutchAuction is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct CreateReq {
        // pool name
        string name;
        // creator of the pool
        address creator;
        // address of sell token
        address token0;
        // address of buy token
        address token1;
        // total amount of token0
        uint amountTotal0;
        // maximum amount of ETH that creator want to swap
        uint amountMax1;
        // minimum amount of ETH that creator want to swap
        uint amountMin1;
//        uint amountReserve1;
        // how many times a bid will decrease it's price
        uint times;
        // the timestamp in seconds the pool will open
        uint openAt;
        // the timestamp in seconds the pool will be closed
        uint closeAt;
    }

    struct Pool {
        // pool name
        string name;
        // creator of the pool
        address creator;
        // address of sell token
        address token0;
        // address of buy token
        address token1;
        // total amount of sell token
        uint amountTotal0;
        // maximum amount of ETH that creator want to swap
        uint amountMax1;
        // minimum amount of ETH that creator want to swap
        uint amountMin1;
//        uint amountReserve1;
        // how many times a bid will decrease it's price
        uint times;
        // the duration in seconds the pool will be closed
        uint duration;
        // the timestamp in seconds the pool will open
        uint openAt;
        // the timestamp in seconds the pool will be closed
        uint closeAt;
    }

    address public royaltyAddress;
    Pool[] public pools;

    // pool index => amount of sell token has been swap
    mapping(uint => uint) public amountSwap0P;
    // pool index => amount of ETH has been swap
    mapping(uint => uint) public amountSwap1P;
    // pool index => a flag that if creator is claimed the pool
    mapping(uint => bool) public creatorClaimedP;

    mapping(uint => uint) public lowestBidPrice;
    // bidder address => pool index => whether or not bidder claimed
    mapping(address => mapping(uint => bool)) public bidderClaimedP;
    // bidder address => pool index => swapped amount of token0
    mapping(address => mapping(uint => uint)) public myAmountSwap0P;
    // bidder address => pool index => swapped amount of token1
    mapping(address => mapping(uint => uint)) public myAmountSwap1P;

    // creator address => pool index + 1. if the result is 0, the account don't create any pool.
    mapping(address => uint) public myCreatedP;

    event Created(uint indexed index, address indexed sender, Pool pool);
    event Bid(uint indexed index, address indexed sender, uint amount0, uint amount1);
    event Claimed(uint indexed index, address indexed sender, uint unFilledAmount0);

    function initialize(address _royaltyAddress) public initializer {
        super.__Ownable_init();
        super.__ReentrancyGuard_init();
        royaltyAddress = _royaltyAddress;
    }

    function create(CreateReq memory poolReq) external nonReentrant {
        require(tx.origin == msg.sender, "disallow contract caller");
        require(poolReq.amountTotal0 != 0, "the value of amountTotal0 is zero");
        require(poolReq.amountMin1 != 0, "the value of amountMax1 is zero");
        require(poolReq.amountMax1 != 0, "the value of amountMin1 is zero");
        require(poolReq.amountMax1 > poolReq.amountMin1, "amountMax1 should larger than amountMin1");
        require(poolReq.openAt <= poolReq.closeAt && poolReq.closeAt.sub(poolReq.openAt) < 7 days, "invalid closed");
        require(poolReq.times != 0, "the value of times is zero");
        require(bytes(poolReq.name).length <= 15, "the length of name is too long");

        uint index = pools.length;

        // transfer amount of token0 to this contract
        IERC20Upgradeable  _token0 = IERC20Upgradeable(poolReq.token0);
        uint token0BalanceBefore = _token0.balanceOf(address(this));
        _token0.safeTransferFrom(poolReq.creator, address(this), poolReq.amountTotal0);
        require(
            _token0.balanceOf(address(this)).sub(token0BalanceBefore) == poolReq.amountTotal0,
            "not support deflationary token"
        );

        // creator pool
        Pool memory pool;
        pool.name = poolReq.name;
        pool.creator = poolReq.creator;
        pool.token0 = poolReq.token0;
        pool.token1 = poolReq.token1;
        pool.amountTotal0 = poolReq.amountTotal0;
        pool.amountMax1 = poolReq.amountMax1;
        pool.amountMin1 = poolReq.amountMin1;
//        pool.amountReserve1 = poolReq.amountReserve1;
        pool.times = poolReq.times;
        pool.duration = poolReq.closeAt.sub(poolReq.openAt);
        pool.openAt = poolReq.openAt;
        pool.closeAt = poolReq.closeAt;
        pools.push(pool);

        myCreatedP[poolReq.creator] = pools.length;

        emit Created(index, msg.sender, pool);
    }

    function bid(
        // pool index
        uint index,
        // amount of token0 want to bid
        uint amount0,
        // amount of token1
        uint amount1
    ) external payable
        nonReentrant
        isPoolExist(index)
        isPoolNotClosed(index)
    {
        address sender = msg.sender;
        require(tx.origin == msg.sender, "disallow contract caller");
        Pool memory pool = pools[index];
        require(pool.openAt <= block.timestamp, "pool not open");
        require(amount0 != 0, "the value of amount0 is zero");
        require(amount1 != 0, "the value of amount1 is zero");
        require(pool.amountTotal0 > amountSwap0P[index], "swap amount is zero");

        // calculate price
        uint curPrice = currentPrice(index);
        uint bidPrice = amount1.mul(1 ether).div(amount0);
        require(bidPrice >= curPrice, "the bid price is lower than the current price");

        if (lowestBidPrice[index] == 0 || lowestBidPrice[index] > bidPrice) {
            lowestBidPrice[index] = bidPrice;
        }

        address token1 = pool.token1;
        if (token1 == address(0)) {
            require(amount1 == msg.value, "invalid ETH amount");
        } else {
            IERC20Upgradeable(token1).safeTransferFrom(sender, address(this), amount1);
        }

        _swap(sender, index, amount0, amount1);

        emit Bid(index, sender, amount0, amount1);
    }

    function creatorClaim(uint index) external
        nonReentrant
        isPoolExist(index)
        isPoolClosed(index)
    {
        address creator = msg.sender;
        require(isCreator(creator, index), "sender is not pool creator");
        require(!creatorClaimedP[index], "creator has claimed this pool");
        creatorClaimedP[index] = true;

        // remove ownership of this pool from creator
        delete myCreatedP[creator];

        // calculate un-filled amount0
        Pool memory pool = pools[index];
        uint unFilledAmount0 = pool.amountTotal0.sub(amountSwap0P[index]);
        if (unFilledAmount0 > 0) {
            // transfer un-filled amount of token0 back to creator
            IERC20Upgradeable(pool.token0).safeTransfer(creator, unFilledAmount0);
        }

        // send token1 to creator
        uint amount1 = lowestBidPrice[index].mul(amountSwap0P[index]).div(1 ether);
        if (amount1 > 0) {
            IRoyalty royaltyContract = IRoyalty(royaltyAddress);
            uint royalty = royaltyContract.calculateRoyalty(amount1);
            uint _actualAmount1 = amount1.sub(royalty);
            if (pool.token1 == address(0)) {
                if (_actualAmount1 > 0) {
                    payable(pool.creator).transfer(_actualAmount1);
                }
                royaltyContract.chargeRoyaltyETH{value: royalty}(royalty);
            } else {
                IERC20Upgradeable(pool.token1).safeTransfer(pool.creator, _actualAmount1);
                IERC20Upgradeable(pool.token1).safeApprove(royaltyAddress, royalty);
                royaltyContract.chargeRoyaltyERC20(pool.token1, address(this), royalty);
            }
        }

        emit Claimed(index, creator, unFilledAmount0);
    }

    function bidderClaim(uint index) external
        nonReentrant
        isPoolExist(index)
        isPoolClosed(index)
    {
        address bidder = msg.sender;
        require(!bidderClaimedP[bidder][index], "bidder has claimed this pool");
        bidderClaimedP[bidder][index] = true;

        Pool memory pool = pools[index];
        // send token0 to bidder
        if (myAmountSwap0P[bidder][index] > 0) {
            IERC20Upgradeable(pool.token0).safeTransfer(bidder, myAmountSwap0P[bidder][index]);
        }

        // send unfilled token1 to bidder
        uint actualAmount1 = lowestBidPrice[index].mul(myAmountSwap0P[bidder][index]).div(1 ether);
        uint unfilledAmount1 = myAmountSwap1P[bidder][index].sub(actualAmount1);
        if (unfilledAmount1 > 0) {
            if (pool.token1 == address(0)) {
                payable(bidder).transfer(unfilledAmount1);
            } else {
                IERC20Upgradeable(pool.token1).safeTransfer(bidder, unfilledAmount1);
            }
        }
    }

    function _swap(address sender, uint index, uint amount0, uint amount1) private {
        Pool memory pool = pools[index];
        uint _amount0 = pool.amountTotal0.sub(amountSwap0P[index]);
        uint _amount1 = 0;
        uint _excessAmount1 = 0;

        // check if amount0 is exceeded
        if (_amount0 < amount0) {
            _amount1 = _amount0.mul(amount1).div(amount0);
            _excessAmount1 = amount1.sub(_amount1);
        } else {
            _amount0 = amount0;
            _amount1 = amount1;
        }
        myAmountSwap0P[sender][index] = myAmountSwap0P[sender][index].add(_amount0);
        myAmountSwap1P[sender][index] = myAmountSwap1P[sender][index].add(_amount1);
        amountSwap0P[index] = amountSwap0P[index].add(_amount0);
        amountSwap1P[index] = amountSwap1P[index].add(_amount1);

        // send excess amount of token1 back to sender
        if (_excessAmount1 > 0) {
            if (pool.token1 == address(0)) {
                payable(sender).transfer(_excessAmount1);
            } else {
                IERC20Upgradeable(pool.token1).safeTransfer(sender, _excessAmount1);
            }
        }
    }

    function isCreator(address target, uint index) private view returns (bool) {
        if (pools[index].creator == target) {
            return true;
        }
        return false;
    }

    function currentPrice(uint index) public view returns (uint) {
        Pool memory pool = pools[index];
        uint _amount1 = pool.amountMin1;
        uint realTimes = pool.times.add(1);

        if (block.timestamp < pool.closeAt) {
            uint stepInSeconds = pool.duration.div(realTimes);
            if (stepInSeconds != 0) {
                uint remainingTimes = pool.closeAt.sub(block.timestamp).sub(1).div(stepInSeconds);
                if (remainingTimes != 0) {
                    _amount1 = pool.amountMax1.sub(pool.amountMin1)
                        .mul(remainingTimes).div(pool.times)
                        .add(pool.amountMin1);
                }
            }
        }

        return _amount1.mul(1 ether).div(pool.amountTotal0);
    }

    function nextRoundInSeconds(uint index) public view returns (uint) {
        Pool memory pool = pools[index];
        if (block.timestamp >= pool.closeAt) return 0;
        uint realTimes = pool.times.add(1);
        uint stepInSeconds = pool.duration.div(realTimes);
        if (stepInSeconds == 0) return 0;
        uint remainingTimes = pool.closeAt.sub(block.timestamp).sub(1).div(stepInSeconds);

        return pool.closeAt.sub(remainingTimes.mul(stepInSeconds)).sub(block.timestamp);
    }

    function getPoolCount() public view returns (uint) {
        return pools.length;
    }

    modifier isPoolClosed(uint index) {
        require(pools[index].closeAt <= block.timestamp, "this pool is not closed");
        _;
    }

    modifier isPoolNotClosed(uint index) {
        require(pools[index].closeAt > block.timestamp, "this pool is closed");
        _;
    }

    modifier isPoolNotCreate(address target) {
        if (myCreatedP[target] > 0) {
            revert("a pool has created by this address");
        }
        _;
    }

    modifier isPoolExist(uint index) {
        require(index < pools.length, "this pool does not exist");
        _;
    }
}
