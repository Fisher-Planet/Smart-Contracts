// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseFactory.sol";
import "../library/UtilLib.sol";

contract StakeManager is BaseFactory {
    using UtilLib for *;

    error Inactive();
    error MinAmountMustBe(uint256);
    error StakingPeriodNotYetOver();

    event Deposit(address indexed account, uint256 amount, TokenTypes tokenType);
    event Withdraw(address indexed account, uint256 amount, uint256 rewards, TokenTypes tokenType);

    struct StakerInfo {
        TokenTypes tokenType;
        uint8 minDurationDay;
        uint64 remainTime;
        uint256 dailyPrizePool;
        uint256 totalStaked;
        uint256 estimatedReward;
        uint256 perSecondReward;
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
        uint256 last; // Last rewarded block timestamp user had their rewards calculated
        uint256 arps; // Accumulated rewards per share times MAGIC
        uint256 perSecondReward; // Daily base Token rewards per second
    }

    struct ConfigData {
        bool isActive; // stake deposit status
        uint8 minDurationDay; // default 30 day
        uint256 dailyFPTMax; // for FPT to earn FPT
        uint256 dailyFPTMin; // for AFT to earn FPT
    }

    // big number to perform mul and div operations
    uint256 private constant MAGIC = 1e12;

    // total seconds in day
    uint256 private constant DAILY_SECONDS = 86400;

    // _pools[tokenType] = pool
    mapping(TokenTypes => PoolData) private _pools;

    // _stakers[tokenType][account] = staker
    mapping(TokenTypes => mapping(address => StakerData)) private _stakers;

    // Contract settings
    ConfigData private _config;

    constructor(IContractFactory _factory) BaseFactory(_factory) {
        _setConfig(ConfigData({isActive: true, minDurationDay: 2, dailyFPTMax: 2000 ether, dailyFPTMin: 1000 ether}));
    }

    function _setConfig(ConfigData memory input) private {
        require(input.dailyFPTMax >= DAILY_SECONDS, "dailyFPTMax");
        require(input.dailyFPTMin >= DAILY_SECONDS, "dailyFPTMin");
        require(input.minDurationDay > 0 && input.minDurationDay < 250, "minDurationDay");

        _config = input;
        _pools[TokenTypes.Governance].perSecondReward = input.dailyFPTMax / DAILY_SECONDS;
        _pools[TokenTypes.Utility].perSecondReward = input.dailyFPTMin / DAILY_SECONDS;
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
        uint256 timestamp = block.timestamp;
        if (pool.size > 0) {
            uint256 rewards = (timestamp - pool.last) * pool.perSecondReward;
            pool.arps = pool.arps + ((rewards * MAGIC) / pool.size);
        }
        pool.last = timestamp;
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
        uint256 timestamp = block.timestamp;
        if (timestamp > last) {
            uint256 tokenReward = ((timestamp - last) * pool.perSecondReward);
            accPerShare = accPerShare + ((tokenReward * MAGIC) / pool.size);
        }
        rewards = (((staker.amount * accPerShare) / MAGIC) - staker.debt) + staker.unclaimed;
    }

    function deposit(TokenTypes tokenType, uint256 amount) external whenNotPaused nonReentrant {
        if (_config.isActive == false) revert Inactive();
        if (amount < 1e18) revert MinAmountMustBe(1);

        address sender = msg.sender;
        IBaseERC20 planetToken = factory.planetToken();
        IBaseERC20 farmingToken = factory.farmingToken();

        // check balances
        if (tokenType == TokenTypes.Governance) {
            if (amount > planetToken.balanceOf(sender)) {
                revert InsufficientBalance();
            }
            planetToken.operatorTransfer(sender, address(this), amount);
        } else if (tokenType == TokenTypes.Utility) {
            if (amount > farmingToken.balanceOf(sender)) {
                revert InsufficientBalance();
            }
            farmingToken.operatorTransfer(sender, address(this), amount);
        } else {
            revert NotExists();
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

        // send event
        emit Deposit(sender, amount, tokenType);
    }

    function withdraw(TokenTypes tokenType) external whenNotPaused nonReentrant {
        if (tokenType != TokenTypes.Governance && tokenType != TokenTypes.Utility) revert NotExists();

        address sender = msg.sender;
        StakerData storage staker = _stakers[tokenType][sender];
        uint256 amount = staker.amount;

        if (amount == 0) revert InsufficientBalance();
        if (block.timestamp < staker.endTime) revert StakingPeriodNotYetOver();

        PoolData storage pool = _pools[tokenType];

        // update pool
        _updatePoolRewards(pool, amount, true);

        // calc all rewards
        uint256 reward = (((staker.amount * pool.arps) / MAGIC) - staker.debt) + staker.unclaimed;

        staker.amount = 0;
        staker.unclaimed = 0;
        staker.endTime = 0;
        staker.debt = 0;

        IBaseERC20 planetToken = factory.planetToken();
        if (tokenType == TokenTypes.Governance) {
            planetToken.operatorTransfer(address(this), sender, amount);
        } else if (tokenType == TokenTypes.Utility) {
            factory.farmingToken().operatorTransfer(address(this), sender, amount);
        }

        if (reward > 0) {
            planetToken.operatorMint(sender, reward);
        }

        // send event
        emit Withdraw(sender, amount, reward, tokenType);
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

            uint256 perSecondReward = ((staker.amount / (pool.size / MAGIC)) * pool.perSecondReward) / MAGIC;

            result[i] = StakerInfo({
                tokenType: tTypes[i],
                minDurationDay: _config.minDurationDay,
                remainTime: staker.endTime.remainTime(),
                dailyPrizePool: tTypes[i] == TokenTypes.Governance ? _config.dailyFPTMax : _config.dailyFPTMin,
                totalStaked: staker.amount,
                estimatedReward: _calcRewards(pool, staker),
                perSecondReward: perSecondReward,
                balance: _balance(tTypes[i], from),
                poolSize: pool.size
            });
        }
    }

    function calculateEarn(TokenTypes tokenType, uint64 stakeAmount) external view returns (uint256 perSecondReward, uint256 dailyEarn) {
        require(stakeAmount > 0, "stakeAmount");
        require(tokenType == TokenTypes.Governance || tokenType == TokenTypes.Utility, "U:TokenType");
        uint256 amount = stakeAmount.toWei();

        PoolData storage pool = _pools[tokenType];
        if (pool.size == 0) {
            return (pool.perSecondReward, pool.perSecondReward * DAILY_SECONDS);
        }
        uint256 size = pool.size + amount;
        size = amount / (size / MAGIC);
        perSecondReward = (size * pool.perSecondReward) / MAGIC;
        dailyEarn = perSecondReward * DAILY_SECONDS;
    }
}
