// lib/screens/transfer_screen.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../blockchain/transfer_service.dart';
import '../blockchain/wallet_service.dart';
import '../blockchain/blockchain_service.dart';
import '../services/push_notification_service.dart';

enum AssetType { electronics, land }

class TransferScreen extends StatefulWidget {
  final AssetType assetType;
  final String assetId;
  final String transactionId;

  // Blockchain identifiers
  final int? tokenId;        // ERC-721
  final int? propertyId;     // ERC-1155
  final int? fractionAmount;

  // Buyer info
  final String buyerUid;

  // Seller info
  final String sellerUid;

  const TransferScreen({
    super.key,
    required this.assetType,
    required this.assetId,
    required this.transactionId,
    required this.buyerUid,
    required this.sellerUid,
    this.tokenId,
    this.propertyId,
    this.fractionAmount,
  });

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final TransferService _transferService = TransferService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final PushNotificationService _pushService = PushNotificationService();

  bool _loading = true;
  bool _processing = false;
  String? _error;
  String? _statusMessage;

  String? _buyerWallet;
  String? _sellerWallet;
  String _transactionStatus = 'pending';
  Map<String, dynamic>? _assetData;

  @override
  void initState() {
    super.initState();
    _loadData();
    _listenToTransactionStatus();
  }

  /// Listen to transaction status changes in real-time
  void _listenToTransactionStatus() {
    _db.collection('transactions').doc(widget.transactionId).snapshots().listen(
          (doc) {
        if (!doc.exists) return;

        final data = doc.data();
        if (data == null) return;

        if (mounted) {
          setState(() {
            _transactionStatus = data['status'] ?? 'pending';
          });
        }
      },
    );
  }

  /// Load all necessary data
  Future<void> _loadData() async {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;

    if (currentUid != widget.buyerUid) {
      // 🚫 Seller should never load this screen
      Navigator.pop(context);
      return;
    }
    try {
      // Load transaction
      final txDoc = await _db.collection('transaction').doc(widget.transactionId).get();
      if (!txDoc.exists) {
        throw Exception('Transaction not found');
      }

      // Load asset
      final assetDoc = await _db.collection('assets').doc(widget.assetId).get();
      if (!assetDoc.exists) {
        throw Exception('Asset not found');
      }

      // Load buyer & seller wallets
      final buyerDoc = await _db.collection('users').doc(widget.buyerUid).get();
      final sellerDoc = await _db.collection('users').doc(widget.sellerUid).get();

      setState(() {
        _assetData = assetDoc.data();
        _buyerWallet = buyerDoc.data()?['walletAddress'];
        _sellerWallet = sellerDoc.data()?['walletAddress'];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load data: $e';
        _loading = false;
      });
    }
  }

