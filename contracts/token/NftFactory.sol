// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../general/BaseControl.sol";
import "../interfaces/INftFactory.sol";

contract NftFactory is ERC1155, BaseControl, INftFactory {
    using Strings for uint256;

    constructor() ERC1155("") {}

    function supportsInterface(bytes4 interfaceId) public view override(AccessControl, ERC1155, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function uri(uint256 tokenId) public view virtual override returns (string memory) {
        string memory _uri = super.uri(tokenId);
        return bytes(_uri).length > 0 ? string(abi.encodePacked(_uri, tokenId.toString(), ".json")) : "";
    }

    function operatorTransfer(address from, address to, uint256 id, uint256 amount, bytes calldata data) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        super._safeTransferFrom(from, to, id, amount, data);
    }

    function operatorTransferBatch(address from, address to, uint256[] calldata ids, uint256[] calldata amounts, bytes calldata data) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        super._safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    function operatorMint(address to, uint256 id, uint256 amount, bytes calldata data) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        super._mint(to, id, amount, data);
    }

    function operatorMintBatch(address to, uint256[] calldata ids, uint256[] calldata amounts, bytes calldata data) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        super._mintBatch(to, ids, amounts, data);
    }

    function operatorBurn(address from, uint256 id, uint256 amount) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        super._burn(from, id, amount);
    }

    function operatorBurnBatch(address from, uint256[] calldata ids, uint256[] calldata amounts) public onlyRole(OPERATOR_ROLE) whenNotPaused {
        super._burnBatch(from, ids, amounts);
    }

    function getBalances(address from, uint256[] calldata tokenIds) public view returns (uint256[] memory ids, uint256[] memory amounts) {
        require(from != address(0), "from");
        require(tokenIds.length > 0, "tokenIds");

        uint256[] memory tempIds = new uint256[](tokenIds.length);
        uint256[] memory tempAms = new uint256[](tokenIds.length);
        uint256 index;

        unchecked {
            for (uint i = 0; i < tokenIds.length; i++) {
                uint256 _balance = balanceOf(from, tokenIds[i]);
                if (_balance > 0) {
                    tempIds[index] = tokenIds[i];
                    tempAms[index] = _balance;
                    index++;
                }
            }

            ids = new uint256[](index);
            amounts = new uint256[](index);
            for (uint i = 0; i < index; i++) {
                ids[i] = tempIds[i];
                amounts[i] = tempAms[i];
            }
        }
    }
}
