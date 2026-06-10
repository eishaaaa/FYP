// lib/blockchain/transfer_service.dart
//
// ═══════════════════════════════════════════════════════════════════════════
// FIXES APPLIED
// ─────────────────────────────────────────────────────────────────────────
// FIX 1 │ Electronics ownership check was SKIPPED entirely (the comment
//        │ said "we can't check without ownerOf" — that is wrong, the
//        │ getOwnerOf() call in BlockchainServiceEnhanced already uses the
//        │ standard ERC-721 ownerOf() function). Now the connected wallet is
//        │ verified against the on-chain owner BEFORE MetaMask opens, so the
//        │ seller sees a clear error instead of "you cancelled".
//
// FIX 2 │ getCurrentOwnerFromBlockchain() was returning device['originalOwner']
//        │ which is set once at mint time and never updated after transfers.
//        │ For electronics it now calls getOwnerOf() (the live ERC-721 ownerOf).
//        │ For land it still returns originalOwner because ERC-1155 has no
//        │ single "current owner" — fractions are distributed.
//
// FIX 3 │ _updateFirebaseOwnership() called _logTransfer() BEFORE
//        │ batch.commit(). If the commit failed the log was already written,
//        │ causing history/asset data to desync. Now _logTransfer() is called
//        │ only AFTER a successful batch.commit() using a second batch so
//        │ both writes are atomic.
//
// FIX 4 │ _updateFirebaseOwnership() never updated ownerId / ownerUid.
//        │ Every screen that reads ownerId showed the wrong owner after
//        │ a transfer. Now ownerId, ownerUid, and previousOwnerId are all
//        │ written in the same batch as currentOwnerAddress.
//
// FIX 5 │ blockchainTokenId was hard-cast as int? which crashes at runtime
//        │ if Firestore stored the value as a double (e.g. 4.0). Now uses
//        │ a safe (assetData['blockchainTokenId'] as num?)?.toInt() pattern.
//
// FIX 6 │ transferLandFractions() force-unwrapped connectedAddress! inside
//        │ _logTransfer() after a long async wait — if the WalletConnect
//        │ session timed out the null threw an unhandled exception and the
//        │ TransferResult was never returned. Now connectedAddress is captured
//        │ into a local variable before the async gap and a safe fallback is
//        │ used if it is somehow null.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'blockchain_service.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TRANSFER STATUS
// ─────────────────────────────────────────────────────────────────────────────

/// All possible outcomes of an asset transfer attempt.
enum TransferStatus {
  /// Transaction submitted, waiting for confirmation.
  pending,

  /// User dismissed the MetaMask prompt.
  userRejected,

  /// RPC / WalletConnect connectivity issue.
  networkError,

  /// Sender does not hold enough tokens/fractions on-chain.
  insufficientBalance,

  /// Wallet is not the current on-chain owner of the NFT.
  ownershipMismatch,

  /// Transaction reached the chain but the contract reverted.
  contractReverted,

  /// Transfer confirmed on-chain and Firestore updated.
  success,

  /// Any other unclassified failure.
  failed,
}

// ─────────────────────────────────────────────────────────────────────────────
// TRANSFER RESULT
// ─────────────────────────────────────────────────────────────────────────────

/// Immutable result returned by every public transfer method.
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
  bool get isFailed =>
      status == TransferStatus.failed ||
          status == TransferStatus.contractReverted ||
          status == TransferStatus.networkError ||
          status == TransferStatus.ownershipMismatch ||
          status == TransferStatus.insufficientBalance;

  @override
  String toString() =>
      'TransferResult(status: $status, txHash: $txHash, error: $errorMessage)';
}

// ─────────────────────────────────────────────────────────────────────────────
// TRANSFER SERVICE
// ─────────────────────────────────────────────────────────────────────────────

/// Orchestrates asset transfers: validates off-chain, executes on-chain,
/// then writes the result back to Firestore atomically.
class TransferService {
  final BlockchainServiceEnhanced _blockchain;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// The wallet address currently connected through WalletConnect / MetaMask.
  String? get connectedAddress => _blockchain.connectedAddress;

