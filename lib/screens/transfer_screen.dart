// lib/screens/transfer_screen.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../blockchain/blockchain_service.dart';

enum AssetType { electronics, land }

class TransferScreen extends StatefulWidget {
  final String assetId;
  final AssetType assetType;
  final String transactionId;
  final String buyerUid;
  final String sellerUid;
  final int? tokenId;         // electronics ERC-721 token id
  final int? propertyId;      // land ERC-1155 property id
  final int? fractionAmount;  // land fractions to transfer
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

  // ── Stepper state ───────────────────────────────────────────
  int _currentStep = 0;

  // ── Data ────────────────────────────────────────────────────
  String? _buyerWalletAddress;
  String? _assetTitle;
  bool _legalConfirmed = false;   // land-only gate
  bool _walletConnected = false;

  // ── Transfer state ──────────────────────────────────────────
  bool _transferring = false;
  String _statusMessage = '';
  String? _txHash;
  bool _success = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPrerequisites();
  }

  // ── Load buyer wallet + asset title ────────────────────────
  Future<void> _loadPrerequisites() async {
    try {
      final results = await Future.wait([
        _db.collection('users').doc(widget.buyerUid).get(),
        _db.collection('assets').doc(widget.assetId).get(),
      ]);

      final buyerDoc  = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final assetDoc  = results[1] as DocumentSnapshot<Map<String, dynamic>>;

      if (mounted) {
        setState(() {
          _buyerWalletAddress = buyerDoc.data()?['walletAddress'] as String?;
          _assetTitle         = assetDoc.data()?['title'] as String? ?? 'Asset';
        });
      }
    } catch (e) {
      debugPrint('_loadPrerequisites error: $e');
    }
  }

  // ── Step 1 : Connect seller wallet ──────────────────────────
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
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Wallet error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Step 4 : Execute blockchain transfer ────────────────────
  Future<void> _executeTransfer() async {
    if (_buyerWalletAddress == null || _buyerWalletAddress!.isEmpty) {
      setState(() => _errorMessage = 'Buyer has not connected a wallet yet. Ask them to connect their wallet in the app first.');
      return;
    }

    setState(() {
      _transferring    = true;
      _errorMessage    = null;
      _statusMessage   = 'Preparing transaction…';
    });

    try {
      // ── 4a. Send blockchain transaction ──
      String? txHash;

      if (widget.assetType == AssetType.electronics) {
        final id = widget.tokenId;
        if (id == null) throw Exception('Missing tokenId for electronics transfer');

        setState(() => _statusMessage = 'Sending NFT transfer to blockchain…\nPlease approve in your wallet.');
        txHash = await _bs.transferElectronic(
          toAddress: _buyerWalletAddress!,
          tokenId: id,
        );
      } else {
        final pid    = widget.propertyId;
        final amount = widget.fractionAmount ?? 1;
        if (pid == null) throw Exception('Missing propertyId for land transfer');

        setState(() => _statusMessage = 'Sending land fraction transfer…\nPlease approve in your wallet.');
        txHash = await _bs.transferLandFraction(
          toAddress: _buyerWalletAddress!,
          propertyId: pid,
          amount: amount,
        );
      }

      if (txHash == null) {
        throw Exception('Transaction was not submitted. Check your wallet.');
      }

      // Trim stray whitespace/newlines that can cause the length==66 check to fail
      txHash = txHash.trim();
      debugPrint('🔍 blockchain returned (trimmed): "$txHash" len=${txHash.length}');

      final isValidHash = txHash.startsWith('0x') &&
          txHash.length == 66 &&
          RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(txHash);

      if (!isValidHash) {
        final lower = txHash.toLowerCase();

        // Only treat as explicit user rejection when MetaMask's own code is
        // present AND there is no sign of a contract/gas level error.
        final isExplicitUserRejection =
            (lower.contains('user rejected') || lower.contains('user denied')) &&
                !lower.contains('gas') &&
                !lower.contains('revert') &&
                !lower.contains('execution');

        if (isExplicitUserRejection || lower.contains('4001')) {
          throw Exception(
              'You cancelled the transaction in MetaMask.\n'
                  'Tap "Execute Blockchain Transfer" again and tap Confirm.');
        }
        if (lower.contains('5000')) {
          throw Exception(
              'MetaMask session error (5000). Disconnect your wallet, '
                  'reconnect, and make sure MetaMask is on the Polygon Amoy network.');
        }
        if (lower.contains('insufficient') || lower.contains('gas')) {
          throw Exception(
              'Not enough MATIC for gas fees. Add MATIC to your wallet on '
                  'Polygon Amoy and try again.');
        }
        if (lower.contains('revert') || lower.contains('execution reverted')) {
          throw Exception(
              'Contract reverted the transaction. Make sure this wallet '
                  'holds the NFT/fractions being transferred.\n\nRaw: $txHash');
        }
        // Catch-all: expose the raw string so you can see exactly what came back
        throw Exception(
            'Unexpected wallet response — raw value:\n\n$txHash\n\n'
                'Check MetaMask is on Polygon Amoy and this wallet holds the asset.');
      }
      setState(() {
        _txHash        = txHash;
        _statusMessage = 'Transaction submitted ✅\nWaiting for blockchain confirmation…\n\n$txHash';
      });

      // ── 4b. Poll for confirmation ──
      final confirmed = await _pollConfirmation(txHash);
      if (!confirmed) throw Exception('Transaction not confirmed after timeout. Check Polygonscan for hash:\n$txHash');

      setState(() => _statusMessage = 'Confirmed on-chain ✅\nUpdating ownership records…');

      // ── 4c. Update Firestore ownership ──
      await _finalizeOwnership();

      setState(() {
        _success       = true;
        _transferring  = false;
        _statusMessage = 'Ownership transferred successfully!';
      });

      // Pop back with success signal so AssetDetailScreen can refresh
      if (mounted) {
        await Future.delayed(const Duration(seconds: 2));
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {
        _transferring  = false;
        _errorMessage  = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  // ── Poll tx receipt via public Amoy RPC (no API key needed) ─
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
          if (status == '0x0') throw Exception('Transaction reverted on-chain. Check contract permissions.');
        }
      } catch (e) {
        if (e.toString().contains('reverted')) rethrow;
        // Network hiccup – continue polling
      }
      setState(() => _statusMessage =
      'Waiting for confirmation… (attempt ${i + 1}/$retries)\n\nTx: $_txHash');
      await Future.delayed(const Duration(seconds: 3));
    }
    return false;
  }

  // ── Update Firestore after on-chain success ─────────────────
  Future<void> _finalizeOwnership() async {
    debugPrint('✅ _finalizeOwnership: setting ownerId → ${widget.buyerUid} on asset ${widget.assetId}');
    final batch = _db.batch();

    // 1. Transfer asset ownership — write BOTH ownerId and ownerUid so
    //    MyAssetsScreen query (which checks ownerId) always finds the asset.
    final assetRef = _db.collection('assets').doc(widget.assetId);
    batch.update(assetRef, {
      'ownerId'          : widget.buyerUid,
      'ownerUid'         : widget.buyerUid,
      'previousOwnerId'  : widget.sellerUid,
      'transferredAt'    : FieldValue.serverTimestamp(),
      'txHash'           : _txHash,
    });

    // 2. Mark transaction as completed
    final txRef = _db.collection('transactions').doc(widget.transactionId);
    batch.update(txRef, {
      'status'           : 'completed',
      'completedAt'      : FieldValue.serverTimestamp(),
      'blockchainTxHash' : _txHash,
    });

    // 3. Create order record for buyer — powers MyAssetsScreen
    final orderRef = _db.collection('orders').doc();
    batch.set(orderRef, {
      'buyerId'       : widget.buyerUid,
      'sellerUid'     : widget.sellerUid,
      'assetId'       : widget.assetId,
      'category'      : widget.assetType == AssetType.electronics ? 'electronics' : 'land',
      'assetPrice'    : widget.assetPrice,
      'txHash'        : _txHash,
      'transferredAt' : FieldValue.serverTimestamp(),
      // Electronics-specific: warranty activation timestamp
      if (widget.assetType == AssetType.electronics && widget.tokenId != null) ...{
        'tokenId'             : widget.tokenId,
        'warrantyActivatedAt' : FieldValue.serverTimestamp(),
      },
      // Land-specific: fraction details
      if (widget.assetType == AssetType.land) ...{
        'propertyId'     : widget.propertyId,
        'fractionAmount' : widget.fractionAmount ?? 1,
      },
    });

    // 4. Payment: debit buyer, credit seller
    final price = double.tryParse(widget.assetPrice) ?? 0;
    if (price > 0) {
      final buyerRef  = _db.collection('users').doc(widget.buyerUid);
      final sellerRef = _db.collection('users').doc(widget.sellerUid);
      batch.update(buyerRef,  {'walletBalance': FieldValue.increment(-price)});
      batch.update(sellerRef, {'walletBalance': FieldValue.increment(price)});

      // 5. Payment record
      final payRef = _db.collection('payments').doc();
      batch.set(payRef, {
        'assetId'    : widget.assetId,
        'buyerUid'   : widget.buyerUid,
        'sellerUid'  : widget.sellerUid,
        'amount'     : price,
        'txHash'     : _txHash,
        'createdAt'  : FieldValue.serverTimestamp(),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(isLand ? 'Transfer Land Ownership' : 'Transfer Electronics Ownership'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: _success ? _buildSuccessView() : _buildStepperView(isLand),
    );
  }

  // ── Success view ────────────────────────────────────────────
  Widget _buildSuccessView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 80),
            const SizedBox(height: 20),
            const Text(
              'Ownership Transferred!',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              '${widget.buyerName} is now the official owner of $_assetTitle.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Colors.grey),
            ),
            if (_txHash != null) ...[
              const SizedBox(height: 16),
              SelectableText(
                'Tx: $_txHash',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Stepper ─────────────────────────────────────────────────
  Widget _buildStepperView(bool isLand) {
    return Stepper(
      currentStep: _currentStep,
      onStepContinue: _onStepContinue,
      onStepCancel: _currentStep > 0 ? () => setState(() => _currentStep--) : null,
      controlsBuilder: _buildStepControls,
      steps: [
        _stepReview(isLand),
        _stepBuyerWallet(),
        _stepConnectSeller(),
        if (isLand) _stepLegalConfirmation(),
        _stepExecute(isLand),
      ],
    );
  }

  void _onStepContinue() {
    final isLand = widget.assetType == AssetType.land;
    final totalSteps = isLand ? 5 : 4;

    if (_currentStep == 2 && !_walletConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect your wallet first.')),
      );
      return;
    }
    if (isLand && _currentStep == 3 && !_legalConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please confirm legal paperwork before proceeding.')),
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
    final isLand     = widget.assetType == AssetType.land;
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
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                border: Border.all(color: Colors.red),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red[800], fontSize: 13),
              ),
            ),
          if (_transferring)
            Column(
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
                Text(
                  _statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            )
          else ...[
            ElevatedButton(
              onPressed: details.onStepContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: isLastStep ? Colors.deepPurple : null,
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(isLastStep ? '🔗 Execute Blockchain Transfer' : 'Continue'),
            ),
            if (_currentStep > 0) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: details.onStepCancel,
                child: const Text('Back'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ── Step 0: Review summary ──────────────────────────────────
  Step _stepReview(bool isLand) {
    return Step(
      title: const Text('Transfer Summary'),
      subtitle: const Text('Review before proceeding'),
      isActive: _currentStep >= 0,
      content: Card(
        color: Colors.deepPurple[50],
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(Icons.inventory_2_outlined, 'Asset', _assetTitle ?? '…'),
              _infoRow(Icons.person_outline, 'Buyer', widget.buyerName),
              _infoRow(Icons.payments_outlined, 'Amount', 'PKR ${widget.assetPrice}'),
              if (isLand && widget.fractionAmount != null)
                _infoRow(Icons.pie_chart_outline, 'Fractions', '${widget.fractionAmount}'),
              _infoRow(
                Icons.token_outlined,
                isLand ? 'Property ID' : 'Token ID',
                '${isLand ? widget.propertyId : widget.tokenId}',
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.amber, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isLand
                            ? 'This will transfer land fractions on-chain. The buyer will become the official NFT + land owner.'
                            : 'This will transfer the electronics NFT on-chain. The buyer will own both the device and its NFT.',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Step 1: Check buyer wallet ──────────────────────────────
  Step _stepBuyerWallet() {
    final hasWallet = _buyerWalletAddress != null && _buyerWalletAddress!.isNotEmpty;
    return Step(
      title: const Text("Buyer's Wallet"),
      subtitle: Text(hasWallet ? 'Wallet registered ✅' : 'Not yet connected ⚠️'),
      isActive: _currentStep >= 1,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasWallet) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green[700], size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${widget.buyerName} has a registered wallet.',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[800]),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    _buyerWalletAddress!,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The NFT will be sent directly to this address.',
                    style: TextStyle(fontSize: 12, color: Colors.green[700]),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.red[700], size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.buyerName} has not connected a wallet.',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[800]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'The buyer must connect their MetaMask wallet in the app before you can transfer ownership.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadPrerequisites,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ],
      ),
    );
  }

  // ── Step 2: Connect seller wallet ───────────────────────────
  Step _stepConnectSeller() {
    return Step(
      title: const Text('Connect Your Wallet'),
      subtitle: Text(_walletConnected
          ? 'Connected: ${_bs.connectedAddress?.substring(0, 12) ?? ''}…'
          : 'Not connected'),
      isActive: _currentStep >= 2,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Connect the wallet that currently holds the NFT. This wallet will sign the transfer transaction.',
            style: TextStyle(color: Colors.grey[700], fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (_walletConnected)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green),
              ),
              child: Row(
                children: [
                  Icon(Icons.account_balance_wallet, color: Colors.green[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _bs.connectedAddress ?? '',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _connectWallet,
              icon: const Icon(Icons.account_balance_wallet),
              label: const Text('Connect Wallet'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
        ],
      ),
    );
  }

  // ── Step 3 (land only): Legal paperwork ─────────────────────
  Step _stepLegalConfirmation() {
    return Step(
      title: const Text('Legal Confirmation'),
      subtitle: const Text('Required for land transfers'),
      isActive: _currentStep >= 3,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.gavel, color: Colors.blue, size: 18),
                    SizedBox(width: 8),
                    Text('Land Registry Requirements',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  '• All legal sale documents have been signed by both parties.\n'
                      '• The sale deed / transfer deed has been executed.\n'
                      '• Stamp duty and registration fees have been paid.\n'
                      '• Land registry has been notified of the pending transfer.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _legalConfirmed,
            onChanged: (v) => setState(() => _legalConfirmed = v ?? false),
            title: const Text(
              'I confirm all legal paperwork has been completed and the land registry transfer is linked to this blockchain transaction.',
              style: TextStyle(fontSize: 13),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: Colors.deepPurple,
          ),
        ],
      ),
    );
  }

  // ── Step 3/4: Execute transfer ──────────────────────────────
  Step _stepExecute(bool isLand) {
    return Step(
      title: const Text('Execute Transfer'),
      subtitle: const Text('Sign & send on blockchain'),
      isActive: _currentStep >= (isLand ? 4 : 3),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isLand
                ? 'Clicking the button below will:\n'
                '1. Open your wallet to sign the ERC-1155 safeTransferFrom transaction\n'
                '2. Transfer ${widget.fractionAmount ?? 1} fraction(s) of Property #${widget.propertyId} to ${widget.buyerName}\n'
                '3. Update ownership in the app once confirmed on Polygon Amoy'
                : 'Clicking the button below will:\n'
                '1. Open your wallet to sign the ERC-721 safeTransferFrom transaction\n'
                '2. Transfer Token #${widget.tokenId} to ${widget.buyerName}\n'
                '3. Update ownership in the app once confirmed on Polygon Amoy',
            style: TextStyle(color: Colors.grey[700], fontSize: 13, height: 1.6),
          ),
          const SizedBox(height: 12),
          if (_txHash != null) ...[
            const Divider(),
            Row(
              children: [
                const Icon(Icons.link, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: SelectableText(
                    _txHash!,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Small info row helper ───────────────────────────────────
  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.deepPurple),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text('$label:', style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BUYER OWNERSHIP ACCEPT SCREEN
// Shown to the BUYER from their TransactionsScreen when transfer status is
// 'completed'. Lets them connect their wallet and confirms they received the NFT.
// Navigate to this from TransactionsScreen when txStatus == 'completed'.
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
  final _db  = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _bs  = BlockchainServiceEnhanced();

  Map<String, dynamic>? _assetData;
  Map<String, dynamic>? _txData;
  bool _walletConnected = false;
  bool _walletSaved     = false;
  bool _loading         = true;
  String? _connectedAddress;
  String? _error;

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
        _txData    = (results[1] as DocumentSnapshot<Map<String, dynamic>>).data();
        _loading   = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // Buyer connects their wallet so their address is stored in Firestore
  Future<void> _connectAndSaveWallet() async {
    try {
      String? addr = _bs.connectedAddress;

      if (addr == null || addr.isEmpty) {
        addr = await _bs.connectWallet(context);
      }

      if (addr == null || addr.isEmpty) return;

      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      // Persist wallet address so seller's TransferScreen can find it
      await _db.collection('users').doc(uid).update({'walletAddress': addr});

      if (mounted) {
        setState(() {
          _walletConnected  = true;
          _walletSaved      = true;
          _connectedAddress = addr;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Wallet connected & saved: ${addr.substring(0, 12)}…'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
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
      appBar: AppBar(
        title: const Text('Incoming Transfer'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header card ────────────────────────
            _buildHeaderCard(isLand, txCompleted),
            const SizedBox(height: 16),

            // ── Asset details ──────────────────────
            _buildAssetCard(),
            const SizedBox(height: 16),

            // ── Blockchain confirmation ────────────
            if (txCompleted && txHash != null)
              _buildConfirmationCard(txHash),

            if (txCompleted && txHash != null)
              const SizedBox(height: 16),

            // ── Wallet section ─────────────────────
            _buildWalletSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(bool isLand, bool txCompleted) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: txCompleted
              ? [Colors.teal[700]!, Colors.teal[400]!]
              : [Colors.orange[700]!, Colors.orange[400]!],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            txCompleted ? Icons.move_to_inbox : Icons.hourglass_top,
            color: Colors.white, size: 52,
          ),
          const SizedBox(height: 10),
          Text(
            txCompleted
                ? isLand
                ? '🏡 Land Ownership Transferred!'
                : '📦 Device Ownership Transferred!'
                : 'Transfer Pending…',
            style: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'From: ${widget.sellerName}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetCard() {
    final title   = _assetData?['title'] ?? 'Asset';
    final price   = _txData?['assetPrice'] ?? _assetData?['price'] ?? '—';
    final tokenId = _assetData?['blockchainTokenId'];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Asset Details',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const Divider(),
            _buyerInfoRow('Asset', title),
            _buyerInfoRow('Price', 'PKR $price'),
            if (tokenId != null) _buyerInfoRow('Token ID', '#$tokenId'),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmationCard(String txHash) {
    return Card(
      color: Colors.green[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green[300]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified, color: Colors.green[700]),
                const SizedBox(width: 8),
                Text('Confirmed on Blockchain',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    )),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'The NFT has been transferred on Polygon Amoy. You are now the on-chain owner.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            SelectableText(
              'Tx: $txHash',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletSection() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet),
                const SizedBox(width: 8),
                const Text('Your Wallet',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Connect your MetaMask wallet so the seller can send the NFT directly to your address. '
                  'Your address is stored securely in your profile.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (_walletConnected && _connectedAddress != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green[700], size: 18),
                        const SizedBox(width: 8),
                        const Text('Wallet connected & saved',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      _connectedAddress!,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'The seller can now initiate the blockchain transfer to this address.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: _connectAndSaveWallet,
                icon: const Icon(Icons.account_balance_wallet),
                label: const Text('Connect & Save Wallet Address'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '⚠️ The seller cannot transfer the NFT until your wallet address is registered.',
                style: TextStyle(fontSize: 12, color: Colors.orange),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buyerInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text('$label:', style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}