/**
 * Comprehensive test script for Digital Goods smart contracts
 * Hardhat/Ethers.js v5 compatible - Fixed API calls
 * Tests alignment with FYP synopsis requirements
 */

const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Digital Goods - Electronics NFT", function () {
  let electronicsNFT;
  let owner, user1, user2;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();
    
    const ElectronicsNFT = await ethers.getContractFactory("ElectronicsNFT");
    electronicsNFT = await ElectronicsNFT.deploy();
    await electronicsNFT.deployed(); // ✅ FIXED: Use .deployed() not .waitForDeployment()
  });

  describe("Minting Electronics", function () {
    it("Should mint electronics NFT with IPFS metadata", async function () {
      const tx = await electronicsNFT.mintElectronic(
        user1.address,
        "IMEI123456789",
        "Samsung",
        "Galaxy S24",
        "2026-12-31",
        "ipfs://QmTest123"
      );

      const receipt = await tx.wait();
      
      // ✅ FIXED: Hardhat event parsing
      const mintEvent = receipt.events?.find(e => e.event === 'DeviceMinted');
      
      expect(mintEvent).to.not.be.undefined;
      expect(await electronicsNFT.totalMinted()).to.equal(1);
    });

    it("Should prevent duplicate serial numbers", async function () {
      await electronicsNFT.mintElectronic(
        user1.address,
        "IMEI123456789",
        "Samsung",
        "Galaxy S24",
        "2026-12-31",
        "ipfs://QmTest123"
      );

      await expect(
        electronicsNFT.mintElectronic(
          user2.address,
          "IMEI123456789",
          "Apple",
          "iPhone 15",
          "2026-12-31",
          "ipfs://QmTest456"
        )
      ).to.be.revertedWith("Device already registered");
    });

    it("Should retrieve device by serial number", async function () {
      await electronicsNFT.mintElectronic(
        user1.address,
        "IMEI123456789",
        "Samsung",
        "Galaxy S24",
        "2026-12-31",
        "ipfs://QmTest123"
      );

      const device = await electronicsNFT.getDeviceBySerial("IMEI123456789");
      expect(device.brand).to.equal("Samsung");
      expect(device.model).to.equal("Galaxy S24");
      expect(device.serialNumber).to.equal("IMEI123456789");
    });
  });

  describe("Verification", function () {
    it("Should verify device authenticity", async function () {
      await electronicsNFT.mintElectronic(
        user1.address,
        "IMEI123456789",
        "Samsung",
        "Galaxy S24",
        "2026-12-31",
        "ipfs://QmTest123"
      );

      await electronicsNFT.verifyDevice(1);
      expect(await electronicsNFT.isDeviceVerified(1)).to.be.true;
    });

    it("Should prevent non-owner from verifying", async function () {
      await electronicsNFT.mintElectronic(
        user1.address,
        "IMEI123456789",
        "Samsung",
        "Galaxy S24",
        "2026-12-31",
        "ipfs://QmTest123"
      );

      // ✅ FIXED: OZ v5 uses custom errors, not string messages
      await expect(
        electronicsNFT.connect(user1).verifyDevice(1)
      ).to.be.reverted;
    });
  });

  describe("Reviews (On-Chain Hashing)", function () {
    it("Should submit hashed review", async function () {
      await electronicsNFT.mintElectronic(
        user1.address,
        "IMEI123456789",
        "Samsung",
        "Galaxy S24",
        "2026-12-31",
        "ipfs://QmTest123"
      );

      const reviewContent = "Great phone! Highly recommended.";
      // ✅ FIXED: Use ethers.utils for v5
      const reviewHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(reviewContent));

      const tx = await electronicsNFT.connect(user2).submitReview(1, reviewHash);
      const receipt = await tx.wait();
      
      // ✅ FIXED: Hardhat event parsing
      const reviewEvent = receipt.events?.find(e => e.event === 'ReviewSubmitted');
      
      expect(reviewEvent).to.not.be.undefined;
    });

    it("Should prevent duplicate reviews", async function () {
      await electronicsNFT.mintElectronic(
        user1.address,
        "IMEI123456789",
        "Samsung",
        "Galaxy S24",
        "2026-12-31",
        "ipfs://QmTest123"
      );

      const reviewHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Test review"));

      await electronicsNFT.connect(user2).submitReview(1, reviewHash);
      
      await expect(
        electronicsNFT.connect(user2).submitReview(1, reviewHash)
      ).to.be.revertedWith("Already reviewed");
    });
  });
});

