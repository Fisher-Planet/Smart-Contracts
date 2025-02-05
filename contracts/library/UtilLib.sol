// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
import "../general/Structs.sol";

library UtilLib {
    function throwIfZero(uint256 a) internal pure {
        require(a > 0, "a zero.");
    }

    function throwIfEmpty(address a) internal pure {
        require(a != address(0), "0x");
    }

    function throwIfContract(address a) internal view {
        require(!isContract(a), "sc address not allowed");
    }

    function throwIfEmptyOrContract(address a) internal view {
        throwIfEmpty(a);
        throwIfContract(a);
    }

    function isContract(address a) internal view returns (bool) {
        return a.code.length > 0;
    }

    function throwIfRarityInvalid(uint8 v) internal pure {
        require(v >= uint8(type(RarityTypes).min) && v <= uint8(type(RarityTypes).max), "enum outside bounds");
        require(v > 0, "enum zero");
    }

    function randRange(uint256 h, uint256 min, uint256 max) internal pure returns (uint256 result) {
        require(h > max, "randRange:h max");
        require(max > min, "randRange:max > min");
        result = (h % (max - min + 1)) + min;
    }

    function randIndex(uint256 h, uint256 min, uint256 max) internal pure returns (uint256 result) {
        require(h > max, "randIndex:h max");
        require(max > min, "randIndex:max > min");
        result = (h % (max - min)) + min;
        if (result >= max) {
            max--;
            result = max;
        }
    }

    function _getRandom() private view returns (bytes32 addr) {
        assembly {
            let freemem := mload(0x40)
            let start_addr := add(freemem, 0)
            if iszero(staticcall(gas(), 0x18, 0, 0, start_addr, 32)) {
                invalid()
            }
            addr := mload(freemem)
        }
    }

    function randBytes(uint256 _nonce) internal view returns (bytes32) {
        bytes32 vrf = _getRandom();
        return keccak256(abi.encodePacked(block.timestamp + 10 minutes, msg.sender, _nonce, blockhash(block.number - 1), block.prevrandao, vrf));
    }

    function randMax(uint256 h, uint256 max) internal pure returns (uint256 result) {
        require(h > max, "randMax:h max");
        require(max > 0, "randMax:max");
        result = (h % max) + 1;
    }

    function remainTime(uint64 endTime) internal view returns (uint64 remain) {
        if (endTime > 0) {
            uint64 currentTime = uint64(block.timestamp);
            if (endTime > currentTime) {
                unchecked {
                    remain = endTime - currentTime;
                }
            }
        }
    }

    function createEndTime(uint256 duration, uint256 timeMul) internal view returns (uint64 endTime) {
        if (duration > 0) {
            duration = (block.timestamp + (duration * timeMul)) - 1 minutes;
            endTime = uint64(duration);
        }
    }

    function isBytesValid(bytes memory safeBytes, uint256 min, uint256 max) internal pure returns (bool) {
        uint256 len = safeBytes.length;
        if (len < min) {
            return false;
        }
        if (len > max) {
            return false;
        }
        for (uint256 i; i < safeBytes.length; i++) {
            bytes1 char = safeBytes[i];
            if (
                !(char >= 0x30 && char <= 0x39) && //9-0
                !(char >= 0x41 && char <= 0x5A) && //A-Z
                !(char >= 0x61 && char <= 0x7A) //a-z
            ) {
                return false;
            }
        }
        return true;
    }

    function toSafeBytes(bytes32 str) internal pure returns (bytes memory bytesArray) {
        uint8 length = 0;
        while (str[length] != 0 && length < 32) {
            length++;
        }
        if (length == 0) {
            return bytesArray;
        }
        assembly {
            bytesArray := mload(0x40)
            mstore(0x40, add(bytesArray, 0x40))
            mstore(bytesArray, length)
            mstore(add(bytesArray, 0x20), str)
        }
    }

    function _lower(bytes1 _b1) private pure returns (bytes1) {
        if (_b1 >= 0x41 && _b1 <= 0x5A) {
            return bytes1(uint8(_b1) + 32);
        }
        return _b1;
    }

    function toLowerCase(bytes memory safeBytes) internal pure returns (bytes memory result) {
        result = new bytes(safeBytes.length);
        for (uint256 i = 0; i < safeBytes.length; i++) {
            result[i] = _lower(safeBytes[i]);
        }
    }

    function isAscii(string memory str, uint8 min, uint8 max) internal pure returns (bool) {
        bytes memory b = bytes(str);
        if (b.length == 0) {
            return false;
        }

        uint256 _strLen = strlen(str);
        if (!(b.length == _strLen && b.length >= min && b.length <= max)) {
            return false;
        }

        for (uint256 i; i < b.length; i++) {
            bytes1 char = b[i];
            if (
                !(char >= 0x30 && char <= 0x39) && //9-0
                !(char >= 0x41 && char <= 0x5A) && //A-Z
                !(char >= 0x61 && char <= 0x7A) //a-z
            ) return false;
        }
        return true;
    }

    function strlen(string memory s) internal pure returns (uint256) {
        uint256 len;
        uint256 i = 0;
        uint256 bytelength = bytes(s).length;
        for (len = 0; i < bytelength; len++) {
            bytes1 b = bytes(s)[i];
            if (b < 0x80) {
                i += 1;
            } else if (b < 0xE0) {
                i += 2;
            } else if (b < 0xF0) {
                i += 3;
            } else if (b < 0xF8) {
                i += 4;
            } else if (b < 0xFC) {
                i += 5;
            } else {
                i += 6;
            }
        }
        return len;
    }

    function calcShares(uint256 _amount, uint256 _fee) internal pure returns (uint256 fee, uint256 remain) {
        require(_amount > 0, "_amount zero");
        require(_fee > 0, "_fee zero");
        fee = (_amount * _fee) / 10000;
        remain = _amount - fee;
    }

    function toWei(uint256 value) internal pure returns (uint256 amount) {
        amount = value * 1e18;
    }

    function validateBytes(bytes16 input, bool needKey) internal pure returns (bytes16 key, bytes16 value) {
        uint8 length = 0;
        bytes memory buffer = new bytes(16);

        for (uint8 i = 0; i < 16; i++) {
            if (input[i] != 0) {
                buffer[length] = input[i];
                unchecked {
                    length++;
                }
            }
        }

        require(length != 0, "Word require");

        bytes memory data = new bytes(length);
        for (uint8 i = 0; i < length; i++) {
            data[i] = buffer[i];
        }

        require(isBytesValid(data, 5, 16), "Word letter range must be 5-16 and can only contain 9-0 A-Z a-z");

        value = bytes16(data);
        if (needKey) {
            key = bytes16(toLowerCase(data));
        }
    }
}
