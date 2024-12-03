// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseControl.sol";
import "../interfaces/IContractFactory.sol";

abstract contract BaseFactory is BaseControl {
    IContractFactory internal factory;

    constructor(IContractFactory _factory) {
        factory = _factory;
    }

    function setFactory(address a) external onlyRole(MANAGER_ROLE) {
        require(a != address(0), "0x");
        factory = IContractFactory(a);
    }
}
