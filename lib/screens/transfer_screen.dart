// lib/screens/transfer_screen.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../theme.dart';

import '../blockchain/blockchain_service.dart';
import '../services/push_notification_service.dart';

enum AssetType { electronics, land }

class TransferScreen extends StatefulWidget {
  final String assetId;
  final AssetType assetType;
  final String transactionId;
  final String buyerUid;
  final String sellerUid;
  final int? tokenId;
  final int? propertyId;
  final int? fractionAmount;
  final String assetPrice;
  final String buyerName;

  const TransferScreen({
    super.key,
    required this.assetId,
    required this.assetType,
    required this.transactionId,
    required this.buyerUid,
    required this.sellerUid,
    this.tokenId,
    this.propertyId,
    this.fractionAmount,
    required this.assetPrice,
    required this.buyerName,
  });

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _db = FirebaseFirestore.instance;
  final _bs = BlockchainServiceEnhanced();
  final _notif = PushNotificationService();

  // ── Stepper state ────────────────────────────────────────────
  int _currentStep = 0;

  // ── Data ─────────────────────────────────────────────────────
  String? _buyerWalletAddress;
  String? _assetTitle;
  bool _legalConfirmed = false;
  bool _walletConnected = false;

  // ── Transfer state ───────────────────────────────────────────
  bool _transferring = false;
  String _statusMessage = '';
  String? _txHash;
  bool _success = false;
  String? _errorMessage;

  // ── Stolen report guard ──────────────────────────────────────
  bool _loadingCheck = true;
  bool _isStolen = false;

  // ── Design tokens ────────────────────────────────────────────
  static const _accent = AppTheme.primaryStart;
  static const _surface = AppTheme.background;
  static const _cardRadius = 18.0;

  @override
  void initState() {
    super.initState();
    _loadPrerequisites();
  }

  Future<void> _loadPrerequisites() async {
    try {
      final results = await Future.wait([
        _db.collection('users').doc(widget.buyerUid).get(),
        _db.collection('assets').doc(widget.assetId).get(),
      ]);

      final buyerDoc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final assetDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>;
      final stolenFlag = assetDoc.data()?['isStolenReported'] as bool? ?? false;

      if (mounted) {
        setState(() {
          _buyerWalletAddress = buyerDoc.data()?['walletAddress'] as String?;
          _assetTitle = assetDoc.data()?['title'] as String? ?? 'Asset';
          _isStolen = stolenFlag;
          _loadingCheck = false;
        });
      }
    } catch (e) {
      debugPrint('_loadPrerequisites error: $e');
      if (mounted) setState(() => _loadingCheck = false);
    }
  }

