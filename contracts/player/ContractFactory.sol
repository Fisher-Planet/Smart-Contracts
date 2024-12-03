// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseControl.sol";
import "../interfaces/IContractFactory.sol";

contract ContractFactory is BaseControl, IContractFactory {
    bytes32 private constant _INftFactory = keccak256("INftFactory");
    bytes32 private constant _IFisherPlanetToken = keccak256("IFisherPlanetToken");
    bytes32 private constant _IAquaFarmingToken = keccak256("IAquaFarmingToken");
    bytes32 private constant _IAquaFarming = keccak256("IAquaFarming");
    bytes32 private constant _IFishFactory = keccak256("IFishFactory");
    bytes32 private constant _IDockManager = keccak256("IDockManager");
    bytes32 private constant _ITournaments = keccak256("ITournaments");
    bytes32 private constant _INftMarket = keccak256("INftMarket");
    bytes32 private constant _IPlayerManager = keccak256("IPlayerManager");
    bytes32 private constant _IBoatFactory = keccak256("IBoatFactory");

    INftFactory private _nftFactory;
    IBaseERC20 private _planetToken;
    IBaseERC20 private _farmingToken;
    IAquaFarming private _aquaFarming;
    IFishFactory private _fishFactory;
    IDockManager private _dockManager;
    ITournaments private _tournaments;
    INftMarket private _nftMarket;
    IPlayerManager private _playerManager;
    IBoatFactory private _boatFactory;

    // Global settings
    AppConfig private _config;

    struct CInfo {
        address c;
        bytes32 h;
    }

    constructor() {
        _config = AppConfig({BlockPeriod: 5, DailyBlock: 17280});
    }

    function setConfig(AppConfig memory _item) external onlyRole(MANAGER_ROLE) {
        require(_item.BlockPeriod > 0, "BlockPeriod");
        if (_item.DailyBlock == 0) {
            uint8 blockPeriod = _item.BlockPeriod;
            uint32 dailyBlock = 86400 / blockPeriod;
            _item.DailyBlock = dailyBlock;
            require(dailyBlock > 0, "dailyBlock zero");
        }
        _config = _item;
    }

    function setContracts(CInfo[] calldata inputs) external onlyRole(MANAGER_ROLE) {
        require(inputs.length > 0, "no data");
        for (uint i = 0; i < inputs.length; i++) {
            CInfo memory d = inputs[i];
            if (d.h == _INftFactory) {
                _nftFactory = INftFactory(d.c);
            } else if (d.h == _IFisherPlanetToken) {
                _planetToken = IBaseERC20(d.c);
            } else if (d.h == _IAquaFarmingToken) {
                _farmingToken = IBaseERC20(d.c);
            } else if (d.h == _IAquaFarming) {
                _aquaFarming = IAquaFarming(d.c);
            } else if (d.h == _IFishFactory) {
                _fishFactory = IFishFactory(d.c);
            } else if (d.h == _IDockManager) {
                _dockManager = IDockManager(d.c);
            } else if (d.h == _ITournaments) {
                _tournaments = ITournaments(d.c);
            } else if (d.h == _INftMarket) {
                _nftMarket = INftMarket(d.c);
            } else if (d.h == _IPlayerManager) {
                _playerManager = IPlayerManager(d.c);
            } else if (d.h == _IBoatFactory) {
                _boatFactory = IBoatFactory(d.c);
            } else {
                revert("unknown");
            }
        }
    }

    function getConfig() external view returns (AppConfig memory) {
        return _config;
    }

    function getBlockPeriod() public view returns (uint8) {
        return _config.BlockPeriod;
    }

    function getDailyBlock() public view returns (uint32) {
        return _config.DailyBlock;
    }

    function nftFactory() public view returns (INftFactory) {
        return _nftFactory;
    }

    function planetToken() public view returns (IBaseERC20) {
        return _planetToken;
    }

    function farmingToken() public view returns (IBaseERC20) {
        return _farmingToken;
    }

    function dockManager() public view returns (IDockManager) {
        return _dockManager;
    }

    function fishFactory() public view returns (IFishFactory) {
        return _fishFactory;
    }

    function tournaments() public view returns (ITournaments) {
        return _tournaments;
    }

    function aquaFarming() public view returns (IAquaFarming) {
        return _aquaFarming;
    }

    function nftMarket() public view returns (INftMarket) {
        return _nftMarket;
    }

    function playerManager() public view returns (IPlayerManager) {
        return _playerManager;
    }

    function boatFactory() public view returns (IBoatFactory) {
        return _boatFactory;
    }

    function checkReady(address account) public view {
        _playerManager.checkReady(account);
    }
}