  /// BUYER SIDE: Accept or Reject Checkout
  Future<void> _handleBuyerDecision(bool accept) async {
    if (accept) {
      // Update status to accepted
      await _db.collection('transaction').doc(widget.transactionId).update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      // Notify supplier
      final sellerDoc = await _db.collection('users').doc(widget.sellerUid).get();
      final sellerToken = sellerDoc.data()?['fcmToken'];

      if (sellerToken != null) {
        await _pushService.sendInAppNotification(
          receiverUid: widget.sellerUid,
          title: 'Checkout Accepted',
          body: 'Buyer accepted the checkout for "${_assetData?['title']}"',
          type: 'checkout_accepted',
          relatedId: widget.transactionId,
        );
      }

      // Show wallet connect popup
      if (mounted) {
        _showWalletConnectDialog();
      }
    } else {
      // Reject
      await _db.collection('transaction').doc(widget.transactionId).update({
        'status': 'rejected',
        'rejectedAt': FieldValue.serverTimestamp(),
      });

      // Notify supplier
      final sellerDoc = await _db.collection('users').doc(widget.sellerUid).get();
      final sellerToken = sellerDoc.data()?['fcmToken'];

      if (sellerToken != null) {
        await _pushService.sendInAppNotification(
          receiverUid: widget.sellerUid,
          title: 'Checkout rejected',
          body: 'Buyer rejected the checkout for "${_assetData?['title']}"',
          type: 'checkout_rejected',
          relatedId: widget.transactionId,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Checkout rejected'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  /// Show wallet connection dialog for buyer
  void _showWalletConnectDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect Your Wallet'),
        content: const Text(
          'To proceed with this transfer, you need to connect your wallet first.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _connectBuyerWallet();
            },
            child: const Text('Connect Wallet'),
          ),
        ],
      ),
    );
  }

  /// Connect buyer's wallet
  Future<void> _connectBuyerWallet() async {
    try {
      setState(() {
        _statusMessage = 'Opening wallet...';
        _error = null;
      });

      final walletService = SimpleWalletService();
      final address = await walletService.connect(context);

      if (!mounted) return;

      if (address == null) {
        throw Exception('Wallet connection failed');
      }

      // Save wallet address
      await _db.collection('users').doc(widget.buyerUid).update({
        'walletAddress': address,
      });

      setState(() {
        _buyerWallet = address;
        _statusMessage = '✅ Wallet connected successfully!';
      });

      // Show success and instructions
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Wallet connected! Now click "Proceed to Transfer"'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _statusMessage = null;
      });
    }
  }

  /// Execute the blockchain transfer
  Future<void> _executeTransfer() async {
    if (_buyerWallet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please connect your wallet first')),
      );
      return;
    }

    setState(() {
      _processing = true;
      _error = null;
      _statusMessage = 'Preparing transfer...';
    });

    try {
      // 1️⃣ Validate transfer
      setState(() => _statusMessage = 'Validating transfer...');

      final validationError = await _transferService.validateTransfer(
        assetId: widget.assetId,
        receiverAddress: _buyerWallet!,
        assetType: widget.assetType == AssetType.electronics ? 'electronics' : 'land',
        amount: widget.fractionAmount,
      );

      if (validationError != null) {
        throw Exception(validationError);
      }

      // 2️⃣ Execute smart contract transfer
      setState(() => _statusMessage = 'Please confirm in your wallet...');

      TransferResult result;

      if (widget.assetType == AssetType.electronics) {
        result = await _transferService.transferElectronics(
          assetId: widget.assetId,
          tokenId: widget.tokenId!,
          receiverAddress: _buyerWallet!,
        );
      } else {
        result = await _transferService.transferLandFractions(
          assetId: widget.assetId,
          propertyId: widget.propertyId!,
          receiverAddress: _buyerWallet!,
          amount: widget.fractionAmount!,
        );
      }

      if (!mounted) return;

      if (result.isSuccess) {
        // 3️⃣ Update transaction status
        await _db.collection('transaction').doc(widget.transactionId).update({
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
          'txHash': result.txHash,
        });

        // 4️⃣ Send notifications
        await _sendCompletionNotifications(result.txHash!);

        // 5️⃣ Show success
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 32),
                  SizedBox(width: 12),
                  Text('Transfer Complete!'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('The ownership has been successfully transferred.'),
                  const SizedBox(height: 12),
                  Text(
                    'TX Hash: ${result.txHash!.substring(0, 10)}...',
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context, true);
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          );
        }
      } else {
        throw Exception(result.errorMessage ?? 'Transfer failed');
      }
    } catch (e) {
      setState(() {
        _processing = false;
        _error = e.toString();
        _statusMessage = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transfer failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Send completion notifications to both parties
  Future<void> _sendCompletionNotifications(String txHash) async {
    final assetTitle = _assetData?['title'] ?? 'Asset';

    // Notify buyer
    final buyerDoc = await _db.collection('users').doc(widget.buyerUid).get();
    final buyerToken = buyerDoc.data()?['fcmToken'];
    if (buyerToken != null) {
      await _pushService.sendInAppNotification(
        receiverUid: widget.buyerUid,
        title: 'Transfer Complete',
        body: 'You are now the new owner of "$assetTitle"',
        type: 'transfer_complete',
        relatedId: widget.transactionId,
        payload: {
          'txHash': txHash,
          'assetTitle': assetTitle,
        },
      );
    }


    // Notify seller
    final sellerDoc = await _db.collection('users').doc(widget.sellerUid).get();
    final sellerToken = sellerDoc.data()?['fcmToken'];
    if (sellerToken != null) {
      await PushNotificationService().sendInAppNotification(
        receiverUid: widget.sellerUid,
        title: 'Product Sold',
        body: 'Your product "$assetTitle" has been transferred',
        type: 'product_sold',
        relatedId: widget.transactionId,
        payload: {
          'txHash': txHash,
          'assetTitle': assetTitle,
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Transfer')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isSupplier = widget.sellerUid == _db.app.options.projectId; // Check if current user is supplier
    final isPending = _transactionStatus == 'pending';
    final isAccepted = _transactionStatus == 'accepted';
    final isCompleted = _transactionStatus == 'completed';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Transfer'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Asset Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _assetData?['title'] ?? 'Asset',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _infoRow('Type', widget.assetType == AssetType.electronics
                        ? 'Electronics (ERC-721)'
                        : 'Land (ERC-1155)'),
                    if (widget.assetType == AssetType.land)
                      _infoRow('Fractions', widget.fractionAmount.toString()),
                    _infoRow('Price', 'PKR ${_assetData?['price']}'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Status Card
            Card(
              color: isCompleted
                  ? Colors.green[50]
                  : isAccepted
                  ? Colors.blue[50]
                  : Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      isCompleted
                          ? Icons.check_circle
                          : isAccepted
                          ? Icons.pending
                          : Icons.hourglass_empty,
                      color: isCompleted
                          ? Colors.green
                          : isAccepted
                          ? Colors.blue
                          : Colors.orange,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Status: ${_transactionStatus.toUpperCase()}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (_statusMessage != null)
                            Text(_statusMessage!, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Wallet Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Wallet Information',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const Divider(),
                    _infoRow(
                      'Seller Wallet',
                      _sellerWallet != null
                          ? _transferService.shortenAddress(_sellerWallet!)
                          : 'Not connected',
                    ),
                    _infoRow(
                      'Buyer Wallet',
                      _buyerWallet != null
                          ? _transferService.shortenAddress(_buyerWallet!)
                          : 'Not connected',
                    ),
                  ],
                ),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Action Buttons
            if (isPending && !isSupplier) ...[
              // Buyer Decision Buttons
              const Text(
                'The supplier wants to proceed with checkout. Do you accept?',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _handleBuyerDecision(false),
                      icon: const Icon(Icons.close),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _handleBuyerDecision(true),
                      icon: const Icon(Icons.check),
                      label: const Text('Accept'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        minimumSize: const Size.fromHeight(50),
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (isAccepted && !isSupplier) ...[
              // Connect Wallet & Transfer Buttons
              if (_buyerWallet == null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _connectBuyerWallet,
                    icon: const Icon(Icons.account_balance_wallet),
                    label: const Text('Connect Wallet'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _processing ? null : _executeTransfer,
                    icon: _processing
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Icon(Icons.send),
                    label: Text(_processing ? 'Processing...' : 'Proceed to Transfer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      minimumSize: const Size.fromHeight(50),
                    ),
                  ),
                ),
            ] else if (isCompleted) ...[
              const Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle, size: 64, color: Colors.green),
                    SizedBox(height: 16),
                    Text(
                      'Transfer Completed!',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}