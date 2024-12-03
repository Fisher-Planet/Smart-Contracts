// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseFactory.sol";
import "../library/UtilLib.sol";

contract TournamentRewards is BaseFactory {
    using UtilLib for *;

    event Reward(address indexed to, uint256 amount);

    struct TopList {
        uint8 rank;
        uint8 rankShare;
        uint256 reward;
    }

    uint32 private _prizePool = 3000;

    constructor(IContractFactory _factory) BaseFactory(_factory) {}

    function setPrizePool(uint32 input) external onlyRole(MANAGER_ROLE) {
        require(input > 0, "input zero");
        _prizePool = input;
    }

    function _getTopRewards() private view returns (TopList[] memory result) {
        uint8[20] memory _shares = [10, 9, 8, 7, 6, 5, 5, 5, 5, 5, 4, 4, 4, 4, 4, 3, 3, 3, 3, 3];
        result = new TopList[](_shares.length);
        unchecked {
            for (uint8 i = 0; i < _shares.length; i++) {
                TopList memory item;
                item.rank = i + 1;
                item.rankShare = _shares[i];
                item.reward = ((_shares[i] * _prizePool) / 100).toWei();
                result[i] = item;
            }
        }
    }

    function _sendRewards(address[] memory input) private {
        TopList[] memory topList = _getTopRewards();
        require(input.length > 0, "input length zero");
        require(input.length <= topList.length, "input length invalid");

        IBaseERC20 planetToken = factory.planetToken();

        for (uint256 i = 0; i < input.length; i++) {
            address to = input[i];
            require(to != address(0), "input zero address");
            uint256 reward = topList[i].reward;

            // send rewards
            planetToken.operatorMint(to, reward);

            // send event
            emit Reward(to, reward);
        }
    }

    function sendRewardsManual(address[] calldata input) external onlyRole(MANAGER_ROLE) whenNotPaused {
        _sendRewards(input);
    }

    function sendRewardsAuto() external onlyRole(MANAGER_ROLE) whenNotPaused {
        address[] memory input = factory.tournaments().getTopListAddress();
        _sendRewards(input);
    }

    function getRewards() external view returns (TopList[] memory rewards, uint32 prizePool) {
        rewards = _getTopRewards();
        prizePool = _prizePool;
    }
}