describe("Digital Goods - Land Fractional NFT", function () {
  let landNFT;
  let owner, user1, user2;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();
    
    const LandFractionalNFT = await ethers.getContractFactory("LandFractionalNFT");
    landNFT = await LandFractionalNFT.deploy();
    await landNFT.deployed(); // ✅ FIXED: Use .deployed() not .waitForDeployment()
  });

  describe("Property Creation", function () {
    it("Should create fractionalized land property", async function () {
      const tx = await landNFT.createProperty(
        "DHA Phase 5, Block A",
        "Lahore",
        10, // 10 marlas
        "marla",
        100, // 100 fractions
        ethers.utils.parseEther("0.1"), // ✅ FIXED: Use ethers.utils.parseEther
        "ipfs://QmPropertyDeed123"
      );

      const receipt = await tx.wait();
      
      // ✅ FIXED: Hardhat event parsing
      const createEvent = receipt.events?.find(e => e.event === 'PropertyCreated');
      
      expect(createEvent).to.not.be.undefined;
      expect(await landNFT.getTotalProperties()).to.equal(1);
    });

    it("Should support marla and kanal units", async function () {
      await landNFT.createProperty(
        "Bahria Town",
        "Islamabad",
        5,
        "kanal",
        200,
        ethers.utils.parseEther("0.5"), // ✅ FIXED
        "ipfs://QmPropertyDeed456"
      );

      const property = await landNFT.getProperty(1);
      expect(property.areaUnit).to.equal("kanal");
      expect(property.totalArea).to.equal(5);
    });
  });

  describe("Fractional Ownership", function () {
    beforeEach(async function () {
      await landNFT.connect(user1).createProperty(
        "DHA Phase 5",
        "Lahore",
        10,
        "marla",
        100,
        ethers.utils.parseEther("0.1"), // ✅ FIXED
        "ipfs://QmPropertyDeed123"
      );
    });

    it("Should purchase fractions", async function () {
      const fractionsToBuy = 10;
      const totalCost = ethers.utils.parseEther("1"); // ✅ FIXED: 10 * 0.1 MATIC

      await landNFT.connect(user2).purchaseFractions(1, fractionsToBuy, {
        value: totalCost
      });

      const balance = await landNFT.balanceOf(user2.address, 1);
      expect(balance).to.equal(fractionsToBuy);
    });

    it("Should refund excess payment", async function () {
      const fractionsToBuy = 10;
      const exactCost = ethers.utils.parseEther("1"); // ✅ FIXED
      const excessPayment = ethers.utils.parseEther("1.5"); // ✅ FIXED

      const balanceBefore = await ethers.provider.getBalance(user2.address);

      const tx = await landNFT.connect(user2).purchaseFractions(1, fractionsToBuy, {
        value: excessPayment
      });
      const receipt = await tx.wait();

      const balanceAfter = await ethers.provider.getBalance(user2.address);
      
      // ✅ FIXED: Calculate gas cost for Hardhat
      const gasUsed = receipt.gasUsed.mul(receipt.effectiveGasPrice);

      // Should have paid only exact cost + gas
      expect(balanceBefore.sub(balanceAfter)).to.be.closeTo(
        exactCost.add(gasUsed),
        ethers.utils.parseEther("0.01") // ✅ FIXED: 0.01 MATIC tolerance
      );
    });
  });

  describe("Rent Distribution (Simulated)", function () {
    beforeEach(async function () {
      // Create property with 100 fractions
      await landNFT.connect(user1).createProperty(
        "DHA Phase 5",
        "Lahore",
        10,
        "marla",
        100,
        ethers.utils.parseEther("0.1"), // ✅ FIXED
        "ipfs://QmPropertyDeed123"
      );

      // User2 buys 20 fractions (20% ownership)
      await landNFT.connect(user2).purchaseFractions(1, 20, {
        value: ethers.utils.parseEther("2") // ✅ FIXED
      });
    });

    it("Should distribute and claim proportional rent", async function () {
      // Distribute 10 MATIC as rent
      const rentAmount = ethers.utils.parseEther("10"); // ✅ FIXED
      await landNFT.distributeRent(1, { value: rentAmount });

      // User2 owns 20%, should get 2 MATIC
      const unclaimedRent = await landNFT.getUnclaimedRent(1, user2.address);
      expect(unclaimedRent).to.equal(ethers.utils.parseEther("2")); // ✅ FIXED

      // Claim rent
      const balanceBefore = await ethers.provider.getBalance(user2.address);
      const tx = await landNFT.connect(user2).claimRent(1);
      const receipt = await tx.wait();
      const balanceAfter = await ethers.provider.getBalance(user2.address);

      const gasUsed = receipt.gasUsed.mul(receipt.effectiveGasPrice); // ✅ FIXED
      const netGain = balanceAfter.sub(balanceBefore).add(gasUsed); // ✅ FIXED

      expect(netGain).to.equal(ethers.utils.parseEther("2")); // ✅ FIXED
    });

    it("Should prevent claiming when no rent available", async function () {
      await expect(
        landNFT.connect(user2).claimRent(1)
      ).to.be.revertedWith("No unclaimed rent");
    });

    it("Should prevent claiming without ownership", async function () {
      await landNFT.distributeRent(1, { value: ethers.utils.parseEther("10") }); // ✅ FIXED

      await expect(
        landNFT.connect(owner).claimRent(1)
      ).to.be.revertedWith("No fractions owned");
    });
  });

  describe("Property Verification", function () {
    it("Should verify property", async function () {
      await landNFT.createProperty(
        "DHA Phase 5",
        "Lahore",
        10,
        "marla",
        100,
        ethers.utils.parseEther("0.1"), // ✅ FIXED
        "ipfs://QmPropertyDeed123"
      );

      await landNFT.verifyProperty(1);
      
      const property = await landNFT.getProperty(1);
      expect(property.isVerified).to.be.true;
    });
  });
});

