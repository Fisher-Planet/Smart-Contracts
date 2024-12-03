// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseFungible.sol";
import "../library/UtilLib.sol";

contract FishFactory is BaseFungible, IFishFactory {
    using UtilLib for *;

    event LoyalReward(address indexed account, uint32 id);

    // special nft id
    uint8 private constant _LOYAL_ID = 7;

    // all Nft Meta Data Items
    FishMetaData[] private _metas;

    constructor(IContractFactory _factory) BaseFungible(_factory) {}

    function add(FishMetaData[] calldata inputs) external onlyRole(MANAGER_ROLE) {
        for (uint32 i = 0; i < inputs.length; i++) {
            FishMetaData memory input = inputs[i];

            require(input.Id >= 1 && input.Id <= 64, "Id range");
            require(input.Production > 0, "Production");
            require(input.CreatureType > 0, "CreatureType");

            if (exists(input.Id)) {
                revert Exists();
            }

            input.Rarity.throwIfRarityInvalid();

            _metas.push(FishMetaData({Rarity: input.Rarity, CreatureType: input.CreatureType, Id: input.Id, Production: input.Production}));
            super.addTokenId(input.Id, _metas.length);
        }
    }

    /* QUERY FOR OPERATORS */
    // ------------------------------------

    function get(uint256 tokenId) public view returns (FishMetaData memory) {
        return _metas[_offset(tokenId)];
    }

    function getProduction(uint256 tokenId) public view returns (uint8) {
        return _metas[_offset(tokenId)].Production;
    }

    /* QUERY FOR DAPP */
    // ------------------------------------
    function getAll() external view returns (FishMetaData[] memory result) {
        return _metas;
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
