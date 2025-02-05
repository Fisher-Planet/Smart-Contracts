// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseFungible.sol";
import "../library/UtilLib.sol";

contract BoatFactory is BaseFungible, IBoatFactory {
    using UtilLib for *;

    // BoatMetaData struct offsets
    uint8 private constant RARITY_OFFSET = 0;
    uint8 private constant ENGINE_TYPE_OFFSET = 8;
    uint8 private constant CAPACITY_OFFSET = 16;
    uint8 private constant FUEL_TANK_OFFSET = 24;
    uint8 private constant WAIT_TIME_OFFSET = 32;
    uint8 private constant ID_OFFSET = 48;

    constructor(IContractFactory _factory) BaseFungible(_factory) {}

    function setMetaData(BoatMetaData[] calldata inputs) external onlyRole(MANAGER_ROLE) {
        for (uint256 i = 0; i < inputs.length; ) {
            BoatMetaData calldata input = inputs[i];

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

            super._setData(input.Id, _packData(input));

            unchecked {
                i++;
            }
        }
    }

    function _packData(BoatMetaData calldata data) private pure returns (uint256) {
        return
            (uint256(data.Rarity) << RARITY_OFFSET) |
            (uint256(data.EngineType) << ENGINE_TYPE_OFFSET) |
            (uint256(data.Capacity) << CAPACITY_OFFSET) |
            (uint256(data.FuelTank) << FUEL_TANK_OFFSET) |
            (uint256(data.WaitTime) << WAIT_TIME_OFFSET) |
            (uint256(data.Id) << ID_OFFSET);
    }

    function _unpackData(uint256 tokenId) private view returns (BoatMetaData memory) {
        uint256 data = getData(tokenId);
        return
            BoatMetaData(
                uint8((data >> RARITY_OFFSET) & type(uint8).max),
                uint8((data >> ENGINE_TYPE_OFFSET) & type(uint8).max),
                uint8((data >> CAPACITY_OFFSET) & type(uint8).max),
                uint8((data >> FUEL_TANK_OFFSET) & type(uint8).max),
                uint16((data >> WAIT_TIME_OFFSET) & type(uint16).max),
                uint32((data >> ID_OFFSET) & type(uint32).max)
            );
    }

    /* QUERY FOR OPERATORS */
    // ------------------------------------

    function getRarity(uint256 tokenId) public view returns (uint8) {
        return uint8((getData(tokenId) >> RARITY_OFFSET) & type(uint8).max);
    }

    function getEngineType(uint256 tokenId) public view returns (uint8) {
        return uint8((getData(tokenId) >> ENGINE_TYPE_OFFSET) & type(uint8).max);
    }

    function getCapacity(uint256 tokenId) public view returns (uint8) {
        return uint8((getData(tokenId) >> CAPACITY_OFFSET) & type(uint8).max);
    }

    function getFuelTank(uint256 tokenId) public view returns (uint8) {
        return uint8((getData(tokenId) >> FUEL_TANK_OFFSET) & type(uint8).max);
    }

    function getWaitTime(uint256 tokenId) public view returns (uint16) {
        return uint16((getData(tokenId) >> WAIT_TIME_OFFSET) & type(uint16).max);
    }

    function get(uint256 tokenId) public view returns (BoatMetaData memory) {
        return _unpackData(tokenId);
    }

    function getAll() public view returns (BoatMetaData[] memory result) {
        uint256 len = _tokenIds.length;
        result = new BoatMetaData[](len);
        for (uint i = 0; i < len; ) {
            result[i] = _unpackData(_tokenIds[i]);
            unchecked {
                i++;
            }
        }
    }
}
