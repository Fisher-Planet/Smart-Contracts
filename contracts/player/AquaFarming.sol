// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseFactory.sol";
import "../library/UtilLib.sol";

contract AquaFarming is BaseFactory, IAquaFarming {
    using UtilLib for *;

    event Deposit(address indexed account, uint256 id, uint256 amount);
    event DepositAll(address indexed account, uint256[] ids, uint256[] amounts);
    event Withdraw(address indexed account, uint256 id, uint256 amount);
    event Claim(address indexed account, uint256 amount);

    struct AquaPoolData {
        uint256 size; // Total tokens staked to pool
        uint256 last; // Last rewarded block number the user had their rewards calculated
        uint256 arps; // Accumulated rewards per share times MAGIC
    }

    struct AquaStakerData {
        uint256 amount; // The total tokens user has staked
        uint256 unclaimed; // Accumulated rewards user can claim
        uint256 debt; // The amount relative to arps the user can't get as reward
    }

    struct AquaRewardInfo {
        uint256 totalProduction;
        uint256 currentReward;
        uint256 perBlockReward;
        uint256 totalFish;
        uint256 poolSize;
        uint256 dailyPrizePool;
    }

    // big number to perform mul and div operations
    uint256 private constant MAGIC = 1e12;

    // daily prize
    uint32 private _dailyPrizePool;

    // per block reward tokens
    uint256 private _perBlockReward;

    // staking pools
    AquaPoolData private _pool;

    // _stakers[account] = staker
    mapping(address => AquaStakerData) private _stakers;

    // fish balance [tokenId][account]
    mapping(uint32 => mapping(address => uint64)) private _balances;

    constructor(IContractFactory _factory) BaseFactory(_factory) {
        _setBlockReward(5000);
    }

    function _setBlockReward(uint32 dailyPrizePool) private {
        require(dailyPrizePool > 0, "dailyPrizePool");
        uint32 dailyBlock = factory.getDailyBlock();
        require(dailyBlock > 0, "dailyBlock");
        uint256 perBlockReward = dailyPrizePool.toWei();
        _dailyPrizePool = dailyPrizePool;
        _perBlockReward = perBlockReward / dailyBlock;
    }

    function setBlockReward(uint32 dailyPrizePool) external onlyRole(MANAGER_ROLE) {
        _setBlockReward(dailyPrizePool);
    }

    function getBlockReward() external view returns (uint32 dailyPrizePool, uint256 perBlockReward) {
        dailyPrizePool = _dailyPrizePool;
        perBlockReward = _perBlockReward;
    }

    function _updatePoolRewards(AquaStakerData storage staker, uint256 amount, uint8 action) private returns (uint256 pendingRewards) {
        // update _pool
        if (_pool.size > 0) {
            uint256 rewards = (block.number - _pool.last) * _perBlockReward;
            _pool.arps = _pool.arps + ((rewards * MAGIC) / _pool.size);
        }
        _pool.last = block.number;

        // staker reward actions
        if (staker.amount > 0) {
            pendingRewards = ((staker.amount * _pool.arps) / MAGIC) - staker.debt;
        }

        if (action == 1) {
            // deposit
            staker.amount += amount;
            staker.unclaimed += pendingRewards;
            _pool.size += amount;
        } else if (action == 2) {
            // withdraw
            staker.amount -= amount;
            staker.unclaimed += pendingRewards;
            _pool.size -= amount;
        } else if (action == 3) {
            // claim
            pendingRewards += staker.unclaimed;
            staker.unclaimed = 0;
        }

        // update staker debt
        staker.debt = (staker.amount * _pool.arps) / MAGIC;
    }

    function _deposit(uint32 id, uint64 amount, address from, uint256 totalProduction) private {
        require(totalProduction > 0, "totalProduction");
        AquaStakerData storage staker = _stakers[from];

        // Update pool
        _updatePoolRewards(staker, totalProduction, 1);

        // balances
        _balances[id][from] += amount;
    }

    function _tp(uint8 production, uint64 amount) private pure returns (uint256 tp) {
        if (production == 0) {
            revert InvalidValue(production);
        }
        tp = production.toWei() * amount;
    }

    function deposit(uint32 id, uint64 amount) external whenNotPaused nonReentrant {
        address sender = msg.sender;
        id.throwIfZero();
        amount.throwIfZero();
        IFishFactory fishFactory = factory.fishFactory();
        uint256 _balance = fishFactory.balanceOf(sender, id);
        if (_balance < amount) {
            revert InsufficientBalance();
        }

        _deposit(id, amount, sender, _tp(fishFactory.getProduction(id), amount));

        fishFactory.deposit(sender, id, amount);

        emit Deposit(sender, id, amount);
    }

    function depositAll() external whenNotPaused nonReentrant {
        address sender = msg.sender;
        IFishFactory fishFactory = factory.fishFactory();
        (uint256[] memory ids, uint256[] memory amounts) = fishFactory.getBalances(sender);
        if (ids.length == 0) {
            revert InsufficientBalance();
        }
        uint32 id;
        uint64 amount;
        for (uint256 i = 0; i < ids.length; i++) {
            id = uint32(ids[i]);
            amount = uint64(amounts[i]);
            _deposit(id, amount, sender, _tp(fishFactory.getProduction(id), amount));
        }

        fishFactory.depositBatch(sender, ids, amounts);

        emit DepositAll(sender, ids, amounts);
    }

    function withdraw(uint32 id, uint64 amount) external whenNotPaused nonReentrant {
        address sender = msg.sender;
        id.throwIfZero();
        amount.throwIfZero();

        AquaStakerData storage staker = _stakers[sender];
        if (staker.amount == 0) {
            revert NotExists();
        }

        if (_balances[id][sender] < amount) {
            revert InsufficientBalance();
        }

        IFishFactory fishFactory = factory.fishFactory();

        // Update pool
        _updatePoolRewards(staker, _tp(fishFactory.getProduction(id), amount), 2);

        // balances
        _balances[id][sender] -= amount;

        // Withdraw nft
        fishFactory.withdraw(sender, id, amount);

        emit Withdraw(sender, id, amount);
    }

    function claimRewards() external whenNotPaused nonReentrant {
        address sender = msg.sender;
        AquaStakerData storage staker = _stakers[sender];
        uint256 rewards;
        if (staker.amount > 0) {
            rewards = _updatePoolRewards(staker, 0, 3);
        } else {
            rewards = staker.unclaimed;
            staker.unclaimed = 0;
        }

        require(rewards > 0, "No rewards");
        factory.farmingToken().operatorMint(sender, rewards);

        emit Claim(sender, rewards);
    }

    /* FOR DAPP */
    // ------------------------------------
    function balanceOf(address account, uint32 id) public view returns (uint64) {
        account.throwIfEmpty();
        return _balances[id][account];
    }

    function getStakerData(address from) external view returns (AquaStakerData memory) {
        from.throwIfEmpty();
        return _stakers[from];
    }

    function getPool() external view returns (AquaPoolData memory) {
        return _pool;
    }

    function _calcRewards(AquaStakerData storage staker) private view returns (uint256 rewards, uint256 perBlockReward) {
        if (_pool.size == 0) {
            return (staker.unclaimed, 0);
        }
        uint256 accPerShare = _pool.arps;
        uint256 last = _pool.last;
        if (block.number > last) {
            uint256 tokenReward = ((block.number - last) * _perBlockReward);
            accPerShare = accPerShare + ((tokenReward * MAGIC) / _pool.size);
        }
        rewards = (((staker.amount * accPerShare) / MAGIC) - staker.debt) + staker.unclaimed;
        perBlockReward = ((staker.amount / (_pool.size / MAGIC)) * _perBlockReward) / MAGIC;
    }

    function getRewardInfo(address from) external view returns (AquaRewardInfo memory result) {
        from.throwIfEmpty();
        AquaStakerData storage staker = _stakers[from];
        uint256 rewards;
        uint256 perBlockReward;
        if (staker.amount > 0) {
            uint256 fishCount;
            uint256[] memory ids = factory.fishFactory().tokenIds();
            for (uint i = 0; i < ids.length; i++) {
                fishCount += _balances[uint32(ids[i])][from];
            }

            (rewards, perBlockReward) = _calcRewards(staker);
            result.totalProduction = staker.amount;
            result.currentReward = rewards;
            result.perBlockReward = perBlockReward;
            result.totalFish = fishCount;
            result.poolSize = _pool.size;
            result.dailyPrizePool = _dailyPrizePool;
        } else {
            result.currentReward = staker.unclaimed;
            result.poolSize = _pool.size;
            result.dailyPrizePool = _dailyPrizePool;
        }
    }

    function getAmounts(address from) external view returns (Amounts[] memory result) {
        uint256[] memory ids = factory.fishFactory().tokenIds();
        Amounts[] memory temp = new Amounts[](ids.length);
        uint32 index;
        uint32 id;
        uint64 amount;
        for (uint32 i = 0; i < ids.length; i++) {
            id = uint32(ids[i]);
            amount = _balances[id][from];
            if (amount > 0) {
                temp[index] = Amounts({Id: id, Balance: amount});
                index++;
            }
        }
        result = new Amounts[](index);
        for (uint32 i = 0; i < index; i++) {
            result[i] = temp[i];
        }
    }

    function calculateEarn(uint64 productionAmount) external view returns (uint256 perBlockReward, uint256 dailyEarn) {
        require(productionAmount > 0, "productionAmount");
        uint256 amount = productionAmount.toWei();
        uint256 dailyBlock = factory.getDailyBlock();
        if (_pool.size == 0) {
            return (_perBlockReward, _perBlockReward * dailyBlock);
        }
        uint256 size = _pool.size + amount;
        size = amount / (size / MAGIC);
        perBlockReward = (size * _perBlockReward) / MAGIC;
        dailyEarn = perBlockReward * dailyBlock;
    }
}
