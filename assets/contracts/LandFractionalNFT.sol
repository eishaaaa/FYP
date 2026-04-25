// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title LandFractionalNFT
 * @dev ERC-1155 contract for fractionalized land ownership with Escrow capabilities
 * @notice Updated with Timestamped Events for Notification Support
 */
contract LandFractionalNFT is ERC1155, ERC1155Holder, Ownable, ReentrancyGuard {
    
    uint256 private _propertyIds;

    struct LandProperty {
        string location;
        string city;
        uint256 totalArea; // in marlas or kanals
        string areaUnit;   // "marla" or "kanal"
        uint256 totalFractions;
        uint256 pricePerFraction;
        uint256 createdAt;
        address payable originalOwner; // Marked payable to receive funds
        string ipfsMetadata;
        bool isVerified;
    }

    // Mapping from property ID to land details
    mapping(uint256 => LandProperty) public properties;
    // Mapping to track rent distribution per property
    mapping(uint256 => uint256) public rentPool;
    // Mapping to track claimed rent per user per property
    mapping(uint256 => mapping(address => uint256)) public claimedRent;

    // Events
    event PropertyCreated(
        uint256 indexed propertyId,
        address indexed owner,
        uint256 totalFractions,
        string location
    );
    event FractionPurchased(
        uint256 indexed propertyId,
        address indexed buyer,
        uint256 amount
    );
    // Updated: Added timestamp
    event RentDistributed(
        uint256 indexed propertyId,
        uint256 totalAmount,
        uint256 timestamp
    );
    // Updated: Added timestamp
    event RentClaimed(
        uint256 indexed propertyId,
        address indexed claimer,
        uint256 amount,
        uint256 timestamp
    );
    event PropertyVerified(uint256 indexed propertyId);

    constructor() ERC1155("https://ipfs.io/ipfs/{id}.json") Ownable(msg.sender) {}

    /**
     * @dev Create a new fractionalized land property.
     * Mints tokens to the CONTRACT address (Escrow) so they can be sold automatically.
     */
    function createProperty(
        string memory location,
        string memory city,
        uint256 totalArea,
        string memory areaUnit,
        uint256 totalFractions,
        uint256 pricePerFraction,
        string memory ipfsMetadata
    ) public nonReentrant returns (uint256) {
        require(totalFractions > 0, "Fractions must be > 0");
        require(totalArea > 0, "Area must be > 0");
        require(pricePerFraction > 0, "Price must be > 0");
        
        _propertyIds += 1;
        uint256 newPropertyId = _propertyIds;

        properties[newPropertyId] = LandProperty({
            location: location,
            city: city,
            totalArea: totalArea,
            areaUnit: areaUnit,
            totalFractions: totalFractions,
            pricePerFraction: pricePerFraction,
            createdAt: block.timestamp,
            originalOwner: payable(msg.sender),
            ipfsMetadata: ipfsMetadata,
            isVerified: false
        });

        // Mint all fractions to the CONTRACT (Escrow) instead of msg.sender
        // This allows the contract to facilitate sales without user approval steps
        _mint(address(this), newPropertyId, totalFractions, "");
        emit PropertyCreated(newPropertyId, msg.sender, totalFractions, location);

        return newPropertyId;
    }

    /**
     * @dev Purchase fractions of a property from the contract escrow
     */
    function purchaseFractions(uint256 propertyId, uint256 amount) 
        public 
        payable 
        nonReentrant 
    {
        LandProperty memory property = properties[propertyId];
        require(property.createdAt > 0, "Property does not exist");
        require(amount > 0, "Amount must be > 0");
        // Check availability in contract escrow
        require(balanceOf(address(this), propertyId) >= amount, "Not enough fractions available");

        uint256 totalCost = property.pricePerFraction * amount;
        require(msg.value >= totalCost, "Insufficient payment");

        // Transfer tokens from Contract to Buyer
        _safeTransferFrom(address(this), msg.sender, propertyId, amount, "");

        // Send payment to the Original Owner
        (bool success, ) = property.originalOwner.call{value: totalCost}("");
        require(success, "Transfer to seller failed");

        // Refund excess payment to buyer
        if (msg.value > totalCost) {
            payable(msg.sender).transfer(msg.value - totalCost);
        }

        emit FractionPurchased(propertyId, msg.sender, amount);
    }

    /**
     * @dev Distribute rent to property (Anyone can pay rent, usually the occupant)
     */
    function distributeRent(uint256 propertyId) public payable nonReentrant {
        require(properties[propertyId].createdAt > 0, "Property does not exist");
        require(msg.value > 0, "Rent amount must be > 0");

        rentPool[propertyId] += msg.value;
        // Emit event with timestamp
        emit RentDistributed(propertyId, msg.value, block.timestamp);
    }

    /**
     * @dev Claim proportional rent based on fraction ownership
     */
    function claimRent(uint256 propertyId) public nonReentrant {
        LandProperty memory property = properties[propertyId];
        require(property.createdAt > 0, "Property does not exist");

        uint256 userFractions = balanceOf(msg.sender, propertyId);
        require(userFractions > 0, "No fractions owned");

        uint256 totalRent = rentPool[propertyId];
        require(totalRent > 0, "No rent available");

        // Calculate proportional rent
        uint256 userRent = (totalRent * userFractions) / property.totalFractions;
        uint256 unclaimedRent = userRent - claimedRent[propertyId][msg.sender];
        
        require(unclaimedRent > 0, "No unclaimed rent");

        claimedRent[propertyId][msg.sender] += unclaimedRent;
        payable(msg.sender).transfer(unclaimedRent);

        // Emit event with timestamp
        emit RentClaimed(propertyId, msg.sender, unclaimedRent, block.timestamp);
    }

    /**
     * @dev Verify property authenticity (admin only)
     */
    function verifyProperty(uint256 propertyId) public onlyOwner {
        require(properties[propertyId].createdAt > 0, "Property does not exist");
        require(!properties[propertyId].isVerified, "Already verified");

        properties[propertyId].isVerified = true;
        emit PropertyVerified(propertyId);
    }

    /**
     * @dev Get property details
     */
    function getProperty(uint256 propertyId) 
        public 
        view 
        returns (LandProperty memory) 
    {
        require(properties[propertyId].createdAt > 0, "Property does not exist");
        return properties[propertyId];
    }

    /**
     * @dev Get unclaimed rent for a user
     */
    function getUnclaimedRent(uint256 propertyId, address user) 
        public 
        view 
        returns (uint256) 
    {
        LandProperty memory property = properties[propertyId];
        if (property.createdAt == 0) return 0;

        uint256 userFractions = balanceOf(user, propertyId);
        if (userFractions == 0) return 0;

        uint256 totalRent = rentPool[propertyId];
        uint256 userRent = (totalRent * userFractions) / property.totalFractions;
        
        return userRent - claimedRent[propertyId][user];
    }

    function getTotalProperties() public view returns (uint256) {
        return _propertyIds;
    }

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    // Required for ERC1155Holder to receive tokens
    function supportsInterface(bytes4 interfaceId) 
        public 
        view 
        virtual 
        override(ERC1155, ERC1155Holder) 
        returns (bool) 
    {
        return super.supportsInterface(interfaceId);
    }
}