// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseFactory.sol";
import "../library/UtilLib.sol";
import "../library/ArrayLib.sol";

contract DockManager is BaseFactory, IDockManager {
    using UtilLib for *;
    using ArrayLib for uint256[];

    event Deposit(address indexed account, uint256 tokenId, uint256 amount);
    event Withdraw(address indexed account, uint256 tokenId, uint256 amount);
    event WithdrawAll(address indexed account, uint256[] ids, uint256[] amounts);
    event RefuelAll(address indexed account, uint256 totalCost);
    event SpeedUpAll(address indexed account, uint256 totalCost);

    struct BoatData {
        uint8 IsWorking;
        uint8 EngineType;
        uint8 Fuel;
        uint32 TokenId;
        uint64 EndTime;
    }

    struct PriceData {
        uint32 TokenId;
        uint256 Refuell; // for refuell boat
        uint256 PerSecond; // for speed up boat
    }

    struct SpeedContainer {
        uint64 remainSeconds;
        uint256 refuellPrice;
        uint256 speedPrice;
    }

    struct BoatInfo {
        bool IsWorking;
        uint8 EngineType;
        uint8 Fuel;
        uint32 TokenId;
        uint64 EndTime;
        uint256 BoatId; // boat index
        uint256 RefuelPrice;
        uint256 SpeedUpPrice;
    }

    struct StatusInfo {
        uint8 totalIdle;
        uint8 totalBusyOrCollect;
        uint8 totalRefuell;
        uint8 totalBoat;
    }

    // BoatData struct offsets
    uint8 private constant BOAT_IS_WORKING_OFFSET = 0;
    uint8 private constant BOAT_ENGINE_TYPE_OFFSET = 8;
    uint8 private constant BOAT_FUEL_OFFSET = 16;
    uint8 private constant BOAT_TOKEN_ID_OFFSET = 24;
    uint8 private constant BOAT_END_TIME_OFFSET = 56;

    // max boat per account
    uint8 private constant _MAX_BOAT_COUNT = 16;

    // _price[tokenId] = target costs
    mapping(uint32 => PriceData) private _prices;

    mapping(address => uint256[]) private _boatData;

    constructor(IContractFactory _factory) BaseFactory(_factory) {}

    function updatePrices(PriceData[] calldata inputs, uint256 percent) external onlyRole(MANAGER_ROLE) {
        require(percent > 0 && percent < 81, "sp");
        IBoatFactory boatFactory = factory.boatFactory();
        for (uint i = 0; i < inputs.length; i++) {
            PriceData memory input = inputs[i];
            if (input.TokenId == 0) {
                revert TokenNotExists(0);
            }

            require(input.Refuell > 0.000000001 ether, "rf");

            BoatMetaData memory meta = boatFactory.get(input.TokenId);

            uint256 perSecondPrice;
            if (meta.EngineType != uint8(EngineTypes.Ufo)) {
                require(meta.WaitTime > 0, "wt");
                perSecondPrice = ((input.Refuell * percent) / 100) / (meta.WaitTime * 3600);
                require(perSecondPrice > 0, "ps");
            }

            PriceData storage price = _prices[input.TokenId];
            price.Refuell = input.Refuell;

            if (perSecondPrice > 0) {
                price.PerSecond = perSecondPrice;
            }

            if (price.TokenId == 0) {
                price.TokenId = input.TokenId;
            }
        }
    }

    function _packData(BoatData memory data) private pure returns (uint256) {
        return
            (uint256(data.IsWorking) << BOAT_IS_WORKING_OFFSET) |
            (uint256(data.EngineType) << BOAT_ENGINE_TYPE_OFFSET) |
            (uint256(data.Fuel) << BOAT_FUEL_OFFSET) |
            (uint256(data.TokenId) << BOAT_TOKEN_ID_OFFSET) |
            (uint256(data.EndTime) << BOAT_END_TIME_OFFSET);
    }

    function _unpackData(uint256 data) private pure returns (BoatData memory) {
        return
            BoatData(
                uint8((data >> BOAT_IS_WORKING_OFFSET) & type(uint8).max),
                uint8((data >> BOAT_ENGINE_TYPE_OFFSET) & type(uint8).max),
                uint8((data >> BOAT_FUEL_OFFSET) & type(uint8).max),
                uint32((data >> BOAT_TOKEN_ID_OFFSET) & type(uint32).max),
                uint64((data >> BOAT_END_TIME_OFFSET) & type(uint64).max)
            );
    }

    function _getTokenId(uint256 data) private pure returns (uint32 tokenId) {
        tokenId = uint32((data >> BOAT_TOKEN_ID_OFFSET) & type(uint32).max);
        if (tokenId == 0) {
            revert TokenNotExists(tokenId);
        }
    }

    function _calcSUP(BoatData memory boat) private view returns (SpeedContainer memory result) {
        PriceData storage prices = _prices[boat.TokenId];
        result.remainSeconds = boat.EndTime.remainTime();
        result.refuellPrice = prices.Refuell;

        if (boat.IsWorking == 1 && boat.EngineType == uint8(EngineTypes.Generic) && result.remainSeconds > 60) {
            result.speedPrice = prices.PerSecond * result.remainSeconds;
            if (result.speedPrice == 0) {
                revert PriceEmpty();
            }
        }
    }

    function getPrices() external view returns (PriceData[] memory result) {
        uint256[] memory ids = factory.boatFactory().tokenIds();
        result = new PriceData[](ids.length);
        for (uint i = 0; i < ids.length; i++) {
            result[i] = _prices[uint32(ids[i])];
        }
    }

    // **** FOR OPERATORS *****
    //--------------------
    function onBoatCollect(address from) public onlyRole(OPERATOR_ROLE) whenNotPaused returns (uint16 totalCapacity, uint16 totalReadyBoat) {
        uint256[] storage datas = _boatData[from];
        uint256 len = datas.length;
        if (len == 0) {
            revert InsufficientBalance();
        }

        IBoatFactory boatFactory = factory.boatFactory();
        for (uint i = 0; i < len; ) {
            BoatData memory boat = _unpackData(datas[i]);

            if (boat.IsWorking == 1) {
                boat.EndTime = boat.EndTime.remainTime();
                if (boat.EndTime == 0) {
                    totalCapacity += boatFactory.getCapacity(boat.TokenId);
                    totalReadyBoat++;
                    boat.IsWorking = 0;

                    datas[i] = _packData(boat);
                }
            }

            unchecked {
                i++;
            }
        }

        require(totalCapacity > 0, "No working boats");
    }

    // **** FOR ACCOUNTS *****
    //--------------------

    function manageBoats(uint8 action) external whenNotPaused nonReentrant {
        if (action < 1 || action > 3) {
            revert NotExists();
        }

        address sender = msg.sender;
        uint256[] storage datas = _boatData[sender];
        uint256 len = datas.length;
        if (len == 0) {
            revert InsufficientBalance();
        }

        IBoatFactory boatFactory = factory.boatFactory();
        uint256 totalPrice;
        uint64 totalScore;
        bool anyPrice = false;

        for (uint i = 0; i < len; ) {
            BoatData memory boat = _unpackData(datas[i]);

            if (action == 1) {
                // refuelAll
                if (boat.Fuel == 0 && boat.EngineType != uint8(EngineTypes.Solar)) {
                    boat.Fuel = boatFactory.getFuelTank(boat.TokenId);
                    totalScore += 1;
                    totalPrice += _prices[boat.TokenId].Refuell;
                    anyPrice = true;

                    datas[i] = _packData(boat);
                }
            } else if (action == 2) {
                // speedUpAll
                SpeedContainer memory result = _calcSUP(boat);
                if (result.speedPrice > 0) {
                    totalPrice += result.speedPrice;
                    boat.EndTime = 0;
                    anyPrice = true;

                    datas[i] = _packData(boat);
                }
            } else if (action == 3) {
                // sendWorkAll
                if (boat.IsWorking == 0) {
                    uint64 endTime = boatFactory.getWaitTime(boat.TokenId).createEndTime(1 hours);
                    if (boat.EngineType == uint8(EngineTypes.Solar)) {
                        boat.EndTime = endTime;
                        boat.IsWorking = 1;

                        datas[i] = _packData(boat);
                    } else if (boat.Fuel > 0) {
                        if (boat.EngineType != uint8(EngineTypes.Ufo)) {
                            boat.EndTime = endTime;
                        }
                        boat.IsWorking = 1;
                        boat.Fuel--;

                        datas[i] = _packData(boat);
                    }
                }
            }

            unchecked {
                i++;
            }
        }

        if (anyPrice) {
            if (totalPrice == 0) {
                revert PriceEmpty();
            }

            factory.planetToken().operatorBurn(sender, totalPrice);

            if (action == 1) {
                factory.playerManager().onLoyalScoreUp(sender, totalScore);
                emit RefuelAll(sender, totalPrice);
            } else if (action == 2) {
                emit SpeedUpAll(sender, totalPrice);
            }
        }
    }

    function deposit(uint32 tokenId, uint8 amount) external whenNotPaused nonReentrant {
        address sender = msg.sender;
        require(amount > 0 && amount <= _MAX_BOAT_COUNT, "Max 16 boat");

        IBoatFactory boatFactory = factory.boatFactory();
        uint256 _balance = boatFactory.balanceOf(sender, tokenId);
        if (_balance < amount) {
            revert InsufficientBalance();
        }

        uint256[] storage datas = _boatData[sender];
        uint256 currentCount = datas.length + amount;
        require(currentCount <= _MAX_BOAT_COUNT, "Max limit reached");

        uint8 engineType = boatFactory.getEngineType(tokenId);

        for (uint i = 0; i < amount; ) {
            BoatData memory boat;
            boat.EngineType = engineType;
            boat.TokenId = tokenId;

            datas.push(_packData(boat));

            unchecked {
                i++;
            }
        }

        boatFactory.deposit(sender, tokenId, amount);

        emit Deposit(sender, tokenId, amount);
    }

    function withdraw(uint256 boatIndex, bool withdrawAll) external whenNotPaused nonReentrant {
        address sender = msg.sender;
        uint256[] storage datas = _boatData[sender];
        uint256 len = datas.length;

        if (len == 0) {
            revert InsufficientBalance();
        }

        if (withdrawAll) {
            uint256[] memory ids = new uint256[](len);
            uint256[] memory amounts = new uint256[](len);

            for (uint i = 0; i < len; ) {
                ids[i] = _getTokenId(datas[i]);
                amounts[i] = 1;

                unchecked {
                    i++;
                }
            }

            delete _boatData[sender];
            factory.boatFactory().withdrawBatch(sender, ids, amounts);

            emit WithdrawAll(sender, ids, amounts);
        } else {
            if (boatIndex == 0) {
                revert InvalidValue(boatIndex);
            }

            // boat index starts with +1
            unchecked {
                boatIndex--;
            }

            if (boatIndex >= len) {
                revert ArrayOverflow();
            }

            uint256 packedData = datas[boatIndex];
            uint256 tokenId = _getTokenId(packedData);

            datas[boatIndex] = datas[len - 1];
            datas.pop();

            factory.boatFactory().withdraw(sender, tokenId, 1);

            emit Withdraw(sender, tokenId, 1);
        }
    }

    function getTotalCost(address from, uint8 arg) external view returns (uint256[2] memory) {
        from.throwIfEmpty();
        require(arg >= 1 && arg <= 2, "arg");

        uint256[] storage datas = _boatData[from];
        uint256 len = datas.length;
        uint256[2] memory buffer = [uint256(0), 0];

        for (uint i = 0; i < len; ) {
            BoatData memory boat = _unpackData(datas[i]);
            SpeedContainer memory spc = _calcSUP(boat);

            if (arg == 1) {
                // 1: speed up price
                if (spc.speedPrice > 0) {
                    buffer[0] += spc.speedPrice;
                    buffer[1] += 1;
                }
            } else if (boat.Fuel == 0 && boat.EngineType != uint8(EngineTypes.Solar)) {
                // 2: fuel price
                buffer[0] += spc.refuellPrice;
                buffer[1] += 1;
            }

            unchecked {
                i++;
            }
        }
        return buffer;
    }

    function getRemainDeposit(address from, uint256 tokenId) external view returns (uint64) {
        from.throwIfEmpty();
        uint256 boatCount = _boatData[from].length;
        uint256 _balance = factory.boatFactory().balanceOf(from, tokenId);
        uint256 remain = _MAX_BOAT_COUNT - boatCount;
        if (remain > _balance) {
            return uint64(_balance);
        } else {
            return uint64(remain);
        }
    }

    function getBoatInfo(address from, uint8 arg) external view returns (BoatInfo[] memory result, StatusInfo memory info) {
        from.throwIfEmpty();
        require(arg >= 1 && arg <= 4, "arg");

        uint256[] storage datas = _boatData[from];
        uint256 len = datas.length;

        uint32 index;
        bool found;

        BoatInfo[] memory buffer = new BoatInfo[](len);
        info.totalBoat = uint8(len);

        for (uint i = 0; i < len; ) {
            BoatData memory boat = _unpackData(datas[i]);
            found = false;

            if (boat.IsWorking == 0 && (boat.EngineType == uint8(EngineTypes.Solar) || boat.Fuel > 0)) {
                info.totalIdle++;
                if (arg == 1) {
                    found = true;
                }
            }

            if (boat.IsWorking == 1) {
                info.totalBusyOrCollect++;
                if (arg == 2) {
                    found = true;
                }
            }

            if (boat.Fuel == 0 && boat.EngineType != uint8(EngineTypes.Solar)) {
                info.totalRefuell++;
                if (arg == 3) {
                    found = true;
                }
            }

            if (arg == 4) {
                found = true;
            }

            if (found) {
                SpeedContainer memory sc = _calcSUP(boat);
                buffer[index] = BoatInfo({
                    IsWorking: boat.IsWorking == 1,
                    EngineType: boat.EngineType,
                    Fuel: boat.Fuel,
                    TokenId: boat.TokenId,
                    EndTime: sc.remainSeconds,
                    BoatId: i + 1,
                    RefuelPrice: sc.refuellPrice,
                    SpeedUpPrice: sc.speedPrice
                });
                index++;
            }

            unchecked {
                i++;
            }
        }

        result = new BoatInfo[](index);
        for (uint i = 0; i < index; i++) {
            result[i] = buffer[i];
        }
    }
}
