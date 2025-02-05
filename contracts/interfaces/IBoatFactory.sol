// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "../general/Structs.sol";
import "./IBaseFungible.sol";

/**
 * @dev Only for internal Operator Contracts. In other words, it is not an externally usable interface of the contract.
 * Required for a base factory contract structure.
 */
interface IBoatFactory is IBaseFungible {
    function getRarity(uint256 tokenId) external view returns (uint8);

    function getEngineType(uint256 tokenId) external view returns (uint8);

    function getCapacity(uint256 tokenId) external view returns (uint8);

    function getFuelTank(uint256 tokenId) external view returns (uint8);

    function getWaitTime(uint256 tokenId) external view returns (uint16);

    function get(uint256 tokenId) external view returns (BoatMetaData memory);

    function getAll() external view returns (BoatMetaData[] memory result);
}
