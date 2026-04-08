// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {Pausable} from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";
import {ERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "lib/openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

/// @title MockAXIE
/// @notice Lightweight ERC721 mock for Sepolia marketplace/frontend POC.
/// @dev Intentionally mirrors only the externally relevant Axie surface.
contract MockAXIE is ERC721Enumerable, AccessControl, Pausable {
    struct Gene {
        uint256 x;
        uint256 y;
    }

    struct AxieData {
        uint256 sireId;
        uint256 matronId;
        uint256 birthDate;
        Gene genes;
        uint8 breedCount;
        uint16 level;
    }

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant SEEDER_ROLE = keccak256("SEEDER_ROLE");

    uint8 public constant STAGE_EGG = 0;
    uint8 public constant STAGE_ADULT = 1;

    string internal _baseTokenURI;
    uint256 public currentAxieId;

    mapping(uint256 => AxieData) internal _axies;
    mapping(uint256 => uint8) internal _stage;

    error MockAXIE__ArrayLengthMismatch();
    error MockAXIE__NotEgg(uint256 axieId);

    constructor() ERC721("MockAXIE", "mAXIE") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _baseTokenURI = "https://metadata.axieinfinity.com/axie/";
    }

    function baseTokenURI() external view returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseTokenURI(string calldata newBaseTokenURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = newBaseTokenURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return string.concat(_baseTokenURI, Strings.toString(tokenId));
    }

    function axie(uint256 axieId)
        external
        view
        returns (uint256 sireId, uint256 matronId, uint256 birthDate, Gene memory genes, uint8 breedCount, uint16 level)
    {
        _requireOwned(axieId);
        AxieData storage data = _axies[axieId];
        return (data.sireId, data.matronId, data.birthDate, data.genes, data.breedCount, data.level);
    }

    function getAxie(uint256 axieId) external view returns (AxieData memory) {
        _requireOwned(axieId);
        return _axies[axieId];
    }

    function mintAxie(address to, AxieData calldata data) external onlyRole(MINTER_ROLE) returns (uint256 axieId) {
        axieId = currentAxieId + 1;
        _mintWithId(to, axieId, data);
    }

    function mintAxieWithId(address to, uint256 axieId, AxieData calldata data) external onlyRole(MINTER_ROLE) {
        _mintWithId(to, axieId, data);
    }

    function batchMintAxiesWithIds(address to, uint256[] calldata ids, AxieData[] calldata data)
        external
        onlyRole(MINTER_ROLE)
    {
        if (ids.length != data.length) revert MockAXIE__ArrayLengthMismatch();
        for (uint256 i = 0; i < ids.length; i++) {
            _mintWithId(to, ids[i], data[i]);
        }
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function stageOf(uint256 axieId) external view returns (uint8) {
        _requireOwned(axieId);
        return _stage[axieId];
    }

    function growAxieggToAdult(uint256 axieId) external {
        _checkRoleOrAdmin(SEEDER_ROLE, msg.sender);
        _requireOwned(axieId);
        if (_stage[axieId] != STAGE_EGG) revert MockAXIE__NotEgg(axieId);
        _stage[axieId] = STAGE_ADULT;
    }

    function setAxieLevel(uint256 axieId, uint16 level) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _requireOwned(axieId);
        _axies[axieId].level = level;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _mintWithId(address to, uint256 axieId, AxieData calldata data) internal {
        _safeMint(to, axieId);
        _axies[axieId] = data;
        _stage[axieId] = STAGE_ADULT;
        if (axieId > currentAxieId) {
            currentAxieId = axieId;
        }
    }

    function _checkRoleOrAdmin(bytes32 role, address account) internal view {
        if (!hasRole(role, account) && !hasRole(DEFAULT_ADMIN_ROLE, account)) {
            revert AccessControlUnauthorizedAccount(account, role);
        }
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721Enumerable)
        whenNotPaused
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721Enumerable) {
        super._increaseBalance(account, value);
    }
}
