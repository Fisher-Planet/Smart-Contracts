// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseFactory.sol";
import "../library/UtilLib.sol";

contract GameManager is BaseFactory {
    using UtilLib for *;

    event Collected(address indexed player, uint256[] ids, uint256[] amounts);

    // fish density in the map : 0=common, 1=uncommon, 2=rare, 3=epic, 4=legendary, 5=ancient
    //bytes32 private constant _FISH_MAP = "00000000000111111112222223333445";
    bytes private constant _FISH_MAP = "0000000000000000000000000000000111111111111111111222222223333445";
    uint256 private _nonce;

    constructor(IContractFactory _factory) BaseFactory(_factory) {}

    function _getOffset(uint32[] memory buffer, uint256 tokenId) private pure returns (uint32 pos, uint32 id) {
        pos = 0xFFFFFFFF;
        id = uint32(tokenId);
        unchecked {
            for (uint32 x = 0; x < buffer.length; x++) {
                if (buffer[x] != 0 && buffer[x] == id) {
                    pos = x;
                    break;
                }
            }
        }
    }

    function _collectFishes(uint8 capacity) private view returns (uint256[] memory ids, uint256[] memory amounts, uint256 totalFish) {
        uint256[] memory tokenIds = factory.fishFactory().tokenIds();
        uint32[] memory buffer = new uint32[](capacity);
        uint32[] memory counts = new uint32[](capacity);
        uint256 payload = uint256(_nonce.randBytes());
        uint256 index;
        uint32 offset;
        uint32 tokenId;
        uint8 i;

        unchecked {
            while (i < capacity) {
                if (payload & 0x1 == 1) {
                    (offset, tokenId) = _getOffset(buffer, tokenIds[(uint8(_FISH_MAP[payload & 0x3F]) - 0x30)]);
                    if (offset == 0xFFFFFFFF) {
                        buffer[index] = tokenId;
                        counts[index] = 1;
                        index++;
                    } else {
                        counts[offset] += 1;
                    }
                }
                i++;
                payload >>= 2;
            }

            ids = new uint256[](index);
            amounts = new uint256[](index);

            for (i = 0; i < index; i++) {
                ids[i] = buffer[i];
                amounts[i] = counts[i];
                totalFish += counts[i];
            }
        }
    }

    function finishWork(uint256 boatId) external whenNotPaused nonReentrant {
        address sender = msg.sender;

        // check boat status
        (uint8 Rarity, uint8 Capacity) = factory.dockManager().onBoatCollect(sender, boatId);

        unchecked {
            _nonce++;
        }

        // collect fishes
        (uint256[] memory ids, uint256[] memory amounts, uint256 totalFish) = _collectFishes(Capacity);

        // we need set our event first for game engine
        emit Collected(sender, ids, amounts);

        // there may not be any fish
        if (ids.length > 0) {
            // send new score to tournaments
            factory.tournaments().onScoreChanged(sender, uint32(totalFish), Rarity);

            // mint fishes
            factory.nftFactory().operatorMintBatch(sender, ids, amounts, "");
        }
    }
}
