// lib/screens/transfer_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../blockchain/transfer_service.dart';
import '../blockchain/wallet_service.dart';
import '../services/push_notification_service.dart';

enum AssetType { electronics, land }

class TransferScreen extends StatefulWidget {
  final AssetType assetType;
  final String assetId;
  final String? transactionId;

  // Blockchain identifiers
  final int? tokenId;        // ERC-721
  final int? propertyId;     // ERC-1155
  final int? fractionAmount;

  // Buyer info
  final String buyerUid;
  final String? buyerWallet;

  // Seller info
  final String sellerUid;
  final String? sellerWallet;


  const TransferScreen({
    super.key,
    required this.assetType,
    required this.assetId,
    required this.buyerUid,
    this.tokenId,
    this.propertyId,
    this.transactionId,
    required this.buyerWallet,
    required this.sellerUid,
    required this.sellerWallet,
    this.fractionAmount,
  });

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final TransferService _transferService = TransferService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _loading = true;
  bool _processing = false;
  String? _error;
  bool _buyerAccepted= false;
  String? _selectedWallet;
  String? _sellerWallet;
  String? _buyerWallet;
  String? _statusMessage;

  bool _walletConnected = false;


  @override
  void initState() {
    super.initState();
    _loadWallets();
    _listenToTransactionStatus();
  }
  void _listenToTransactionStatus() {
    if (widget.transactionId == null) return;

    _db.collection('transaction').doc(widget.transactionId).snapshots().listen(
          (doc) {
        if (!doc.exists) return;

        final status = doc.data()?['status'];

        if (mounted) {
          setState(() {
            _buyerAccepted = status == 'accepted';
          });
        }
      },
    );
  }
  /// Load buyer + seller wallets
  Future<void> _loadWallets() async {
    try {
      final buyerDoc =
      await _db.collection('users').doc(widget.buyerUid).get();
      final sellerDoc =
      await _db.collection('users').doc(widget.sellerUid).get();

      setState(() {
        _buyerWallet = buyerDoc.data()?['walletAddress'];
        _sellerWallet = sellerDoc.data()?['walletAddress'];
        _walletConnected = _buyerWallet != null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load wallet data';
        _loading = false;
      });
    }
  }

  /// Execute blockchain transfer
  Future<void> _approveAndTransfer() async {
    final String transactionId;
    if (_buyerWallet == null) return;

    // Show success message to supplier immediately
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your request has been successfully sent to the buyer.'),
        backgroundColor: Colors.green,
      ),
    );

    setState(() {
      _processing = true;
      _error = null;
    });

    // 1️⃣ Validate transfer
    final validationError = await _transferService.validateTransfer(
      assetId: widget.assetId,
      receiverAddress: _buyerWallet!,
      assetType:
      widget.assetType == AssetType.electronics ? 'electronics' : 'land',
      amount: widget.fractionAmount,
    );

    if (validationError != null) {
      setState(() {
        _processing = false;
        _error = validationError;
      });
      return;
    }

    // 2️⃣ Execute smart contract transfer
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
    // When transfer succeeds
    await _db.collection('transaction').doc(widget.transactionId).update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
      'txHash': result.txHash,
    });

// Send notifications
    final transactionDoc = await _db.collection('transaction').doc(widget.transactionId).get();
    final buyerUid = transactionDoc['buyerUid'];
    final sellerUid = transactionDoc['sellerUid'];
    final assetName = 'Asset Name'; // replace if available
    final pushService = PushNotificationService();

// Notify buyer
    final buyerDoc = await _db.collection('users').doc(buyerUid).get();
    final buyerToken = buyerDoc.data()?['fcmToken'];
    if (buyerToken != null) {
      await pushService.sendPushMessage(
        token: buyerToken,
        title: 'Transfer Complete',
        body: 'You are now the new owner of "$assetName"',
        data: {'transactionId': widget.transactionId},
      );
    }

