// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title LandFractionalNFT
 * @dev ERC-1155 contract for fractionalized land ownership with escrow and proportional rent distribution.
 */
contract LandFractionalNFT is ERC1155, ERC1155Holder, Ownable, ReentrancyGuard {

    uint256 private _propertyIds;

    struct LandProperty {
        string  location;
        string  city;
        uint256 totalArea;
        string  areaUnit;
        uint256 totalFractions;
        uint256 pricePerFraction;
        uint256 createdAt;
        address payable originalOwner;
        string  ipfsMetadata;
        bool    isVerified;
        // Rental Fields
        bool    isForRent;
        uint256 monthlyRent;
        address currentTenant;
        address pendingTenant;
    }

    mapping(uint256 => LandProperty)                    public properties;
    mapping(uint256 => uint256)                         public rentPool;
    mapping(uint256 => mapping(address => uint256))     public claimedRent;

    event PropertyCreated(uint256 indexed propertyId, address indexed owner, uint256 totalFractions, string location);
    event FractionPurchased(uint256 indexed propertyId, address indexed buyer, uint256 amount);
    event RentDistributed(uint256 indexed propertyId, uint256 totalAmount, uint256 timestamp);
    event RentClaimed(uint256 indexed propertyId, address indexed claimer, uint256 amount, uint256 timestamp);
    event PropertyVerified(uint256 indexed propertyId);
    event RentalListed(uint256 indexed propertyId, uint256 monthlyRent);
    event RentalRequested(uint256 indexed propertyId, address indexed tenant);
    event RentalAccepted(uint256 indexed propertyId, address indexed tenant);

    constructor() ERC1155("https://ipfs.io/ipfs/{id}.json") Ownable(msg.sender) {}

    /**
     * @dev Create a new property and mint all fractions to the contract for escrow sale.
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
        require(totalFractions > 0,   "Fractions must be > 0");
        require(totalArea > 0,        "Area must be > 0");
        require(pricePerFraction > 0, "Price must be > 0");

        _propertyIds += 1;
        uint256 pid = _propertyIds;

        properties[pid] = LandProperty({
            location:         location,
            city:             city,
            totalArea:        totalArea,
            areaUnit:         areaUnit,
            totalFractions:   totalFractions,
            pricePerFraction: pricePerFraction,
            createdAt:        block.timestamp,
            originalOwner:    payable(msg.sender),
            ipfsMetadata:     ipfsMetadata,
            isVerified:       false,
            isForRent:        false,
            monthlyRent:      0,
            currentTenant:    address(0),
            pendingTenant:    address(0)
        });

        _mint(address(this), pid, totalFractions, "");
        emit PropertyCreated(pid, msg.sender, totalFractions, location);
        return pid;
    }

    /**
     * @dev Buy fractions from the contract. Funds are automatically routed to the original owner.
     */
    function purchaseFractions(uint256 propertyId, uint256 amount)
        public payable nonReentrant
    {
        LandProperty memory p = properties[propertyId];
        require(p.createdAt > 0, "Property does not exist");
        require(amount > 0, "Amount must be > 0");
        require(balanceOf(address(this), propertyId) >= amount, "Not enough fractions");

        uint256 totalCost = p.pricePerFraction * amount;
        require(msg.value >= totalCost, "Insufficient payment");

        _safeTransferFrom(address(this), msg.sender, propertyId, amount, "");

        (bool ok, ) = p.originalOwner.call{value: totalCost}("");
        require(ok, "Payment to owner failed");

        if (msg.value > totalCost) {
            (bool successRefund, ) = payable(msg.sender).call{value: msg.value - totalCost}("");
            require(successRefund, "Refund failed");
        }

        emit FractionPurchased(propertyId, msg.sender, amount);
    }

    /**
     * @dev Add ETH to the rent pool for a specific property.
     */
    function distributeRent(uint256 propertyId) public payable nonReentrant {
        require(properties[propertyId].createdAt > 0, "Property does not exist");
        require(msg.value > 0, "Rent must be > 0");

        rentPool[propertyId] += msg.value;
        emit RentDistributed(propertyId, msg.value, block.timestamp);
    }

    /**
     * @dev Claim accrued rent proportional to owned fractions.
     */
    function claimRent(uint256 propertyId) public nonReentrant {
        LandProperty memory p = properties[propertyId];
        require(p.createdAt > 0, "Property does not exist");
        require(balanceOf(msg.sender, propertyId) > 0, "No fractions owned");

        uint256 unclaimed = _computeUnclaimed(propertyId, msg.sender, p.totalFractions);
        require(unclaimed > 0, "No unclaimed rent");

        // Effects before interaction (CEI Pattern)
        claimedRent[propertyId][msg.sender] += unclaimed;

        (bool ok, ) = payable(msg.sender).call{value: unclaimed}("");
        require(ok, "Rent transfer failed");

        emit RentClaimed(propertyId, msg.sender, unclaimed, block.timestamp);
    }

    /**
     * @dev Returns the amount of rent currently available for a user to claim.
     */
    function getUnclaimedRent(uint256 propertyId, address user)
        public view returns (uint256)
    {
        LandProperty memory p = properties[propertyId];
        if (p.createdAt == 0 || p.totalFractions == 0) return 0;
        return _computeUnclaimed(propertyId, user, p.totalFractions);
    }

    /**
     * @dev Helper to check fractional balance of a user for a property.
     */
    function getUserFractions(uint256 propertyId, address user)
        public view returns (uint256)
    {
        return balanceOf(user, propertyId);
    }

    function getProperty(uint256 propertyId)
        public view returns (LandProperty memory)
    {
        require(properties[propertyId].createdAt > 0, "Property does not exist");
        return properties[propertyId];
    }

    function getTotalProperties() public view returns (uint256) { return _propertyIds; }

    /**
     * @dev Admin function to verify property authenticity.
     */
    function verifyProperty(uint256 propertyId) public onlyOwner {
        require(properties[propertyId].createdAt > 0, "Property does not exist");
        require(!properties[propertyId].isVerified,   "Already verified");
        properties[propertyId].isVerified = true;
        emit PropertyVerified(propertyId);
    }

    /**
     * @dev List a property for rent. Only the original owner can list.
     */
    function listForRent(uint256 propertyId, uint256 rentAmount) public nonReentrant {
        LandProperty storage p = properties[propertyId];
        require(msg.sender == p.originalOwner, "Only owner can list for rent");
        require(rentAmount > 0, "Rent must be > 0");
        
        p.isForRent = true;
        p.monthlyRent = rentAmount;
        
        emit RentalListed(propertyId, rentAmount);
    }

    /**
     * @dev Request to rent a property.
     */
    function requestRent(uint256 propertyId) public nonReentrant {
        LandProperty storage p = properties[propertyId];
        require(p.isForRent, "Property not for rent");
        require(p.currentTenant == address(0), "Already has a tenant");
        require(msg.sender != p.originalOwner, "Owner cannot rent");

        p.pendingTenant = msg.sender;
        emit RentalRequested(propertyId, msg.sender);
    }

    /**
     * @dev Accept a rent request. Only the original owner can accept.
     */
    function acceptRentRequest(uint256 propertyId) public nonReentrant {
        LandProperty storage p = properties[propertyId];
        require(msg.sender == p.originalOwner, "Only owner can accept");
        require(p.pendingTenant != address(0), "No pending tenant");

        p.currentTenant = p.pendingTenant;
        p.pendingTenant = address(0);
        p.isForRent = false;

        emit RentalAccepted(propertyId, p.currentTenant);
    }

    /**
     * @dev Tenant pays monthly rent. Funds are automatically distributed to the rent pool.
     */
    function payMonthlyRent(uint256 propertyId) public payable nonReentrant {
        LandProperty memory p = properties[propertyId];
        require(msg.sender == p.currentTenant, "Only tenant can pay rent");
        require(msg.value >= p.monthlyRent, "Insufficient rent payment");

        rentPool[propertyId] += msg.value;
        emit RentDistributed(propertyId, msg.value, block.timestamp);
    }

    function setURI(string memory newuri) public onlyOwner { _setURI(newuri); }

    /**
     * @dev Internal shared logic for calculating unclaimed rent.
     */
    function _computeUnclaimed(
        uint256 propertyId,
        address user,
        uint256 totalFractions
    ) internal view returns (uint256) {
        uint256 userFractions = balanceOf(user, propertyId);
        if (userFractions == 0) return 0;

        uint256 entitlement    = (rentPool[propertyId] * userFractions) / totalFractions;
        uint256 alreadyClaimed = claimedRent[propertyId][user];
        if (entitlement <= alreadyClaimed) return 0;

        return entitlement - alreadyClaimed;
    }

    function supportsInterface(bytes4 interfaceId)
        public view virtual override(ERC1155, ERC1155Holder) returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}