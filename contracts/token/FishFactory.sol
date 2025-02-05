// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseFungible.sol";
import "../library/UtilLib.sol";

contract FishFactory is BaseFungible, IFishFactory {
    using UtilLib for *;

    event LoyalReward(address indexed account, uint256 id);

    // FishMetaData struct offsets
    uint8 private constant RARITY_OFFSET = 0;
    uint8 private constant CREATURE_TYPE_OFFSET = 8;
    uint8 private constant PRODUCTION_OFFSET = 16;
    uint8 private constant ID_OFFSET = 32;

    // special nft id
    uint8 private constant _LOYAL_ID = 7;

    constructor(IContractFactory _factory) BaseFungible(_factory) {}

    function setMetaData(FishMetaData[] calldata inputs) external onlyRole(MANAGER_ROLE) {
        for (uint256 i = 0; i < inputs.length; ) {
            FishMetaData calldata input = inputs[i];

            require(input.Id >= 1 && input.Id <= 64, "Id range");
            require(input.Production > 0, "Production");
            require(input.CreatureType > 0, "CreatureType");

            input.Rarity.throwIfRarityInvalid();

            super._setData(input.Id, _packData(input));

            unchecked {
                i++;
            }
        }
    }

    function _packData(FishMetaData calldata data) private pure returns (uint256) {
        return
            (uint256(data.Rarity) << RARITY_OFFSET) |
            (uint256(data.CreatureType) << CREATURE_TYPE_OFFSET) |
            (uint256(data.Production) << PRODUCTION_OFFSET) |
            (uint256(data.Id) << ID_OFFSET);
    }

    function _unpackData(uint256 tokenId) private view returns (FishMetaData memory) {
        uint256 data = getData(tokenId);
        return
            FishMetaData(
                uint8((data >> RARITY_OFFSET) & type(uint8).max),
                uint8((data >> CREATURE_TYPE_OFFSET) & type(uint8).max),
                uint16((data >> PRODUCTION_OFFSET) & type(uint16).max),
                uint32((data >> ID_OFFSET) & type(uint32).max)
            );
    }

    function getRarity(uint256 tokenId) public view returns (uint8) {
        return uint8((getData(tokenId) >> RARITY_OFFSET) & type(uint8).max);
    }

    function getCreatureType(uint256 tokenId) public view returns (uint8) {
        return uint8((getData(tokenId) >> CREATURE_TYPE_OFFSET) & type(uint8).max);
    }

    function getProduction(uint256 tokenId) public view returns (uint16) {
        return uint16((getData(tokenId) >> PRODUCTION_OFFSET) & type(uint16).max);
    }

    function get(uint256 tokenId) public view returns (FishMetaData memory) {
        return _unpackData(tokenId);
    }

    function getAll() public view returns (FishMetaData[] memory result) {
        uint256 len = _tokenIds.length;
        result = new FishMetaData[](len);
        for (uint i = 0; i < len; ) {
            result[i] = _unpackData(_tokenIds[i]);
            unchecked {
                i++;
            }
        }
    }

    /* ACCOUNT */
    // ------------------------------------
    function mintLoyalNft() external whenNotPaused nonReentrant {
        address sender = msg.sender;
        bool isReset = factory.playerManager().onLoyalScoreReset(sender);
        require(isReset, "Not ready");
        factory.nftFactory().operatorMint(sender, _LOYAL_ID, 1, "");
        emit LoyalReward(sender, _LOYAL_ID);
    }
}
