/**
 * Performance Measurement Script for Digital Goods Project
 * Measures Gas Costs and Transaction Finality Latency on Polygon Amoy (or Local Network)
 */

const hre = require("hardhat");
const fs = require("fs");
const path = require("path");
const { ethers } = hre;

// Helper to fetch live MATIC price in USD
async function getMaticPrice() {
  try {
    const response = await fetch("https://api.coingecko.com/api/v3/simple/price?ids=matic-network&vs_currencies=usd");
    const data = await response.json();
    return data["matic-network"].usd || 0.70; // Fallback to 0.70 if API fails
  } catch (error) {
    console.log("⚠️ Could not fetch live MATIC price, using fallback value of $0.70");
    return 0.70;
  }
}

// Helper to wait for transaction confirmation with retry logic for flaky RPC nodes
async function waitWithRetry(tx, maxRetries = 12, delayMs = 4000) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      return await tx.wait();
    } catch (error) {
      const errMsg = error.message ? error.message.toLowerCase() : "";
      if (
        errMsg.includes("unknown block") ||
        errMsg.includes("not found") ||
        errMsg.includes("timeout") ||
        errMsg.includes("server response") ||
        errMsg.includes("bad response")
      ) {
        console.log(`   ⚠️ RPC Node lag / Unknown Block error. Retrying receipt fetch in ${delayMs / 1000}s... (Attempt ${i + 1}/${maxRetries})`);
        await new Promise(resolve => setTimeout(resolve, delayMs));
        
        try {
          const receipt = await ethers.provider.getTransactionReceipt(tx.hash);
          if (receipt && receipt.blockNumber) {
            return receipt;
          }
        } catch (receiptError) {
          console.log(`   ⚠️ Direct receipt fetch failed: ${receiptError.message ? receiptError.message.substring(0, 50) : receiptError}...`);
        }
      } else {
        throw error;
      }
    }
  }
  throw new Error(`Failed to confirm transaction ${tx.hash} after ${maxRetries} retries.`);
}

