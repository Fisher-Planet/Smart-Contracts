// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseERC20.sol";

contract AquaFarmingToken is BaseERC20 {
    constructor() BaseERC20("Aqua Farming Token", "AFT") {
        _mint(msg.sender, 500_000 ether);
    }

    function mint(address to, uint256 amount) external whenNotPaused onlyRole(MANAGER_ROLE) {
        require(amount > 0, "amount");
        if (to == address(0)) {
            to = msg.sender;
        }
        _mint(to, amount);
    }

    function burn(uint256 amount) external whenNotPaused onlyRole(MANAGER_ROLE) {
        _burn(msg.sender, amount);
    }
}
