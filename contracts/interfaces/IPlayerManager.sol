// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev Only for internal Operator Contracts. In other words, it is not an externally usable interface of the contract.
 * Required for a base factory contract structure.
 */
interface IPlayerManager {
    function onLoyalScoreUp(address account, uint64 score) external;

    function onLoyalScoreReset(address account) external returns (bool);

    function isReady(address account) external view returns (bool);

    function getNick(address account) external view returns (string memory);

    function checkReady(address account) external view;

    function onRefExists(address sender, uint256 price) external;
}