async function main() {
  console.log("📊 Starting Digital Goods Blockchain Performance Measurement...\n");

  const [deployer] = await ethers.getSigners();
  console.log("👤 Using account:", deployer.address);
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("💰 Account Balance:", ethers.utils.formatEther(balance), "MATIC\n");

  // Load deployment info
  const deploymentPath = path.join(__dirname, "../deployment-info.json");
  if (!fs.existsSync(deploymentPath)) {
    console.error("❌ Error: deployment-info.json not found. Please run 'npx hardhat run scripts/deploy.js --network amoy' first.");
    process.exit(1);
  }

  const deploymentInfo = JSON.parse(fs.readFileSync(deploymentPath, "utf8"));
  const electronicsAddress = deploymentInfo.contracts.ElectronicsNFT.address;
  const landAddress = deploymentInfo.contracts.LandFractionalNFT.address;

  console.log(`🔌 Connected to ElectronicsNFT at: ${electronicsAddress}`);
  console.log(`🔌 Connected to LandFractionalNFT at: ${landAddress}`);

  // Attach contracts
  const ElectronicsNFT = await ethers.getContractFactory("ElectronicsNFT");
  const electronicsNFT = ElectronicsNFT.attach(electronicsAddress);

  const LandFractionalNFT = await ethers.getContractFactory("LandFractionalNFT");
  const landNFT = LandFractionalNFT.attach(landAddress);

  // Fetch live MATIC price and network gas price
  const maticPriceUSD = await getMaticPrice();
  console.log(`🏷️ Current MATIC price: $${maticPriceUSD.toFixed(2)} USD`);

  const feeData = await ethers.provider.getFeeData();
  const gasPrice = feeData.gasPrice || ethers.BigNumber.from("35000000000"); // fallback 35 gwei
  console.log(`⛽ Current Gas Price: ${ethers.utils.formatUnits(gasPrice, "gwei")} gwei\n`);

  const results = [];

  // ==========================================
  // OPERATION 1: Minting ERC-721 NFT (ElectronicsNFT)
  // ==========================================
  console.log("1️⃣ Measuring ERC-721 Minting (mintElectronic)...");
  const uniqueSerial = `SN-721-${Date.now()}`;
  const start721 = Date.now();
  
  const tx721 = await electronicsNFT.mintElectronic(
    deployer.address,
    uniqueSerial,
    "Apple",
    "iPhone 15 Pro",
    "2027-05-24",
    "ipfs://QmExample721Hash"
  );
  console.log("   - Transaction sent. Waiting for confirmation...");
  const receipt721 = await waitWithRetry(tx721);
  const end721 = Date.now();
  
  const latency721 = (end721 - start721) / 1000; // seconds
  const gasUsed721 = receipt721.gasUsed;
  const maticCost721 = gasUsed721.mul(gasPrice);
  const usdCost721 = parseFloat(ethers.utils.formatEther(maticCost721)) * maticPriceUSD;
  
  console.log(`   ✅ Confirmed in ${latency721.toFixed(2)}s`);
  console.log(`   ⛽ Gas Used: ${gasUsed721.toString()}`);
  console.log(`   🪙 Cost: ${ethers.utils.formatEther(maticCost721)} MATIC (~$${usdCost721.toFixed(6)} USD)\n`);

  results.push({
    operation: "Minting ERC-721 NFT (ElectronicsNFT)",
    latency: latency721,
    gasUsed: gasUsed721.toString(),
    maticCost: ethers.utils.formatEther(maticCost721),
    usdCost: usdCost721
  });

  // Extract token ID for transfer step
  let tokenId721;
  if (receipt721.events) {
    const event721 = receipt721.events.find(e => e.event === "DeviceMinted");
    tokenId721 = event721.args.tokenId;
  } else {
    for (const log of receipt721.logs) {
      try {
        const parsedLog = electronicsNFT.interface.parseLog(log);
        if (parsedLog.name === "DeviceMinted") {
          tokenId721 = parsedLog.args.tokenId;
          break;
        }
      } catch (e) {
        // Log not from this contract or doesn't match ABI
      }
    }
  }
  if (!tokenId721) {
    throw new Error("Failed to extract tokenId721 from logs or events.");
  }

  // ==========================================
  // OPERATION 2: Minting ERC-1155 NFT (LandFractionalNFT)
  // ==========================================
  console.log("2️⃣ Measuring ERC-1155 Property Minting (createProperty)...");
  const start1155 = Date.now();
  
  const tx1155 = await landNFT.createProperty(
    `Property Loc ${Date.now()}`,
    "Islamabad",
    5000,
    "sqft",
    1000, // totalFractions
    ethers.utils.parseUnits("0.0001", "ether"), // pricePerFraction (0.0001 MATIC)
    "ipfs://QmExample1155Hash"
  );
  console.log("   - Transaction sent. Waiting for confirmation...");
  const receipt1155 = await waitWithRetry(tx1155);
  const end1155 = Date.now();
  
  const latency1155 = (end1155 - start1155) / 1000;
  const gasUsed1155 = receipt1155.gasUsed;
  const maticCost1155 = gasUsed1155.mul(gasPrice);
  const usdCost1155 = parseFloat(ethers.utils.formatEther(maticCost1155)) * maticPriceUSD;

  console.log(`   ✅ Confirmed in ${latency1155.toFixed(2)}s`);
  console.log(`   ⛽ Gas Used: ${gasUsed1155.toString()}`);
  console.log(`   🪙 Cost: ${ethers.utils.formatEther(maticCost1155)} MATIC (~$${usdCost1155.toFixed(6)} USD)\n`);

  results.push({
    operation: "Minting ERC-1155 NFT (LandFractionalNFT)",
    latency: latency1155,
    gasUsed: gasUsed1155.toString(),
    maticCost: ethers.utils.formatEther(maticCost1155),
    usdCost: usdCost1155
  });

  // ==========================================
  // OPERATION 3: Ownership Transfer (ElectronicsNFT Transfer)
  // ==========================================
  console.log("3️⃣ Measuring Ownership Transfer (transferFrom)...");
  // Generate a random recipient address
  const recipient = ethers.Wallet.createRandom().address;
  const startTransfer = Date.now();
  
  const txTransfer = await electronicsNFT.transferFrom(
    deployer.address,
    recipient,
    tokenId721
  );
  console.log("   - Transaction sent. Waiting for confirmation...");
  const receiptTransfer = await waitWithRetry(txTransfer);
  const endTransfer = Date.now();

  const latencyTransfer = (endTransfer - startTransfer) / 1000;
  const gasUsedTransfer = receiptTransfer.gasUsed;
  const maticCostTransfer = gasUsedTransfer.mul(gasPrice);
  const usdCostTransfer = parseFloat(ethers.utils.formatEther(maticCostTransfer)) * maticPriceUSD;

  console.log(`   ✅ Confirmed in ${latencyTransfer.toFixed(2)}s`);
  console.log(`   ⛽ Gas Used: ${gasUsedTransfer.toString()}`);
  console.log(`   🪙 Cost: ${ethers.utils.formatEther(maticCostTransfer)} MATIC (~$${usdCostTransfer.toFixed(6)} USD)\n`);

  results.push({
    operation: "Ownership Transfer (ERC-721)",
    latency: latencyTransfer,
    gasUsed: gasUsedTransfer.toString(),
    maticCost: ethers.utils.formatEther(maticCostTransfer),
    usdCost: usdCostTransfer
  });

  // ==========================================
  // Summary and Report Generation
  // ==========================================
  console.log("📋 Summary of Results:");
  console.table(results.map(r => ({
    "Operation": r.operation,
    "Latency (s)": r.latency.toFixed(2),
    "Gas Used": r.gasUsed,
    "Cost (MATIC)": parseFloat(r.maticCost).toFixed(6),
    "Cost (USD)": `$${r.usdCost.toFixed(4)}`
  })));

  // Write a markdown report
  const reportPath = path.join(__dirname, "../performance-report.md");
  let mdContent = `# Performance Measurement Report\n\n`;
  mdContent += `**Date:** ${new Date().toLocaleString()}\n`;
  mdContent += `**Network:** ${hre.network.name} (Chain ID: ${hre.network.config.chainId})\n`;
  mdContent += `**Gas Price:** ${ethers.utils.formatUnits(gasPrice, "gwei")} gwei\n`;
  mdContent += `**MATIC Price:** $${maticPriceUSD.toFixed(2)} USD\n\n`;
  mdContent += `## Quantitative Results\n\n`;
  mdContent += `| Operation | Latency (s) | Gas Used | Gas Cost (MATIC) | Gas Cost (USD) |\n`;
  mdContent += `| --- | --- | --- | --- | --- |\n`;
  
  results.forEach(r => {
    mdContent += `| ${r.operation} | ${r.latency.toFixed(2)}s | ${r.gasUsed} | ${parseFloat(r.maticCost).toFixed(6)} MATIC | $${r.usdCost.toFixed(5)} |\n`;
  });
  
  mdContent += `\n*Note: Ethereum Mainnet gas costs estimated for comparison typically range from $5.00 to $50.00 depending on network congestion.*`;

  fs.writeFileSync(reportPath, mdContent);
  console.log(`\n💾 Saved performance report to: ${reportPath}`);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error("\n❌ Execution failed:", error);
    process.exit(1);
  });