describe("Synopsis Requirements Alignment", function () {
  let electronicsNFT;
  let landNFT;
  let owner, user1, user2, user3;

  beforeEach(async function () {
    [owner, user1, user2, user3] = await ethers.getSigners();
    
    const ElectronicsNFT = await ethers.getContractFactory("ElectronicsNFT");
    electronicsNFT = await ElectronicsNFT.deploy();
    await electronicsNFT.deployed();

    const LandFractionalNFT = await ethers.getContractFactory("LandFractionalNFT");
    landNFT = await LandFractionalNFT.deploy();
    await landNFT.deployed();
  });

  it("✅ Tamper-proof record immutability", async function () {
    await electronicsNFT.mintElectronic(
      user1.address,
      "IMMUTABLE123",
      "Apple",
      "iPhone 15",
      "2026-12-31",
      "ipfs://QmImmutableHash"
    );

    let device = await electronicsNFT.getDevice(1);
    expect(device.brand).to.equal("Apple");
    expect(device.model).to.equal("iPhone 15");
    expect(device.serialNumber).to.equal("IMMUTABLE123");
    expect(await electronicsNFT.tokenURI(1)).to.equal("ipfs://QmImmutableHash");

    await electronicsNFT.connect(user1).transferFrom(user1.address, user2.address, 1);
    
    device = await electronicsNFT.getDevice(1);
    expect(device.brand).to.equal("Apple");
    expect(device.model).to.equal("iPhone 15");
    expect(device.serialNumber).to.equal("IMMUTABLE123");
    expect(await electronicsNFT.tokenURI(1)).to.equal("ipfs://QmImmutableHash");
    expect(await electronicsNFT.ownerOf(1)).to.equal(user2.address);
  });

  it("✅ Fractionalized land ownership", async function () {
    await landNFT.connect(user1).createProperty(
      "DHA Phase 6",
      "Lahore",
      10,
      "marla",
      100,
      ethers.utils.parseEther("0.1"),
      "ipfs://QmDeedHash"
    );

    await landNFT.connect(user2).purchaseFractions(1, 30, {
      value: ethers.utils.parseEther("3.0")
    });

    await landNFT.connect(user3).purchaseFractions(1, 20, {
      value: ethers.utils.parseEther("2.0")
    });

    expect(await landNFT.balanceOf(user2.address, 1)).to.equal(30);
    expect(await landNFT.balanceOf(user3.address, 1)).to.equal(20);

    await landNFT.distributeRent(1, { value: ethers.utils.parseEther("10.0") });

    expect(await landNFT.getUnclaimedRent(1, user2.address)).to.equal(ethers.utils.parseEther("3.0"));
    expect(await landNFT.getUnclaimedRent(1, user3.address)).to.equal(ethers.utils.parseEther("2.0"));
  });

  it("✅ QR code verification", async function () {
    await electronicsNFT.mintElectronic(
      user1.address,
      "QR_CODE_SERIAL_999",
      "Dell",
      "Latitude",
      "2027-01-01",
      "ipfs://QmDellHash"
    );

    const deviceById = await electronicsNFT.getDevice(1);
    expect(deviceById.brand).to.equal("Dell");
    expect(deviceById.serialNumber).to.equal("QR_CODE_SERIAL_999");

    const deviceBySerial = await electronicsNFT.getDeviceBySerial("QR_CODE_SERIAL_999");
    expect(deviceBySerial.brand).to.equal("Dell");
  });

  it("✅ On-chain review authenticity", async function () {
    await electronicsNFT.mintElectronic(
      user1.address,
      "REVIEW123",
      "Sony",
      "WH-1000XM5",
      "2026-06-01",
      "ipfs://QmSonyHash"
    );

    const reviewContent = "Amazing noise cancelling!";
    const reviewHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(reviewContent));

    const tx = await electronicsNFT.connect(user2).submitReview(1, reviewHash);
    const receipt = await tx.wait();

    const event = receipt.events.find(e => e.event === "ReviewSubmitted");
    expect(event).to.not.be.undefined;
    expect(event.args.reviewer).to.equal(user2.address);
    expect(event.args.reviewHash).to.equal(reviewHash);

    await expect(
      electronicsNFT.connect(user2).submitReview(1, reviewHash)
    ).to.be.revertedWith("Already reviewed");
  });

  it("✅ Low-cost transactions", async function () {
    const tx = await electronicsNFT.mintElectronic(
      user1.address,
      "LOWCOST123",
      "HP",
      "Spectre",
      "2026-10-01",
      "ipfs://QmHpHash"
    );
    const receipt = await tx.wait();

    expect(receipt.gasUsed).to.be.below(300000);

    const gasPrice = ethers.utils.parseUnits("30", "gwei");
    const totalCost = receipt.gasUsed.mul(gasPrice);

    expect(totalCost).to.be.below(ethers.utils.parseEther("0.01"));
  });
});