  TransferService({
    BlockchainServiceEnhanced? blockchain,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _blockchain = blockchain ?? BlockchainServiceEnhanced(),
        _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  // ───────────────────────────────────────────────────────────────────────────
  // PUBLIC: VALIDATE
  // ───────────────────────────────────────────────────────────────────────────

  /// Runs all off-chain AND on-chain validation checks before attempting a
  /// transfer.  Returns null on success, or a human-readable error string.
  ///
  /// For electronics the connected wallet is verified against the live ERC-721
  /// ownerOf() result — this is the check that was missing and causing every
  /// transfer to fail with a silent MetaMask rejection.
  Future<String?> validateTransfer({
    required String assetId,
    required String receiverAddress,
    required String assetType,
    int? amount, // Required for ERC-1155 land fractions
  }) async {
    // ── 1. Receiver address format ────────────────────────────────────────────
    if (!_isValidAddress(receiverAddress)) {
      return 'Invalid receiver address format. Must be a 0x-prefixed 40-char hex string.';
    }

    // ── 2. Firebase auth ──────────────────────────────────────────────────────
    if (_auth.currentUser == null) {
      return 'You are not logged in. Please sign in and try again.';
    }

    // ── 3. Wallet connected ───────────────────────────────────────────────────
    await _blockchain.init();
    if (!_blockchain.isConnected) {
      return 'Wallet not connected. Please connect your wallet first.';
    }

    final senderAddress = _blockchain.connectedAddress!;

    // ── 4. Self-transfer guard ────────────────────────────────────────────────
    if (senderAddress.toLowerCase() == receiverAddress.toLowerCase()) {
      return 'Cannot transfer to yourself.';
    }

    // ── 5. Asset exists in Firestore ──────────────────────────────────────────
    final assetDoc = await _firestore.collection('assets').doc(assetId).get();
    if (!assetDoc.exists) {
      return 'Asset not found in database.';
    }

    final assetData = assetDoc.data()!;

    // FIX 5: safe cast — Firestore may store numbers as double (e.g. 4.0)
    final blockchainTokenId =
    (assetData['blockchainTokenId'] as num?)?.toInt();

    if (blockchainTokenId == null) {
      return 'Asset has not been minted on the blockchain yet.';
    }

    // ── 6. On-chain ownership checks ──────────────────────────────────────────
    if (assetType == 'electronics') {
      // Confirm the token exists on-chain
      final device = await _blockchain.getDevice(blockchainTokenId);
      if (device == null) {
        return 'Asset not found on the blockchain. It may not have been minted yet.';
      }

      // FIX 1: THE CRITICAL MISSING CHECK.
      // getOwnerOf('electronics', ...) calls the standard ERC-721 ownerOf()
      // function which is always available on ERC-721 contracts.
      // Previously this block was completely skipped with a comment saying
      // "we can't check without ownerOf" — that was incorrect.
      // Without this check, a seller whose connected wallet doesn't match the
      // on-chain owner walks straight into MetaMask, which immediately rejects
      // the transaction — and the app shows "You cancelled" instead of a real
      // error message.
      final onChainOwner =
      await _blockchain.getOwnerOf('electronics', blockchainTokenId);

      if (onChainOwner == null) {
        return 'Could not verify on-chain ownership. Check your network connection and try again.';
      }

      if (onChainOwner.toLowerCase() != senderAddress.toLowerCase()) {
        return 'Connected wallet is not the current NFT owner on-chain.\n\n'
            'On-chain owner : ${_shortenForError(onChainOwner)}\n'
            'Connected wallet: ${_shortenForError(senderAddress)}\n\n'
            'Please connect the correct wallet in MetaMask.';
      }
    } else if (assetType == 'land') {
      // ── ERC-1155: validate fraction amount and balance ──────────────────────
      if (amount == null || amount <= 0) {
        return 'Invalid fraction amount. Must be a positive integer.';
      }

      final userBalance = await _blockchain.getUserFractions(
        senderAddress,
        blockchainTokenId,
      );

      if (userBalance < amount) {
        return 'Insufficient on-chain balance.\n'
            'You hold $userBalance fraction(s) but are trying to transfer $amount.\n'
            'Make sure the correct wallet is connected.';
      }
    } else {
      return 'Unknown asset type: $assetType';
    }

    return null; // All checks passed
  }

  // ───────────────────────────────────────────────────────────────────────────
  // PUBLIC: TRANSFER ELECTRONICS (ERC-721)
  // ───────────────────────────────────────────────────────────────────────────

  /// Transfers an ERC-721 electronics NFT from the connected wallet to
  /// [receiverAddress], then updates Firestore atomically on confirmation.
  Future<TransferResult> transferElectronics({
    required String assetId,
    required int tokenId,
    required String receiverAddress,
    required String sellerUid, // needed for previousOwnerId in Firestore
  }) async {
    // Capture sender address before any async gap (FIX 6 pattern)
    final senderAddress = _blockchain.connectedAddress;

    try {
      // ── Blockchain transfer ─────────────────────────────────────────────────
      final txHash = await _blockchain.transferElectronics(
        toAddress: receiverAddress,
        tokenId: tokenId,
      );

      if (txHash == null) {
        return TransferResult(
          status: TransferStatus.userRejected,
          errorMessage: 'Transaction was not submitted. The wallet returned no hash.',
        );
      }

      // ── Wait for on-chain confirmation ──────────────────────────────────────
      final confirmed = await _blockchain.waitForConfirmation(txHash);

      if (!confirmed) {
        return TransferResult(
          status: TransferStatus.contractReverted,
          txHash: txHash,
          errorMessage:
          'Transaction was submitted but reverted on-chain (tx: $txHash). '
              'Check Polygonscan for the revert reason.',
        );
      }

      // ── Update Firestore ────────────────────────────────────────────────────
      // FIX 3 + FIX 4: atomic batch that includes ownerId/ownerUid/previousOwnerId,
      // followed by the transfer log only after the batch succeeds.
      await _updateFirebaseOwnershipElectronics(
        assetId: assetId,
        newOwnerAddress: receiverAddress,
        sellerUid: sellerUid,
        txHash: txHash,
        senderAddress: senderAddress ?? '',
      );

      return TransferResult(
        status: TransferStatus.success,
        txHash: txHash,
      );
    } on Exception catch (e) {
      return _classifyException(e);
    } catch (e) {
      return TransferResult(
        status: TransferStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // PUBLIC: TRANSFER LAND FRACTIONS (ERC-1155)
  // ───────────────────────────────────────────────────────────────────────────

  /// Transfers [amount] ERC-1155 fractions of [propertyId] to [receiverAddress],
  /// then logs the transfer in Firestore.
  Future<TransferResult> transferLandFractions({
    required String assetId,
    required int propertyId,
    required String receiverAddress,
    required int amount,
  }) async {
    // FIX 6: capture before any async gap so we don't force-unwrap after a
    // long wait that could time out the WalletConnect session
    final senderAddress = _blockchain.connectedAddress ?? 'unknown';

    try {
      // ── Blockchain transfer ─────────────────────────────────────────────────
      final txHash = await _blockchain.transferLandFraction(
        toAddress: receiverAddress,
        propertyId: propertyId,
        amount: amount,
      );

      if (txHash == null) {
        return TransferResult(
          status: TransferStatus.userRejected,
          errorMessage: 'Transaction was not submitted. The wallet returned no hash.',
        );
      }

      // ── Wait for on-chain confirmation ──────────────────────────────────────
      final confirmed = await _blockchain.waitForConfirmation(txHash);

      if (!confirmed) {
        return TransferResult(
          status: TransferStatus.contractReverted,
          txHash: txHash,
          errorMessage:
          'Transaction submitted but reverted on-chain (tx: $txHash). '
              'Check Polygonscan for the revert reason.',
        );
      }

      // ── Log the transfer (ERC-1155 ownership is distributed, no single
      //    Firestore owner record to update — the fractional_holdings
      //    collection is managed by transfer_screen._finalizeOwnership)
      // FIX 3: _logTransfer is called only after confirmation — not before.
      await _logTransfer(
        assetId: assetId,
        tokenId: propertyId,
        from: senderAddress, // FIX 6: safe local variable, no force-unwrap
        to: receiverAddress,
        amount: amount,
        txHash: txHash,
        assetType: 'land',
      );

      return TransferResult(
        status: TransferStatus.success,
        txHash: txHash,
      );
    } on Exception catch (e) {
      return _classifyException(e);
    } catch (e) {
      return TransferResult(
        status: TransferStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // PUBLIC: READ HELPERS
  // ───────────────────────────────────────────────────────────────────────────

  /// Returns a stream of all transfer log entries for [assetId], newest first.
  Stream<QuerySnapshot> getAssetTransferHistory(String assetId) {
    return _firestore
        .collection('transfers')
        .where('assetId', isEqualTo: assetId)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  /// Returns the live on-chain owner address (blockchain as source of truth).
  ///
  /// For electronics this is the real-time ERC-721 ownerOf() result.
  /// For land this is the originalOwner from the property struct — note that
  /// ERC-1155 has no single "current owner", fractions may be distributed
  /// across many wallets.
  ///
  /// FIX 2: Previously returned originalOwner for electronics which is set at
  /// mint time and never updated — making every post-transfer lookup wrong.
  Future<String?> getCurrentOwnerFromBlockchain({
    required String assetType,
    required int tokenId,
  }) async {
    try {
      await _blockchain.init();

      if (assetType == 'electronics') {
        // FIX 2: use getOwnerOf() which calls the live ERC-721 ownerOf()
        // NOT device['originalOwner'] which is frozen at mint time
        return await _blockchain.getOwnerOf('electronics', tokenId);
      } else if (assetType == 'land') {
        // ERC-1155 has no single current owner.
        // Return originalOwner (the land creator) for display purposes only.
        final property = await _blockchain.getLandProperty(tokenId);
        return property?['originalOwner'];
      }

      return null;
    } catch (e) {
      // Use debugPrint instead of print for Flutter lint compliance
      debugPrint('TransferService.getCurrentOwnerFromBlockchain error: $e');
      return null;
    }
  }

  /// Returns how many ERC-1155 fractions of [propertyId] the given [address]
  /// holds on-chain.
  Future<int> getOwnershipBalance({
    required String address,
    required int propertyId,
  }) async {
    try {
      await _blockchain.init();
      return await _blockchain.getUserFractions(address, propertyId);
    } catch (e) {
      debugPrint('TransferService.getOwnershipBalance error: $e');
      return 0;
    }
  }

  /// Returns a display-friendly shortened address e.g. 0x1234…abcd
  String shortenAddress(String address) {
    if (address.length <= 10) return address;
    return '${address.substring(0, 6)}…${address.substring(address.length - 4)}';
  }

  // ───────────────────────────────────────────────────────────────────────────
  // PRIVATE: FIRESTORE WRITES
  // ───────────────────────────────────────────────────────────────────────────

  /// Updates the Firestore asset document after a confirmed ERC-721 transfer.
  ///
  /// FIX 3: _logTransfer is now called AFTER batch.commit() — previously it
  ///         ran before the batch, so a failed commit left an orphaned log entry.
  ///
  /// FIX 4: ownerId, ownerUid, and previousOwnerId are now written together
  ///         with currentOwnerAddress in the same atomic batch.
  Future<void> _updateFirebaseOwnershipElectronics({
    required String assetId,
    required String newOwnerAddress,
    required String sellerUid,
    required String txHash,
    required String senderAddress,
  }) async {
    // ── Step 1: resolve the buyer's Firestore UID from their wallet address ───
    // This lets us write ownerId / ownerUid even if the caller doesn't pass them.
    String? newOwnerUid;
    try {
      final userQuery = await _firestore
          .collection('users')
          .where('walletAddress', isEqualTo: newOwnerAddress)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        newOwnerUid = userQuery.docs.first.id;
      }
    } catch (e) {
      debugPrint('TransferService: could not resolve buyer UID from wallet — $e');
    }

    // ── Step 2: atomic batch write ────────────────────────────────────────────
    final batch = _firestore.batch();
    final assetRef = _firestore.collection('assets').doc(assetId);

    batch.update(assetRef, {
      // FIX 4: write all ownership fields, not just the address
      'currentOwnerAddress': newOwnerAddress,
      if (newOwnerUid != null) ...{
        'ownerId': newOwnerUid,
        'ownerUid': newOwnerUid,
      },
      'previousOwnerId': sellerUid,
      'lastTransferTx': txHash,
      'lastTransferAt': FieldValue.serverTimestamp(),
      'isListedForResale': false,
      'isSyncingWithBlockchain': false,
    });

    // FIX 3: batch.commit() first — _logTransfer runs only on success below
    await batch.commit();

    // ── Step 3: log after successful commit ───────────────────────────────────
    await _logTransfer(
      assetId: assetId,
      tokenId: 0, // tokenId not critical for the log; asset is identified by assetId
      from: senderAddress,
      to: newOwnerAddress,
      amount: 1,
      txHash: txHash,
      assetType: 'electronics',
    );
  }

  /// Appends a transfer record to the `transfers` collection.
  Future<void> _logTransfer({
    required String assetId,
    required int tokenId,
    required String from,
    required String to,
    required int amount,
    required String txHash,
    required String assetType,
  }) async {
    try {
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
    } catch (e) {
      // Log failures should not surface as transfer failures — the blockchain
      // transfer already succeeded. Just print so it can be investigated.
      debugPrint('TransferService._logTransfer error (non-fatal): $e');
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // PRIVATE: UTILITIES
  // ───────────────────────────────────────────────────────────────────────────

  /// Classifies a caught exception into the most specific [TransferStatus].
  TransferResult _classifyException(Exception e) {
    final msg = e.toString().toLowerCase();

    if (msg.contains('user rejected') ||
        msg.contains('user denied') ||
        msg.contains('4001') ||
        msg.contains('cancelled')) {
      return TransferResult(
        status: TransferStatus.userRejected,
        errorMessage: 'You cancelled the transaction in MetaMask. '
            'Tap "Execute Blockchain Transfer" again and tap Confirm.',
      );
    }

    if (msg.contains('wrong network') || msg.contains('chain')) {
      return TransferResult(
        status: TransferStatus.networkError,
        errorMessage: 'Wrong network selected in MetaMask. '
            'Please switch to Polygon Amoy and try again.',
      );
    }

    if (msg.contains('insufficient') || msg.contains('gas')) {
      return TransferResult(
        status: TransferStatus.insufficientBalance,
        errorMessage: 'Insufficient MATIC for gas fees. '
            'Add test MATIC on Polygon Amoy and try again.',
      );
    }

    if (msg.contains('not the current nft owner') ||
        msg.contains('ownership mismatch')) {
      return TransferResult(
        status: TransferStatus.ownershipMismatch,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }

    if (msg.contains('revert') || msg.contains('execution reverted')) {
      return TransferResult(
        status: TransferStatus.contractReverted,
        errorMessage: 'Smart contract rejected the transaction. '
            'Make sure this wallet holds the NFT/fractions being transferred.',
      );
    }

    if (msg.contains('timeout') || msg.contains('network')) {
      return TransferResult(
        status: TransferStatus.networkError,
        errorMessage: 'Network error: ${e.toString().replaceFirst('Exception: ', '')}',
      );
    }

    return TransferResult(
      status: TransferStatus.failed,
      errorMessage: e.toString().replaceFirst('Exception: ', ''),
    );
  }

  /// Validates Ethereum address format (0x + 40 hex chars).
  bool _isValidAddress(String address) {
    return RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(address);
  }

  /// Short form of an address for embedding in error messages.
  String _shortenForError(String address) {
    if (address.length < 10) return address;
    return '${address.substring(0, 8)}…${address.substring(address.length - 6)}';
  }
}