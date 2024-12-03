// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseFactory.sol";
import "../library/UtilLib.sol";

contract Store is BaseFactory {
    using UtilLib for *;

    event Buy(address indexed account, uint256 tokenId, uint256 quantity, uint256 amount);

    struct ListingData {
        bool Active;
        uint256 TokenId;
        uint256 Supply;
        uint256 Sold;
        uint256 Price;
    }

    // Sales
    ListingData[] private _sales;

    // _indexMap[tokenId]-1 give target index
    mapping(uint256 => uint256) private _indexMap;

    constructor(IContractFactory _factory) BaseFactory(_factory) {}

    function _offset(uint256 id) private view returns (uint256 pos) {
        id.throwIfZero();
        pos = _indexMap[id];
        if (pos == 0) {
            revert TokenNotExists(id);
        }
        unchecked {
            pos--;
        }
    }

    function removeToken(uint256 tokenId) external onlyRole(MANAGER_ROLE) {
        require(tokenId > 0, "tokenId");
        uint256 index = _offset(tokenId);
        uint256 lastIndex = _sales.length - 1;
        if (lastIndex != index) {
            _sales[index] = _sales[lastIndex];
        }
        _sales.pop();
        _indexMap[tokenId] = 0;
    }

    function removeAll() external onlyRole(MANAGER_ROLE) {
        for (uint i = 0; i < _sales.length; i++) {
            _indexMap[_sales[i].TokenId] = 0;
        }
        delete _sales;
    }

    function add(ListingData[] calldata inputs) external onlyRole(MANAGER_ROLE) {
        for (uint256 i = 0; i < inputs.length; i++) {
            ListingData memory input = inputs[i];

            require(input.TokenId > 0, "TokenId");
            require(input.Supply > 0, "Supply");
            require(input.Price > 0.00000001 ether, "Price");
            require(_indexMap[input.TokenId] == 0, "TokenId Exists");

            _sales.push(ListingData({Active: input.Active, TokenId: input.TokenId, Supply: input.Supply, Sold: input.Sold, Price: input.Price}));
            _indexMap[input.TokenId] = _sales.length;
        }
    }

    function setStatus(uint256[] calldata ids, bool[] calldata values) external onlyRole(MANAGER_ROLE) {
        require(ids.length <= _sales.length && ids.length == values.length, "overflow");
        for (uint i = 0; i < ids.length; i++) {
            _sales[_offset(ids[i])].Active = values[i];
        }
    }

    function setPrices(uint256[] calldata ids, uint256[] calldata values) external onlyRole(MANAGER_ROLE) {
        require(ids.length <= _sales.length && ids.length == values.length, "overflow");
        for (uint i = 0; i < ids.length; i++) {
            require(values[i] > 0.00000001 ether, "Price");
            _sales[_offset(ids[i])].Price = values[i];
        }
    }

    function buy(uint256 tokenId, uint8 quantity) external whenNotPaused nonReentrant {
        address sender = msg.sender;
        quantity.throwIfZero();

        ListingData storage list = _sales[_offset(tokenId)];
        require(list.Active, "Sale not active");
        uint256 remain = list.Supply - list.Sold;
        require(quantity <= remain, "Not enough supply");

        uint256 price = list.Price * quantity;
        require(price > 0, "Price");
        if (factory.planetToken().balanceOf(sender) < price) {
            revert InsufficientBalance();
        }

        list.Sold += quantity;
        if (list.Sold == list.Supply) {
            list.Active = false;
        }

        factory.planetToken().operatorBurn(sender, price);
        factory.playerManager().onRefExists(sender, price);
        factory.nftFactory().operatorMint(sender, tokenId, quantity, "");

        emit Buy(sender, tokenId, quantity, price);
    }

    function count() external view returns (uint256) {
        return _sales.length;
    }

    function get(uint256 tokenId) external view returns (ListingData memory) {
        return _sales[_offset(tokenId)];
    }

    function getPrice(uint256 tokenId) external view returns (uint256) {
        return _sales[_offset(tokenId)].Price;
    }

    function getAll() external view returns (ListingData[] memory) {
        return _sales;
    }

    function getRange(uint256 tokenIdMin, uint256 tokenIdMax) external view returns (ListingData[] memory result) {
        require(tokenIdMin > 0, "tokenIdMin");
        require(tokenIdMax > 0, "tokenIdMax");
        ListingData[] memory buffer = new ListingData[](_sales.length);
        uint32 index;
        for (uint i = 0; i < _sales.length; i++) {
            ListingData storage item = _sales[i];
            if (item.TokenId >= tokenIdMin && item.TokenId <= tokenIdMax) {
                buffer[index] = item;
                index++;
            }
        }
        result = new ListingData[](index);
        for (uint i = 0; i < index; i++) {
            result[i] = buffer[i];
        }
    }

    function listings(uint8 dataCount, uint256 startIndex) external view returns (ListingData[] memory result, uint256 nextIndex) {
        uint256 len = _sales.length;
        if (len == 0) {
            return (new ListingData[](0), 0);
        }

        require(startIndex < len, "to big startIndex");
        uint256 index;
        uint256 maxCount = len - startIndex;
        if (maxCount < dataCount) {
            dataCount = uint8(maxCount);
        }

        result = new ListingData[](dataCount);
        do {
            result[index] = _sales[startIndex];
            index++;
            startIndex++;
        } while (startIndex < len && index < dataCount);

        nextIndex = startIndex;
        if (nextIndex >= len) {
            nextIndex = 0;
        }
    }
}
