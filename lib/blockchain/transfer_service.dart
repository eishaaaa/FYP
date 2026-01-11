// lib/blockchain/transfer_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'blockchain_service.dart';

/// Transfer result status
enum TransferStatus {
  pending,
  userRejected,
  networkError,
  insufficientBalance,
  contractReverted,
  success,
  failed,
}

/// Transfer result data
class TransferResult {
  final TransferStatus status;
  final String? txHash;
  final String? errorMessage;
  final DateTime timestamp;

  TransferResult({
    required this.status,
    this.txHash,
    this.errorMessage,
  }) : timestamp = DateTime.now();

  bool get isSuccess => status == TransferStatus.success;
  bool get isPending => status == TransferStatus.pending;
  bool get isFailed => status == TransferStatus.failed ||
      status == TransferStatus.contractReverted ||
      status == TransferStatus.networkError;
}

/// Service for handling asset transfers
class TransferService {
  final BlockchainServiceEnhanced _blockchain;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  // getter
  String? get connectedAddress => _blockchain.connectedAddress;

  TransferService({
    BlockchainServiceEnhanced? blockchain,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _blockchain = blockchain ?? BlockchainServiceEnhanced(),
        _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// Validate transfer request (off-chain checks)
  Future<String?> validateTransfer({
    required String assetId,
    required String receiverAddress,
    required String assetType,
    int? amount, // For ERC-1155 only
  }) async {
    // 1. Check receiver address format
    if (!_isValidAddress(receiverAddress)) {
      return 'Invalid receiver address format';
    }

    // 2. Check user is logged in
    if (_auth.currentUser == null) {
      return 'User not authenticated';
    }

    // 3. Check wallet is connected
    await _blockchain.init();
    if (!_blockchain.isConnected) {
      return 'Wallet not connected';
    }

    final senderAddress = _blockchain.connectedAddress!;

    // 4. Check sender != receiver
    if (senderAddress.toLowerCase() == receiverAddress.toLowerCase()) {
      return 'Cannot transfer to yourself';
    }

    // 5. Get asset data from Firebase
    final assetDoc = await _firestore.collection('assets').doc(assetId).get();
    if (!assetDoc.exists) {
      return 'Asset not found';
    }

    final assetData = assetDoc.data()!;
    final blockchainTokenId = assetData['blockchainTokenId'] as int?;

    if (blockchainTokenId == null) {
      return 'Asset not minted on blockchain';
    }

    // 6. Verify ownership on blockchain
    if (assetType == 'electronics') {
      final device = await _blockchain.getDevice(blockchainTokenId);
      if (device == null) {
        return 'Asset not found on blockchain';
      }

      // In ERC-721, we can't easily check ownership without ownerOf function
      // This would require adding ownerOf to your smart contract
      // For now, trust Firebase data as preliminary check
    } else if (assetType == 'land') {
      if (amount == null || amount <= 0) {
        return 'Invalid amount for fractional transfer';
      }

      final userBalance = await _blockchain.getUserFractions(
        senderAddress,
        blockchainTokenId,
      );

      if (userBalance < amount) {
        return 'Insufficient balance: You own $userBalance fractions but trying to transfer $amount';
      }
    }

    return null; // Validation passed
  }

  /// Transfer Electronics NFT (ERC-721)
  Future<TransferResult> transferElectronics({
    required String assetId,
    required int tokenId,
    required String receiverAddress,
  }) async {
    try {
      // Execute blockchain transfer
      final txHash = await _blockchain.transferElectronic(
        toAddress: receiverAddress,
        tokenId: tokenId,
      );

      if (txHash == null) {
        return TransferResult(
          status: TransferStatus.userRejected,
          errorMessage: 'Transaction rejected by user',
        );
      }

      // Wait for confirmation
      final confirmed = await _blockchain.waitForConfirmation(txHash);

      if (!confirmed) {
        return TransferResult(
          status: TransferStatus.contractReverted,
          txHash: txHash,
          errorMessage: 'Transaction reverted on blockchain',
        );
      }

      // Update Firebase (secondary record)
      await _updateFirebaseOwnership(
        assetId: assetId,
        newOwnerAddress: receiverAddress,
        txHash: txHash,
        assetType: 'electronics',
      );

      return TransferResult(
        status: TransferStatus.success,
        txHash: txHash,
      );
    } catch (e) {
      return TransferResult(
        status: TransferStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  /// Transfer Land Fractions (ERC-1155)
  Future<TransferResult> transferLandFractions({
    required String assetId,
    required int propertyId,
    required String receiverAddress,
    required int amount,
  }) async {
    try {
      // Execute blockchain transfer
      final txHash = await _blockchain.transferLandFraction(
        toAddress: receiverAddress,
        propertyId: propertyId,
        amount: amount,
      );

      if (txHash == null) {
        return TransferResult(
          status: TransferStatus.userRejected,
          errorMessage: 'Transaction rejected by user',
        );
      }

      // Wait for confirmation
      final confirmed = await _blockchain.waitForConfirmation(txHash);

      if (!confirmed) {
        return TransferResult(
          status: TransferStatus.contractReverted,
          txHash: txHash,
          errorMessage: 'Transaction reverted on blockchain',
        );
      }

      // For ERC-1155, ownership is distributed
      // We don't change Firebase owner, but log the transfer
      await _logTransfer(
        assetId: assetId,
        tokenId: propertyId,
        from: _blockchain.connectedAddress!,
        to: receiverAddress,
        amount: amount,
        txHash: txHash,
        assetType: 'land',
      );

      return TransferResult(
        status: TransferStatus.success,
        txHash: txHash,
      );
    } catch (e) {
      return TransferResult(
        status: TransferStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  /// Update Firebase ownership record (ERC-721 only)
  Future<void> _updateFirebaseOwnership({
    required String assetId,
    required String newOwnerAddress,
    required String txHash,
    required String assetType,
  }) async {
    final batch = _firestore.batch();

    // Update asset document
    final assetRef = _firestore.collection('assets').doc(assetId);
    batch.update(assetRef, {
      'currentOwnerAddress': newOwnerAddress,
      'lastTransferTx': txHash,
      'lastTransferAt': FieldValue.serverTimestamp(),
    });

    // Log transfer history
    await _logTransfer(
      assetId: assetId,
      tokenId: 0, // Will be fetched from asset doc
      from: _blockchain.connectedAddress!,
      to: newOwnerAddress,
      amount: 1,
      txHash: txHash,
      assetType: assetType,
    );

    await batch.commit();
  }

  /// Log transfer to history collection
  Future<void> _logTransfer({
    required String assetId,
    required int tokenId,
    required String from,
    required String to,
    required int amount,
    required String txHash,
    required String assetType,
  }) async {
    await _firestore.collection('transfers').add({
      'assetId': assetId,
      'tokenId': tokenId,
      'from': from,
      'to': to,
      'amount': amount,
      'txHash': txHash,
      'assetType': assetType,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'confirmed',
    });
  }

  /// Get transfer history for an asset
  Stream<QuerySnapshot> getAssetTransferHistory(String assetId) {
    return _firestore
        .collection('transfers')
        .where('assetId', isEqualTo: assetId)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  /// Get current owner from blockchain (source of truth)
  Future<String?> getCurrentOwnerFromBlockchain({
    required String assetType,
    required int tokenId,
  }) async {
    try {
      await _blockchain.init();

      if (assetType == 'electronics') {
        final device = await _blockchain.getDevice(tokenId);
        return device?['originalOwner']; // Note: ERC-721 needs ownerOf function
      } else if (assetType == 'land') {
        final property = await _blockchain.getLandProperty(tokenId);
        return property?['originalOwner'];
      }

      return null;
    } catch (e) {
      print('Error fetching owner from blockchain: $e');
      return null;
    }
  }

  /// Check if address owns any fractions (for ERC-1155)
  Future<int> getOwnershipBalance({
    required String address,
    required int propertyId,
  }) async {
    try {
      await _blockchain.init();
      return await _blockchain.getUserFractions(address, propertyId);
    } catch (e) {
      print('Error checking balance: $e');
      return 0;
    }
  }

  /// Validate Ethereum address format
  bool _isValidAddress(String address) {
    final hexPattern = RegExp(r'^0x[a-fA-F0-9]{40}$');
    return hexPattern.hasMatch(address);
  }

  /// Shorten address for display
  String shortenAddress(String address) {
    if (address.length <= 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }
}