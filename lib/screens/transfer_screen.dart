// lib/screens/transfer_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../blockchain/transfer_service.dart';

enum AssetType { electronics, land }

class TransferScreen extends StatefulWidget {
  final AssetType assetType;
  final String assetId;

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

  String? _buyerWallet;
  String? _sellerWallet;

  @override
  void initState() {
    super.initState();
    _loadWallets();
  }

  /// Load buyer + seller wallets
  Future<void> _loadWallets() async {
    try {
      final buyerDoc =
      await _db.collection('users').doc(widget.buyerUid).get();

      if (!buyerDoc.exists || buyerDoc['walletAddress'] == null) {
        setState(() {
          _error = 'Buyer wallet not found';
          _loading = false;
        });
        return;
      }

      final sellerWallet = _transferService.connectedAddress;

      setState(() {
        _buyerWallet = buyerDoc['walletAddress'];
        _sellerWallet = sellerWallet;
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
    if (_buyerWallet == null) return;

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
                  : 'Loading...',
            ),
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
                icon: const Icon(Icons.account_balance_wallet),
                label: _processing
                    ? const Text('Processing...')
                    : const Text('Approve in Wallet'),
                onPressed:
                _processing || _buyerWallet == null
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
