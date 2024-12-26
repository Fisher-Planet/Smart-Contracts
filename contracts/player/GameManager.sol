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

    function _collectFishes(uint16 capacity) private view returns (FishContainer memory result) {
        FishContainer memory fc;
        fc.ids = factory.fishFactory().tokenIds();
        fc.amounts = new uint256[](fc.ids.length);
        require(fc.ids.length > 0, "id");

        uint8[6] memory _scores = [uint8(2), 4, 8, 16, 32, 64];
        uint256 payload = uint256(_nonce.randBytes());
        uint256 index;
        uint256 x;

        unchecked {
            while (capacity > 0) {
                if (payload & 0x1 == 1) {
                    index = (uint8(_FISH_MAP[payload & 0x3F]) - 0x30);
                    fc.amounts[index] += 1;
                    fc.score += _scores[index];
                }
                capacity--;

                if (payload < 0xFF) {
                    payload = uint256((payload + capacity).randBytes());
                }

                payload >>= 1;
            }

            index = 0;
            FishContainer memory buffer;
            buffer.ids = new uint256[](fc.ids.length);
            buffer.amounts = new uint256[](fc.ids.length);

            for (x = 0; x < fc.ids.length; x++) {
                if (fc.amounts[x] > 0) {
                    buffer.ids[index] = fc.ids[x];
                    buffer.amounts[index] = fc.amounts[x];
                    index++;
                }
            }

            result.ids = new uint256[](index);
            result.amounts = new uint256[](index);
            result.score = fc.score;

            for (x = 0; x < index; x++) {
                result.ids[x] = fc.ids[x];
                result.amounts[x] = fc.amounts[x];
            }
        }
    }

    function finishWorkAll() external whenNotPaused nonReentrant {
        address sender = msg.sender;
        uint16 totalCapacity = factory.dockManager().onBoatCollect(sender);

        unchecked {
            _nonce++;
        }

        FishContainer memory fc = _collectFishes(totalCapacity);

        emit Collected(sender, fc.ids, fc.amounts);

        if (fc.ids.length > 0) {
            factory.tournaments().onScoreChanged(sender, fc.score);
            factory.nftFactory().operatorMintBatch(sender, fc.ids, fc.amounts, "");
        }
    }
}
