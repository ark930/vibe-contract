// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";

import "./interfaces/IRoyaltyConfig.sol";

contract VibeNFTEnglishAuction is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint    internal constant TypeErc721                = 0;
    uint    internal constant TypeErc1155               = 1;

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
        // amount of token id of token0
        uint tokenAmount0;
        // maximum amount of token1 that creator want to swap
        uint amountMax1;
        // minimum amount of token1 that creator want to swap
        uint amountMin1;
        // minimum incremental amount of token1
        uint amountMinIncr1;
        // the duration in seconds the pool will be closed
        uint openAt;
        // the timestamp in seconds the pool will be closed
        uint closeAt;
        // NFT token type
        uint nftType;
    }

    Pool[] public pools;

    // pool index => a flag that if creator is claimed the pool
    mapping(uint => bool) public creatorClaimedP;
    // pool index => the candidate of winner who bid the highest amount1 in current round
    mapping(uint => address) public currentBidderP;
    // pool index => the highest amount1 in current round
    mapping(uint => uint) public currentBidderAmount1P;
    // pool index => reserve amount of token1
    mapping(uint => uint) public reserveAmount1P;

    // creator address => pool index => whether the account create the pool.
    mapping(address => mapping(uint => bool)) public myCreatedP;
    // account => pool index => bid amount1
    mapping(address => mapping(uint => uint)) public myBidderAmount1P;
    // account => pool index => claim flag
    mapping(address => mapping(uint => bool)) public myClaimedP;

    // pool index => bid count
    mapping(uint => uint) public bidCountP;

    uint public totalTxFee;
    // pool index => a flag whether pool has been cancelled
    mapping(uint => bool) public creatorCanceledP;

    event Created(address indexed sender, uint indexed index, Pool pool);
    event Bid(address indexed sender, uint indexed index, uint amount1);
    event Canceled(address indexed sender, uint indexed index, uint tokenId, uint amount0);
    event CreatorClaimed(address indexed sender, uint indexed index, uint tokenId, uint amount0, uint amount1);
    event BidderClaimed(address indexed sender, uint indexed index, uint tokenId, uint amount0, uint amount1);

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
        // maximum amount of token1
        uint amountMax1,
        // minimum amount of token1
        uint amountMin1,
        // minimum incremental amount of token1
        uint amountMinIncr1,
        // reserve amount of token1
        uint amountReserve1,
        // open at
        uint openAt,
        // duration
        uint duration
    ) public {
        uint tokenAmount0 = 1;
        _create(name, token0, token1, tokenId, tokenAmount0, amountMax1, amountMin1, amountMinIncr1, amountReserve1, openAt, duration, TypeErc721);
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
        // amount of token id of token0
        uint tokenAmount0,
        // maximum amount of token1
        uint amountMax1,
        // minimum amount of token1
        uint amountMin1,
        // minimum incremental amount of token1
        uint amountMinIncr1,
        // reserve amount of token1
        uint amountReserve1,
        // open at
        uint openAt,
        // duration
        uint duration
    ) public {
        _create(name, token0, token1, tokenId, tokenAmount0, amountMax1, amountMin1, amountMinIncr1, amountReserve1, openAt, duration, TypeErc1155);
    }

    function _create(
        // name of the pool
        string memory name,
        // address of token0
        address token0,
        // address of token1
        address token1,
        // token id of token0
        uint tokenId,
        // amount of token id of token0
        uint tokenAmount0,
        // maximum amount of token1
        uint amountMax1,
        // minimum amount of token1
        uint amountMin1,
        // minimum incremental amount of token1
        uint amountMinIncr1,
        // reserve amount of token1
        uint amountReserve1,
        // open at
        uint openAt,
        // duration
        uint duration,
        // NFT token type
        uint nftType
    ) private {
        address creator = msg.sender;

//        require(tx.origin == msg.sender, "disallow contract caller");
        require(tokenAmount0 != 0, "invalid tokenAmount0");
        require(amountReserve1 == 0 || amountReserve1 >= amountMin1, "invalid amountReserve1");
        require(amountMax1 == 0 || (amountMax1 >= amountReserve1 && amountMax1 >= amountMin1), "invalid amountMax1");
        require(amountMinIncr1 != 0, "invalid amountMinIncr1");
        require(duration != 0, "invalid duration");
        require(bytes(name).length <= 32, "the length of name is too long");

        // transfer tokenId of token0 to this contract
        if (nftType == TypeErc721) {
            IERC721Upgradeable(token0).safeTransferFrom(creator, address(this), tokenId);
        } else {
            IERC1155Upgradeable(token0).safeTransferFrom(creator, address(this), tokenId, tokenAmount0, "");
        }

        // creator pool
        Pool memory pool;
        pool.creator = creator;
        pool.name = name;
        pool.token0 = token0;
        pool.token1 = token1;
        pool.tokenId = tokenId;
        pool.tokenAmount0 = tokenAmount0;
        pool.amountMax1 = amountMax1;
        pool.amountMin1 = amountMin1;
        pool.amountMinIncr1 = amountMinIncr1;
        pool.openAt = openAt;
        pool.closeAt = openAt.add(duration);
        pool.nftType = nftType;

        uint index = pools.length;
        reserveAmount1P[index] = amountReserve1;
        myCreatedP[msg.sender][index] = true;

        pools.push(pool);

        emit Created(msg.sender, index, pool);
    }

    function bid(
        // pool index
        uint index,
        // amount of token1
        uint amount1
    ) external payable
        nonReentrant
        isPoolExist(index)
        isPoolNotClosed(index)
    {
        address sender = msg.sender;

        Pool storage pool = pools[index];
//        require(tx.origin == msg.sender, "disallow contract caller");
        require(pool.creator != sender, "creator can't bid the pool created by self");
        require(pool.openAt <= block.timestamp, "pool is not open");
        require(amount1 != 0, "invalid amount1");
        require(amount1 >= pool.amountMin1, "the bid amount is lower than minimum bidder amount");
        require(amount1 >= currentBidderAmount(index), "the bid amount is lower than the current bidder amount");

        if (pool.token1 == address(0)) {
            require(amount1 == msg.value, "invalid ETH amount");
        } else {
            IERC20Upgradeable(pool.token1).safeTransferFrom(sender, address(this), amount1);
        }

        // return ETH to previous bidder
        if (currentBidderP[index] != address(0) && currentBidderAmount1P[index] > 0) {
            if (pool.token1 == address(0)) {
                payable(currentBidderP[index]).transfer(currentBidderAmount1P[index]);
            } else {
                IERC20Upgradeable(pool.token1).safeTransfer(currentBidderP[index], currentBidderAmount1P[index]);
            }
        }

        // record new winner
        currentBidderP[index] = sender;
        currentBidderAmount1P[index] = amount1;
        bidCountP[index] = bidCountP[index] + 1;
        myBidderAmount1P[sender][index] = amount1;

        emit Bid(sender, index, amount1);

        if (pool.amountMax1 > 0 && pool.amountMax1 <= amount1) {
            _creatorClaim(index);
            _bidderClaim(sender, index);
        }
    }

    function cancel(uint index) external
        isPoolExist(index)
    {
        Pool memory pool = pools[index];
        require(pool.openAt > block.timestamp, "cannot cancel pool when pool is open");
        require(!creatorCanceledP[index], "pool has been cancelled");
        require(isCreator(msg.sender, index), "sender is not pool's creator");

        creatorCanceledP[index] = true;

        // transfer token0 back to creator
        if (pool.nftType == TypeErc721) {
            IERC721Upgradeable(pool.token0).safeTransferFrom(address(this), pool.creator, pool.tokenId);
            emit Canceled(pool.creator, index, pool.tokenId, 1);
        } else {
            IERC1155Upgradeable(pool.token0).safeTransferFrom(address(this), pool.creator, pool.tokenId, pool.tokenAmount0, "");
            emit Canceled(pool.creator, index, pool.tokenId, pool.tokenAmount0);
        }
    }

    function creatorClaim(uint index) external
        isPoolExist(index)
        isPoolClosed(index)
    {
        require(isCreator(msg.sender, index), "sender is not pool's creator");
        _creatorClaim(index);
    }

    function _creatorClaim(uint index) private {
        require(!creatorClaimedP[index], "creator has claimed");
        creatorClaimedP[index] = true;

        Pool memory pool = pools[index];
        uint amount1 = currentBidderAmount1P[index];
        if (currentBidderP[index] != address(0) && amount1 >= reserveAmount1P[index]) {
            (uint platformFee, uint royaltyFee, uint _actualAmount1) = IRoyaltyConfig(getFeeConfigContract())
                .getFeeAndRemaining(pools[index].token0, amount1);
            uint totalFee = platformFee.add(royaltyFee);
            if (pool.token1 == address(0)) {
                // transfer ETH to creator
                if (_actualAmount1 > 0) {
                    payable(pool.creator).transfer(_actualAmount1);
                }
                IRoyaltyConfig(getFeeConfigContract())
                    .chargeFeeETH{value: totalFee}(pools[index].token0, platformFee, royaltyFee);
            } else {
                IERC20Upgradeable(pool.token1).safeTransfer(pool.creator, _actualAmount1);
                IERC20Upgradeable(pool.token1).safeApprove(getFeeConfigContract(), totalFee);
                IRoyaltyConfig(getFeeConfigContract())
                    .chargeFeeToken(pools[index].token0, pools[index].token1, address(this), platformFee, royaltyFee);
            }
            emit CreatorClaimed(pool.creator, index, pool.tokenId, 0, amount1);
        } else {
            // transfer token0 back to creator
            if (pool.nftType == TypeErc721) {
                IERC721Upgradeable(pool.token0).safeTransferFrom(address(this), pool.creator, pool.tokenId);
                emit CreatorClaimed(pool.creator, index, pool.tokenId, 1, 0);
            } else {
                IERC1155Upgradeable(pool.token0).safeTransferFrom(address(this), pool.creator, pool.tokenId, pool.tokenAmount0, "");
                emit CreatorClaimed(pool.creator, index, pool.tokenId, pool.tokenAmount0, 0);
            }
        }
    }

    function bidderClaim(uint index) external
        isPoolExist(index)
        isPoolClosed(index)
    {
        _bidderClaim(msg.sender, index);
    }

    function withdrawFee(address payable to, uint amount) external onlyOwner {
        totalTxFee = totalTxFee.sub(amount);
        to.transfer(amount);
    }

    function withdrawToken(address token, address to, uint amount) external onlyOwner {
        IERC20Upgradeable(token).safeTransfer(to, amount);
    }

    function _bidderClaim(address sender, uint index) private {
        require(currentBidderP[index] == sender, "sender is not winner");
        require(!myClaimedP[sender][index], "sender has claimed");
        myClaimedP[sender][index] = true;

        uint amount1 = currentBidderAmount1P[index];
        Pool memory pool = pools[index];
        if (amount1 >= reserveAmount1P[index]) {
            // transfer token0 to bidder
            if (pool.nftType == TypeErc721) {
                IERC721Upgradeable(pool.token0).safeTransferFrom(address(this), sender, pool.tokenId);
                emit BidderClaimed(sender, index, pool.tokenId, 1, 0);
            } else {
                IERC1155Upgradeable(pool.token0).safeTransferFrom(address(this), sender, pool.tokenId, pool.tokenAmount0, "");
                emit BidderClaimed(sender, index, pool.tokenId, pool.tokenAmount0, 0);
            }
        } else {
            // transfer token1 back to bidder
            if (pool.token1 == address(0)) {
                payable(sender).transfer(amount1);
            } else {
                IERC20Upgradeable(pool.token1).safeTransfer(sender, amount1);
            }
            emit BidderClaimed(sender, index, pool.tokenId, 0, amount1);
        }
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns(bytes4) {
        return this.onERC1155Received.selector;
    }

    function getPoolCount() external view returns (uint) {
        return pools.length;
    }

    function currentBidderAmount(uint index) public view returns (uint) {
        Pool memory pool = pools[index];
        uint amount = pool.amountMin1;

        if (currentBidderP[index] != address(0)) {
            amount = currentBidderAmount1P[index].add(pool.amountMinIncr1);
        } else if (pool.amountMin1 == 0) {
            amount = pool.amountMinIncr1;
        }

        return amount;
    }

    function isCreator(address target, uint index) private view returns (bool) {
        if (pools[index].creator == target) {
            return true;
        }
        return false;
    }

    function getFeeConfigContract() public view returns (address) {
        // TODO
        return address(this);
    }

    modifier isPoolClosed(uint index) {
        require(pools[index].closeAt <= block.timestamp || creatorClaimedP[index], "this pool is not closed");
        _;
    }

    modifier isPoolNotClosed(uint index) {
        require(pools[index].closeAt > block.timestamp && !creatorClaimedP[index], "this pool is closed");
        _;
    }

    modifier isPoolExist(uint index) {
        require(index < pools.length, "this pool does not exist");
        _;
    }
}
