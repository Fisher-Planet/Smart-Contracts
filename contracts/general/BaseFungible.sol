// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseFactory.sol";
import "../interfaces/IBaseFungible.sol";
import "../library/ArrayLib.sol";

abstract contract BaseFungible is BaseFactory, IBaseFungible {
    using ArrayLib for uint256[];

    // all tokenIds
    uint256[] internal _tokenIds;

    // _dataMap[tokenId] = dataPack
    mapping(uint256 => uint256) internal _dataMap;

    constructor(IContractFactory _factory) BaseFactory(_factory) {}

    function _setData(uint256 tokenId, uint256 dataPack) internal {
        if (tokenId == 0) revert TokenIdRequire();
        if (dataPack == 0) revert PacketDataRequired();
        _dataMap[tokenId] = dataPack;
        (bool found, ) = _tokenIds.getIndex(tokenId);
        if (!found) {
            _tokenIds.push(tokenId);
        }
    }

    function getData(uint256 tokenId) public view returns (uint256 dataPack) {
        dataPack = _dataMap[tokenId];
        if (dataPack == 0) {
            revert TokenNotExists(tokenId);
        }
    }

    function _checkArray(uint256[] calldata ids, uint256[] calldata amounts) private view {
        if (ids.length == 0 || amounts.length == 0) {
            revert ArrayEmpty();
        }
        if (ids.length != amounts.length) {
            revert ArrayOverflow();
        }
        for (uint i = 0; i < ids.length; i++) {
            if (!exists(ids[i])) {
                revert TokenNotExists(ids[i]);
            }
            if (amounts[i] == 0) {
                revert InsufficientBalance();
            }
        }
    }

    function deposit(address from, uint256 id, uint256 amount) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        if (!exists(id)) {
            revert TokenNotExists(id);
        }
        factory.nftFactory().operatorTransfer(from, address(this), id, amount, "");
    }

    function depositBatch(address from, uint256[] calldata ids, uint256[] calldata amounts) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        _checkArray(ids, amounts);
        factory.nftFactory().operatorTransferBatch(from, address(this), ids, amounts, "");
    }

    function withdraw(address to, uint256 id, uint256 amount) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        if (!exists(id)) {
            revert TokenNotExists(id);
        }
        factory.nftFactory().operatorTransfer(address(this), to, id, amount, "");
    }

    function withdrawBatch(address to, uint256[] calldata ids, uint256[] calldata amounts) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        _checkArray(ids, amounts);
        factory.nftFactory().operatorTransferBatch(address(this), to, ids, amounts, "");
    }

    function onERC1155Received(address operator, address, uint256, uint256, bytes calldata) public view returns (bytes4) {
        if (operator != address(this)) {
            revert NotAllowed();
        }
        return 0xf23a6e61;
    }

    function onERC1155BatchReceived(address operator, address, uint256[] calldata, uint256[] calldata, bytes calldata) public view returns (bytes4) {
        if (operator != address(this)) {
            revert NotAllowed();
        }
        return 0xbc197c81;
    }

    function count() public view returns (uint256) {
        return _tokenIds.length;
    }

    function tokenIds() public view returns (uint256[] memory) {
        return _tokenIds;
    }

    function exists(uint256 tokenId) public view returns (bool) {
        return _dataMap[tokenId] > 0;
    }

    function balanceOf(address account, uint256 tokenId) public view returns (uint256) {
        if (!exists(tokenId)) {
            revert TokenNotExists(tokenId);
        }
        return factory.nftFactory().balanceOf(account, tokenId);
    }

    function getBalances(address from) public view returns (uint256[] memory ids, uint256[] memory amounts) {
        return factory.nftFactory().getBalances(from, _tokenIds);
    }

    function getAmounts(address from) external view returns (Amounts[] memory result) {
        (uint256[] memory ids, uint256[] memory amounts) = factory.nftFactory().getBalances(from, _tokenIds);
        result = new Amounts[](ids.length);
        for (uint i = 0; i < ids.length; i++) {
            result[i] = Amounts({Id: uint32(ids[i]), Balance: uint64(amounts[i])});
        }
    }
}