  Future<void> _connectWallet() async {
    try {
      if (_bs.isConnected) {
        setState(() => _walletConnected = true);
        return;
      }
      final addr = await _bs.connectWallet(context);
      if (addr != null && mounted) {
        setState(() => _walletConnected = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Wallet connected: ${addr.substring(0, 10)}...'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Wallet error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _executeTransfer() async {
    if (_buyerWalletAddress == null || _buyerWalletAddress!.isEmpty) {
      setState(() => _errorMessage =
      'Buyer has not connected a wallet yet. Ask them to connect their wallet in the app first.');
      return;
    }

    setState(() {
      _transferring = true;
      _errorMessage = null;
      _statusMessage = 'Preparing transaction…';
    });

    final isLand    = widget.assetType == AssetType.land;
    final assetLabel = _assetTitle ?? 'Asset';

    try {
      // Flag asset as syncing to prevent race conditions in the UI
      await _db.collection('assets').doc(widget.assetId).update({
        'isSyncingWithBlockchain': true,
      });

      // ── Notify both parties: transfer is starting ─────────────
      await Future.wait([
        _notif.notify(
          receiverUid: widget.sellerUid,
          title       : '⏳ Transfer Initiated',
          body        : 'Blockchain transfer of "$assetLabel" to ${widget.buyerName} is in progress.',
          type        : NotificationType.transactionPending,
          relatedId   : widget.transactionId,
          payload     : {'assetId': widget.assetId, 'assetType': isLand ? 'land' : 'electronics'},
        ),
        _notif.notify(
          receiverUid: widget.buyerUid,
          title       : '⏳ Transfer In Progress',
          body        : 'The seller is transferring "$assetLabel" to your wallet. This may take a minute.',
          type        : NotificationType.transactionPending,
          relatedId   : widget.transactionId,
          payload     : {'assetId': widget.assetId},
        ),
      ]);

      String? txHash;

      if (widget.assetType == AssetType.electronics) {
        final id = widget.tokenId;
        if (id == null) throw Exception('Missing tokenId for electronics transfer');
        setState(() => _statusMessage =
        'Sending NFT transfer to blockchain…\nPlease approve in your wallet.');
        txHash = await _bs.transferElectronics(toAddress: _buyerWalletAddress!, tokenId: id);
      } else {
        final pid = widget.propertyId;
        final amount = widget.fractionAmount ?? 1;
        if (pid == null) throw Exception('Missing propertyId for land transfer');
        setState(() => _statusMessage =
        'Sending land fraction transfer…\nPlease approve in your wallet.');
        txHash = await _bs.transferLandFraction(
            toAddress: _buyerWalletAddress!, propertyId: pid, amount: amount);
      }

      if (txHash == null) throw Exception('Transaction was not submitted. Check your wallet.');

      txHash = txHash.trim();
      debugPrint('🔍 blockchain returned (trimmed): "$txHash" len=${txHash.length}');

      final isValidHash = txHash.startsWith('0x') &&
          txHash.length == 66 &&
          RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(txHash);

      if (!isValidHash) {
        final lower = txHash.toLowerCase();
        final isExplicitUserRejection =
            (lower.contains('user rejected') || lower.contains('user denied')) &&
                !lower.contains('gas') &&
                !lower.contains('revert') &&
                !lower.contains('execution');

        if (isExplicitUserRejection || lower.contains('4001')) {
          throw Exception(
              'You cancelled the transaction in MetaMask.\nTap "Execute Blockchain Transfer" again and tap Confirm.');
        }
        if (lower.contains('5000')) {
          throw Exception(
              'MetaMask session error (5000). Disconnect your wallet, reconnect, and make sure MetaMask is on the Polygon Amoy network.');
        }
        if (lower.contains('insufficient') || lower.contains('gas')) {
          throw Exception(
              'Not enough MATIC for gas fees. Add MATIC to your wallet on Polygon Amoy and try again.');
        }
        if (lower.contains('revert') || lower.contains('execution reverted')) {
          throw Exception(
              'Contract reverted the transaction. Make sure this wallet holds the NFT/fractions being transferred.\n\nRaw: $txHash');
        }
        throw Exception(
            'Unexpected wallet response — raw value:\n\n$txHash\n\nCheck MetaMask is on Polygon Amoy and this wallet holds the asset.');
      }

      setState(() {
        _txHash = txHash;
        _statusMessage =
        'Transaction submitted ✅\nWaiting for blockchain confirmation…\n\n$txHash';
      });

      final confirmed = await _pollConfirmation(txHash);
      if (!confirmed)
        throw Exception('Transaction not confirmed after timeout. Check Polygonscan for hash:\n$txHash');

      setState(() => _statusMessage = 'Confirmed on-chain ✅\nUpdating ownership records…');

      await _finalizeOwnership();

      // ── Notify both parties: transfer fully complete ──────────────
      final typeLabel = isLand ? 'Land fraction(s)' : 'Device';
      await Future.wait([
        _notif.notifyProductSold(
          sellerUid  : widget.sellerUid,
          productName: assetLabel,
          amount     : widget.assetPrice,
          orderId    : widget.transactionId,
        ),
        _notif.notifyProductPurchased(
          buyerUid   : widget.buyerUid,
          productName: assetLabel,
          amount     : widget.assetPrice,
          orderId    : widget.transactionId,
        ),
      ]);

      setState(() {
        _success = true;
        _transferring = false;
        _statusMessage = 'Ownership transferred successfully!';
      });

      if (mounted) {
        await Future.delayed(const Duration(seconds: 2));
        Navigator.pop(context, true);
      }
    } catch (e) {
      // Revert syncing flag on error
      try {
        await _db.collection('assets').doc(widget.assetId).update({
          'isSyncingWithBlockchain': false,
        });
      } catch (_) {}

      final errorMsg = e.toString().replaceFirst('Exception: ', '');
      final assetLabel = _assetTitle ?? 'Asset';

      // Notify both parties about the failure
      await Future.wait([
        _notif.notifyTransactionFailed(
          userUid  : widget.sellerUid,
          amount   : widget.assetPrice,
          currency : 'PKR',
          reason   : 'Transfer of "$assetLabel" could not be completed.',
          transactionId: widget.transactionId,
        ),
        _notif.notifyTransactionFailed(
          userUid  : widget.buyerUid,
          amount   : widget.assetPrice,
          currency : 'PKR',
          reason   : 'Transfer of "$assetLabel" by seller failed. Please contact support.',
          transactionId: widget.transactionId,
        ),
      ]);

      setState(() {
        _transferring = false;
        _errorMessage = errorMsg;
      });
    }
  }

  Future<bool> _pollConfirmation(String txHash, {int retries = 40}) async {
    const rpcUrl = 'https://rpc-amoy.polygon.technology';
    for (int i = 0; i < retries; i++) {
      try {
        final resp = await http.post(
          Uri.parse(rpcUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'method': 'eth_getTransactionReceipt',
            'params': [txHash],
            'id': 1,
          }),
        ).timeout(const Duration(seconds: 10));

        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final result = body['result'];
        if (result != null && result is Map) {
          final status = result['status'] as String?;
          if (status == '0x1') return true;
          if (status == '0x0')
            throw Exception('Transaction reverted on-chain. Check contract permissions.');
        }
      } catch (e) {
        if (e.toString().contains('reverted')) rethrow;
      }
      setState(() => _statusMessage =
      'Waiting for confirmation… (attempt ${i + 1}/$retries)\n\nTx: $_txHash');
      await Future.delayed(const Duration(seconds: 3));
    }
    return false;
  }

  Future<void> _finalizeOwnership() async {
    final batch = _db.batch();

    final assetRef = _db.collection('assets').doc(widget.assetId);
    batch.update(assetRef, {
      'ownerId': widget.buyerUid,
      'ownerUid': widget.buyerUid,
      'previousOwnerId': widget.sellerUid,
      'transferredAt': FieldValue.serverTimestamp(),
      'txHash': _txHash,
      'isListedForResale': false,
      'isSyncingWithBlockchain': false,
    });

    final txRef = _db.collection('transactions').doc(widget.transactionId);
    batch.update(txRef, {
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
      'blockchainTxHash': _txHash,
    });

    final orderRef = _db.collection('orders').doc();
    batch.set(orderRef, {
      'buyerId': widget.buyerUid,
      'sellerUid': widget.sellerUid,
      'assetId': widget.assetId,
      'category': widget.assetType == AssetType.electronics ? 'electronics' : 'land',
      'assetPrice': widget.assetPrice,
      'txHash': _txHash,
      'transferredAt': FieldValue.serverTimestamp(),
      if (widget.assetType == AssetType.electronics && widget.tokenId != null) ...{
        'tokenId': widget.tokenId,
        'warrantyActivatedAt': FieldValue.serverTimestamp(),
      },
      if (widget.assetType == AssetType.land) ...{
        'propertyId': widget.propertyId,
        'fractionAmount': widget.fractionAmount ?? 1,
      },
    });

    final price = double.tryParse(widget.assetPrice) ?? 0;
    if (price > 0) {
      final buyerRef = _db.collection('users').doc(widget.buyerUid);
      final sellerRef = _db.collection('users').doc(widget.sellerUid);
      batch.update(buyerRef, {'walletBalance': FieldValue.increment(-price)});
      batch.update(sellerRef, {'walletBalance': FieldValue.increment(price)});

      final payRef = _db.collection('payments').doc();
      batch.set(payRef, {
        'assetId': widget.assetId,
        'buyerUid': widget.buyerUid,
        'sellerUid': widget.sellerUid,
        'amount': price,
        'txHash': _txHash,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isLand = widget.assetType == AssetType.land;
    final title = isLand ? 'Transfer Land Ownership' : 'Transfer Electronics Ownership';

    PreferredSizeWidget appBar = AppBar(
      title: Text(title, style: AppTheme.heading(18, color: Colors.white)),
      flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.primaryGradient)),
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
    );

    if (_loadingCheck) {
      return Scaffold(
        backgroundColor: _surface,
        appBar: appBar,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_isStolen) {
      return Scaffold(
        backgroundColor: _surface,
        appBar: appBar,
        body: _buildStolenView(),
      );
    }

    return Scaffold(
      backgroundColor: _surface,
      appBar: appBar,
      body: _success ? _buildSuccessView() : _buildStepperView(isLand),
    );
  }

  // ── Stolen asset view ────────────────────────────────────────
  Widget _buildStolenView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.red[50],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.report_problem_rounded, color: Colors.red[600], size: 68),
          ),
          const SizedBox(height: 24),
          const Text(
            '🚨 Transfer Blocked',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Stolen asset reported',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          _infoCard(
            borderColor: Colors.red[200]!,
            backgroundColor: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '"${_assetTitle ?? 'This asset'}" has been reported as stolen by its registered owner.',
                  style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Divider(color: Colors.red[100]),
                const SizedBox(height: 12),
                const Text(
                  'This transfer cannot proceed. The asset is locked until the stolen report is resolved.',
                  style: TextStyle(fontSize: 13, height: 1.5, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _infoCard(
            borderColor: Colors.orange[200]!,
            backgroundColor: Colors.orange[50]!,
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.orange[700], size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'If you believe this is an error, contact the seller or reach out to support.',
                    style: TextStyle(fontSize: 12, color: Colors.orange[800]),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.chevron_left),
              label: const Text('Go Back'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: Colors.grey[300]!),
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Success view ─────────────────────────────────────────────
  Widget _buildSuccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.green[50],
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 72),
            ),
            const SizedBox(height: 24),
            const Text(
              'Ownership Transferred!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 10),
            Text(
              '${widget.buyerName} is now the official owner of $_assetTitle.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey[600], height: 1.5),
            ),
            if (_txHash != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: SelectableText(
                  'Tx: $_txHash',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500], fontFamily: 'monospace'),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Stepper view ─────────────────────────────────────────────
  Widget _buildStepperView(bool isLand) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppTheme.primaryStart),
      ),
      child: Stepper(
        currentStep: _currentStep,
        onStepContinue: _onStepContinue,
        onStepCancel: _currentStep > 0 ? () => setState(() => _currentStep--) : null,
        controlsBuilder: _buildStepControls,
        connectorColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _accent;
          return Colors.grey[300]!;
        }),
        steps: [
          _stepReview(isLand),
          _stepBuyerWallet(),
          _stepConnectSeller(),
          if (isLand) _stepLegalConfirmation(),
          _stepExecute(isLand),
        ],
      ),
    );
  }

  void _onStepContinue() {
    final isLand = widget.assetType == AssetType.land;
    final totalSteps = isLand ? 5 : 4;

    if (_currentStep == 2 && !_walletConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please connect your wallet first.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    if (isLand && _currentStep == 3 && !_legalConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please confirm legal paperwork before proceeding.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    if (_currentStep < totalSteps - 1) {
      setState(() => _currentStep++);
    } else {
      _executeTransfer();
    }
  }

  Widget _buildStepControls(BuildContext context, ControlsDetails details) {
    final isLand = widget.assetType == AssetType.land;
    final totalSteps = isLand ? 5 : 4;
    final isLastStep = _currentStep == totalSteps - 1;

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red[50],
                border: Border.all(color: Colors.red[200]!),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: Colors.red[700], size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red[800], fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          if (_transferring)
            Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(minHeight: 4),
                ),
                const SizedBox(height: 14),
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.5),
                ),
              ],
            )
          else ...[
            ElevatedButton(
              onPressed: details.onStepContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: isLastStep ? AppTheme.primaryStart : AppTheme.primaryStart,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: Text(
                isLastStep ? '🔗 Execute Blockchain Transfer' : 'Continue',
                style: AppTheme.heading(15, color: Colors.white),
              ),
            ),
            if (_currentStep > 0) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: details.onStepCancel,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  side: BorderSide(color: Colors.grey[300]!),
                  foregroundColor: Colors.black54,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Back'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ── Step 0: Review summary ───────────────────────────────────
  Step _stepReview(bool isLand) {
    return Step(
      title: Text('Transfer Summary', style: AppTheme.heading(16)),
      subtitle: Text('Review before proceeding', style: AppTheme.body(12)),
      isActive: _currentStep >= 0,
      content: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_cardRadius),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow(Icons.inventory_2_outlined, 'Asset', _assetTitle ?? '…'),
            _dividerLine(),
            _infoRow(Icons.person_outline, 'Buyer', widget.buyerName),
            _dividerLine(),
            _infoRow(Icons.payments_outlined, 'Amount', 'PKR ${widget.assetPrice}'),
            if (isLand && widget.fractionAmount != null) ...[
              _dividerLine(),
              _infoRow(Icons.pie_chart_outline, 'Fractions', '${widget.fractionAmount}'),
            ],
            _dividerLine(),
            _infoRow(
              Icons.token_outlined,
              isLand ? 'Property ID' : 'Token ID',
              '${isLand ? widget.propertyId : widget.tokenId}',
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber[200]!),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.amber[800], size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isLand
                          ? 'This will transfer land fractions on-chain. The buyer will become the official NFT + land owner.'
                          : 'This will transfer the electronics NFT on-chain. The buyer will own both the device and its NFT.',
                      style: TextStyle(fontSize: 12, color: Colors.amber[900], height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step 1: Buyer wallet ─────────────────────────────────────
  Step _stepBuyerWallet() {
    final hasWallet = _buyerWalletAddress != null && _buyerWalletAddress!.isNotEmpty;
    return Step(
      title: Text("Buyer's Wallet", style: AppTheme.heading(16)),
      subtitle: Text(hasWallet ? 'Wallet registered ✅' : 'Not yet connected ⚠️', style: AppTheme.body(12)),
      isActive: _currentStep >= 1,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasWallet) ...[
            _statusTile(
              icon: Icons.check_circle_rounded,
              iconColor: Colors.green,
              backgroundColor: Colors.green[50]!,
              borderColor: Colors.green[200]!,
              title: '${widget.buyerName} has a registered wallet.',
              subtitle: _buyerWalletAddress!,
              note: 'The NFT will be sent directly to this address.',
            ),
          ] else ...[
            _statusTile(
              icon: Icons.warning_amber_rounded,
              iconColor: Colors.red[600]!,
              backgroundColor: Colors.red[50]!,
              borderColor: Colors.red[200]!,
              title: '${widget.buyerName} has not connected a wallet.',
              subtitle:
              'The buyer must connect their MetaMask wallet in the app before you can transfer ownership.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadPrerequisites,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.grey[300]!),
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Step 2: Seller wallet ────────────────────────────────────
  Step _stepConnectSeller() {
    return Step(
      title: Text('Connect Your Wallet', style: AppTheme.heading(16)),
      subtitle: Text(_walletConnected
          ? 'Connected: ${_bs.connectedAddress?.substring(0, 12) ?? ''}…'
          : 'Not connected', style: AppTheme.body(12)),
      isActive: _currentStep >= 2,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Connect the wallet that currently holds the NFT. This wallet will sign the transfer transaction.',
            style: TextStyle(color: Colors.grey[600], fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 14),
          if (_walletConnected)
            _statusTile(
              icon: Icons.account_balance_wallet_rounded,
              iconColor: Colors.green[700]!,
              backgroundColor: Colors.green[50]!,
              borderColor: Colors.green[200]!,
              title: 'Wallet Connected',
              subtitle: _bs.connectedAddress ?? '',
            )
          else
            ElevatedButton.icon(
              onPressed: _connectWallet,
              icon: const Icon(Icons.account_balance_wallet_rounded),
              label: const Text('Connect Wallet'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
        ],
      ),
    );
  }

  // ── Step 3 (land only): Legal paperwork ─────────────────────
  Step _stepLegalConfirmation() {
    return Step(
      title: Text('Legal Confirmation', style: AppTheme.heading(16)),
      subtitle: Text('Required for land transfers', style: AppTheme.body(12)),
      isActive: _currentStep >= 3,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.gavel_rounded, color: Colors.blue[700], size: 18),
                    const SizedBox(width: 8),
                    Text('Land Registry Requirements',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, color: Colors.blue[800], fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 10),
                _legalPoint('All legal sale documents have been signed by both parties.'),
                _legalPoint('The sale deed / transfer deed has been executed.'),
                _legalPoint('Stamp duty and registration fees have been paid.'),
                _legalPoint('Land registry has been notified of the pending transfer.'),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: CheckboxListTile(
              value: _legalConfirmed,
              onChanged: (v) => setState(() => _legalConfirmed = v ?? false),
              title: const Text(
                'I confirm all legal paperwork has been completed and the land registry transfer is linked to this blockchain transaction.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: _accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 3/4: Execute ────────────────────────────────────────
  Step _stepExecute(bool isLand) {
    return Step(
      title: Text('Execute Transfer', style: AppTheme.heading(16)),
      subtitle: Text('Sign & send on blockchain', style: AppTheme.body(12)),
      isActive: _currentStep >= (isLand ? 4 : 3),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Text(
              isLand
                  ? '1. Opens your wallet to sign the ERC-1155 safeTransferFrom transaction.\n'
                  '2. Transfers ${widget.fractionAmount ?? 1} fraction(s) of Property #${widget.propertyId} to ${widget.buyerName}.\n'
                  '3. Updates ownership in the app once confirmed on Polygon Amoy.'
                  : '1. Opens your wallet to sign the ERC-721 safeTransferFrom transaction.\n'
                  '2. Transfers Token #${widget.tokenId} to ${widget.buyerName}.\n'
                  '3. Updates ownership in the app once confirmed on Polygon Amoy.',
              style: TextStyle(color: Colors.grey[700], fontSize: 13, height: 1.7),
            ),
          ),
          if (_txHash != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.link_rounded, size: 16, color: Colors.grey[500]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      _txHash!,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey[500], fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────
  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _accent),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _dividerLine() => Divider(height: 1, color: Colors.grey[100]);

  Widget _legalPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline, size: 14, color: Colors.blue[600]),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, height: 1.4))),
        ],
      ),
    );
  }

  Widget _statusTile({
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
    required Color borderColor,
    required String title,
    required String subtitle,
    String? note,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.black54)),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(note, style: TextStyle(fontSize: 12, color: iconColor)),
          ],
        ],
      ),
    );
  }

  Widget _infoCard({
    required Color borderColor,
    required Color backgroundColor,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BUYER OWNERSHIP ACCEPT SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class BuyerOwnershipAcceptScreen extends StatefulWidget {
  final String assetId;
  final String transactionId;
  final String sellerName;
  final AssetType assetType;

  const BuyerOwnershipAcceptScreen({
    super.key,
    required this.assetId,
    required this.transactionId,
    required this.sellerName,
    required this.assetType,
  });

  @override
  State<BuyerOwnershipAcceptScreen> createState() => _BuyerOwnershipAcceptScreenState();
}

class _BuyerOwnershipAcceptScreenState extends State<BuyerOwnershipAcceptScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _bs = BlockchainServiceEnhanced();
  final _notif = PushNotificationService();

  Map<String, dynamic>? _assetData;
  Map<String, dynamic>? _txData;
  bool _walletConnected = false;
  bool _walletSaved = false;
  bool _loading = true;
  String? _connectedAddress;
  String? _error;

  static const _accent = AppTheme.primaryStart;
  static const _surface = AppTheme.background;
  static const _cardRadius = 18.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _db.collection('assets').doc(widget.assetId).get(),
        _db.collection('transactions').doc(widget.transactionId).get(),
      ]);
      setState(() {
        _assetData = (results[0] as DocumentSnapshot<Map<String, dynamic>>).data();
        _txData = (results[1] as DocumentSnapshot<Map<String, dynamic>>).data();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _connectAndSaveWallet() async {
    try {
      String? addr = _bs.connectedAddress;
      if (addr == null || addr.isEmpty) addr = await _bs.connectWallet(context);
      if (addr == null || addr.isEmpty) return;

      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      await _db.collection('users').doc(uid).update({'walletAddress': addr});

      // Fetch the transaction to get the sellerUid and asset title
      final txDoc    = await _db.collection('transactions').doc(widget.transactionId).get();
      final txData   = txDoc.data() ?? {};
      final sellerUid = txData['sellerUid'] as String? ?? '';
      final assetTitle = _assetData?['title'] as String? ?? 'Asset';

      // Notify the buyer — wallet saved
      if (uid.isNotEmpty) {
        await _notif.notify(
          receiverUid: uid,
          title       : '✅ Wallet Registered',
          body        : 'Your wallet address has been saved. The seller can now initiate the transfer.',
          type        : NotificationType.general,
          relatedId   : widget.transactionId,
        );
      }

      // Notify the seller — buyer's wallet is now ready, they can proceed
      if (sellerUid.isNotEmpty) {
        await _notif.notify(
          receiverUid: sellerUid,
          title       : '🟢 Buyer Wallet Ready',
          body        : '${widget.sellerName.isNotEmpty ? "The buyer" : "Buyer"} has registered their wallet for "$assetTitle". You can now execute the blockchain transfer.',
          type        : NotificationType.transactionPending,
          relatedId   : widget.transactionId,
          payload     : {'assetId': widget.assetId, 'buyerWallet': addr},
        );
      }

      if (mounted) {
        setState(() {
          _walletConnected = true;
          _walletSaved = true;
          _connectedAddress = addr;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Wallet connected & saved: ${addr.substring(0, 12)}…'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLand = widget.assetType == AssetType.land;
    final txCompleted = _txData?['status'] == 'completed';
    final txHash = _txData?['blockchainTxHash'] as String?;

    return Scaffold(
      backgroundColor: _surface,
      appBar: AppBar(
        title: Text('Incoming Transfer', style: AppTheme.heading(18, color: Colors.white)),
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.primaryGradient)),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeaderCard(isLand, txCompleted),
            const SizedBox(height: 16),
            _buildAssetCard(),
            const SizedBox(height: 16),
            if (txCompleted && txHash != null) ...[
              _buildConfirmationCard(txHash),
              const SizedBox(height: 16),
            ],
            _buildWalletSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(bool isLand, bool txCompleted) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(_cardRadius),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryStart.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              txCompleted ? Icons.move_to_inbox_rounded : Icons.hourglass_top_rounded,
              color: Colors.white,
              size: 44,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            txCompleted
                ? isLand
                ? '🏡 Land Ownership Transferred!'
                : '📦 Device Ownership Transferred!'
                : 'Transfer Pending…',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'From: ${widget.sellerName}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetCard() {
    final title = _assetData?['title'] ?? 'Asset';
    final price = _txData?['assetPrice'] ?? _assetData?['price'] ?? '—';
    final tokenId = _assetData?['blockchainTokenId'];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Asset Details',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          Divider(color: Colors.grey[100], height: 1),
          const SizedBox(height: 12),
          _buyerInfoRow('Asset', title),
          _buyerInfoRow('Price', 'PKR $price'),
          if (tokenId != null) _buyerInfoRow('Token ID', '#$tokenId'),
        ],
      ),
    );
  }

  Widget _buildConfirmationCard(String txHash) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_rounded, color: Colors.green[700]),
              const SizedBox(width: 8),
              Text(
                'Confirmed on Blockchain',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[800]),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'The NFT has been transferred on Polygon Amoy. You are now the on-chain owner.',
            style: TextStyle(fontSize: 13, color: Colors.green[900], height: 1.5),
          ),
          const SizedBox(height: 10),
          SelectableText(
            'Tx: $txHash',
            style: TextStyle(fontSize: 11, color: Colors.grey[500], fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletSection() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_rounded, color: Colors.grey[700]),
              const SizedBox(width: 8),
              const Text('Your Wallet',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Connect your MetaMask wallet so the seller can send the NFT directly to your address. '
                'Your address is stored securely in your profile.',
            style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.5),
          ),
          const SizedBox(height: 16),
          if (_walletConnected && _connectedAddress != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.green[700], size: 18),
                      const SizedBox(width: 8),
                      const Text('Wallet connected & saved',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    _connectedAddress!,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.black54),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'The seller can now initiate the blockchain transfer to this address.',
                    style: TextStyle(fontSize: 12, color: Colors.green[700]),
                  ),
                ],
              ),
            ),
          ] else ...[
            ElevatedButton.icon(
              onPressed: _connectAndSaveWallet,
              icon: const Icon(Icons.account_balance_wallet_rounded),
              label: const Text('Connect & Save Wallet Address'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryStart,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 15, color: Colors.orange),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'The seller cannot transfer the NFT until your wallet address is registered.',
                    style: TextStyle(fontSize: 12, color: Colors.orange[800]),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buyerInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
