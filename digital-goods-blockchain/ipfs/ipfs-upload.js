/**
 * IPFS Upload Utility for Digital Goods
 * Handles uploading property deeds and warranty certificates to IPFS
 */

const { create } = require('ipfs-http-client');
const fs = require('fs');
const path = require('path');
require('dotenv').config();

// Initialize IPFS client (using Infura)
const auth = 'Basic ' + Buffer.from(
  process.env.IPFS_PROJECT_ID + ':' + process.env.IPFS_PROJECT_SECRET
).toString('base64');

const ipfs = create({
  host: 'ipfs.infura.io',
  port: 5001,
  protocol: 'https',
  headers: {
    authorization: auth
  }
});

/**
 * Upload file to IPFS
 * @param {string} filePath - Path to file
 * @returns {Promise<string>} - IPFS hash
 */
async function uploadFileToIPFS(filePath) {
  try {
    const fileContent = fs.readFileSync(filePath);
    const result = await ipfs.add(fileContent);
    console.log(`✅ File uploaded to IPFS: ${result.path}`);
    return result.path;
  } catch (error) {
    console.error('❌ Error uploading to IPFS:', error);
    throw error;
  }
}

/**
 * Upload JSON metadata to IPFS
 * @param {Object} metadata - Metadata object
 * @returns {Promise<string>} - IPFS hash
 */
async function uploadMetadataToIPFS(metadata) {
  try {
    const metadataString = JSON.stringify(metadata);
    const result = await ipfs.add(metadataString);
    console.log(`✅ Metadata uploaded to IPFS: ${result.path}`);
    return result.path;
  } catch (error) {
    console.error('❌ Error uploading metadata to IPFS:', error);
    throw error;
  }
}

/**
 * Create electronics NFT metadata
 * @param {Object} device - Device details
 * @param {string} warrantyHash - IPFS hash of warranty certificate
 * @returns {Object} - NFT metadata
 */
function createElectronicsMetadata(device, warrantyHash) {
  return {
    name: `${device.brand} ${device.model}`,
    description: `Digital Goods authenticated ${device.brand} ${device.model} with serial ${device.serialNumber}`,
    image: device.imageIPFS || "", // IPFS hash of device image
    attributes: [
      {
        trait_type: "Brand",
        value: device.brand
      },
      {
        trait_type: "Model",
        value: device.model
      },
      {
        trait_type: "Serial Number",
        value: device.serialNumber
      },
      {
        trait_type: "Warranty Expiry",
        value: device.warrantyExpiry
      },
      {
        trait_type: "Condition",
        value: device.condition || "New"
      }
    ],
    properties: {
      warranty_certificate: `ipfs://${warrantyHash}`,
      purchase_date: new Date().toISOString(),
      authenticity: "Verified by Digital Goods"
    }
  };
}

/**
 * Create land property metadata
 * @param {Object} property - Property details
 * @param {string} deedHash - IPFS hash of property deed
 * @returns {Object} - NFT metadata
 */
function createLandMetadata(property, deedHash) {
  return {
    name: `${property.location} - ${property.totalArea} ${property.areaUnit}`,
    description: `Fractionalized land property in ${property.city}, Pakistan. Total area: ${property.totalArea} ${property.areaUnit}.`,
    image: property.imageIPFS || "", // IPFS hash of property image
    attributes: [
      {
        trait_type: "Location",
        value: property.location
      },
      {
        trait_type: "City",
        value: property.city
      },
      {
        trait_type: "Total Area",
        value: property.totalArea
      },
      {
        trait_type: "Area Unit",
        value: property.areaUnit
      },
      {
        trait_type: "Total Fractions",
        value: property.totalFractions
      },
      {
        trait_type: "Price Per Fraction",
        value: `${property.pricePerFraction} MATIC`
      }
    ],
    properties: {
      property_deed: `ipfs://${deedHash}`,
      registration_date: new Date().toISOString(),
      verification_status: "Pending"
    }
  };
}

/**
 * Complete workflow: Upload document and create metadata
 * @param {string} documentPath - Path to deed/warranty
 * @param {Object} assetDetails - Asset details
 * @param {string} assetType - "electronics" or "land"
 * @returns {Promise<string>} - IPFS hash of complete metadata
 */
async function uploadAssetToIPFS(documentPath, assetDetails, assetType) {
  try {
    console.log(`📤 Uploading ${assetType} asset to IPFS...`);
    
    // Step 1: Upload document (deed/warranty)
    const documentHash = await uploadFileToIPFS(documentPath);
    console.log(`📄 Document hash: ${documentHash}`);
    
    // Step 2: Create metadata
    let metadata;
    if (assetType === 'electronics') {
      metadata = createElectronicsMetadata(assetDetails, documentHash);
    } else if (assetType === 'land') {
      metadata = createLandMetadata(assetDetails, documentHash);
    } else {
      throw new Error('Invalid asset type');
    }
    
    // Step 3: Upload metadata
    const metadataHash = await uploadMetadataToIPFS(metadata);
    console.log(`🎯 Metadata hash: ${metadataHash}`);
    console.log(`🔗 Full URI: ipfs://${metadataHash}`);
    
    return metadataHash;
  } catch (error) {
    console.error('❌ Upload workflow failed:', error);
    throw error;
  }
}

/**
 * Generate hash for on-chain verification
 * @param {string} data - Data to hash
 * @returns {string} - Keccak256 hash
 */
function generateHash(data) {
  const { keccak256 } = require('ethers');
  const { toUtf8Bytes } = require('ethers');
  return keccak256(toUtf8Bytes(data));
}

// Export functions
module.exports = {
  uploadFileToIPFS,
  uploadMetadataToIPFS,
  createElectronicsMetadata,
  createLandMetadata,
  uploadAssetToIPFS,
  generateHash
};

// Example usage (uncomment to test)
/*
(async () => {
  const electronicsDetails = {
    brand: "Samsung",
    model: "Galaxy S24",
    serialNumber: "IMEI123456789",
    warrantyExpiry: "2026-12-31",
    condition: "New"
  };
  
  const metadataHash = await uploadAssetToIPFS(
    './warranty.pdf',
    electronicsDetails,
    'electronics'
  );
  
  console.log('✅ Complete! Use this URI in your smart contract:');
  console.log(`ipfs://${metadataHash}`);
})();
*/