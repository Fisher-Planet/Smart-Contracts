// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

library ArrayLib {
    function _c(uint256 len, uint256 i) private pure {
        require(len > 0, "Arr:Empty");
        require(i < len, "Arr:Overflow");
    }

    function remove(uint256[] storage a, uint256 i) internal {
        _c(a.length, i);
        a[i] = a[a.length - 1];
        a.pop();
    }

    function remove(address[] storage a, uint256 i) internal {
        _c(a.length, i);
        a[i] = a[a.length - 1];
        a.pop();
    }

    function getIndex(uint256[] storage arr, uint256 input) internal view returns (bool found, uint256 index) {
        require(input > 0, "Arr:input");
        uint256 len = arr.length;
        for (uint256 i = 0; i < len; ) {
            if (arr[i] == input) {
                found = true;
                index = i;
                break;
            }
            unchecked {
                i++;
            }
        }
    }

    function getIndex(address[] storage arr, address input) internal view returns (bool found, uint256 index) {
        require(input != address(0), "Arr:input");
        uint256 len = arr.length;
        for (uint256 i = 0; i < len; ) {
            if (arr[i] == input) {
                found = true;
                index = i;
                break;
            }
            unchecked {
                i++;
            }
        }
    }
}
