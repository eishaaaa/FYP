// ═══════════════════════════════════════════════════════════
// COMPLETE BLOCKCHAIN SERVICE (FINAL OPTIMIZED VERSION)
// Location: lib/blockchain/blockchain_service.dart
//
// FIXES INCLUDED:
// 1. Gas Fees: Tuned to 25.5 Gwei (Minimum safe for Amoy Testnet)
// 2. Struct Parsing: Correctly unwraps nested lists from Web3Dart
// 3. ABI Loading: Handles both Hardhat Artifacts and Flat JSON
// ═══════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';
import 'package:reown_appkit/reown_appkit.dart';
// import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;

import 'wallet_service.dart';
import 'contract_config.dart';

class BlockchainServiceEnhanced {
  // Singleton Pattern
  static final BlockchainServiceEnhanced _instance = BlockchainServiceEnhanced._internal();
  factory BlockchainServiceEnhanced() => _instance;
  BlockchainServiceEnhanced._internal() {
    _client = Web3Client(ContractConfig.rpcUrl, http.Client());
  }

  late final Web3Client _client;
  late DeployedContract _electronicsContract;
  late DeployedContract _landContract;

  final SimpleWalletService _walletService = SimpleWalletService();
  bool _isInitialized = false;

  /// Helper: Clean address string to prevent parsing errors
  String _sanitizeAddress(String address) {
    String clean = address.replaceAll(RegExp(r'[^0-9a-fA-FxX]'), '');
    if (!clean.startsWith('0x')) {
      clean = '0x$clean';
    }
    return clean;
  }

  /// Initialize Contracts & ABIs
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // Load ABI files
      final electronicsAbiString = await rootBundle.loadString('assets/abi/ElectronicsNFT.json');
      final landAbiString = await rootBundle.loadString('assets/abi/LandFractionalNFT.json');

      final electronicsJson = jsonDecode(electronicsAbiString);
      final landJson = jsonDecode(landAbiString);

      // FIX: Robustly extract ABI whether it is a Map (Hardhat Artifact) or List (Flat ABI)
      List<dynamic> getAbiList(dynamic jsonInput) {
        if (jsonInput is Map<String, dynamic> && jsonInput.containsKey('abi')) {
          return jsonInput['abi'];
        }
        return jsonInput as List<dynamic>;
      }

      // Setup Contracts
      _electronicsContract = DeployedContract(
        ContractAbi.fromJson(jsonEncode(getAbiList(electronicsJson)), 'ElectronicsNFT'),
        EthereumAddress.fromHex(_sanitizeAddress(ContractConfig.electronicsNFTAddress)),
      );

      _landContract = DeployedContract(
        ContractAbi.fromJson(jsonEncode(getAbiList(landJson)), 'LandFractionalNFT'),
        EthereumAddress.fromHex(_sanitizeAddress(ContractConfig.landNFTAddress)),
      );

