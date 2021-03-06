// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "./interfaces/IRoyalty.sol";

contract VibeFixedSwap is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for uint;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct CreateReq {
        // pool name
        string name;
        // address of sell token
        address token0;
        // address of buy token
        address token1;
        // total amount of token0
        uint amountTotal0;
        // total amount of token1
        uint amountTotal1;
        // the timestamp in seconds the pool will open
        uint openAt;
        // the timestamp in seconds the pool will be closed
        uint closeAt;
        // the delay timestamp in seconds when buyers can claim after pool filled
        uint claimAt;
        uint maxAmount1PerWallet;
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
        // total amount of token0
        uint amountTotal0;
        // total amount of token1
        uint amountTotal1;
        // the timestamp in seconds the pool will open
        uint openAt;
        // the timestamp in seconds the pool will be closed
        uint closeAt;
        // the delay timestamp in seconds when buyers can claim after pool filled
        uint claimAt;
    }

    address public royaltyAddress;
    Pool[] public pools;

    // pool index => the timestamp which the pool filled at
    mapping(uint => uint) public filledAtP;
    // pool index => swap amount of token0
    mapping(uint => uint) public amountSwap0P;
    // pool index => swap amount of token1
    mapping(uint => uint) public amountSwap1P;
    // pool index => maximum swap amount1 per wallet, if the value is not set, the default value is zero
    mapping(uint => uint) public maxAmount1PerWalletP;
    // team address => pool index => whether or not creator's pool has been claimed
    mapping(address => mapping(uint => bool)) public creatorClaimed;
    // user address => pool index => swapped amount of token0
    mapping(address => mapping(uint => uint)) public myAmountSwapped0;
    // user address => pool index => swapped amount of token1
    mapping(address => mapping(uint => uint)) public myAmountSwapped1;
    // user address => pool index => whether or not my pool has been claimed
    mapping(address => mapping(uint => bool)) public myClaimed;

    event Created(uint indexed index, address indexed sender, Pool pool);
    event Swapped(uint indexed index, address indexed sender, uint amount0, uint amount1, uint royalty);
    event Claimed(uint indexed index, address indexed sender, uint amount0);
    event UserClaimed(uint indexed index, address indexed sender, uint amount0);

    function initialize(address _royaltyAddress) public initializer {
        super.__Ownable_init();
        super.__ReentrancyGuard_init();
        royaltyAddress = _royaltyAddress;
    }

    function create(CreateReq memory poolReq) external nonReentrant {
        uint index = pools.length;
        require(tx.origin == msg.sender, "disallow contract caller");
        require(poolReq.amountTotal0 != 0, "invalid amountTotal0");
        require(poolReq.amountTotal1 != 0, "invalid amountTotal1");
        require(poolReq.openAt >= block.timestamp, "invalid openAt");
        require(poolReq.closeAt > poolReq.openAt, "invalid closeAt");
        require(poolReq.claimAt == 0 || poolReq.claimAt >= poolReq.closeAt, "invalid closeAt");
        require(bytes(poolReq.name).length <= 15, "length of name is too long");

        if (poolReq.maxAmount1PerWallet != 0) {
            maxAmount1PerWalletP[index] = poolReq.maxAmount1PerWallet;
        }

        // transfer amount of token0 to this contract
        IERC20Upgradeable _token0 = IERC20Upgradeable(poolReq.token0);
        uint token0BalanceBefore = _token0.balanceOf(address(this));
        _token0.safeTransferFrom(msg.sender, address(this), poolReq.amountTotal0);
        require(
            _token0.balanceOf(address(this)).sub(token0BalanceBefore) == poolReq.amountTotal0,
            "not support deflationary token"
        );

        Pool memory pool;
        pool.name = poolReq.name;
        pool.creator = msg.sender;
        pool.token0 = poolReq.token0;
        pool.token1 = poolReq.token1;
        pool.amountTotal0 = poolReq.amountTotal0;
        pool.amountTotal1 = poolReq.amountTotal1;
        pool.openAt = poolReq.openAt;
        pool.closeAt = poolReq.closeAt;
        pool.claimAt = poolReq.claimAt;
        pools.push(pool);

        emit Created(index, msg.sender, pool);
    }

    function swap(uint index, uint amount1) external payable
        nonReentrant
        isPoolExist(index)
        isPoolNotClosed(index)
    {
        require(tx.origin == msg.sender, "disallow contract caller");
        Pool memory pool = pools[index];

        require(pool.openAt <= block.timestamp, "pool not open");
        require(pool.amountTotal1 > amountSwap1P[index], "swap amount is zero");

        // check if amount1 is exceeded
        uint excessAmount1 = 0;
        uint _amount1 = pool.amountTotal1.sub(amountSwap1P[index]);
        if (_amount1 < amount1) {
            excessAmount1 = amount1.sub(_amount1);
        } else {
            _amount1 = amount1;
        }

        // check if amount0 is exceeded
        uint amount0 = _amount1.mul(pool.amountTotal0).div(pool.amountTotal1);
        uint _amount0 = pool.amountTotal0.sub(amountSwap0P[index]);
        if (_amount0 > amount0) {
            _amount0 = amount0;
        }

        amountSwap0P[index] = amountSwap0P[index].add(_amount0);
        amountSwap1P[index] = amountSwap1P[index].add(_amount1);
        myAmountSwapped0[msg.sender][index] = myAmountSwapped0[msg.sender][index].add(_amount0);
        // check if swapped amount of token1 is exceeded maximum allowance
        if (maxAmount1PerWalletP[index] != 0) {
            require(
                myAmountSwapped1[msg.sender][index].add(_amount1) <= maxAmount1PerWalletP[index],
                "swapped amount of token1 is exceeded maximum allowance"
            );
            myAmountSwapped1[msg.sender][index] = myAmountSwapped1[msg.sender][index].add(_amount1);
        }

        if (pool.amountTotal1 == amountSwap1P[index]) {
            filledAtP[index] = block.timestamp;
        }

        // transfer amount of token1 to this contract
        if (pool.token1 == address(0)) {
            require(msg.value == amount1, "invalid amount of ETH");
        } else {
            IERC20Upgradeable(pool.token1).safeTransferFrom(msg.sender, address(this), amount1);
        }

        if (pool.claimAt == 0) {
            if (_amount0 > 0) {
                // send token0 to msg.sender
                IERC20Upgradeable(pool.token0).safeTransfer(msg.sender, _amount0);
            }
        }
        if (excessAmount1 > 0) {
            // send excess amount of token1 back to msg.sender
            if (pool.token1 == address(0)) {
                payable(msg.sender).transfer(excessAmount1);
            } else {
                IERC20Upgradeable(pool.token1).safeTransfer(msg.sender, excessAmount1);
            }
        }

        // send token1 to creator
        IRoyalty royaltyContract = IRoyalty(royaltyAddress);
        uint royalty = royaltyContract.calculateRoyalty(amount1);
        uint _actualAmount1 = amount1.sub(royalty);
        if (pool.token1 == address(0)) {
            payable(pool.creator).transfer(_actualAmount1);
            royaltyContract.chargeRoyaltyETH{value: royalty}(royalty);
        } else {
            IERC20Upgradeable(pool.token1).safeTransfer(pool.creator, _actualAmount1);
            IERC20Upgradeable(pool.token1).safeApprove(royaltyAddress, royalty);
            royaltyContract.chargeRoyaltyERC20(pool.token1, address(this), royalty);
        }

        emit Swapped(index, msg.sender, _amount0, _actualAmount1, royalty);
    }

    function creatorClaim(uint index) external
        nonReentrant
        isPoolExist(index)
        isPoolClosed(index)
    {
        Pool memory pool = pools[index];
        require(!creatorClaimed[pool.creator][index], "claimed");
        creatorClaimed[pool.creator][index] = true;

        uint unSwapAmount0 = pool.amountTotal0.sub(amountSwap0P[index]);
        if (unSwapAmount0 > 0) {
            IERC20Upgradeable(pool.token0).safeTransfer(pool.creator, unSwapAmount0);
        }

        emit Claimed(index, msg.sender, unSwapAmount0);
    }

    function userClaim(uint index) external
        nonReentrant
        isPoolExist(index)
        isClaimReady(index)
    {
        Pool memory pool = pools[index];
        require(!myClaimed[msg.sender][index], "claimed");
        myClaimed[msg.sender][index] = true;
        if (myAmountSwapped0[msg.sender][index] > 0) {
            // send token0 to msg.sender
            IERC20Upgradeable(pool.token0).safeTransfer(msg.sender, myAmountSwapped0[msg.sender][index]);
        }
        emit UserClaimed(index, msg.sender, myAmountSwapped0[msg.sender][index]);
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

    modifier isClaimReady(uint index) {
        require(pools[index].claimAt != 0, "invalid claim");
        require(pools[index].claimAt <= block.timestamp, "claim not ready");
        _;
    }

    modifier isPoolExist(uint index) {
        require(index < pools.length, "this pool does not exist");
        _;
    }
}
