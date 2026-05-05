// ═══════════════════════════════════════════════════════════
// COMPLETE BLOCKCHAIN SERVICE (FINAL OPTIMIZED VERSION)
// Location: lib/blockchain/blockchain_service.dart
//
// FIXES INCLUDED:
// 1. Gas Fees: Tuned to 25.5 Gwei (Minimum safe for Amoy Testnet)
// 2. Struct Parsing: Correctly unwraps nested lists from Web3Dart
// 3. ABI Loading: Handles both Hardhat Artifacts and Flat JSON
// ═══════════════════════════════════════════════════════════

import 'dart:async';
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

  String? _extractTransactionHash(dynamic rawValue) {
    if (rawValue == null) return null;
    final raw = rawValue.toString().trim();
    final match = RegExp(r'0x[a-fA-F0-9]{64}').firstMatch(raw);
    return match?.group(0);
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

      // FIX: TUNED GAS FEES (Robust values for Amoy — basefee can spike to 50+ Gwei)
      // maxFeePerGas must always exceed basefee + priority tip or MetaMask rejects immediately.
      // Rule: maxFeePerGas >= network basefee + maxPriorityFeePerGas
      final maxPriorityFee = BigInt.from(30000000000); // 30 Gwei tip
      final maxFee = BigInt.from(100000000000);        // 100 Gwei cap (absorbs basefee spikes)

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
      // NOTE: 8 minutes because Reown AppKit sometimes receives the WalletConnect
      // approval event (visible in logs as "[WalletKit] ✅ storeEvent") but does NOT
      // resolve the pending future. Giving extra time reduces false timeouts.
      // Callers must handle TimeoutException gracefully by verifying on-chain.
      final result = await futureResult.timeout(
        const Duration(minutes: 8),
        onTimeout: () {
          throw Exception(
            'Timeout: WalletConnect did not return the transaction hash. '
                'Your transaction may still have been submitted — '
                'check MetaMask Activity or Polygonscan for a pending tx.',
          );
        },
      );

      final normalizedHash = _extractTransactionHash(result);
      if (normalizedHash == null) {
        debugPrint('⚠️ Unexpected wallet response: $result');
        return result.toString().trim();
      }

      debugPrint('✅ Transaction Hash: $normalizedHash');
      return normalizedHash;

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

  Future<String?> _sendContractTransaction(DeployedContract contract, String functionName, List<dynamic> params, {BigInt? value, ContractFunction? function}) async {
    await init();
    try {
      final func = function ?? contract.function(functionName);
      final transaction = Transaction.callContract(
        contract: contract,
        function: func,
        parameters: params,
        value: value != null ? EtherAmount.inWei(value) : null,
      );
      return await _sendTransaction(transaction);
    } catch (e) {
      debugPrint('Error in _sendContractTransaction ($functionName): $e');
      rethrow; // ← Surface real errors to the UI instead of silently returning null
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
    return _sendContractTransaction(_electronicsContract, 'mintElectronic', [
      EthereumAddress.fromHex(toAddress),
      serialNumber,
      brand,
      model,
      warrantyExpiry,
      tokenURI,
    ]);
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

      // SAFE PARSING: Check length to prevent RangeError
      return {
        'brand': deviceData.isNotEmpty ? deviceData[0] : 'Unknown',
        'model': deviceData.length > 1 ? deviceData[1] : 'Unknown',
        'serialNumber': deviceData.length > 2 ? deviceData[2] : 'Unknown',
        'warrantyExpiry': deviceData.length > 3 ? deviceData[3] : 'Unknown',
        'mintedAt': deviceData.length > 4 ? (deviceData[4] as BigInt).toInt() : 0,
        'originalOwner': deviceData.length > 5 ? (deviceData[5] as EthereumAddress).toString() : '0x0',
        'isVerified': deviceData.length > 6 ? deviceData[6] : false,
        'status': deviceData.length > 7 ? (deviceData[7] as BigInt).toInt() : 0,
        'ownerCount': deviceData.length > 8 ? (deviceData[8] as BigInt).toInt() : 0,
      };
    } catch (e) {
      debugPrint('Error getDevice: $e');
      return null;
    }
  }


  Future<String?> submitElectronicsReview({required int tokenId, required String reviewText}) async {
    final reviewBytes = Uint8List.fromList(utf8.encode(reviewText));
    final reviewHash = keccak256(reviewBytes);
    return _sendContractTransaction(_electronicsContract, 'submitReview', [BigInt.from(tokenId), reviewHash]);
  }

  Future<String?> grantVendorRole(String address) async {
    return _sendContractTransaction(_electronicsContract, 'addVendor', [EthereumAddress.fromHex(address)]);
  }

  Future<String?> grantRetailerRole(String address) async {
    return _sendContractTransaction(_electronicsContract, 'addRetailer', [EthereumAddress.fromHex(address)]);
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
    return _sendContractTransaction(_landContract, 'purchaseFractions', [BigInt.from(propertyId), BigInt.from(amount)], value: totalCost);
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
      return (result.first as BigInt).toInt(); // IDs are 1-indexed in contract (_tokenIds++)
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
      return (result.first as BigInt).toInt(); // IDs are 1-indexed in contract (_propertyIds += 1)
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

      // SAFE PARSING: Check length to prevent RangeError (The contract ABI has 10 fields)
      return {
        'location': landData.isNotEmpty ? landData[0] : 'Unknown',
        'city': landData.length > 1 ? landData[1] : 'Unknown',
        'totalArea': landData.length > 2 ? (landData[2] as BigInt).toInt() : 0,
        'areaUnit': landData.length > 3 ? landData[3] : 'unit',
        'totalFractions': landData.length > 4 ? (landData[4] as BigInt).toInt() : 0,
        'pricePerFraction': landData.length > 5 ? (landData[5] as BigInt) : BigInt.zero,
        'createdAt': landData.length > 6 ? (landData[6] as BigInt).toInt() : 0,
        'originalOwner': landData.length > 7 ? (landData[7] as EthereumAddress).toString() : '0x0',
        'ipfsMetadata': landData.length > 8 ? landData[8] : '',
        'isVerified': landData.length > 9 ? landData[9] : false,
        // FALLBACKS for rental fields (if not in current ABI)
        'hasRentalData': landData.length > 10,
        'isForRent': landData.length > 10 ? landData[10] : false,
        'monthlyRent': landData.length > 11 ? (landData[11] as BigInt) : BigInt.zero,
        'currentTenant': landData.length > 12 ? (landData[12] as EthereumAddress).toString() : '0x0000000000000000000000000000000000000000',
        'pendingTenant': landData.length > 13 ? (landData[13] as EthereumAddress).toString() : '0x0000000000000000000000000000000000000000',
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

  Future<int> getEscrowBalance(int propertyId) async {
    await init();
    try {
      final function = _landContract.function('balanceOf');
      final result = await _client.call(
        contract: _landContract,
        function: function,
        params: [EthereumAddress.fromHex(_landContract.address.hex), BigInt.from(propertyId)],
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
    return _sendContractTransaction(_landContract, 'distributeRent', [BigInt.from(propertyId)], value: amount);
  }

  Future<String?> listLandForRent({required int propertyId, required BigInt rentAmount}) async {
    return _sendContractTransaction(_landContract, 'listForRent', [BigInt.from(propertyId), rentAmount]);
  }

  Future<String?> requestLandRent(int propertyId) async {
    return _sendContractTransaction(_landContract, 'requestRent', [BigInt.from(propertyId)]);
  }

  Future<String?> acceptLandRentRequest(int propertyId) async {
    return _sendContractTransaction(_landContract, 'acceptRentRequest', [BigInt.from(propertyId)]);
  }

  Future<String?> payLandMonthlyRent({required int propertyId, required BigInt amount}) async {
    return _sendContractTransaction(_landContract, 'payMonthlyRent', [BigInt.from(propertyId)], value: amount);
  }

  Future<String?> claimLandRent(int propertyId) async {
    return _sendContractTransaction(_landContract, 'claimRent', [BigInt.from(propertyId)]);
  }

  // ═══════════════════════════════════════════════════════════
  // REVIEWS & ROLES
  // ═══════════════════════════════════════════════════════════

  Future<String?> transferLandFraction({
    required String toAddress,
    required int propertyId,
    required int amount,
  }) async {
    await init();
    final overloads = _landContract.findFunctionsByName('safeTransferFrom');
    final function = overloads.firstWhere(
          (f) => f.parameters.length == 5,
      orElse: () => overloads.first,
    );
    return _sendContractTransaction(_landContract, 'safeTransferFrom', [
      EthereumAddress.fromHex(connectedAddress!),
      EthereumAddress.fromHex(toAddress),
      BigInt.from(propertyId),
      BigInt.from(amount),
      Uint8List(0),
    ], function: function);
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

  Future<bool> waitForConfirmation(String txHash, {int retries = 80}) async {
    final normalizedHash = _extractTransactionHash(txHash) ?? txHash.trim();
    if (!RegExp(r'^0x[a-fA-F0-9]{64}$').hasMatch(normalizedHash)) {
      debugPrint('❌ Invalid transaction hash for confirmation: $txHash');
      return false;
    }

    debugPrint('⏳ Waiting for confirmation: $normalizedHash');
    for (int i = 0; i < retries; i++) {
      try {
        final receipt = await _client.getTransactionReceipt(normalizedHash);
        if (receipt != null) {
          if (receipt.status == true) {
            debugPrint('✅ Transaction Confirmed!');
            return true;
          } else {
            debugPrint('❌ Transaction Reverted');
            return false;
          }
        }
      } catch (_) {}

      try {
        final resp = await http.post(
          Uri.parse('https://rpc-amoy.polygon.technology'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'method': 'eth_getTransactionReceipt',
            'params': [normalizedHash],
            'id': 1,
          }),
        ).timeout(const Duration(seconds: 10));

        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final result = body['result'];
        if (result != null && result is Map) {
          final status = result['status'] as String?;
          if (status == '0x1') {
            debugPrint('✅ Transaction Confirmed via fallback RPC!');
            return true;
          }
          if (status == '0x0') {
            debugPrint('❌ Transaction Reverted via fallback RPC');
            return false;
          }
        }
      } catch (_) {}

      await Future.delayed(const Duration(seconds: 4));
    }
    return false;
  }

  // ═══════════════════════════════════════════════════════════
  // SECURITY & SELF-HEALING
  // ═══════════════════════════════════════════════════════════

  /// Restores a missing Firestore document from blockchain truth.
  Future<void> restoreAssetFromBlockchain({
    required String type,
    required int tokenId,
    required FirebaseFirestore firestore,
  }) async {
    try {
      await init();
      final owner = await getOwnerOf(type, tokenId);
      if (owner == null) return;

      Map<String, dynamic> chainData;
      if (type == 'electronics') {
        final d = await getDevice(tokenId);
        if (d == null) return;
        chainData = {
          'title': '${d['brand']} ${d['model']}',
          'brand': d['brand'],
          'model': d['model'],
          'serial': d['serialNumber'],
          'category': 'electronics',
          'verified': d['isVerified'],
        };
      } else {
        final l = await getLandProperty(tokenId);
        if (l == null) return;
        chainData = {
          'title': l['location'],
          'city': l['city'],
          'plotArea': l['plotArea'],
          'category': 'land',
          'verified': l['isVerified'],
          'totalFractions': l['totalFractions'],
        };
      }

      // Resolve owner UID
      final userQuery = await firestore.collection('users')
          .where('walletAddress', isEqualTo: owner)
          .limit(1).get();

      String? ownerUid;
      if (userQuery.docs.isNotEmpty) {
        ownerUid = userQuery.docs.first.id;
      }

      final assetId = 'restored_$tokenId';
      await firestore.collection('assets').doc(assetId).set({
        ...chainData,
        'blockchainTokenId': tokenId,
        'ownerId': ownerUid,
        'ownerUid': ownerUid,
        'currentOwnerAddress': owner,
        'isRestored': true,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      debugPrint('✅ Restored asset $assetId from blockchain');
    } catch (e) {
      debugPrint('❌ Restoration failed: $e');
    }
  }

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

      if (!docSnap.exists) {
        // 🚨 Problem 7: If deleted from Firebase, recreate it!
        await restoreAssetFromBlockchain(type: type, tokenId: blockchainId, firestore: firestore);
        return false;
      }

      final data = docSnap.data()!;

      // 🚨 NEW: Grace period (2 minutes) to allow blockchain confirmation
      final lastUpdate = data['updatedAt'] ?? data['createdAt'];
      if (lastUpdate is Timestamp) {
        final age = DateTime.now().difference(lastUpdate.toDate());
        if (age.inMinutes < 2) {
          debugPrint('🛡️ Healing skipped (Grace period active for $firestoreDocId)');
          return true;
        }
      }

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

        // Check Stolen Status (from blockchain status field)
        // status 0 = Normal, 1 = Stolen
        final chainStolen = device['status'] == 1;
        final dbStolen = data['isStolen'] == true || data['reportedStolen'] == true;
        if (chainStolen != dbStolen) {
          isTampered = true;
          updates['isStolen'] = chainStolen;
          updates['reportedStolen'] = chainStolen;
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

        // --- Rental Healing (Only if Blockchain supports it) ---
        if (property['hasRentalData'] == true) {
          if (data['isForRent'] != property['isForRent']) {
            isTampered = true;
            updates['isForRent'] = property['isForRent'];
          }

          final chainRentEther = double.parse(weiToEther(property['monthlyRent']));
          final dbRent = (data['monthlyRent'] ?? 0).toDouble();
          if ((chainRentEther - dbRent).abs() > 0.0001) {
            isTampered = true;
            updates['monthlyRent'] = chainRentEther;
          }

          final chainTenant = property['currentTenant'].toString().toLowerCase();
          final dbTenant = (data['currentTenantAddress'] ?? data['currentTenant'] ?? '').toString().toLowerCase();
          if (dbTenant != chainTenant) {
            isTampered = true;
            updates['currentTenantAddress'] = property['currentTenant'];
          }
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
    return _sendContractTransaction(_electronicsContract, 'verifyDevice', [BigInt.from(tokenId)]);
  }

  Future<String?> verifyProperty(int propertyId) async {
    return _sendContractTransaction(_landContract, 'verifyProperty', [BigInt.from(propertyId)]);
  }

  /// Transfers an electronics NFT from the current owner (Admin/Dell) to a Supplier.
  Future<String?> transferElectronics({
    required String toAddress,
    required int tokenId,
  }) async {
    await init();
    final overloads = _electronicsContract.findFunctionsByName('safeTransferFrom');
    final function = overloads.firstWhere(
          (f) => f.parameters.length == 3,
      orElse: () => overloads.first,
    );
    return _sendContractTransaction(_electronicsContract, 'safeTransferFrom', [
      EthereumAddress.fromHex(connectedAddress!),
      EthereumAddress.fromHex(toAddress),
      BigInt.from(tokenId),
    ], function: function);
  }

  // ═══════════════════════════════════════════════════════════
  // RENTAL STATE MACHINE (State-Managed Flow)
  // ═══════════════════════════════════════════════════════════

  /// Moves funds to escrow and activates the rental
  Future<void> activateRental(String txId) async {
    final txRef = FirebaseFirestore.instance.collection('transactions').doc(txId);
    final txSnap = await txRef.get();
    if (!txSnap.exists) return;

    final data = txSnap.data()!;
    final fee = (data['rentalFee'] ?? 0.0).toDouble();
    final deposit = (data['depositAmount'] ?? 0.0).toDouble();
    final leaseMonths = data['leaseMonths'] ?? 6;
    final ownerUid = data['sellerUid'];

    // 💸 Immediate Transfer of Rent to Owner (Supplier)
    // and Lock Deposit in Escrow
    await _walletService.lockFunds(fee + deposit);
    await _walletService.consumeLockedFunds(fee); // Transfer rent to owner immediately

    // Log the transaction for the owner
    if (ownerUid != null) {
      await FirebaseFirestore.instance.collection('users').doc(ownerUid).collection('history').add({
        'type': 'received',
        'amount': fee,
        'title': 'Rental Payment Received',
        'timestamp': FieldValue.serverTimestamp(),
        'transactionId': txId,
      });
    }

    final start = DateTime.now();
    final expiry = start.add(Duration(days: leaseMonths * 30));

    await txRef.update({
      'status': 'active',
      'startDate': start,
      'expiryDate': expiry,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // 🕒 Start a local timer for this rental
    _watchRentalExpiry(txId, expiry);
    debugPrint('🚀 Rental Activated: $txId. Expiry: $expiry');
  }

  /// Finalizes transaction: releases deposit to renter, pays fee to owner
  Future<void> finalizeTransaction(String txId) async {
    final txRef = FirebaseFirestore.instance.collection('transactions').doc(txId);
    final txSnap = await txRef.get();
    if (!txSnap.exists) return;

    final data = txSnap.data()!;
    if (data['status'] == 'completed' || data['status'] == 'disputed') return;

    final fee = (data['rentalFee'] ?? 0.0).toDouble();
    final deposit = (data['depositAmount'] ?? 0.0).toDouble();

    // 💸 Distribute funds: Deposit back to user, Fee to owner
    await _walletService.unlockFunds(deposit);
    await _walletService.consumeLockedFunds(fee);

    await txRef.update({
      'status': 'completed',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Reset asset availability
    final assetId = data['assetId'];
    if (assetId != null) {
      await FirebaseFirestore.instance.collection('assets').doc(assetId).update({
        'currentTenant': null,
        'currentTenantAddress': null,
        'isForRent': true, // Make it available again
      });
    }
    debugPrint('🏁 Rental Finalized: $txId');
  }

  /// Owner recalls the asset with a pro-rata refund to the renter
  Future<void> recallAsset(String txId) async {
    final txRef = FirebaseFirestore.instance.collection('transactions').doc(txId);
    final txSnap = await txRef.get();
    if (!txSnap.exists) return;

    final data = txSnap.data()!;
    final startTs = data['startDate'] as Timestamp?;
    final expiryTs = data['expiryDate'] as Timestamp?;

    if (startTs == null || expiryTs == null) return;

    final start = startTs.toDate();
    final expiry = expiryTs.toDate();
    final totalDays = expiry.difference(start).inDays;
    final usedDays = DateTime.now().difference(start).inDays;

    final fee = (data['rentalFee'] ?? 0.0).toDouble();
    final deposit = (data['depositAmount'] ?? 0.0).toDouble();

    // 🧮 Pro-rata refund calculation: (RemainingTime / TotalTime) * Fee
    double refund = 0;
    if (totalDays > 0 && usedDays < totalDays) {
      refund = fee * (1 - (usedDays / totalDays));
    }

    // Move status to recallPending before finalization
    await txRef.update({
      'status': 'recallPending',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Finalize with refund
    await _walletService.unlockFunds(deposit + refund);
    await _walletService.consumeLockedFunds(fee - refund);

    await txRef.update({
      'status': 'completed',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final assetId = data['assetId'];
    if (assetId != null) {
      await FirebaseFirestore.instance.collection('assets').doc(assetId).update({
        'currentTenant': null,
        'currentTenantAddress': null,
        'isForRent': true,
      });
    }
    debugPrint('🚨 Asset Recalled: $txId. Refund: $refund');
  }

  /// Moves rental to DISPUTED status, locking funds for admin review
  Future<void> disputeRental(String txId, String reason) async {
    final txRef = FirebaseFirestore.instance.collection('transactions').doc(txId);
    await txRef.update({
      'status': 'disputed',
      'disputeReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('⚖️ Rental Disputed: $txId. Reason: $reason');
  }

  /// Internal watcher for rental expiry
  void _watchRentalExpiry(String txId, DateTime expiry) {
    final duration = expiry.difference(DateTime.now());
    if (duration.isNegative) {
      finalizeTransaction(txId);
    } else {
      Timer(duration, () => finalizeTransaction(txId));
    }
  }
}