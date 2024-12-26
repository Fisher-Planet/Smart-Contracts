// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "../general/Structs.sol";
import "./IBaseFungible.sol";

/**
 * @dev Only for internal Operator Contracts. In other words, it is not an externally usable interface of the contract.
 * Required for a base factory contract structure.
 */
interface IFishFactory is IBaseFungible {
    function get(uint256 tokenId) external view returns (FishMetaData memory);

    function getProduction(uint256 tokenId) external view returns (uint16);
}
