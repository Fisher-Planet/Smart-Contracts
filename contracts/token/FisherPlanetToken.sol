// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseERC20.sol";

contract FisherPlanetToken is BaseERC20 {
    uint256 public constant _MAX_SUPPLY = 250_000_000 ether;

    constructor() BaseERC20("Fisher Planet Token", "FPT") {
        _mint(msg.sender, 20_000_000 ether);
    }

    function mint(uint256 amount) external onlyRole(MANAGER_ROLE) {
        require(amount > 0, "amount");
        uint256 totalMinted = totalSupply() + amount;
        require(totalMinted <= _MAX_SUPPLY, "_MAX_SUPPLY");
        _mint(msg.sender, amount);
    }

    function burn(uint256 amount) external onlyRole(MANAGER_ROLE) {
        _burn(msg.sender, amount);
    }

    function airDrop(address[] calldata accounts, uint256[] calldata amounts) external onlyRole(MANAGER_ROLE) {
        require(accounts.length > 0, "no input");
        require(accounts.length == amounts.length, "ids and amounts length mismatch");
        for (uint256 i = 0; i < accounts.length; ++i) {
            _transfer(msg.sender, accounts[i], amounts[i]);
        }
    }
}
