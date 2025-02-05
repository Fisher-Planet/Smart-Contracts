// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseFactory.sol";
import "../library/UtilLib.sol";

contract GameManager is BaseFactory {
    using UtilLib for *;

    event Collected(address indexed player, uint256[] ids, uint256[] amounts);

    struct FishContainer {
        uint32 score;
        uint256[] ids;
        uint256[] amounts;
    }

    /**
     * @dev Map of fish in water according to rarity.The rarest fish will be the most difficult to find.
     * fish density in the map : 0=common, 1=uncommon, 2=rare, 3=epic, 4=legendary, 5=ancient
     */
    bytes private constant _FISH_MAP = "0000000000000000000000000000000111111111111111111222222223333445";

    uint256 private _nonce;

    constructor(IContractFactory _factory) BaseFactory(_factory) {}

    function _collectFishes(uint256 currentNonce, uint256 capacity, uint256 totalReadyBoat) private view returns (FishContainer memory result) {
        if (totalReadyBoat < 1 || totalReadyBoat > 16) {
            revert InvalidValue(totalReadyBoat);
        }

        FishContainer memory fc;
        fc.ids = factory.fishFactory().tokenIds();
        fc.amounts = new uint256[](fc.ids.length);

        uint256 payload = uint256(currentNonce.randBytes());
        uint256 fishCount = payload % capacity;
        uint256 fishSwap = payload;

        uint256 index;
        uint256 i;

        if (fishCount < totalReadyBoat) {
            // range of 1 ~ 16 depends on boat count.
            fishCount = totalReadyBoat;
        }

        for (i = 0; i < fishCount; ) {
            fishSwap = (fishSwap >> 1) ^ (fishSwap << 3);
            index = uint8(_FISH_MAP[fishSwap & 0x3F]) - 0x30;

            unchecked {
                fc.amounts[index] += 1;
                i++;
            }
        }

        index = 0;
        for (i = 0; i < fc.ids.length; ) {
            unchecked {
                if (fc.amounts[i] != 0) {
                    index++;
                }
                i++;
            }
        }

        // set score
        totalReadyBoat = payload % (totalReadyBoat * 16);
        if (totalReadyBoat < 16) {
            // range of 16 ~ 256 depends on number of boats and randomness.
            totalReadyBoat = 16;
        }

        result.ids = new uint256[](index);
        result.amounts = new uint256[](index);
        result.score = uint32(totalReadyBoat);

        index = 0;
        for (i = 0; i < fc.ids.length; ) {
            unchecked {
                if (fc.amounts[i] != 0) {
                    result.ids[index] = fc.ids[i];
                    result.amounts[index] = fc.amounts[i];
                    index++;
                }
                i++;
            }
        }
    }

    function finishWorkAll() external whenNotPaused nonReentrant {
        address sender = msg.sender;
        (uint16 totalCapacity, uint16 totalReadyBoat) = factory.dockManager().onBoatCollect(sender);
        uint256 currentNonce;
        unchecked {
            currentNonce = ++_nonce;
        }

        FishContainer memory fc = _collectFishes(currentNonce, totalCapacity, totalReadyBoat);

        emit Collected(sender, fc.ids, fc.amounts);

        if (fc.ids.length > 0) {
            factory.tournaments().onScoreChanged(sender, fc.score);
            factory.nftFactory().operatorMintBatch(sender, fc.ids, fc.amounts, "");
        }
    }
}
