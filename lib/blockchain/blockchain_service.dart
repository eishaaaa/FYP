// ═══════════════════════════════════════════════════════════
// COMPLETE BLOCKCHAIN SERVICE (FINAL FIX)
// Place this in: lib/blockchain/blockchain_service.dart
// ═══════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:crypto/crypto.dart';

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
      final electronicsAbi = await rootBundle.loadString('assets/abi/ElectronicsNFT.json');
      final landAbi = await rootBundle.loadString('assets/abi/LandFractionalNFT.json');

      final electronicsJson = jsonDecode(electronicsAbi);
      final landJson = jsonDecode(landAbi);

      // Setup Contracts
      _electronicsContract = DeployedContract(
        ContractAbi.fromJson(jsonEncode(electronicsJson['abi']), 'ElectronicsNFT'),
        EthereumAddress.fromHex(_sanitizeAddress(ContractConfig.electronicsNFTAddress)),
      );

      _landContract = DeployedContract(
        ContractAbi.fromJson(jsonEncode(landJson['abi']), 'LandFractionalNFT'),
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
  // ✅ THE FIX: ROBUST TRANSACTION LOGIC
  // ═══════════════════════════════════════════════════════════

  Future<String> _sendTransaction(Transaction transaction) async {
    if (!isConnected) throw Exception('Wallet not connected. Please connect first.');

    final session = _walletService.appKitModal.session;
    if (session == null) throw Exception('Session is null. Reconnect.');

    // 1. NETWORK CHECK
    // If the wallet is on the wrong chain, we attempt to warn or switch
    final requiredChainId = 'eip155:${ContractConfig.chainId}';
    final approvedChains = session.namespaces?['eip155']?.chains ?? [];

    // Strict check: If session doesn't support Amoy, warn user
    if (!approvedChains.contains(requiredChainId)) {
      debugPrint('⚠️ Network Warning: App expects $requiredChainId. Wallet chains: $approvedChains');
    }

    try {
      debugPrint('🚀 Preparing Transaction...');

      // 2. CLEAN PARAMETERS (The Fix for Stale Nonces)
      // We explicitly REMOVE 'nonce', 'gas', and 'gasPrice'.
      // This forces MetaMask to calculate the NEXT valid nonce for every single click.
      final txParams = {
        'from': connectedAddress,
        'to': transaction.to?.toString(),
        'data': bytesToHex(transaction.data ?? Uint8List(0), include0x: true),
        'value': '0x${(transaction.value?.getInWei ?? BigInt.zero).toRadixString(16)}',
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

      // 4. 🔥 FORCE OPEN METAMASK (Deep Link)
      // We wait 1 second to ensure the request is registered, then switch apps.
      await Future.delayed(const Duration(milliseconds: 1000));
      _walletService.appKitModal.launchConnectedWallet();

      debugPrint('⏳ Waiting for user signature...');

      // 5. TIMEOUT
      // We wait 3 minutes. If you have "pending" transactions in MetaMask, clear them!
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
      // If RPC Error -32000, it usually means "Nonce too low" (Stale state)
      if (e.toString().contains('-32000')) {
        throw Exception('Wallet Sync Error: Please clear "Activity" or "Nonce" in MetaMask settings.');
      }
      rethrow;
    }
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
      return {
        'brand': result[0],
        'model': result[1],
        'serialNumber': result[2],
        'warrantyExpiry': result[3],
        'mintedAt': (result[4] as BigInt).toInt(),
        'originalOwner': (result[5] as EthereumAddress).toString(),
        'isVerified': result[6],
      };
    } catch (e) {
      debugPrint('Error getDevice: $e');
      return null;
    }
  }

  Future<String?> transferElectronic({
    required String toAddress,
    required int tokenId,
  }) async {
    await init();
    final function = _electronicsContract.function('safeTransferFrom');
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

  Future<String?> submitElectronicsReview({required int tokenId, required String reviewText}) async {
    await init();
    // Hash the review text
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

  Future<Map<String, dynamic>?> getLandProperty(int propertyId) async {
    await init();
    try {
      final function = _landContract.function('getProperty');
      final result = await _client.call(
        contract: _landContract,
        function: function,
        params: [BigInt.from(propertyId)],
      );

      return {
        'location': result[0],
        'city': result[1],
        'totalArea': (result[2] as BigInt).toInt(),
        'areaUnit': result[3],
        'totalFractions': (result[4] as BigInt).toInt(),
        'pricePerFraction': result[5] as BigInt,
        'createdAt': (result[6] as BigInt).toInt(),
        'originalOwner': (result[7] as EthereumAddress).toString(),
        'ipfsMetadata': result[8],
        'isVerified': result[9],
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

  Future<String?> transferLandFraction({
    required String toAddress,
    required int propertyId,
    required int amount,
  }) async {
    await init();
    final function = _landContract.function('safeTransferFrom');
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
}