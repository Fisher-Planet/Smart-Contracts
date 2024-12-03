// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../general/BaseFactory.sol";
import "../library/UtilLib.sol";
import "../library/ArrayLib.sol";

contract NftMarket is BaseFactory, INftMarket {
    using UtilLib for *;
    using ArrayLib for uint256[];

    error SaleExists(uint256 id);

    event Add(address indexed from, uint256 id, uint256 amount);
    event Update(address indexed from, uint256 id, uint256 amount);
    event Remove(address indexed from, uint256 id, uint256 amount);
    event RemoveAll(address indexed from, uint256[] id, uint256[] amount);
    event Buy(address indexed buyer, address indexed seller, uint256 id, uint256 amount);

    struct ListingData {
        uint32 TokenId;
        uint32 Quantity;
        uint64 EndTime;
        uint64 RemainTime;
        address Owner;
        uint256 Price;
        uint256 ListId;
    }

    struct InputArgs {
        uint32 Quantity;
        uint32 Duration;
        uint256 Price;
        uint256 Id; // when add method call then value must be tokenId when update then listid !
    }

    struct IdInfo {
        bool Exists;
        uint32 TokenId;
        uint32 TotalList;
    }

    uint8 private constant _MAX_LIST_PER_ACCOUNT = 16;

    // default market fee : 10 %
    uint16 private _fee = 1000;

    // list id
    uint256 private _listIdCounter;

    //_listings[listId] = target list
    mapping(uint256 => ListingData) private _listing;

    //_accountListIds[account] = owner listid array
    mapping(address => uint256[]) private _accountListIds;

    constructor(IContractFactory _factory) BaseFactory(_factory) {}

    function onERC1155Received(address, address, uint256, uint256, bytes memory) public pure returns (bytes4) {
        return 0xf23a6e61;
    }

    function onERC1155BatchReceived(address, address, uint256[] memory, uint256[] memory, bytes memory) public pure returns (bytes4) {
        return 0xbc197c81;
    }

    function setFee(uint16 fee) external onlyRole(MANAGER_ROLE) {
        require(fee > 0 && fee < 81, "invalid fee");
        _fee = fee * 100;
    }

    function getFee() public view returns (uint16) {
        return _fee / 100;
    }

    function _getCurrentTime() private view returns (uint64) {
        return uint64(block.timestamp + 10 minutes);
    }

    function _checkThis(InputArgs calldata input) private pure {
        require(input.Id > 0, "Id");
        require(input.Quantity > 0, "Quantity");
        require(input.Duration > 0 && input.Duration < 8, "Duration invalid.");
        require(input.Price >= 0.00001 ether, "Price min 0.00001");
    }

    function _removeListing(uint256 listId, address account) private {
        uint256[] storage ids = _accountListIds[account];
        (bool found, uint256 index) = ids.getIndex(listId);
        require(found, "listId index not found");

        uint256 lastIndex = ids.length - 1;
        if (lastIndex != index) {
            ids[index] = ids[lastIndex];
        }
        ids.pop();

        _listing[listId].ListId = 0;
    }

    function _exists(ListingData storage listing) private view {
        require(listing.ListId > 0, "Listing not found");
        require(listing.Owner != address(0), "No Owner");
    }

    function _validate(ListingData storage listing, address owner) private view {
        _exists(listing);
        require(owner != address(0), "owner:0x");
        require(listing.Owner == owner, "Wrong owner");
    }

    function _formatData(ListingData storage listing) private view returns (ListingData memory result) {
        result = listing;
        result.RemainTime = result.EndTime.remainTime();
    }

    function _isTokenExists(uint256[] storage listIds, uint256 tokenId) private view returns (bool) {
        for (uint i = 0; i < listIds.length; i++) {
            if (_listing[listIds[i]].TokenId == tokenId) {
                return true;
            }
        }
        return false;
    }

    function isTokenExists(address from, uint256 tokenId) external view returns (bool tokenExists, bool limitReached) {
        from.throwIfEmpty();
        tokenId.throwIfZero();
        uint256[] storage accountListIds = _accountListIds[from];
        tokenExists = _isTokenExists(accountListIds, tokenId);
        limitReached = accountListIds.length == _MAX_LIST_PER_ACCOUNT;
    }

    // input.Id must be tokenId
    function add(InputArgs calldata input) external whenNotPaused nonReentrant {
        _checkThis(input);

        address sender = msg.sender;

        // check nft balance
        INftFactory nftFactory = factory.nftFactory();
        uint256 balance = nftFactory.balanceOf(sender, input.Id);
        if (input.Quantity > balance) {
            revert InsufficientBalance();
        }

        // check limits
        uint256[] storage accountListIds = _accountListIds[sender];
        require(accountListIds.length < _MAX_LIST_PER_ACCOUNT, "Max List limit reached");

        // check if some tokenid exist then revert. cuz need update
        if (_isTokenExists(accountListIds, input.Id)) {
            revert SaleExists(input.Id);
        }

        _listIdCounter += 1;
        uint256 listId = _listIdCounter;

        accountListIds.push(listId);

        ListingData storage listing = _listing[listId];
        require(listing.ListId == 0, "listfull");

        listing.TokenId = uint32(input.Id);
        listing.Quantity = input.Quantity;
        listing.EndTime = input.Duration.createEndTime(1 days);
        listing.Owner = sender;
        listing.Price = input.Price;
        listing.ListId = listId;

        nftFactory.operatorTransfer(sender, address(this), input.Id, input.Quantity, "");

        emit Add(sender, input.Id, input.Quantity);
    }

    // input.Id must be listId
    function update(InputArgs calldata input) external whenNotPaused nonReentrant {
        _checkThis(input);
        address sender = msg.sender;

        ListingData storage listing = _listing[input.Id];
        _validate(listing, sender);

        listing.EndTime = input.Duration.createEndTime(1 days);

        if (listing.Price != input.Price) {
            listing.Price = input.Price;
        }

        uint256 tokenId = listing.TokenId;
        uint256 currentQuantity = listing.Quantity;

        INftFactory nftFactory = factory.nftFactory();
        if (input.Quantity != currentQuantity) {
            // transfer nft to owner
            nftFactory.safeTransferFrom(address(this), sender, tokenId, currentQuantity, "");

            // check new balance
            uint256 balance = nftFactory.balanceOf(sender, tokenId);
            if (input.Quantity > balance) {
                revert InsufficientBalance();
            }

            // update new balance
            listing.Quantity = input.Quantity;

            // transfer nft to here
            nftFactory.operatorTransfer(sender, address(this), tokenId, input.Quantity, "");

            emit Update(sender, tokenId, input.Quantity);
        }
    }

    function remove(uint256 listId) external whenNotPaused nonReentrant {
        address sender = msg.sender;

        ListingData storage listing = _listing[listId];
        _validate(listing, sender);

        uint256 quantity = listing.Quantity;
        uint256 tokenId = listing.TokenId;

        // remove listing
        _removeListing(listId, sender);

        // transfer nft to owner
        factory.nftFactory().safeTransferFrom(address(this), sender, tokenId, quantity, "");

        // send event
        emit Remove(sender, tokenId, quantity);
    }

    function removeAll() external whenNotPaused nonReentrant {
        address sender = msg.sender;
        uint256[] storage ids = _accountListIds[sender];
        require(ids.length > 0, "No listing");

        uint256[] memory all_Ids = new uint256[](ids.length);
        uint256[] memory all_amounts = new uint256[](ids.length);
        for (uint i = 0; i < ids.length; i++) {
            ListingData storage listing = _listing[ids[i]];
            all_Ids[i] = listing.TokenId;
            all_amounts[i] = listing.Quantity;
            listing.ListId = 0;
        }

        // remove all listIds from sender
        delete _accountListIds[sender];

        // transfer nft to owner
        factory.nftFactory().operatorTransferBatch(address(this), sender, all_Ids, all_amounts, "");

        // send event
        emit RemoveAll(sender, all_Ids, all_amounts);
    }

    function buy(uint256 listId, uint32 quantity) external whenNotPaused nonReentrant {
        address buyer = msg.sender;
        buyer.throwIfEmpty();

        require(quantity > 0, "quantity");

        ListingData storage listing = _listing[listId];
        _exists(listing);
        require(listing.Owner != buyer, "Same owner");

        address seller = listing.Owner;
        uint32 sellerQuantity = listing.Quantity;

        require(sellerQuantity >= quantity, "Quantity to much");
        require(listing.EndTime > block.timestamp, "Time Out");

        sellerQuantity -= quantity;
        uint256 amount = listing.Price * quantity;
        uint32 tokenId = listing.TokenId;

        if (sellerQuantity == 0) {
            // remove listing from seller
            _removeListing(listId, seller);
        } else {
            listing.Quantity = sellerQuantity;
        }

        (uint256 fee, uint256 remain) = amount.calcShares(_fee);

        factory.farmingToken().operatorTransfer(buyer, seller, remain);
        factory.farmingToken().operatorBurn(buyer, fee);
        factory.nftFactory().safeTransferFrom(address(this), buyer, tokenId, quantity, "");

        emit Buy(buyer, seller, tokenId, quantity);
    }

    function currentId() public view returns (uint256) {
        return _listIdCounter;
    }

    function getListing(uint256 listId) public view returns (ListingData memory result) {
        ListingData storage listing = _listing[listId];
        _exists(listing);
        result = _formatData(listing);
    }

    function getIdsFrom(address from) external view returns (uint256[] memory result) {
        from.throwIfEmpty();
        result = _accountListIds[from];
    }

    function getListFrom(address from) external view returns (ListingData[] memory result) {
        from.throwIfEmpty();
        uint256[] storage ids = _accountListIds[from];
        uint256 len = ids.length;
        if (len == 0) {
            return result;
        }
        result = new ListingData[](len);
        unchecked {
            for (uint i = 0; i < len; i++) {
                result[i] = _formatData(_listing[ids[i]]);
            }
        }
    }

    // start id must be 1 then use nextId and data count like 16
    function _listingFetch(uint8 dataCount, uint256 startId, uint32 tokenId) private view returns (ListingData[] memory, uint256) {
        uint256 totalList = _listIdCounter;

        // there is no any listing
        if (totalList == 0) {
            return (new ListingData[](0), 0);
        }

        // startId must be small or equal
        require(startId <= totalList, "to big startId");
        bool isTokenSearch = tokenId > 0;
        uint256[] memory buffer = new uint256[](dataCount);
        uint256 index;
        uint64 currentTime = _getCurrentTime();
        unchecked {
            while (startId <= totalList && index < dataCount) {
                ListingData storage item = _listing[startId];
                if (item.ListId > 0 && item.EndTime > currentTime) {
                    if (!isTokenSearch) {
                        buffer[index] = item.ListId;
                        index++;
                    } else if (item.TokenId == tokenId) {
                        buffer[index] = item.ListId;
                        index++;
                    }
                }
                startId++;
            }
        }

        // next id must be small or equal
        if (startId > totalList) {
            startId = 0;
        }

        // now our buffer maybe have empty rows so need clear
        ListingData[] memory result = new ListingData[](index);
        unchecked {
            for (uint i = 0; i < index; i++) {
                result[i] = _formatData(_listing[buffer[i]]);
            }
        }

        return (result, startId);
    }

    function listingFetchAll(uint8 dataCount, uint256 startId) external view returns (ListingData[] memory result, uint256 nextId) {
        return _listingFetch(dataCount, startId, 0);
    }

    function listingFetchByTokenId(uint8 dataCount, uint256 startId, uint32 tokenId) external view returns (ListingData[] memory result, uint256 nextId) {
        require(tokenId > 0, "tokenId");
        return _listingFetch(dataCount, startId, tokenId);
    }

    function listingTokenIds(IdInfo[] memory tokenIds) external view returns (IdInfo[] memory result) {
        require(tokenIds.length > 0, "tokenIds");
        uint256 totalList = _listIdCounter;
        uint64 currentTime = _getCurrentTime();

        unchecked {
            for (uint listId = 1; listId <= totalList; listId++) {
                ListingData storage item = _listing[listId];
                if (item.ListId > 0 && item.EndTime > currentTime) {
                    for (uint i = 0; i < tokenIds.length; i++) {
                        if (tokenIds[i].TokenId == item.TokenId) {
                            tokenIds[i].Exists = true;
                            tokenIds[i].TotalList += 1;
                            break;
                        }
                    }
                }
            }
        }
        return tokenIds;
    }
}
