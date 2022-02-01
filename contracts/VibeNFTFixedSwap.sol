// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";

import "./interfaces/IRoyalty.sol";

contract VibeNFTFixedSwap is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for uint;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint internal constant TypeErc721 = 0;
    uint internal constant TypeErc1155 = 1;

    struct Pool {
        // address of pool creator
        address creator;
        // pool name
        string name;
        // address of sell token
        address token0;
        // address of buy token
        address token1;
        // token id of token0
        uint tokenId;
        // total amount of token0
        uint amountTotal0;
        // total amount of token1
        uint amountTotal1;
        // NFT token type
        uint nftType;
        // open at
        uint openAt;
    }

    address public royaltyAddress;
    Pool[] public pools;

    // creator address => pool index => whether the account create the pool.
    mapping(address => mapping(uint => bool)) public myCreatedP;

    // pool index => a flag that if creator is canceled the pool
    mapping(uint => bool) public creatorCanceledP;
    mapping(uint => bool) public swappedP;

    // pool index => swapped amount of token0
    mapping(uint => uint) public swappedAmount0P;
    // pool index => swapped amount of token1
    mapping(uint => uint) public swappedAmount1P;

    event Created(address indexed sender, uint indexed index, Pool pool);
    event Canceled(address indexed sender, uint indexed index, uint unswappedAmount0);
    event Swapped(address indexed sender, uint indexed index, uint swappedAmount0, uint swappedAmount1);

    function initialize() public initializer {
        super.__Ownable_init();
        super.__ReentrancyGuard_init();
    }

    function createErc721(
        // name of the pool
        string memory name,
        // address of token0
        address token0,
        // address of token1
        address token1,
        // token id of token0
        uint tokenId,
        // total amount of token1
        uint amountTotal1,
        // open at
        uint openAt
    ) external {
        uint amountTotal0 = 1;
        _create(
           name, token0, token1, tokenId, amountTotal0, amountTotal1, openAt, TypeErc721
        );
    }

    function createErc1155(
        // name of the pool
        string memory name,
        // address of token0
        address token0,
        // address of token1
        address token1,
        // token id of token0
        uint tokenId,
        // total amount of token0
        uint amountTotal0,
        // total amount of token1
        uint amountTotal1,
        // open at
        uint openAt
    ) external {
        _create(
           name, token0, token1, tokenId, amountTotal0, amountTotal1, openAt, TypeErc1155
        );
    }

    function _create(
        string memory name,
        address token0,
        address token1,
        uint tokenId,
        uint amountTotal0,
        uint amountTotal1,
        uint openAt,
        uint nftType
    ) private {
//        require(tx.origin == msg.sender, "disallow contract caller");
        require(amountTotal1 != 0, "the value of amountTotal1 is zero.");
        require(bytes(name).length <= 32, "the length of name is too long");

        // transfer tokenId of token0 to this contract
        if (nftType == TypeErc721) {
            require(amountTotal0 == 1, "invalid amountTotal0");
            IERC721Upgradeable(token0).safeTransferFrom(msg.sender, address(this), tokenId);
        } else {
            require(amountTotal0 != 0, "invalid amountTotal0");
            IERC1155Upgradeable(token0).safeTransferFrom(msg.sender, address(this), tokenId, amountTotal0, "");
        }

        // creator pool
        Pool memory pool;
        pool.creator = msg.sender;
        pool.name = name;
        pool.token0 = token0;
        pool.token1 = token1;
        pool.tokenId = tokenId;
        pool.amountTotal0 = amountTotal0;
        pool.amountTotal1 = amountTotal1;
        pool.nftType = nftType;
        pool.openAt = openAt;

        uint index = pools.length;
        myCreatedP[msg.sender][index] = true;

        pools.push(pool);

        emit Created(msg.sender, index, pool);
    }

    function swap(uint index, uint amount0) external payable
        isPoolExist(index)
        isPoolNotSwap(index)
    {
//        require(tx.origin == msg.sender, "disallow contract caller");
        require(!creatorCanceledP[index], "creator has canceled this pool");

        Pool storage pool = pools[index];
        require(pool.creator != msg.sender, "creator can't swap the pool created by self");
        require(amount0 >= 1 && amount0 <= pool.amountTotal0, "invalid amount0");
        require(swappedAmount0P[index].add(amount0) <= pool.amountTotal0, "pool filled or invalid amount0");
        require(pool.openAt <= block.timestamp, "pool is not open");

        uint amount1 = amount0.mul(pool.amountTotal1).div(pool.amountTotal0);
        swappedAmount0P[index] = swappedAmount0P[index].add(amount0);
        swappedAmount1P[index] = swappedAmount1P[index].add(amount1);
        if (swappedAmount0P[index] == pool.amountTotal0) {
            // mark pool is swapped
            swappedP[index] = true;
        }

        // transfer amount of token1 to creator
        IRoyalty royaltyContract = IRoyalty(royaltyAddress);
        uint royalty = royaltyContract.calculateRoyalty(amount1);
        uint _actualAmount1 = amount1.sub(royalty);
        if (pool.token1 == address(0)) {
            require(amount1 == msg.value, "invalid ETH amount");
            if (_actualAmount1 > 0) {
                // transfer ETH to creator
                payable(pool.creator).transfer(_actualAmount1);
            }
            royaltyContract.chargeRoyaltyETH{value: royalty}(royalty);
        } else {
            // transfer token1 to creator
            IERC20Upgradeable(pool.token1).safeTransferFrom(msg.sender, pool.creator, _actualAmount1);
            royaltyContract.chargeRoyaltyERC20(pools[index].token1, msg.sender, royalty);
        }

        // transfer tokenId of token0 to sender
        if (pool.nftType == TypeErc721) {
            IERC721Upgradeable(pool.token0).safeTransferFrom(address(this), msg.sender, pool.tokenId);
        } else {
            IERC1155Upgradeable(pool.token0).safeTransferFrom(address(this), msg.sender, pool.tokenId, amount0, "");
        }

        emit Swapped(msg.sender, index, amount0, amount1);
    }

    function cancel(uint index) external
        isPoolExist(index)
        isPoolNotSwap(index)
    {
        require(isCreator(msg.sender, index), "sender is not pool creator");
        require(!creatorCanceledP[index], "creator has canceled this pool");
        creatorCanceledP[index] = true;

        Pool memory pool = pools[index];
        if (pool.nftType == TypeErc721) {
            IERC721Upgradeable(pool.token0).safeTransferFrom(address(this), pool.creator, pool.tokenId);
        } else {
            IERC1155Upgradeable(pool.token0).safeTransferFrom(address(this), pool.creator, pool.tokenId, pool.amountTotal0.sub(swappedAmount0P[index]), "");
        }

        emit Canceled(msg.sender, index, pool.amountTotal0.sub(swappedAmount0P[index]));
    }

    function isCreator(address target, uint index) internal view returns (bool) {
        if (pools[index].creator == target) {
            return true;
        }
        return false;
    }

    function getFeeConfigContract() public view returns (address) {
        // TODO
        return address(this);
    }

    function getPoolCount() external view returns (uint) {
        return pools.length;
    }

    function onERC721Received(address, address, uint, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint, uint, bytes calldata) external pure returns(bytes4) {
        return this.onERC1155Received.selector;
    }

    modifier isPoolNotSwap(uint index) {
        require(!swappedP[index], "this pool is swapped");
        _;
    }

    modifier isPoolExist(uint index) {
        require(index < pools.length, "this pool does not exist");
        _;
    }
}
