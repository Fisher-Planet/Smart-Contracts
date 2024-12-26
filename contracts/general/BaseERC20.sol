// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./BaseControl.sol";
import "../interfaces/IBaseERC20.sol";

abstract contract BaseERC20 is ERC20, BaseControl, IBaseERC20 {
    mapping(address account => bool) private _operatorAuth;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    modifier onlySpender(address account) {
        require(_operatorAuth[account], "Allowance Auth Require");
        _;
    }

    // ************ REMOVE WHEN LIVE !!! ************
    // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    mapping(address => bool) private _testPlayersMintMap;

    // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    // *********************************************

    /**
     * @dev Players who want to enter the Fisher Planet universe must authorize Fisher Planet smart contracts to spend FPT and AFT tokens.
     * It is not possible for players to sign erc20 allowance for every transaction because some smart contracts on Fisher Planet work in conjunction with each other.
     * true : fisher planet contracts can transfer or burn the wallet owner's FPT and AFT tokens.
     * false : cancels authorization
     */

    function setAuth(bool status) external {
        address account = msg.sender;
        if (_operatorAuth[account] != status) {
            _operatorAuth[account] = status;
        }

        // ************ REMOVE WHEN LIVE !!! ************
        // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        // this only for test players. 20k each

        if (!_testPlayersMintMap[account]) {
            _testPlayersMintMap[account] = true;
            _mint(account, 20000 ether);
        }

        // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        // *********************************************
    }

    function getAuth(address account) public view returns (bool) {
        return _operatorAuth[account];
    }

    function operatorMint(address to, uint256 amount) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        _mint(to, amount);
    }

    function operatorBurn(address from, uint256 amount) public onlyRole(OPERATOR_ROLE) onlySpender(from) whenNotPaused {
        _burn(from, amount);
    }

    function operatorTransfer(address from, address to, uint256 amount) public onlyRole(OPERATOR_ROLE) onlySpender(from) whenNotPaused {
        _transfer(from, to, amount);
    }

    function operatorTransferSelf(address from, uint256 amount) public onlyRole(OPERATOR_ROLE) onlySpender(from) whenNotPaused {
        _transfer(from, address(this), amount);
    }

    fallback() external payable {
        revert("fallback");
    }

    receive() external payable {
        revert("receive");
    }
}
