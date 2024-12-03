// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "../general/Structs.sol";

/**
 * @dev Only for internal Operator Contracts. In other words, it is not an externally usable interface of the contract.
 * Required for a base factory contract structure.
 */
interface IBaseFungible {
    function deposit(address from, uint256 id, uint256 amount) external;

    function depositBatch(address from, uint256[] calldata ids, uint256[] calldata amounts) external;

    function withdraw(address to, uint256 id, uint256 amount) external;

    function withdrawBatch(address to, uint256[] calldata ids, uint256[] calldata amounts) external;

    function count() external view returns (uint256);

    function tokenIds() external view returns (uint256[] memory);

    function exists(uint256 tokenId) external view returns (bool);

    function balanceOf(address account, uint256 tokenId) external view returns (uint256);

    function getBalances(address from) external view returns (uint256[] memory ids, uint256[] memory amounts);
}
