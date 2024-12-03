// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseFactory.sol";
import "../library/UtilLib.sol";

contract StakeManager is BaseFactory {
    using UtilLib for *;

    event Deposit(address indexed account, uint256 amount, TokenTypes tokenType);

    event Withdraw(address indexed account, uint256 amount, TokenTypes tokenType);

    struct StakerInfo {
        TokenTypes tokenType;
        uint8 minDurationDay;
        uint32 dailyPrizePool;
        uint64 remainTime;
        uint256 totalStaked;
        uint256 currentReward;
        uint256 perBlockReward;
        uint256 balance;
        uint256 poolSize;
    }

    struct StakerData {
        uint64 endTime; // Stake Expiry Time
        uint256 amount; // The total tokens user has staked
        uint256 unclaimed; // Accumulated rewards user can claim
        uint256 debt; // The amount relative to arps the user can't get as reward
    }

    struct PoolData {
        uint256 size; // Total tokens staked to pool
        uint256 last; // Last rewarded block number the user had their rewards calculated
        uint256 arps; // Accumulated rewards per share times MAGIC
        uint256 perBlockReward; // Daily base Token rewards per block
    }

    struct ConfigData {
        uint8 minDurationDay; // default 30 day
        uint32 dailyFPTMax; // for FPT to earn FPT
        uint32 dailyFPTMin; // for AFT to earn FPT
    }

    // big number to perform mul and div operations
    uint256 private constant MAGIC = 1e12;

    // _pools[tokenType] = pool
    mapping(TokenTypes => PoolData) private _pools;

    // _stakers[tokenType][account] = staker
    mapping(TokenTypes => mapping(address => StakerData)) private _stakers;

    // Contract settings
    ConfigData private _config;

    // ************ REMOVE WHEN LIVE !!! ************
    // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    constructor(IContractFactory _factory) BaseFactory(_factory) {
        _setConfig(ConfigData({minDurationDay: 14, dailyFPTMax: 2000, dailyFPTMin: 1000}));
    }

    // ************ REMOVE WHEN LIVE !!! ************
    // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    // this only for test players. 20k each

    // ************ REMOVE WHEN LIVE !!! FPT, AFT and STAKEMANAGER ************
    mapping(address => bool) private mintMap;

    function claimToken() external whenNotPaused {
        address to = msg.sender;
        to.throwIfEmpty();

        bool isMinted = mintMap[to];
        require(!isMinted, "Each address can mint once.");
        mintMap[to] = true;

        factory.planetToken().operatorMint(to, 20000 ether);
        factory.farmingToken().operatorMint(to, 20000 ether);
    }

    // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    // *********************************************

    function _setConfig(ConfigData memory input) private {
        require(input.dailyFPTMax > 0, "dailyFPTMax");
        require(input.dailyFPTMin > 0, "dailyFPTMin");
        require(input.minDurationDay > 0 && input.minDurationDay < 250, "minDurationDay");

        uint32 dailyBlock = factory.getDailyBlock();
        uint256 highReward = input.dailyFPTMax.toWei();
        uint256 lowReward = input.dailyFPTMin.toWei();
        require(dailyBlock > 0, "dailyBlock");

        _config = input;
        _pools[TokenTypes.Governance].perBlockReward = highReward / dailyBlock;
        _pools[TokenTypes.Utility].perBlockReward = lowReward / dailyBlock;
    }

    function setConfig(ConfigData calldata input) external onlyRole(MANAGER_ROLE) {
        _setConfig(input);
    }

    function getConfig() external view returns (ConfigData memory result) {
        result = _config;
    }

    function getPools() external view returns (PoolData[] memory result) {
        TokenTypes[2] memory tTypes = _gettokenTypes();
        result = new PoolData[](2);
        for (uint256 i = 0; i < tTypes.length; i++) {
            result[i] = _pools[tTypes[i]];
        }
    }

    function _gettokenTypes() private pure returns (TokenTypes[2] memory) {
        TokenTypes[2] memory array = [TokenTypes.Governance, TokenTypes.Utility];
        return array;
    }

    function _updatePoolRewards(PoolData storage pool, uint256 amount, bool isDown) private {
        if (pool.size > 0) {
            uint256 rewards = (block.number - pool.last) * pool.perBlockReward;
            pool.arps = pool.arps + ((rewards * MAGIC) / pool.size);
        }
        pool.last = block.number;
        if (isDown) {
            pool.size -= amount;
        } else {
            pool.size += amount;
        }
    }

    function _balance(TokenTypes tokenType, address from) private view returns (uint256 balance) {
        if (tokenType == TokenTypes.Governance) {
            balance = factory.planetToken().balanceOf(from);
        } else if (tokenType == TokenTypes.Utility) {
            balance = factory.farmingToken().balanceOf(from);
        }
    }

    function _calcRewards(PoolData storage pool, StakerData storage staker) private view returns (uint256 rewards) {
        uint256 accPerShare = pool.arps;
        uint256 last = pool.last;
        if (block.number > last) {
            uint256 tokenReward = ((block.number - last) * pool.perBlockReward);
            accPerShare = accPerShare + ((tokenReward * MAGIC) / pool.size);
        }
        rewards = (((staker.amount * accPerShare) / MAGIC) - staker.debt) + staker.unclaimed;
    }

    function deposit(TokenTypes tokenType, uint256 amount) external whenNotPaused nonReentrant {
        require(amount >= 1e18, "Min amount 1");

        address sender = msg.sender;
        IBaseERC20 planetToken = factory.planetToken();
        IBaseERC20 farmingToken = factory.farmingToken();

        // check balances
        if (tokenType == TokenTypes.Governance) {
            require(planetToken.balanceOf(sender) >= amount, "No balance");
        } else if (tokenType == TokenTypes.Utility) {
            require(farmingToken.balanceOf(sender) >= amount, "No balance");
        } else {
            revert("U:TokenType");
        }

        StakerData storage staker = _stakers[tokenType][sender];
        PoolData storage pool = _pools[tokenType];

        // update pool
        _updatePoolRewards(pool, amount, false);

        // deposit
        staker.unclaimed += ((staker.amount * pool.arps) / MAGIC) - staker.debt;
        staker.amount += amount;
        staker.debt = (staker.amount * pool.arps) / MAGIC;

        // check first time deposit
        if (staker.endTime == 0) {
            staker.endTime = _config.minDurationDay.createEndTime(1 days);
        }

        // burn staker tokens
        if (tokenType == TokenTypes.Governance) {
            planetToken.operatorBurn(sender, amount);
        } else if (tokenType == TokenTypes.Utility) {
            farmingToken.operatorBurn(sender, amount);
        }

        // send event
        emit Deposit(sender, amount, tokenType);
    }

    function withdraw(TokenTypes tokenType) external whenNotPaused nonReentrant {
        require(tokenType == TokenTypes.Governance || tokenType == TokenTypes.Utility, "U:TokenType");
        address sender = msg.sender;
        StakerData storage staker = _stakers[tokenType][sender];

        uint256 amount = staker.amount;
        require(amount > 0, "No Staked token");
        require(block.timestamp > staker.endTime, "Staking not expired");

        PoolData storage pool = _pools[tokenType];

        // update pool
        _updatePoolRewards(pool, amount, true);

        // calc all rewards
        uint256 reward = (((staker.amount * pool.arps) / MAGIC) - staker.debt) + staker.unclaimed;
        require(reward > 0, "No rewards");

        staker.amount = 0;
        staker.unclaimed = 0;
        staker.endTime = 0;
        staker.debt = 0;

        // mint tokens to staker
        if (tokenType == TokenTypes.Governance) {
            factory.planetToken().operatorMint(sender, reward + amount);
        } else if (tokenType == TokenTypes.Utility) {
            factory.farmingToken().operatorMint(sender, amount);
            factory.planetToken().operatorMint(sender, reward);
        }

        // send event
        emit Withdraw(sender, amount, tokenType);
    }

    function getInfo(address from) external view returns (StakerInfo[] memory result) {
        from.throwIfEmpty();

        TokenTypes[2] memory tTypes = _gettokenTypes();
        result = new StakerInfo[](2);

        for (uint256 i = 0; i < tTypes.length; i++) {
            StakerData storage staker = _stakers[tTypes[i]][from];
            PoolData storage pool = _pools[tTypes[i]];

            if (staker.amount == 0) {
                result[i].dailyPrizePool = tTypes[i] == TokenTypes.Governance ? _config.dailyFPTMax : _config.dailyFPTMin;
                result[i].poolSize = pool.size;
                result[i].balance = _balance(tTypes[i], from);
                result[i].tokenType = tTypes[i];
                result[i].minDurationDay = _config.minDurationDay;
                continue;
            }

            uint256 perBlockReward = ((staker.amount / (pool.size / MAGIC)) * pool.perBlockReward) / MAGIC;

            result[i] = StakerInfo({
                tokenType: tTypes[i],
                minDurationDay: _config.minDurationDay,
                dailyPrizePool: tTypes[i] == TokenTypes.Governance ? _config.dailyFPTMax : _config.dailyFPTMin,
                remainTime: staker.endTime.remainTime(),
                totalStaked: staker.amount,
                currentReward: _calcRewards(pool, staker),
                perBlockReward: perBlockReward,
                balance: _balance(tTypes[i], from),
                poolSize: pool.size
            });
        }
    }

    function calculateEarn(TokenTypes tokenType, uint64 stakeAmount) external view returns (uint256 perBlockReward, uint256 dailyEarn) {
        require(stakeAmount > 0, "stakeAmount");
        require(tokenType == TokenTypes.Governance || tokenType == TokenTypes.Utility, "U:TokenType");
        uint256 amount = stakeAmount.toWei();
        uint256 dailyBlock = factory.getDailyBlock();
        PoolData storage pool = _pools[tokenType];
        if (pool.size == 0) {
            return (pool.perBlockReward, pool.perBlockReward * dailyBlock);
        }
        uint256 size = pool.size + amount;
        size = amount / (size / MAGIC);
        perBlockReward = (size * pool.perBlockReward) / MAGIC;
        dailyEarn = perBlockReward * dailyBlock;
    }
}
