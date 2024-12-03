// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./BaseFactory.sol";
import "../interfaces/IBaseFungible.sol";

abstract contract BaseFungible is BaseFactory, IBaseFungible {
    // all tokenIds
    uint256[] internal _tokenIds;

    // _indexMap[tokenId]-1 give target index
    mapping(uint256 => uint256) private _indexMap;

    constructor(IContractFactory _factory) BaseFactory(_factory) {}

    function _offset(uint256 id) internal view returns (uint256 pos) {
        pos = _indexMap[id];
        if (pos == 0) {
            revert TokenNotExists(id);
        }
        unchecked {
            pos--;
        }
    }

    function addTokenId(uint32 tokenId, uint256 mapPosition) internal {
        _tokenIds.push(tokenId);
        _indexMap[tokenId] = mapPosition;
    }

    function deposit(address from, uint256 id, uint256 amount) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        factory.nftFactory().operatorTransfer(from, address(this), id, amount, "");
    }

    function depositBatch(address from, uint256[] calldata ids, uint256[] calldata amounts) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        factory.nftFactory().operatorTransferBatch(from, address(this), ids, amounts, "");
    }

    function withdraw(address to, uint256 id, uint256 amount) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        factory.nftFactory().operatorTransfer(address(this), to, id, amount, "");
    }

    function withdrawBatch(address to, uint256[] calldata ids, uint256[] calldata amounts) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        factory.nftFactory().operatorTransferBatch(address(this), to, ids, amounts, "");
    }

    function onERC1155Received(address operator, address, uint256, uint256, bytes memory) public view returns (bytes4) {
        if (operator != address(this)) {
            revert NotAllowed();
        }
        return 0xf23a6e61;
    }

    function onERC1155BatchReceived(address operator, address, uint256[] memory, uint256[] memory, bytes memory) public view returns (bytes4) {
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
        return _indexMap[tokenId] > 0;
    }

    function balanceOf(address account, uint256 tokenId) public view returns (uint256) {
        if (_indexMap[tokenId] == 0) {
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
