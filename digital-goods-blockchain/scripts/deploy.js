/**
 * Deployment script for Digital Goods smart contracts
 * Deploys to Polygon Amoy Testnet
 */

const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  console.log("🚀 Starting deployment to Polygon Amoy Testnet...\n");

  // Get deployer account
  const [deployer] = await hre.ethers.getSigners();
  console.log("📍 Deploying contracts with account:", deployer.address);

  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log(
    "💰 Account balance:",
    hre.ethers.utils.formatEther(balance),
    "MATIC\n"
  );

  // =============================
  // Deploy ElectronicsNFT
  // =============================
  console.log("📱 Deploying ElectronicsNFT contract...");
  const ElectronicsNFT = await hre.ethers.getContractFactory("ElectronicsNFT");
  const electronicsNFT = await ElectronicsNFT.deploy();
  await electronicsNFT.deployed();

  const electronicsAddress = electronicsNFT.address;
  console.log("✅ ElectronicsNFT deployed to:", electronicsAddress);

  // =============================
  // Deploy LandFractionalNFT
  // =============================
  console.log("\n🏡 Deploying LandFractionalNFT contract...");
  const LandFractionalNFT = await hre.ethers.getContractFactory("LandFractionalNFT");
  const landNFT = await LandFractionalNFT.deploy();
  await landNFT.deployed();

  const landAddress = landNFT.address;
  console.log("✅ LandFractionalNFT deployed to:", landAddress);

  // =============================
  // Save deployment info
  // =============================
  const network = await hre.ethers.provider.getNetwork();

  const deploymentInfo = {
    network: hre.network.name,
    chainId: network.chainId.toString(),
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    contracts: {
      ElectronicsNFT: {
        address: electronicsAddress,
        abi: "ElectronicsNFT.json"
      },
      LandFractionalNFT: {
        address: landAddress,
        abi: "LandFractionalNFT.json"
      }
    }
  };

  const deploymentPath = path.join(__dirname, "../deployment-info.json");
  fs.writeFileSync(deploymentPath, JSON.stringify(deploymentInfo, null, 2));
  console.log("\n📄 Deployment info saved to:", deploymentPath);

  // =============================
  // Flutter config generation
  // =============================
  const flutterConfig = `
// lib/blockchain/contract_config.dart
// Auto-generated on ${new Date().toISOString()}

class ContractConfig {
  static const String networkName = '${hre.network.name}';
  static const int chainId = ${network.chainId};
  static const String rpcUrl = '${process.env.POLYGON_AMOY_RPC_URL}';
  
  static const String electronicsNFTAddress = '${electronicsAddress}';
  static const String landNFTAddress = '${landAddress}';
  
  static String getExplorerUrl(String txHash) {
    return 'https://amoy.polygonscan.com/tx/\\$txHash';
  }

  static String getAddressUrl(String address) {
    return 'https://amoy.polygonscan.com/address/\\$address';
  }
}
`;

  const flutterConfigPath = path.join(
    __dirname,
    "../flutter_contract_config.dart"
  );

  fs.writeFileSync(flutterConfigPath, flutterConfig);
  console.log("📱 Flutter config saved to:", flutterConfigPath);

  console.log("\n✨ Deployment completed successfully!");
  console.log("\n📋 Next steps:");
  console.log("1. Copy flutter_contract_config.dart to your Flutter project");
  console.log("2. Copy ABI files from artifacts/ to Flutter assets");
  console.log("3. Verify contracts on PolygonScan:");
  console.log(`   npx hardhat verify --network amoy ${electronicsAddress}`);
  console.log(`   npx hardhat verify --network amoy ${landAddress}`);

  console.log("\n🔗 Contract URLs:");
  console.log(`   ElectronicsNFT: https://amoy.polygonscan.com/address/${electronicsAddress}`);
  console.log(`   LandFractionalNFT: https://amoy.polygonscan.com/address/${landAddress}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
