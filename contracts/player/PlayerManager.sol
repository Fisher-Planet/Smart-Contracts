// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseFactory.sol";
import "../library/UtilLib.sol";

contract PlayerManager is BaseFactory, IPlayerManager {
    using UtilLib for *;

    bytes32 private constant _CHARS = "123456789ABCDEFGHKLMNPQRSTUVWXYZ";
    bytes16 private constant _DEF_NICK = "Guest";
    bytes16 private immutable _DEF_NICK_KEY;

    event RefReward(address indexed buyer, address indexed collector, uint256 amount);
    event ClaimRefRewards(address indexed account, uint256 amount);

    struct PlayerData {
        bool Ready;
        bytes16 Nick;
        uint64 LoyalScore;
    }

    struct PlayerInfo {
        bool Ready;
        uint8 BlockPeriod;
        uint8 AuthStatus; // 0:none, 1:only FPT, 2:only AFT, 3:full auth
        uint16 NftMarketFee;
        uint32 DailyBlock;
        string Nick;
        uint64 LoyalScore;
        uint256 PrimaryBalance;
        uint256 SecondaryBalance;
        uint256 NativeBalance;
    }

    struct ReferrerInfo {
        bool isCollected;
        address collector;
    }

    struct CollectorInfo {
        bool isCodeExists;
        bytes16 refCode;
        uint256 balance;
        uint256 totalRef;
        uint256 totalBuyer;
    }

    // referance reward percent 0-30 range
    uint8 private _referencePercent = 10;

    // refcollector map
    mapping(address => CollectorInfo) private _collector;

    // directed map
    mapping(address => ReferrerInfo) private _refMap;

    // ref code map
    mapping(bytes16 => address) private _refCodeOwner;

    // for unique nick
    mapping(bytes16 => address) private _nickKeyMap;

    // player info
    mapping(address => PlayerData) private _account;

    constructor(IContractFactory _factory) BaseFactory(_factory) {
        bytes memory nickData = abi.encodePacked(_DEF_NICK);
        _DEF_NICK_KEY = bytes16(nickData.toLowerCase());
    }

    // **** REFERRER SYSTEM *****
    //--------------------

    function setRefPercent(uint8 refPercent) external onlyRole(MANAGER_ROLE) {
        require(refPercent < 31, "out range");
        _referencePercent = refPercent;
    }

    function getRefPercent() external view returns (uint8) {
        return _referencePercent;
    }

    function _refCodeGen(address sender) private view returns (bytes16 result) {
        uint256 maxCounter;
        address zero = address(0);
        bytes memory buffer = new bytes(16);
        bytes16 value;
        do {
            value = bytes16(keccak256(abi.encodePacked(block.timestamp, maxCounter, sender, blockhash(block.number - 1))));
            for (uint8 i = 0; i < 16; i++) {
                buffer[i] = _CHARS[uint8(value[i]) & 0x1f];
            }
            result = bytes16(buffer);
            maxCounter++;
        } while (_refCodeOwner[result] != zero && maxCounter < 10000);
        require(maxCounter < 10000, "Could not generate ref code.");
    }

    function getReferrerInfo(address from) external view returns (ReferrerInfo memory result) {
        from.throwIfEmpty();
        result = _refMap[from];
    }

    function getCollectorInfo(address from) external view returns (CollectorInfo memory result, uint8 refPercent, bool refApplied) {
        from.throwIfEmpty();
        result = _collector[from];
        refPercent = _referencePercent;
        refApplied = _refMap[from].collector != address(0);
    }

    function createRefCode() external whenNotPaused nonReentrant {
        address sender = msg.sender;
        sender.throwIfEmpty();

        CollectorInfo storage collector = _collector[sender];
        require(!collector.isCodeExists, "Ref code exists");

        bytes16 refCode = _refCodeGen(sender);
        _refCodeOwner[refCode] = sender;
        collector.refCode = refCode;
        collector.isCodeExists = true;
    }

    function addReference(bytes16 refCode) external whenNotPaused nonReentrant {
        address referrer = _refCodeOwner[refCode];
        address sender = msg.sender;

        require(referrer != address(0), "Ref Code owner not exists or invalid");
        require(referrer != sender, "Sender cannot be a Ref Code owner");
        CollectorInfo storage collector = _collector[referrer];
        require(collector.isCodeExists && collector.refCode == refCode, "Collector not found");

        ReferrerInfo storage refOwner = _refMap[sender];
        require(refOwner.collector == address(0), "Reference exists");
        refOwner.collector = referrer;
        collector.totalRef++;
    }

    function onRefExists(address sender, uint256 price) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        require(price > 0, "Ref:price");
        ReferrerInfo storage refOwner = _refMap[sender];
        if (!refOwner.isCollected && refOwner.collector != address(0) && _referencePercent > 0) {
            CollectorInfo storage collector = _collector[refOwner.collector];
            uint256 share = (price * _referencePercent) / 100;
            uint256 cb = collector.balance;
            refOwner.isCollected = true;
            collector.balance = cb + share;
            collector.totalBuyer++;

            emit RefReward(sender, refOwner.collector, share);
        }
    }

    function claimRefRewards() external whenNotPaused nonReentrant {
        address to = msg.sender;
        uint256 _amount = _collector[to].balance;
        require(_amount > 0, "No referral reward");
        _collector[to].balance = 0;
        factory.planetToken().operatorMint(to, _amount);
        emit ClaimRefRewards(to, _amount);
    }

    // **** OTHERS *****
    //--------------------

    function _getNick(PlayerData storage player) private view returns (string memory) {
        if (player.Ready) {
            return string(abi.encodePacked(player.Nick));
        } else {
            return string(abi.encodePacked(_DEF_NICK));
        }
    }

    function registerNick(bytes16 input) external whenNotPaused nonReentrant {
        address sender = msg.sender;
        sender.throwIfEmpty();
        PlayerData storage player = _account[sender];

        if (player.Ready) {
            bytes memory oldNickData = abi.encodePacked(player.Nick);
            bytes16 oldNickKey = bytes16(oldNickData.toLowerCase());
            delete _nickKeyMap[oldNickKey];
        }

        (bytes16 key, bytes16 value) = input.validateBytes(true);
        address nickOwner = _nickKeyMap[key];
        require(nickOwner == address(0) || nickOwner == sender, "Nick already exists choose another");

        require(_DEF_NICK_KEY != key, "Default nick not available");

        _nickKeyMap[key] = sender;
        player.Nick = value;

        if (!player.Ready) {
            player.Ready = true;
        }
    }

    /**
     * @dev Rewarding those who are loyal to the game. Everyone who reaches 128 score will mint a special ancient fish nft.
     *
     * Fishing Boat NFT refuell : +1 point is gained for each refueling of boats. So, to reach 128 points, 16 boats must be refuelled 8 times.
     */
    function onLoyalScoreUp(address account, uint64 score) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        if (score > 0) {
            _account[account].LoyalScore += score;
        }
    }

    function onLoyalScoreReset(address account) public onlyRole(OPERATOR_ROLE) whenNotPaused returns (bool) {
        PlayerData storage player = _account[account];
        uint64 current = player.LoyalScore;
        if (current >= 128) {
            player.LoyalScore = current - 128;
            return true;
        }
        return false;
    }

    function isReady(address account) public view returns (bool) {
        return _account[account].Ready;
    }

    function getNick(address account) public view returns (string memory) {
        return _getNick(_account[account]);
    }

    function checkReady(address account) public view {
        require(account != address(0), "0x");
        if (_account[account].Ready == false) {
            revert("Nickname required, check game settings");
        }
    }

    function getInfo(address account) external view returns (PlayerInfo memory result) {
        account.throwIfEmpty();

        IBaseERC20 planetToken = factory.planetToken();
        IBaseERC20 farmingToken = factory.farmingToken();
        uint8 authStatus = 0;
        if (planetToken.getAuth(account) == true) {
            authStatus = 1;
        }
        if (farmingToken.getAuth(account) == true) {
            if (authStatus == 1) {
                authStatus = 3;
            } else {
                authStatus = 2;
            }
        }

        PlayerData storage player = _account[account];
        result = PlayerInfo({
            Ready: player.Ready,
            BlockPeriod: factory.getBlockPeriod(),
            AuthStatus: authStatus,
            NftMarketFee: factory.nftMarket().getFee(),
            LoyalScore: player.LoyalScore,
            DailyBlock: factory.getDailyBlock(),
            PrimaryBalance: planetToken.balanceOf(account),
            SecondaryBalance: farmingToken.balanceOf(account),
            NativeBalance: account.balance,
            Nick: _getNick(player)
        });
    }
}
