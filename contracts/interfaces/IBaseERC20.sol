// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Only for internal Operator Contracts. In other words, it is not an externally usable interface of the contract.
 * Required for a base factory contract structure.
 */
interface IBaseERC20 is IERC20 {
    function getAuth(address account) external view returns (bool);

    function operatorMint(address to, uint256 amount) external;

    function operatorBurn(address from, uint256 amount) external;

    function operatorTransfer(address from, address to, uint256 amount) external;

    function operatorTransferSelf(address from, uint256 amount) external;
}
