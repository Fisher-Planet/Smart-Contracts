// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseFungible.sol";
import "../library/UtilLib.sol";

contract BoatFactory is BaseFungible, IBoatFactory {
    using UtilLib for *;

    // all boat meta datas
    BoatMetaData[] private _metas;

    constructor(IContractFactory _factory) BaseFungible(_factory) {}

    function add(BoatMetaData[] calldata inputs) external onlyRole(MANAGER_ROLE) {
        for (uint256 i = 0; i < inputs.length; i++) {
            BoatMetaData memory input = inputs[i];

            require(input.Id >= 128 && input.Id <= 192, "Id range");
            require(input.Capacity > 1 && input.Capacity < 65, "Capacity");
            require(input.EngineType > 0, "EngineType");

            if (input.EngineType != uint8(EngineTypes.Solar)) {
                require(input.FuelTank > 0, "FuelTank");
            }

            if (input.EngineType != uint8(EngineTypes.Ufo)) {
                require(input.WaitTime > 0, "WaitTime");
            }

            input.Rarity.throwIfRarityInvalid();

            if (exists(input.Id)) {
                revert Exists();
            }

            _metas.push(BoatMetaData({Rarity: input.Rarity, EngineType: input.EngineType, Capacity: input.Capacity, FuelTank: input.FuelTank, WaitTime: input.WaitTime, Id: input.Id}));

            super.addTokenId(input.Id, _metas.length);
        }
    }

    function setWaitTimes(uint32[] calldata ids, uint16[] calldata values) external onlyRole(MANAGER_ROLE) {
        require(ids.length <= _metas.length && ids.length == values.length, "overflow");
        for (uint i = 0; i < ids.length; i++) {
            _metas[_offset(ids[i])].WaitTime = values[i];
        }
    }

    function setCapacities(uint32[] calldata ids, uint8[] calldata values) external onlyRole(MANAGER_ROLE) {
        require(ids.length <= _metas.length && ids.length == values.length, "overflow");
        for (uint i = 0; i < ids.length; i++) {
            _metas[_offset(ids[i])].Capacity = values[i];
        }
    }

    function setFuelTanks(uint32[] calldata ids, uint8[] calldata values) external onlyRole(MANAGER_ROLE) {
        require(ids.length <= _metas.length && ids.length == values.length, "overflow");
        for (uint i = 0; i < ids.length; i++) {
            _metas[_offset(ids[i])].FuelTank = values[i];
        }
    }

    /* QUERY FOR OPERATORS */
    // ------------------------------------

    function get(uint256 tokenId) public view returns (BoatMetaData memory) {
        return _metas[_offset(tokenId)];
    }

    function getWaitTime(uint256 tokenId) public view returns (uint16) {
        return _metas[_offset(tokenId)].WaitTime;
    }

    function getEngineType(uint256 tokenId) public view returns (uint8) {
        return _metas[_offset(tokenId)].EngineType;
    }

    function getCapacity(uint256 tokenId) public view returns (uint8) {
        return _metas[_offset(tokenId)].Capacity;
    }

    function getFuelTank(uint256 tokenId) public view returns (uint8) {
        return _metas[_offset(tokenId)].FuelTank;
    }

    function getRC(uint256 tokenId) public view returns (uint8 Rarity, uint8 Capacity) {
        BoatMetaData storage meta = _metas[_offset(tokenId)];
        Rarity = meta.Rarity;
        Capacity = meta.Capacity;
    }

    function getRF(uint256 tokenId) public view returns (uint8 Rarity, uint8 FuelTank) {
        BoatMetaData storage meta = _metas[_offset(tokenId)];
        Rarity = meta.Rarity;
        FuelTank = meta.FuelTank;
    }

    function getRE(uint256 tokenId) public view returns (uint8 Rarity, uint8 EngineType) {
        BoatMetaData storage meta = _metas[_offset(tokenId)];
        Rarity = meta.Rarity;
        EngineType = meta.EngineType;
    }

    /* QUERY FOR DAPP */
    // ------------------------------------
    function getAll() external view returns (BoatMetaData[] memory) {
        return _metas;
    }
}
