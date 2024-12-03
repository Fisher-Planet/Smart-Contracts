// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev Only for internal Operator Contracts. In other words, it is not an externally usable interface of the contract.
 * Required for a base factory contract structure.
 */
interface INftMarket {
    function getFee() external view returns (uint16);
}