      _isInitialized = true;
      debugPrint('✅ Blockchain Service Initialized');
    } catch (e) {
      debugPrint('❌ Blockchain Init Error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // WALLET CONNECTION WRAPPERS
  // ═══════════════════════════════════════════════════════════

  Future<String?> connectWallet(BuildContext context) async {
    return await _walletService.connect(context);
  }

  String? get connectedAddress => _walletService.address;
  bool get isConnected => _walletService.isConnected;

  // ═══════════════════════════════════════════════════════════
  // ROBUST TRANSACTION LOGIC (GAS OPTIMIZED)
  // ═══════════════════════════════════════════════════════════

  Future<String> _sendTransaction(Transaction transaction) async {
    if (!isConnected) throw Exception('Wallet not connected. Please connect first.');

    final session = _walletService.appKitModal.session;
    if (session == null) throw Exception('Session is null. Reconnect.');

    // 1. NETWORK CHECK
    final requiredChainId = 'eip155:${ContractConfig.chainId}';
    final approvedChains = session.namespaces?['eip155']?.chains ?? [];

    if (!approvedChains.contains(requiredChainId)) {
      debugPrint('⚠️ Network Warning: App expects $requiredChainId. Wallet chains: $approvedChains');
    }

    try {
      debugPrint('🚀 Preparing Transaction...');

      // FIX: TUNED GAS FEES (Lowest Safe Values for Amoy)
      // Network Requirement: Min 25 Gwei Tip
      // Our Setting: 25.5 Gwei Tip (Just enough to pass)
      final maxPriorityFee = BigInt.from(25500000000); // 25.5 Gwei
      final maxFee = BigInt.from(50000000000);         // 50 Gwei (Cap)

      // 2. CLEAN PARAMETERS
      final txParams = {
        'from': connectedAddress,
        'to': transaction.to?.toString(),
        'data': bytesToHex(transaction.data ?? Uint8List(0), include0x: true),
        'value': '0x${(transaction.value?.getInWei ?? BigInt.zero).toRadixString(16)}',

        // VITAL: Explicit Gas Fields to prevent "Transaction underpriced" errors
        'maxPriorityFeePerGas': '0x${maxPriorityFee.toRadixString(16)}',
        'maxFeePerGas': '0x${maxFee.toRadixString(16)}',
      };

      debugPrint('🚀 Sending Request to Wallet: $txParams');

      // 3. SEND REQUEST
      final futureResult = _walletService.appKitModal.request(
        topic: session.topic,
        chainId: requiredChainId,
        request: SessionRequestParams(
          method: 'eth_sendTransaction',
          params: [txParams],
        ),
      );

      // 4. FORCE OPEN METAMASK (Deep Link)
      await Future.delayed(const Duration(milliseconds: 1000));
      _walletService.appKitModal.launchConnectedWallet();

      debugPrint('⏳ Waiting for user signature...');

      // 5. TIMEOUT
      final result = await futureResult.timeout(
        const Duration(minutes: 3),
        onTimeout: () {
          throw Exception('Timeout. Please open MetaMask and check for "Pending" transactions to clear.');
        },
      );

      debugPrint('✅ Transaction Hash: $result');
      return result.toString();

    } catch (e) {
      debugPrint('❌ Transaction Failed: $e');

      if (e.toString().contains('User rejected')) {
        throw Exception('User rejected the transaction');
      }
      if (e.toString().contains('5000') || e.toString().contains('needed')) {
        throw Exception('Network requires ~25 Gwei gas. Please ensure you have enough Test MATIC.');
      }
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ─── HELPERS ───────────────────────────────────────────────────────────────
  // ═══════════════════════════════════════════════════════════

  /// Fetch the *current* owner of a token from the blockchain.
  Future<String?> getOwnerOf(String type, int tokenId) async {
    await init();
    try {
      if (type == 'electronics') {
        // ERC-721: Use standard ownerOf(tokenId)
        final function = _electronicsContract.function('ownerOf');
        final result = await _client.call(
          contract: _electronicsContract,
          function: function,
          params: [BigInt.from(tokenId)],
        );
        return (result.first as EthereumAddress).toString();
      } else if (type == 'land') {
        // ERC-1155: Get 'originalOwner' from property struct
        final property = await getLandProperty(tokenId);
        return property?['originalOwner'];
      }
    } catch (e) {
      debugPrint('Error fetching ownerOf: $e');
    }
    return null;
  }

  // ═══════════════════════════════════════════════════════════
  // ELECTRONICS NFT METHODS
  // ═══════════════════════════════════════════════════════════

  Future<String?> mintElectronics({
    required String toAddress,
    required String serialNumber,
    required String brand,
    required String model,
    required String warrantyExpiry,
    required String tokenURI,
  }) async {
    await init();
    final function = _electronicsContract.function('mintElectronic');
    final transaction = Transaction.callContract(
      contract: _electronicsContract,
      function: function,
      parameters: [
        EthereumAddress.fromHex(toAddress),
        serialNumber,
        brand,
        model,
        warrantyExpiry,
        tokenURI,
      ],
    );
    return await _sendTransaction(transaction);
  }

  Future<Map<String, dynamic>?> getDevice(int tokenId) async {
    await init();
    try {
      final function = _electronicsContract.function('getDevice');
      final result = await _client.call(
        contract: _electronicsContract,
        function: function,
        params: [BigInt.from(tokenId)],
      );

      // FIX: Unwrap the struct (it is the first item in the result list)
      final deviceData = result[0] as List<dynamic>;

      return {
        'brand': deviceData[0],
        'model': deviceData[1],
        'serialNumber': deviceData[2],
        'warrantyExpiry': deviceData[3],
        'mintedAt': (deviceData[4] as BigInt).toInt(),
        'originalOwner': (deviceData[5] as EthereumAddress).toString(),
        'isVerified': deviceData[6],
        'status': deviceData.length > 7 ? (deviceData[7] as BigInt).toInt() : 0,
        'ownerCount': deviceData.length > 8 ? (deviceData[8] as BigInt).toInt() : 0,
      };
    } catch (e) {
      debugPrint('Error getDevice: $e');
      return null;
    }
  }


  Future<String?> submitElectronicsReview({required int tokenId, required String reviewText}) async {
    await init();
    final reviewBytes = Uint8List.fromList(utf8.encode(reviewText));
    final reviewHash = keccak256(reviewBytes);

    final function = _electronicsContract.function('submitReview');
    final transaction = Transaction.callContract(
      contract: _electronicsContract,
      function: function,
      parameters: [BigInt.from(tokenId), reviewHash],
    );
    return await _sendTransaction(transaction);
  }

  Future<String?> grantVendorRole(String address) async {
    await init();
    final function = _electronicsContract.function('addVendor');
    final transaction = Transaction.callContract(
      contract: _electronicsContract,
      function: function,
      parameters: [EthereumAddress.fromHex(address)],
    );
    return await _sendTransaction(transaction);
  }

  Future<String?> grantRetailerRole(String address) async {
    await init();
    final function = _electronicsContract.function('addRetailer');
    final transaction = Transaction.callContract(
      contract: _electronicsContract,
      function: function,
      parameters: [EthereumAddress.fromHex(address)],
    );
    return await _sendTransaction(transaction);
  }

  // ═══════════════════════════════════════════════════════════
  // LAND FRACTIONAL NFT METHODS
  // ═══════════════════════════════════════════════════════════

  Future<String?> createLandProperty({
    required String location,
    required String city,
    required int totalArea,
    required String areaUnit,
    required int totalFractions,
    required BigInt pricePerFraction,
    required String ipfsMetadata,
  }) async {
    await init();
    final function = _landContract.function('createProperty');
    final transaction = Transaction.callContract(
      contract: _landContract,
      function: function,
      parameters: [
        location,
        city,
        BigInt.from(totalArea),
        areaUnit,
        BigInt.from(totalFractions),
        pricePerFraction,
        ipfsMetadata,
      ],
    );
    return await _sendTransaction(transaction);
  }

  Future<String?> purchaseLandFractions({
    required int propertyId,
    required int amount,
    required BigInt totalCost,
  }) async {
    await init();
    final function = _landContract.function('purchaseFractions');
    final transaction = Transaction.callContract(
      contract: _landContract,
      function: function,
      parameters: [BigInt.from(propertyId), BigInt.from(amount)],
      value: EtherAmount.inWei(totalCost),
    );
    return await _sendTransaction(transaction);
  }

  /// Returns the ID of the most recently minted electronics token (= totalMinted).
  /// Call this immediately after a confirmed mintElectronics transaction.
  Future<int?> getLastElectronicsTokenId() async {
    await init();
    try {
      final function = _electronicsContract.function('totalMinted');
      final result = await _client.call(
        contract: _electronicsContract,
        function: function,
        params: [],
      );
      return (result.first as BigInt).toInt();
    } catch (e) {
      debugPrint('getLastElectronicsTokenId error: $e');
      return null;
    }
  }

  /// Returns the ID of the most recently created land property (= getTotalProperties).
  /// Call this immediately after a confirmed createLandProperty transaction.
  Future<int?> getLastLandPropertyId() async {
    await init();
    try {
      final function = _landContract.function('getTotalProperties');
      final result = await _client.call(
        contract: _landContract,
        function: function,
        params: [],
      );
      return (result.first as BigInt).toInt();
    } catch (e) {
      debugPrint('getLastLandPropertyId error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getLandProperty(int propertyId) async {
    await init();
    try {
      final function = _landContract.function('getProperty');
      final result = await _client.call(
        contract: _landContract,
        function: function,
        params: [BigInt.from(propertyId)],
      );

      // FIX: Unwrap the struct (same logic as getDevice)
      final landData = result[0] as List<dynamic>;

      return {
        'location': landData[0],
        'city': landData[1],
        'totalArea': (landData[2] as BigInt).toInt(),
        'areaUnit': landData[3],
        'totalFractions': (landData[4] as BigInt).toInt(),
        'pricePerFraction': landData[5] as BigInt,
        'createdAt': (landData[6] as BigInt).toInt(),
        'originalOwner': (landData[7] as EthereumAddress).toString(),
        'ipfsMetadata': landData[8],
        'isVerified': landData[9],
      };
    } catch (e) {
      debugPrint('Error getLandProperty: $e');
      return null;
    }
  }

  Future<int> getUserFractions(String userAddress, int propertyId) async {
    await init();
    try {
      final function = _landContract.function('balanceOf');
      final result = await _client.call(
        contract: _landContract,
        function: function,
        params: [EthereumAddress.fromHex(userAddress), BigInt.from(propertyId)],
      );
      return (result.first as BigInt).toInt();
    } catch (e) {
      return 0;
    }
  }

  Future<BigInt> getUnclaimedRent(String userAddress, int propertyId) async {
    await init();
    try {
      final function = _landContract.function('getUnclaimedRent');
      final result = await _client.call(
        contract: _landContract,
        function: function,
        params: [BigInt.from(propertyId), EthereumAddress.fromHex(userAddress)],
      );
      return result.first as BigInt;
    } catch (e) {
      return BigInt.zero;
    }
  }

  Future<String?> distributeLandRent({required int propertyId, required BigInt amount}) async {
    await init();
    final function = _landContract.function('distributeRent');
    final transaction = Transaction.callContract(
      contract: _landContract,
      function: function,
      parameters: [BigInt.from(propertyId)],
      value: EtherAmount.inWei(amount),
    );
    return await _sendTransaction(transaction);
  }

  Future<String?> claimLandRent(int propertyId) async {
    await init();
    final function = _landContract.function('claimRent');
    final transaction = Transaction.callContract(
      contract: _landContract,
      function: function,
      parameters: [BigInt.from(propertyId)],
    );
    return await _sendTransaction(transaction);
  }

  // ═══════════════════════════════════════════════════════════
  // TENANT RENT PAYMENT
  // ═══════════════════════════════════════════════════════════

  /// Tenant pays rent on-chain for [propertyId].
  ///
  /// [amount] must be in Wei — use [etherToWei] before calling:
  ///   final wei = blockchainService.etherToWei(0.05);
  ///   final tx  = await blockchainService.payLandRent(propertyId: 42, amount: wei);
  ///
  /// Returns tx hash on success, null if the user rejected in their wallet.
  Future<String?> payLandRent({
    required int propertyId,
    required BigInt amount,
  }) async {
    await init();
    final function = _landContract.function('payRent');
    final transaction = Transaction.callContract(
      contract: _landContract,
      function: function,
      parameters: [BigInt.from(propertyId)],
      value: EtherAmount.inWei(amount),   // MATIC sent with the call
    );
    return await _sendTransaction(transaction);
  }

  Future<String?> transferLandFraction({
    required String toAddress,
    required int propertyId,
    required int amount,
  }) async {
    await init();
    // FIX: ERC-1155 safeTransferFrom takes 5 params (from, to, id, amount, bytes).
    // Use findFunctionsByName to avoid "Too many elements" if ABI has overloads.
    final overloads = _landContract.findFunctionsByName('safeTransferFrom');
    final function = overloads.firstWhere(
          (f) => f.parameters.length == 5,
      orElse: () => overloads.first,
    );
    final transaction = Transaction.callContract(
      contract: _landContract,
      function: function,
      parameters: [
        EthereumAddress.fromHex(connectedAddress!),
        EthereumAddress.fromHex(toAddress),
        BigInt.from(propertyId),
        BigInt.from(amount),
        Uint8List(0),
      ],
    );
    return await _sendTransaction(transaction);
  }

  // ═══════════════════════════════════════════════════════════
  // UTILITIES
  // ═══════════════════════════════════════════════════════════

  String bytesToHex(Uint8List bytes, {bool include0x = false}) {
    return (include0x ? "0x" : "") + bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  BigInt etherToWei(double ether) {
    String val = ether.toStringAsFixed(18);
    val = val.replaceAll(RegExp(r'0+$'), '');
    val = val.replaceAll(RegExp(r'\.$'), '');
    if (val.isEmpty || val == '0') return BigInt.zero;
    return EtherAmount.fromBase10String(EtherUnit.ether, val).getInWei;
  }

  String weiToEther(BigInt wei) {
    return EtherAmount.inWei(wei).getValueInUnit(EtherUnit.ether).toString();
  }

  Future<bool> waitForConfirmation(String txHash, {int retries = 30}) async {
    debugPrint('⏳ Waiting for confirmation: $txHash');
    for (int i = 0; i < retries; i++) {
      try {
        final receipt = await _client.getTransactionReceipt(txHash);
        if (receipt != null) {
          if (receipt.status == true) {
            debugPrint('✅ Transaction Confirmed!');
            return true;
          } else {
            debugPrint('❌ Transaction Reverted');
            return false;
          }
        }
      } catch (e) {
        // Ignore temporary network issues
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════
  // SECURITY & SELF-HEALING
  // ═══════════════════════════════════════════════════════════

  /// Verifies Firestore data against Blockchain truth and heals if tampered.
  /// Returns true if data was healthy, false if a healing operation was performed.
  Future<bool> verifyAndHealAsset({
    required String type,
    required int blockchainId,
    required String firestoreDocId,
    required FirebaseFirestore firestore,
  }) async {
    try {
      await init();
      final docRef = firestore.collection('assets').doc(firestoreDocId);
      final docSnap = await docRef.get();
      if (!docSnap.exists) return true;

      final data = docSnap.data()!;
      bool isTampered = false;
      Map<String, dynamic> updates = {};

      if (type == 'electronics') {
        final device = await getDevice(blockchainId);
        if (device == null) return true;
        
        // Check Owner & Heal ownerId/ownerUid
        final currentOwner = await getOwnerOf(type, blockchainId);
        if (currentOwner != null) {
          final chainAddr = currentOwner.toLowerCase();
          final dbAddr = data['currentOwnerAddress']?.toString().toLowerCase();
          
          if (dbAddr != chainAddr) {
            isTampered = true;
            updates['currentOwnerAddress'] = currentOwner;
          }

          // Resolve ownerId from wallet address
          final userQuery = await firestore.collection('users')
              .where('walletAddress', isEqualTo: currentOwner)
              .limit(1).get();
          
          if (userQuery.docs.isNotEmpty) {
            final correctUid = userQuery.docs.first.id;
            if (data['ownerId'] != correctUid) {
              isTampered = true;
              updates['ownerId'] = correctUid;
              updates['ownerUid'] = correctUid;
            }
          }
        }

        // Check Serial
        if (data['serialNumber'] != device['serialNumber']) {
          isTampered = true;
          updates['serialNumber'] = device['serialNumber'];
        }

        // Check tokenURI / IPFS
        try {
          final uriFunction = _electronicsContract.function('tokenURI');
          final uriResult = await _client.call(
            contract: _electronicsContract,
            function: uriFunction,
            params: [BigInt.from(blockchainId)],
          );
          final tokenURI = uriResult.first as String;
          if (data['ipfsMetadata'] != null && data['ipfsMetadata'] != tokenURI) {
            isTampered = true;
            updates['ipfsMetadata'] = tokenURI;
          }
        } catch (e) {
          debugPrint('Could not fetch tokenURI: $e');
        }
      } else if (type == 'land') {
        final property = await getLandProperty(blockchainId);
        if (property == null) return true;

        // Check Price
        final chainPriceEther = double.parse(weiToEther(property['pricePerFraction']));
        final dbPrice = (data['pricePerFraction'] ?? 0).toDouble();
        
        // Allow tiny precision diffs, but flag major tampering
        if ((chainPriceEther - dbPrice).abs() > 0.0001) {
          isTampered = true;
          updates['pricePerFraction'] = chainPriceEther;
        }

        // Check Total Fractions
        if (data['totalFractions'] != property['totalFractions']) {
          isTampered = true;
          updates['totalFractions'] = property['totalFractions'];
        }
      }

      if (isTampered) {
        debugPrint('⚠️ SECURITY ALERT: Tampered data detected for $firestoreDocId. Healing from blockchain...');
        await docRef.update(updates);
        return false; // Healing performed
      }

      return true; // Healthy
    } catch (e) {
      debugPrint('Healing error: $e');
      return true; // Fail safe
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ADMIN & SUPPLY CHAIN ACTIONS
  // ═══════════════════════════════════════════════════════════

  /// Verifies an electronic device on-chain. Required to flip 'isVerified' to true.
  Future<String?> verifyDevice(int tokenId) async {
    await init();
    final function = _electronicsContract.function('verifyDevice');
    final transaction = Transaction.callContract(
      contract: _electronicsContract,
      function: function,
      parameters: [BigInt.from(tokenId)],
    );
    return await _sendTransaction(transaction);
  }

  /// Verifies a land property on-chain.
  Future<String?> verifyProperty(int propertyId) async {
    await init();
    final function = _landContract.function('verifyProperty');
    final transaction = Transaction.callContract(
      contract: _landContract,
      function: function,
      parameters: [BigInt.from(propertyId)],
    );
    return await _sendTransaction(transaction);
  }

  /// Transfers an electronics NFT from the current owner (Admin/Dell) to a Supplier.
  Future<String?> transferElectronics({
    required String toAddress,
    required int tokenId,
  }) async {
    await init();
    
    // FIX: ERC-721 ABI has overloads for safeTransferFrom. 
    // Pick the one with 3 parameters: (address from, address to, uint256 tokenId)
    final overloads = _electronicsContract.findFunctionsByName('safeTransferFrom');
    final function = overloads.firstWhere(
      (f) => f.parameters.length == 3,
      orElse: () => overloads.first,
    );

    final transaction = Transaction.callContract(
      contract: _electronicsContract,
      function: function,
      parameters: [
        EthereumAddress.fromHex(connectedAddress!),
        EthereumAddress.fromHex(toAddress),
        BigInt.from(tokenId),
      ],
    );
    return await _sendTransaction(transaction);
  }
}