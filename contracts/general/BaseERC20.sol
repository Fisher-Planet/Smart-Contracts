// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./BaseControl.sol";
import "../interfaces/IBaseERC20.sol";

abstract contract BaseERC20 is ERC20, BaseControl, IBaseERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function operatorMint(address to, uint256 amount) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        _mint(to, amount);
    }

    function operatorBurn(address from, uint256 amount) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        _burn(from, amount);
    }

    function operatorTransfer(address from, address to, uint256 amount) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        _transfer(from, to, amount);
    }

    function operatorTransferSelf(address from, uint256 amount) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        _transfer(from, address(this), amount);
    }

    fallback() external payable {
        revert("fallback");
    }

    receive() external payable {
        revert("receive");
    }
}
