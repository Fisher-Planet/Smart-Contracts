// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseERC20.sol";

contract AquaFarmingToken is BaseERC20 {
    constructor() BaseERC20("Aqua Farming Token", "AFT") {
        _mint(msg.sender, 500_000 ether);
    }

    function mint(uint256 amount) external onlyRole(MANAGER_ROLE) {
        require(amount > 0, "amount");
        _mint(msg.sender, amount);
    }

    function burn(uint256 amount) external onlyRole(MANAGER_ROLE) {
        _burn(msg.sender, amount);
    }
}
