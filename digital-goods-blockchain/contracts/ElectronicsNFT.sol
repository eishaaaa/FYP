// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ElectronicsNFT
 * @dev ERC721 contract for electronic goods authentication with Role-Based Access Control
 * @notice Includes Fraud Prevention (Blacklist) and Verifier Management
 */
contract ElectronicsNFT is ERC721URIStorage, AccessControl, ReentrancyGuard {
    
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant VENDOR_ROLE = keccak256("VENDOR_ROLE");
    bytes32 public constant RETAILER_ROLE = keccak256("RETAILER_ROLE");

    enum DeviceStatus { InTransit, InStock, Sold }

    uint256 private _tokenIds;

    struct ElectronicDevice {
        string brand;
        string model;
        string serialNumber;
        string warrantyExpiry;
        uint256 mintedAt;
        address originalOwner;
        bool isVerified;
        DeviceStatus status;
        uint256 ownerCount;
    }

    // tokenId => device
    mapping(uint256 => ElectronicDevice) private devices;
    // serialNumber => tokenId
    mapping(string => uint256) private serialToTokenId;
    // tokenId => reviewer => reviewed
    mapping(uint256 => mapping(address => bool)) private hasReviewed;
    
    // --- FRAUD PREVENTION: Blacklist for stolen serial numbers ---
    mapping(string => bool) public blacklistedSerials;

    /* ================= EVENTS ================= */

    event DeviceMinted(
        uint256 indexed tokenId,
        address indexed owner,
        string serialNumber,
        string tokenURI
    );
    event DeviceVerified(uint256 indexed tokenId, address indexed verifier);
    event ReviewSubmitted(
        uint256 indexed tokenId,
        address indexed reviewer,
        bytes32 reviewHash
    );
    // New Event for Fraud Reporting
    event DeviceBlacklisted(string indexed serialNumber, address indexed reporter);

    /* ================ CONSTRUCTOR ================ */

    constructor() ERC721("Digital Goods Electronics", "DGE") {
        // Grant the deployer the default admin and verifier roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VERIFIER_ROLE, msg.sender);
    }

    /* ================= ADMIN & SECURITY ================= */

    /**
     * @dev Report a serial number as stolen. Prevents it from being minted.
     * Only callable by Verifiers (Manufacturers/Admins).
     */
    function reportStolen(string memory serialNumber) external onlyRole(VERIFIER_ROLE) {
        require(bytes(serialNumber).length > 0, "Invalid serial");
        require(!blacklistedSerials[serialNumber], "Already blacklisted");
        
        blacklistedSerials[serialNumber] = true;
        emit DeviceBlacklisted(serialNumber, msg.sender);
    }

    /**
     * @dev Add a new verifier (e.g., a new Manufacturer or Official Store).
     */
    function addVerifier(address verifier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(VERIFIER_ROLE, verifier);
    }

    /**
     * @dev Remove a verifier.
     */
    function removeVerifier(address verifier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(VERIFIER_ROLE, verifier);
    }

    function addVendor(address vendor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(VENDOR_ROLE, vendor);
    }

    function addRetailer(address retailer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(RETAILER_ROLE, retailer);
    }

    /* ================= MINT ================= */

    function mintElectronic(
        address to,
        string memory serialNumber,
        string memory brand,
        string memory model,
        string memory warrantyExpiry,
        string memory tokenURI
    ) external nonReentrant returns (uint256) {
        require(to != address(0), "Invalid address");
        require(bytes(serialNumber).length > 0, "Serial required");
        // Check Blacklist
        require(!blacklistedSerials[serialNumber], "Device reported stolen/blacklisted");
        // Check Duplicate
        require(serialToTokenId[serialNumber] == 0, "Device already registered");

        _tokenIds++;
        uint256 newTokenId = _tokenIds;
        devices[newTokenId] = ElectronicDevice({
            brand: brand,
            model: model,
            serialNumber: serialNumber,
            warrantyExpiry: warrantyExpiry,
            mintedAt: block.timestamp,
            originalOwner: to,
            isVerified: false,
            status: DeviceStatus.InTransit,
            ownerCount: 0
        });

        serialToTokenId[serialNumber] = newTokenId;

        _safeMint(to, newTokenId);
        _setTokenURI(newTokenId, tokenURI);

        emit DeviceMinted(newTokenId, to, serialNumber, tokenURI);
        return newTokenId;
    }

    /* ================= VERIFY ================= */

    // Only accounts with VERIFIER_ROLE can verify (e.g., Manufacturer or Admin)
    function verifyDevice(uint256 tokenId) external onlyRole(VERIFIER_ROLE) {
        require(_ownerOf(tokenId) != address(0), "Token not found");
        require(!devices[tokenId].isVerified, "Already verified");

        devices[tokenId].isVerified = true;
        emit DeviceVerified(tokenId, msg.sender);
    }

    /* ================= REVIEWS ================= */

    function submitReview(uint256 tokenId, bytes32 reviewHash) external {
        require(_ownerOf(tokenId) != address(0), "Token not found");
        // Ensure user hasn't reviewed this specific device before
        require(!hasReviewed[tokenId][msg.sender], "Already reviewed");
        hasReviewed[tokenId][msg.sender] = true;
        emit ReviewSubmitted(tokenId, msg.sender, reviewHash);
    }

    /* ================= READ ================= */

    function getDevice(uint256 tokenId)
        external
        view
        returns (ElectronicDevice memory)
    {
        require(_ownerOf(tokenId) != address(0), "Token not found");
        return devices[tokenId];
    }

    function getDeviceBySerial(string memory serialNumber)
        external
        view
        returns (ElectronicDevice memory)
    {
        uint256 tokenId = serialToTokenId[serialNumber];
        require(tokenId != 0, "Device not found");
        return devices[tokenId];
    }

    function isDeviceVerified(uint256 tokenId)
        external
        view
        returns (bool)
    {
        if (_ownerOf(tokenId) == address(0)) return false;
        return devices[tokenId].isVerified;
    }

    function totalMinted() external view returns (uint256) {
        return _tokenIds;
    }

    // Required override by Solidity for multiple inheritance
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address previousOwner = super._update(to, tokenId, auth);
        
        if (previousOwner != address(0) && to != address(0)) {
            if (hasRole(RETAILER_ROLE, previousOwner) && !hasRole(RETAILER_ROLE, to) && !hasRole(VENDOR_ROLE, to) && !hasRole(VERIFIER_ROLE, to)) {
                devices[tokenId].status = DeviceStatus.Sold;
                devices[tokenId].ownerCount = 1;
            } else if (devices[tokenId].status == DeviceStatus.Sold) {
                if (hasRole(RETAILER_ROLE, to)) {
                    devices[tokenId].status = DeviceStatus.InStock;
                } else {
                    devices[tokenId].ownerCount += 1;
                }
            } else if (hasRole(VERIFIER_ROLE, previousOwner) && hasRole(VENDOR_ROLE, to)) {
                devices[tokenId].status = DeviceStatus.InTransit;
            } else if (hasRole(VENDOR_ROLE, previousOwner) && hasRole(RETAILER_ROLE, to)) {
                devices[tokenId].status = DeviceStatus.InStock;
            }
        }
        return previousOwner;
    }
}