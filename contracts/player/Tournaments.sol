// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseFactory.sol";
import "../library/UtilLib.sol";

contract Tournaments is BaseFactory, ITournaments {
    using UtilLib for *;

    error AccountInTournament();

    struct ContenderOwner {
        uint32 Score;
        address Account;
    }

    struct ContenderInfo {
        uint32 Score;
        address Account;
        string Nick;
    }

    struct TournamentConfig {
        bool isActive;
        uint8 durationDay;
        uint8 boatRarity;
        uint64 endTime;
    }

    struct TournamentInfo {
        bool isActive;
        bool isEnd;
        uint8 durationDay;
        uint8 boatRarity;
        uint32 totalContender;
        uint64 remainTime;
    }

    struct EntrantData {
        uint32 score;
        uint64 endTime;
    }

    TournamentConfig private config;

    address[] private _accounts;

    mapping(address => bool) private _blackList;

    mapping(address => EntrantData) private _entrant;

    constructor(IContractFactory _factory) BaseFactory(_factory) {
        _setConfig(true, 7, 1);
    }

    modifier checkBlackList() {
        require(!_blackList[msg.sender], "Account is blacklisted.");
        _;
    }

    function _setConfig(bool isActive, uint8 durationDay, uint8 boatRarity) private {
        require(durationDay > 0 && durationDay < 181, "durationDay range 1-180");
        boatRarity.throwIfRarityInvalid();
        // delete prev tournament players
        if (_accounts.length > 0) {
            delete _accounts;
        }
        config = TournamentConfig({isActive: isActive, durationDay: durationDay, boatRarity: boatRarity, endTime: durationDay.createEndTime(1 days)});
    }

    function setConfig(bool isActive, uint8 durationDay, uint8 boatRarity) external onlyRole(MANAGER_ROLE) {
        _setConfig(isActive, durationDay, boatRarity);
    }

    function setBlackList(bool isBlackList, address[] calldata inputs) external onlyRole(MANAGER_ROLE) {
        require(inputs.length > 0, "no address");
        for (uint i = 0; i < inputs.length; i++) {
            inputs[i].throwIfEmpty();
            _blackList[inputs[i]] = isBlackList;
        }
    }

    function onScoreChanged(address from, uint32 score, uint8 boatRarity) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        if (config.isActive && config.boatRarity == boatRarity && config.endTime > block.timestamp) {
            EntrantData storage entrant = _entrant[from];
            if (entrant.endTime == config.endTime && _blackList[from] == false) {
                entrant.score += score;
            }
        }
    }

    function _tournamentInfo() private view returns (TournamentInfo memory result) {
        uint64 remainTime = config.endTime.remainTime();
        result = TournamentInfo({
            isActive: config.isActive,
            isEnd: remainTime == 0,
            durationDay: config.durationDay,
            boatRarity: config.boatRarity,
            totalContender: uint32(_accounts.length),
            remainTime: remainTime
        });
    }

    function _sort() private view returns (ContenderOwner[] memory result) {
        uint256 len = _accounts.length;
        uint64 endTime = config.endTime;
        uint256 validScores;
        ContenderOwner[] memory buffer = new ContenderOwner[](len);
        unchecked {
            for (uint i = 0; i < len; i++) {
                EntrantData storage entrant = _entrant[_accounts[i]];
                if (entrant.endTime == endTime && entrant.score > 0) {
                    buffer[i].Score = entrant.score;
                    buffer[i].Account = _accounts[i];
                    validScores++;
                }
            }
        }

        bool isEnd;
        ContenderOwner memory low;
        ContenderOwner memory high;

        for (uint i = buffer.length; i > 0; i--) {
            isEnd = true;
            for (uint j = 0; j < (i - 1); j++) {
                if (buffer[j].Score < buffer[j + 1].Score) {
                    low = ContenderOwner({Score: buffer[j + 1].Score, Account: buffer[j + 1].Account});
                    high = ContenderOwner({Score: buffer[j].Score, Account: buffer[j].Account});
                    buffer[j + 1] = high;
                    buffer[j] = low;
                    isEnd = false;
                }
            }
            if (isEnd) {
                break;
            }
        }

        result = new ContenderOwner[](validScores > 20 ? 20 : validScores);
        for (uint i = 0; i < result.length; i++) {
            result[i] = buffer[i];
        }
    }

    function enter() external whenNotPaused nonReentrant checkBlackList {
        address from = msg.sender;
        factory.checkReady(from);

        require(config.isActive, "Tournament not active");
        require(config.endTime > block.timestamp, "Tournament over");

        for (uint i = 0; i < _accounts.length; i++) {
            if (_accounts[i] == from) {
                revert AccountInTournament();
            }
        }

        EntrantData storage entrant = _entrant[from];
        if (entrant.endTime == config.endTime) {
            revert AccountInTournament();
        }

        entrant.score = 0;
        entrant.endTime = config.endTime;
        _accounts.push(from);
    }

    function isInBlackList(address account) external view returns (bool result) {
        account.throwIfEmpty();
        result = _blackList[account];
    }

    function getTournamentInfo() external view returns (TournamentInfo memory result) {
        result = _tournamentInfo();
    }

    function getFullInfo(address from) external view returns (TournamentInfo memory tournamentInfo, uint32 playerScore, bool playerInCompetition, bool playerReady) {
        from.throwIfEmpty();
        tournamentInfo = _tournamentInfo();
        EntrantData storage entrant = _entrant[from];
        if (entrant.endTime == config.endTime) {
            playerScore = entrant.score;
            playerInCompetition = true;
        }
        playerReady = factory.playerManager().isReady(from);
    }

    function getTopListAddress() public view returns (address[] memory result) {
        ContenderOwner[] memory _arr = _sort();
        result = new address[](_arr.length);
        for (uint i = 0; i < _arr.length; i++) {
            result[i] = _arr[i].Account;
        }
    }

    function getTopList() external view returns (ContenderInfo[] memory result) {
        ContenderOwner[] memory _arr = _sort();
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
            result[index] = ContenderInfo({Nick: playerManager.getNick(_accounts[startIndex]), Account: _accounts[startIndex], Score: _entrant[_accounts[startIndex]].score});
            index++;
            startIndex++;
        } while (startIndex < len && index < dataCount);

        nextIndex = startIndex;
        if (nextIndex >= len) {
            nextIndex = 0;
        }
    }
}
