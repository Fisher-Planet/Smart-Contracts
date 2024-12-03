// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/**
 * @dev Only for internal Operator Contracts. In other words, it is not an externally usable interface of the contract.
 * Required for a base factory contract structure.
 */
interface INftFactory is IERC1155 {
    function operatorTransfer(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;

    function operatorTransferBatch(address from, address to, uint256[] calldata ids, uint256[] calldata amounts, bytes calldata data) external;

    function operatorMint(address to, uint256 id, uint256 amount, bytes calldata data) external;

    function operatorMintBatch(address to, uint256[] calldata ids, uint256[] calldata amounts, bytes calldata data) external;

    function operatorBurn(address from, uint256 id, uint256 amount) external;

    function operatorBurnBatch(address from, uint256[] calldata ids, uint256[] calldata amounts) external;

    function getBalances(address from, uint256[] calldata tokenIds) external view returns (uint256[] memory ids, uint256[] memory amounts);
}
