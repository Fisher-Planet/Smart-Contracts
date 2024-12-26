// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseFactory.sol";
import "../library/UtilLib.sol";
import "../library/ArrayLib.sol";

contract DockManager is BaseFactory, IDockManager {
    using UtilLib for *;
    using ArrayLib for uint256[];

    error FuelMustRunOut(uint256 boatId);

    event Deposit(address indexed account, uint256 tokenId, uint256 amount);
    event Withdraw(address indexed account, uint256 boatId, uint256 tokenId, uint256 amount);
    event WithdrawAll(address indexed account, uint256 totalBoat);
    event RefuelAll(address indexed account, uint256 totalCost);
    event SpeedUpAll(address indexed account, uint256 totalCost);

    struct BoatData {
        bool IsWorking;
        uint8 EngineType;
        uint8 Fuel;
        uint32 TokenId;
        uint64 EndTime;
        uint256 BoatId;
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
        uint256 BoatId;
        uint256 RefuelPrice;
        uint256 SpeedUpPrice;
    }

    struct StatusInfo {
        uint8 totalIdle;
        uint8 totalBusyOrCollect;
        uint8 totalRefuell;
        uint8 totalBoat;
    }

    // max boat per account
    uint8 private constant _MAX_BOAT_COUNT = 16;

    // boat id counter
    uint256 private _BoatIdCounter;

    // _price[tokenId] = target costs
    mapping(uint32 => PriceData) private _prices;

    // _boat[boatId][account] = target boat data
    mapping(uint256 => mapping(address => BoatData)) private _boat;

    //_boatIds[account] = owner boatId array
    mapping(address => uint256[]) private _boatIds;

    constructor(IContractFactory _factory) BaseFactory(_factory) {}

    function updatePrices(PriceData[] calldata inputs, uint8 percent) external onlyRole(MANAGER_ROLE) {
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

    function _calcSUP(BoatData storage boat) private view returns (SpeedContainer memory result) {
        PriceData storage prices = _prices[boat.TokenId];
        result.remainSeconds = boat.EndTime.remainTime();
        result.refuellPrice = prices.Refuell;

        if (boat.IsWorking && boat.EngineType == uint8(EngineTypes.Generic) && result.remainSeconds > 60) {
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
    function onBoatCollect(address from) public onlyRole(OPERATOR_ROLE) whenNotPaused returns (uint16 totalCapacity) {
        uint256[] storage ids = _boatIds[from];
        if (ids.length == 0) {
            revert InsufficientBalance();
        }

        IBoatFactory boatFactory = factory.boatFactory();

        unchecked {
            for (uint i = 0; i < ids.length; i++) {
                BoatData storage boat = _boat[ids[i]][from];
                if (boat.IsWorking) {
                    uint64 remainTime;
                    if (boat.EndTime > 0) {
                        remainTime = boat.EndTime.remainTime();
                    }
                    if (remainTime == 0) {
                        totalCapacity += boatFactory.getCapacity(boat.TokenId);
                        boat.IsWorking = false;
                        if (boat.EndTime > 0) {
                            boat.EndTime = 0;
                        }
                    }
                }
            }
        }

        require(totalCapacity > 0, "No working boats");
    }

    // **** FOR ACCOUNTS *****
    //--------------------

    function refuelAll() external whenNotPaused nonReentrant {
        address sender = msg.sender;
        uint256[] storage ids = _boatIds[sender];
        if (ids.length == 0) {
            revert InsufficientBalance();
        }

        IBoatFactory boatFactory = factory.boatFactory();
        uint256 totalPrice;
        uint64 totalScore;
        bool anyPrice = false;
        uint8 fuelTank;

        unchecked {
            for (uint i = 0; i < ids.length; i++) {
                BoatData storage boat = _boat[ids[i]][sender];
                if (boat.Fuel == 0 && boat.EngineType != uint8(EngineTypes.Solar)) {
                    fuelTank = boatFactory.getFuelTank(boat.TokenId);
                    boat.Fuel = fuelTank;
                    totalScore += 1;
                    totalPrice += _prices[boat.TokenId].Refuell;
                    anyPrice = true;
                }
            }
        }

        if (anyPrice) {
            if (totalPrice == 0) {
                revert PriceEmpty();
            }

            factory.planetToken().operatorBurn(sender, totalPrice);
            factory.playerManager().onLoyalScoreUp(sender, totalScore);

            emit RefuelAll(sender, totalPrice);
        }
    }

    function sendWorkAll() external whenNotPaused nonReentrant {
        address sender = msg.sender;
        uint256[] storage ids = _boatIds[sender];
        if (ids.length == 0) {
            revert InsufficientBalance();
        }
        IBoatFactory boatFactory = factory.boatFactory();
        unchecked {
            for (uint i = 0; i < ids.length; i++) {
                BoatData storage boat = _boat[ids[i]][sender];
                if (!boat.IsWorking) {
                    uint64 endTime = boatFactory.getWaitTime(boat.TokenId).createEndTime(1 hours);
                    if (boat.EngineType == uint8(EngineTypes.Solar)) {
                        boat.EndTime = endTime;
                        boat.IsWorking = true;
                    } else if (boat.Fuel > 0) {
                        if (boat.EngineType != uint8(EngineTypes.Ufo)) {
                            boat.EndTime = endTime;
                        }
                        boat.IsWorking = true;
                        boat.Fuel--;
                    }
                }
            }
        }
    }

    function speedUpAll() external whenNotPaused nonReentrant {
        address sender = msg.sender;
        uint256[] storage ids = _boatIds[sender];
        if (ids.length == 0) {
            revert InsufficientBalance();
        }
        uint256 totalPrice;
        bool anyPrice = false;

        unchecked {
            for (uint i = 0; i < ids.length; i++) {
                BoatData storage boat = _boat[ids[i]][sender];

                SpeedContainer memory result = _calcSUP(boat);
                if (result.speedPrice > 0) {
                    totalPrice += result.speedPrice;
                    boat.EndTime = 0;
                    anyPrice = true;
                }
            }
        }

        if (anyPrice) {
            if (totalPrice == 0) {
                revert PriceEmpty();
            }

            factory.planetToken().operatorBurn(sender, totalPrice);

            emit SpeedUpAll(sender, totalPrice);
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

        // check limits
        uint256[] storage ids = _boatIds[sender];
        uint256 currentCount = ids.length + amount;
        require(currentCount <= _MAX_BOAT_COUNT, "Max limit reached");

        uint8 EngineType = boatFactory.getEngineType(tokenId);
        uint256 boatId = _BoatIdCounter;

        unchecked {
            for (uint i = 0; i < amount; i++) {
                boatId += 1;

                BoatData storage boat = _boat[boatId][sender];
                if (boat.BoatId > 0) {
                    revert Exists();
                }

                ids.push(boatId);

                boat.EngineType = EngineType;
                boat.TokenId = tokenId;
                boat.BoatId = boatId;
            }
        }

        _BoatIdCounter = boatId;

        boatFactory.deposit(sender, tokenId, amount);

        emit Deposit(sender, tokenId, amount);
    }

    function withdraw(uint256 boatId) external whenNotPaused nonReentrant {
        boatId.throwIfZero();
        address sender = msg.sender;
        BoatData storage boat = _boat[boatId][sender];
        if (boat.BoatId == 0) {
            revert NotExists();
        }

        uint256[] storage ids = _boatIds[sender];
        (bool found, uint256 index) = ids.getIndex(boatId);
        if (!found) {
            revert NotExists();
        }

        if (boat.EngineType != uint8(EngineTypes.Solar) && boat.Fuel > 0) {
            revert FuelMustRunOut(boat.BoatId);
        }

        uint256 tokenId = boat.TokenId;
        boat.BoatId = 0;

        uint256 lastIndex = ids.length - 1;
        if (lastIndex != index) {
            ids[index] = ids[lastIndex];
        }
        ids.pop();

        factory.boatFactory().withdraw(sender, tokenId, 1);

        emit Withdraw(sender, boatId, tokenId, 1);
    }

    function getTotalCost(address from, uint8 arg) external view returns (uint256[2] memory) {
        from.throwIfEmpty();
        require(arg >= 1 && arg <= 2, "arg");
        uint256[] storage ids = _boatIds[from];
        uint256[2] memory buffer = [uint256(0), 0];

        for (uint i = 0; i < ids.length; i++) {
            BoatData storage boat = _boat[ids[i]][from];
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
        }
        return buffer;
    }

    function getBoatIds(address from) public view returns (uint256[] memory) {
        from.throwIfEmpty();
        return _boatIds[from];
    }

    function getRemainDeposit(address from, uint256 tokenId) external view returns (uint64) {
        from.throwIfEmpty();
        uint256 boatCount = _boatIds[from].length;
        uint256 _balance = factory.boatFactory().balanceOf(from, tokenId);
        uint256 remain = _MAX_BOAT_COUNT - boatCount;
        if (remain > _balance) {
            return uint64(_balance);
        } else {
            return uint64(remain);
        }
    }

    function getBoat(address from, uint256 boatId) public view returns (BoatData memory) {
        from.throwIfEmpty();
        return _boat[boatId][from];
    }

    function getBoatInfo(address from, uint8 arg) external view returns (BoatInfo[] memory result, StatusInfo memory info) {
        from.throwIfEmpty();
        require(arg >= 1 && arg <= 4, "arg");

        uint256[] storage boatIds = _boatIds[from];
        uint32 index;
        bool found;

        BoatInfo[] memory buffer = new BoatInfo[](boatIds.length);
        info.totalBoat = uint8(boatIds.length);

        for (uint i = 0; i < boatIds.length; i++) {
            BoatData storage boat = _boat[boatIds[i]][from];
            found = false;
            if (!boat.IsWorking && (boat.EngineType == uint8(EngineTypes.Solar) || boat.Fuel > 0)) {
                info.totalIdle++;
                if (arg == 1) {
                    found = true;
                }
            }

            if (boat.IsWorking) {
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
                    IsWorking: boat.IsWorking,
                    EngineType: boat.EngineType,
                    Fuel: boat.Fuel,
                    TokenId: boat.TokenId,
                    EndTime: sc.remainSeconds,
                    BoatId: boat.BoatId,
                    RefuelPrice: sc.refuellPrice,
                    SpeedUpPrice: sc.speedPrice
                });
                index++;
            }
        }

        result = new BoatInfo[](index);
        for (uint i = 0; i < index; i++) {
            result[i] = buffer[i];
        }
    }
}