// Notify seller
    final sellerDoc = await _db.collection('users').doc(sellerUid).get();
    final sellerToken = sellerDoc.data()?['fcmToken'];
    if (sellerToken != null) {
      await pushService.sendPushMessage(
        token: sellerToken,
        title: 'Product Sold',
        body: 'Your product "$assetName" has been transferred to the buyer',
        data: {'transactionId': widget.transactionId},
      );
    }
    // 3️⃣ Handle result
    if (!mounted) return;

    if (result.isSuccess) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _processing = false;
        _error = result.errorMessage ?? 'Transfer failed';
      });
    }
  }

  Future<void> showBuyerCheckoutPopup({
    required BuildContext context,
    required String transactionId,
    required String buyerUid,
    required String sellerUid,
    required String assetName,
  }) async {
    final FirebaseFirestore _db = FirebaseFirestore.instance;
    final pushService = PushNotificationService();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Checkout Request'),
          content: Text('Supplier wants to checkout "$assetName". Do you accept?'),
          actions: [
            TextButton(
              onPressed: () async {
                // Buyer Rejects
                await _db.collection('transaction').doc(transactionId).update({
                  'status': 'rejected',
                });

                // Notify supplier
                final sellerDoc = await _db.collection('users').doc(sellerUid).get();
                final sellerToken = sellerDoc.data()?['fcmToken'];
                if (sellerToken != null) {
                  await pushService.sendPushMessage(
                    token: sellerToken,
                    title: 'Checkout Rejected',
                    body: 'Buyer rejected the checkout of "$assetName"',
                    data: {'transactionId': transactionId},
                  );
                }

                Navigator.of(context).pop(); // close popup
              },
              child: const Text('Reject'),
            ),
            ElevatedButton(
              onPressed: () async {
                // Buyer Accepts
                await _db.collection('transaction').doc(transactionId).update({
                  'status': 'accepted',
                });

                // Optionally notify supplier that buyer accepted
                final sellerDoc = await _db.collection('users').doc(sellerUid).get();
                final sellerToken = sellerDoc.data()?['fcmToken'];
                if (sellerToken != null) {
                  await pushService.sendPushMessage(
                    token: sellerToken,
                    title: 'Checkout Accepted',
                    body: 'Buyer accepted the checkout of "$assetName"',
                    data: {'transactionId': transactionId},
                  );
                }

                Navigator.of(context).pop(); // close popup

                // Show wallet connect popup in transfer_screen
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Connect Your Wallet'),
                    content: const Text('Click OK to connect your wallet'),
                    actions: [
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          // Navigate to transfer screen here
                          Navigator.of(context).pushNamed(
                            '/transfer',
                            arguments: {'transactionId': transactionId},
                          );
                        },
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Accept'),
            ),
          ],
        );
      },
    );
  }
  void _showWalletConnectDialog(BuildContext context, String transactionId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Connect Your Wallet'),
        content: const Text('Click OK to connect your wallet'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/transfer', arguments: {'transactionId': transactionId});
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // WALLET CONNECTION LOGIC
  // ─────────────────────────────────────────────
  Future<void> _connectWallet() async {
    try {
      final walletService = SimpleWalletService();

      setState(() {
        _statusMessage = 'Waiting for wallet connection...';
        _error = null;
      });

      final address = await walletService.connect(context);

      if (!mounted) return;

      if (address == null) {
        throw Exception('Wallet connection failed or timed out.');
      }

      await _db.collection('users').doc(widget.buyerUid).update({
        'walletAddress': address,
      });

      setState(() {
        _buyerWallet = address;
        _walletConnected = true;
        _statusMessage = 'Wallet connected successfully';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _statusMessage = null;
        _walletConnected = false;
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Transfer')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoTile('Asset ID', widget.assetId),
            _infoTile(
              'Asset Type',
              widget.assetType == AssetType.electronics
                  ? 'Electronics (ERC-721)'
                  : 'Land (ERC-1155)',
            ),
            if (widget.assetType == AssetType.land)
              _infoTile(
                'Fractions',
                widget.fractionAmount.toString(),
              ),
            const Divider(height: 32),
            _infoTile(
              'Seller Wallet',
              _sellerWallet != null
                  ? _transferService.shortenAddress(_sellerWallet!)
                  : 'Not connected',
            ),
            _infoTile(
              'Buyer Wallet',
              _buyerWallet != null
                  ? _transferService.shortenAddress(_buyerWallet!)
                  : 'Not connected',
            ),

// 🔹 CONNECT WALLET BUTTON (ONLY WHEN NEEDED)
            if (!_walletConnected) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.account_balance_wallet),
                  label: const Text('Connect Wallet'),
                  onPressed: _connectWallet,
                ),
              ),
            ],

// 🔹 STATUS MESSAGE
            if (_statusMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _statusMessage!,
                style: const TextStyle(color: Colors.blue),
              ),
            ],
            const Spacer(),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.send),
                label: const Text('Proceed to Transfer'),
                onPressed: (!_buyerAccepted || !_walletConnected || _processing)
                    ? null
                    : _approveAndTransfer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 4),
          Text(value),
        ],
      ),
    );
  }

}