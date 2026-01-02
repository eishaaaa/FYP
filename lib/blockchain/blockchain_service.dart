// lib/blockchain/blockchain_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'wallet_service.dart';
import 'contract_config.dart';

class BlockchainServiceEnhanced {
  late final Web3Client _client;
  late DeployedContract _electronicsContract;
  late DeployedContract _landContract;

  final WalletService _walletService = WalletService();
  bool _isInitialized = false;

  BlockchainServiceEnhanced() {
    _client = Web3Client(ContractConfig.rpcUrl, http.Client());
  }

  /// Helper: Aggressively removes invisible characters and spaces
  String _sanitizeAddress(String address) {
    String clean = address.replaceAll(RegExp(r'[^0-9a-fA-FxX]'), '');
    if (!clean.startsWith('0x')) {
      clean = '0x$clean';
    }
    return clean;
  }

  /// Initialize contracts and load ABIs
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      final electronicsAbi = await rootBundle.loadString('assets/abi/ElectronicsNFT.json');
      final landAbi = await rootBundle.loadString('assets/abi/LandFractionalNFT.json');

      final electronicsJson = jsonDecode(electronicsAbi);
      final landJson = jsonDecode(landAbi);

      final cleanElectronicsAddr = _sanitizeAddress(ContractConfig.electronicsNFTAddress);
      final cleanLandAddr = _sanitizeAddress(ContractConfig.landNFTAddress);

      _electronicsContract = DeployedContract(
        ContractAbi.fromJson(jsonEncode(electronicsJson['abi']), 'ElectronicsNFT'),
        EthereumAddress.fromHex(cleanElectronicsAddr),
      );

      _landContract = DeployedContract(
        ContractAbi.fromJson(jsonEncode(landJson['abi']), 'LandFractionalNFT'),
        EthereumAddress.fromHex(cleanLandAddr),
      );

      _isInitialized = true;
      print('✅ Blockchain Service Initialized');
    } catch (e) {
      print('❌ Blockchain Init Error: $e');
    }
  }

  /// Connect Wallet using Reown AppKit Modal
  Future<String?> connectWallet(BuildContext context) async {
    await _walletService.init(context);
    final modal = _walletService.appKitModal;

    if (!modal.isConnected) {
      await modal.openModalView();
    }

    if (modal.isConnected && modal.session != null) {
      final session = modal.session!;
      if (session.namespaces != null && session.namespaces?['eip155'] != null) {
        final accounts = session.namespaces?['eip155']?.accounts;
        if (accounts != null && accounts.isNotEmpty) {
          final address = accounts.first.split(':').last;
          print('✅ Wallet Connected: $address');
          return address;
        }
      }
    }
    return null;
  }

  String? get connectedAddress {
    if (_walletService.isInitialized && _walletService.appKitModal.isConnected) {
      final session = _walletService.appKitModal.session;
      final accounts = session?.namespaces?['eip155']?.accounts;
      if (accounts != null && accounts.isNotEmpty) {
        return accounts.first.split(':').last;
      }
    }
    return null;
  }

  bool get isConnected => connectedAddress != null;

  // ═══════════════════════════════════════════════════════════
  // TRANSACTION HELPERS
  // ═══════════════════════════════════════════════════════════

  Future<bool> waitForConfirmation(String txHash, {int retries = 30}) async {
    print('⏳ Waiting for confirmation: $txHash');
    for (int i = 0; i < retries; i++) {
      try {
        final receipt = await _client.getTransactionReceipt(txHash);
        if (receipt != null) {
          if (receipt.status == true) {
            print('✅ Transaction Confirmed!');
            return true;
          } else {
            print('❌ Transaction Reverted');
            return false;
          }
        }
      } catch (e) {
        // Ignore network hiccups
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    return false;
  }

  Future<String> _sendTransaction(Transaction transaction) async {
    if (!isConnected) throw Exception('Wallet not connected');

    try {
      final gasPrice = await _client.getGasPrice();
      // Increase gas price slightly (10%) to ensure it goes through
      final adjustedGasPrice = (gasPrice.getInWei * BigInt.from(110)) ~/ BigInt.from(100);

      BigInt estimatedGas;
      try {
        estimatedGas = await _client.estimateGas(
          sender: EthereumAddress.fromHex(connectedAddress!),
          to: transaction.to,
          data: transaction.data,
          value: transaction.value,
        );
      } catch (e) {
        print('⚠️ Gas estimation failed, using fallback: $e');
        estimatedGas = BigInt.from(500000);
      }

      final adjustedGasLimit = (estimatedGas * BigInt.from(120)) ~/ BigInt.from(100);

      final txParams = {
        'from': connectedAddress,
        'to': transaction.to?.toString(),
        'data': bytesToHex(transaction.data ?? Uint8List(0), include0x: true),
        'value': '0x${(transaction.value?.getInWei ?? BigInt.zero).toRadixString(16)}',
        'gas': '0x${adjustedGasLimit.toRadixString(16)}',
        'gasPrice': '0x${adjustedGasPrice.toRadixString(16)}',
      };

      final session = _walletService.appKitModal.session!;
      final result = await _walletService.appKitModal.request(
        topic: session.topic,
        chainId: 'eip155:${ContractConfig.chainId}',
        request: SessionRequestParams(
          method: 'eth_sendTransaction',
          params: [txParams],
        ),
      );

      return result.toString();
    } catch (e) {
      print('❌ Transaction Failed: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // ELECTRONICS METHODS
  // ═══════════════════════════════════════════════════════════

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
      print('Error getDevice: $e');
      return null;
    }
  }

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

  Future<String?> submitElectronicsReview({required int tokenId, required String reviewText}) async {
    await init();
    final reviewBytes = Uint8List.fromList(utf8.encode(reviewText));
    // Keccak256 is available in web3dart package
    final reviewHash = keccak256(reviewBytes);
    final function = _electronicsContract.function('submitReview');
    final transaction = Transaction.callContract(
      contract: _electronicsContract,
      function: function,
      parameters: [BigInt.from(tokenId), reviewHash],
    );
    return await _sendTransaction(transaction);
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

  // ═══════════════════════════════════════════════════════════
  // LAND METHODS
  // ═══════════════════════════════════════════════════════════

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
      print('Error getLandProperty: $e');
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
  // UTILS
  // ═══════════════════════════════════════════════════════════

  String bytesToHex(Uint8List bytes, {bool include0x = false}) {
    return (include0x ? "0x" : "") + bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  BigInt etherToWei(double ether) {
    String val = ether.toString();
    // Safety check: if number is "2.0", turn it into "2"
    if (val.endsWith('.0')) {
      val = val.substring(0, val.length - 2);
    }
    return EtherAmount.fromBase10String(EtherUnit.ether, val).getInWei;
  }

  String weiToEther(BigInt wei) {
    return EtherAmount.inWei(wei).getValueInUnit(EtherUnit.ether).toString();
  }
}