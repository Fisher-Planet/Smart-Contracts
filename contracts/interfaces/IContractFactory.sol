// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "../interfaces/INftFactory.sol";
import "../interfaces/IBaseERC20.sol";
import "../interfaces/IDockManager.sol";
import "../interfaces/IFishFactory.sol";
import "../interfaces/ITournaments.sol";
import "../interfaces/IAquaFarming.sol";
import "../interfaces/IPlayerManager.sol";
import "../interfaces/INftMarket.sol";
import "../interfaces/IBoatFactory.sol";

/**
 * @dev Access to various contracts
 * Almost all contracts use this interface to communicate
 */
interface IContractFactory {
    function nftFactory() external view returns (INftFactory);

    function planetToken() external view returns (IBaseERC20);

    function farmingToken() external view returns (IBaseERC20);

    function dockManager() external view returns (IDockManager);

    function fishFactory() external view returns (IFishFactory);

    function aquaFarming() external view returns (IAquaFarming);

    function tournaments() external view returns (ITournaments);

    function nftMarket() external view returns (INftMarket);

    function playerManager() external view returns (IPlayerManager);

    function boatFactory() external view returns (IBoatFactory);
}
