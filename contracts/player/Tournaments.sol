// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseFactory.sol";
import "../library/UtilLib.sol";

contract Tournaments is BaseFactory, ITournaments {
    using UtilLib for *;

    error AccountInTournament();
    error AccountInBlacklist();
    error TournamentActive();
    error TournamentNotActive();
    error TournamentOver();
    error TournamentNotOver();
    error NoEntrant();

    event ScoreChanged(address indexed account, uint256 indexed endTime, uint256 currentScore, uint256 totalScore);
    event TokenReward(address indexed to, uint256 amount);
    event NftReward(address indexed to, uint256 tokenId, uint256 amount);

    enum RewardTypes {
        fpt, // 0
        fish, // 1
        boat // 2
    }

    struct Config {
        bool isActive;
        uint8 durationDay;
        RewardTypes rewardType;
        uint64 endTime;
        uint256 prizePool;
    }

    struct EntrantData {
        bool blackList;
        uint32 score;
        uint64 endTime;
    }

    struct ContenderOwner {
        uint32 Score;
        address Account;
    }

    struct ContenderInfo {
        uint32 Score;
        address Account;
        string Nick;
    }

    struct NftData {
        uint256 tokenId;
        uint256 amount;
    }

    struct TokenData {
        uint8 rank;
        uint256 reward;
    }

    struct InfoData {
        bool playerCanEnter;
        uint32 totalContender;
        uint64 remainTime;
        EntrantData entrant;
        Config config;
    }

    uint64 private constant MIN_ENTER_TIME = 300; // 5 minute

    // all accounts in current tournament
    address[] private _accounts;

    //_entrant[account] = EntrantData
    mapping(address => EntrantData) private _entrant;

    // tournament settings
    Config private _config;

    // top20 NFTs to be distributed
    NftData[20] private _nftList;

    constructor(IContractFactory _factory) BaseFactory(_factory) {
        _config.durationDay = 7;
        _config.rewardType = RewardTypes.fpt;
        _config.prizePool = 3000 ether;
    }

    function emergencyReset() external onlyRole(MANAGER_ROLE) {
        delete _config;
        delete _accounts;
        delete _nftList;
    }

    function setConfig(Config memory input, NftData[20] calldata nfts) external onlyRole(MANAGER_ROLE) whenNotPaused {
        require(input.durationDay > 0 && input.durationDay < 31, "durationDay");

        if (input.rewardType != RewardTypes.fpt) {
            IBaseFungible sc;
            if (input.rewardType == RewardTypes.fish) {
                sc = factory.fishFactory();
            } else if (input.rewardType == RewardTypes.boat) {
                sc = factory.boatFactory();
            } else {
                revert NotExists();
            }
            for (uint i = 0; i < nfts.length; i++) {
                NftData memory item = nfts[i];
                if (item.tokenId == 0 || item.amount == 0) revert TokenIdRequire();
                if (!sc.exists(item.tokenId)) revert TokenNotExists(item.tokenId);
                _nftList[i] = item;
            }
        } else {
            require(input.prizePool > 100, "prizePool");
        }

        if (input.isActive) {
            _config.endTime = input.durationDay.createEndTime(1 days);
            _config.isActive = true;
        } else {
            _config.endTime = 0;
            _config.isActive = false;
        }

        if (_config.durationDay != input.durationDay) _config.durationDay = input.durationDay;
        if (_config.rewardType != input.rewardType) _config.rewardType = input.rewardType;
        if (_config.prizePool != input.prizePool) _config.prizePool = input.prizePool;

        // delete prev players
        if (_accounts.length > 0) {
            delete _accounts;
        }
    }

    function start() external onlyRole(MOD_ROLE) whenNotPaused nonReentrant {
        if (_config.endTime > block.timestamp) {
            revert TournamentNotOver();
        }
        if (_config.isActive) {
            revert TournamentActive();
        }

        _config.endTime = _config.durationDay.createEndTime(1 days);
        _config.isActive = true;

        // delete prev tournament players
        if (_accounts.length > 0) {
            delete _accounts;
        }
    }

    function sendRewards() external onlyRole(MOD_ROLE) whenNotPaused nonReentrant {
        if (_config.endTime > block.timestamp) {
            revert TournamentNotOver();
        }
        if (!_config.isActive) {
            revert TournamentNotActive();
        }

        ContenderOwner[] memory topList = _getTop20Contenders();
        uint256 topListLen = topList.length;
        if (topListLen < 1 || topListLen > 20) {
            revert NoEntrant();
        }

        _config.isActive = false;

        if (_config.rewardType == RewardTypes.fpt) {
            TokenData[20] memory top20Rewards = _top20TokenRewards();
            IBaseERC20 planetToken = factory.planetToken();
            for (uint i = 0; i < topListLen; ) {
                address account = topList[i].Account;
                planetToken.operatorMint(account, top20Rewards[i].reward);
                emit TokenReward(account, top20Rewards[i].reward);

                unchecked {
                    i++;
                }
            }
        } else {
            for (uint i = 0; i < topListLen; ) {
                address account = topList[i].Account;
                NftData storage item = _nftList[i];
                factory.nftFactory().operatorMint(account, item.tokenId, item.amount, "");
                emit NftReward(account, item.tokenId, item.amount);

                unchecked {
                    i++;
                }
            }
        }
    }

    function setBlackList(bool isBlackList, address[] calldata inputs) external onlyRole(MOD_ROLE) whenNotPaused {
        if (inputs.length == 0) revert ArrayEmpty();
        for (uint i = 0; i < inputs.length; i++) {
            address account = inputs[i];
            account.throwIfEmpty();
            _entrant[account].blackList = isBlackList;
        }
    }

    function _top20TokenRewards() private view returns (TokenData[20] memory list) {
        uint256 reward = _config.prizePool;
        uint8[20] memory _shares = [10, 9, 8, 7, 6, 5, 5, 5, 5, 5, 4, 4, 4, 4, 4, 3, 3, 3, 3, 3];
        for (uint8 i = 0; i < _shares.length; i++) {
            list[i] = TokenData({rank: i + 1, reward: (_shares[i] * reward) / 100});
        }
    }

    function _quickSort(ContenderOwner[] memory arr, int left, int right) private pure {
        int i = left;
        int j = right;
        if (i == j) return;
        uint pivot = arr[uint(left + (right - left) / 2)].Score;

        while (i <= j) {
            while (arr[uint(i)].Score > pivot) i++;
            while (arr[uint(j)].Score < pivot) j--;
            if (i <= j) {
                (arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
                i++;
                j--;
            }
        }

        if (left < j) _quickSort(arr, left, j);
        if (i < right) _quickSort(arr, i, right);
    }

    function _getTop20Contenders() private view returns (ContenderOwner[] memory result) {
        uint256 length = _accounts.length;
        if (length == 0) {
            return result;
        }
        uint256 validScores;
        uint64 configEndTime = _config.endTime;
        ContenderOwner[] memory buffer = new ContenderOwner[](length);

        for (uint i = 0; i < length; ) {
            address account = _accounts[i];
            EntrantData storage entrant = _entrant[account];
            if (configEndTime == entrant.endTime && entrant.score > 0 && !entrant.blackList) {
                buffer[i].Score = entrant.score;
                buffer[i].Account = account;
                validScores++;
            }

            unchecked {
                i++;
            }
        }

        _quickSort(buffer, int(0), int(buffer.length - 1));

        result = new ContenderOwner[](validScores > 20 ? 20 : validScores);
        for (uint i = 0; i < result.length; i++) {
            result[i] = buffer[i];
        }
    }

    function onScoreChanged(address from, uint32 score) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        uint64 endTime = _config.endTime;
        if (_config.isActive && endTime > block.timestamp) {
            EntrantData storage entrant = _entrant[from];
            if (entrant.endTime == endTime && !entrant.blackList) {
                uint32 totalScore = entrant.score + score;
                entrant.score = totalScore;
                emit ScoreChanged(from, endTime, score, totalScore);
            }
        }
    }

    function enter() external whenNotPaused nonReentrant {
        address from = msg.sender;
        factory.playerManager().checkReady(from);

        uint64 endTime = _config.endTime;
        if (!_config.isActive || endTime == 0) {
            revert TournamentNotActive();
        }

        if (endTime.remainTime() < MIN_ENTER_TIME) {
            revert TournamentOver();
        }

        uint len = _accounts.length;
        for (uint i = 0; i < len; ) {
            if (_accounts[i] == from) {
                revert AccountInTournament();
            }

            unchecked {
                i++;
            }
        }

        EntrantData storage entrant = _entrant[from];
        if (entrant.endTime == endTime) {
            revert AccountInTournament();
        }

        if (entrant.blackList) {
            revert AccountInBlacklist();
        }

        entrant.score = 0;
        entrant.endTime = endTime;
        _accounts.push(from);
    }

    function getFullInfo(address account) external view returns (InfoData memory result) {
        account.throwIfEmpty();
        result.config = _config;
        result.entrant = _entrant[account];
        result.remainTime = result.config.endTime.remainTime();
        result.totalContender = uint32(_accounts.length);
        result.playerCanEnter =
            result.entrant.blackList == false &&
            result.config.isActive &&
            result.remainTime > MIN_ENTER_TIME &&
            result.config.endTime != result.entrant.endTime;
    }

    function getNftRewards() external view returns (NftData[20] memory list) {
        return _nftList;
    }

    function getTokenRewards() external view returns (TokenData[20] memory list) {
        return _top20TokenRewards();
    }

    function getTopList() external view returns (ContenderInfo[] memory result) {
        ContenderOwner[] memory _arr = _getTop20Contenders();
        result = new ContenderInfo[](_arr.length);
        IPlayerManager playerManager = factory.playerManager();
        for (uint i = 0; i < _arr.length; i++) {
            result[i] = ContenderInfo({Nick: playerManager.getNick(_arr[i].Account), Account: _arr[i].Account, Score: _arr[i].Score});
        }
    }

    function getContenders(uint8 dataCount, uint256 startIndex) external view returns (ContenderInfo[] memory result, uint256 nextIndex) {
        uint256 len = _accounts.length;
        if (len == 0) {
            return (new ContenderInfo[](0), 0);
        }

        require(startIndex < len, "to big startIndex");
        uint256 index;
        uint256 maxCount = len - startIndex;
        if (maxCount < dataCount) {
            dataCount = uint8(maxCount);
        }

        IPlayerManager playerManager = factory.playerManager();
        result = new ContenderInfo[](dataCount);
        do {
            address account = _accounts[startIndex];
            uint32 score = _entrant[account].score;
            result[index] = ContenderInfo({Nick: playerManager.getNick(_accounts[startIndex]), Account: _accounts[startIndex], Score: score});
            index++;
            startIndex++;
        } while (startIndex < len && index < dataCount);

        nextIndex = startIndex;
        if (nextIndex >= len) {
            nextIndex = 0;
        }
    }
}
