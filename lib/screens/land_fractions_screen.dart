// lib/screens/land_fractions_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../blockchain/blockchain_service.dart';

class LandFractionsScreen extends StatefulWidget {
  final String assetId;
  final int blockchainPropertyId;

  const LandFractionsScreen({
    super.key,
    required this.assetId,
    required this.blockchainPropertyId,
  });

  @override
  State<LandFractionsScreen> createState() => _LandFractionsScreenState();
}

class _LandFractionsScreenState extends State<LandFractionsScreen> {
  final _blockchainService = BlockchainServiceEnhanced();
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Map<String, dynamic>? _propertyData;
  int _selectedFractions = 1;
  bool _loading = true;
  int _userFractions = 0;

  // Tracks whether the current user already has a pending/approved request
  bool _hasExistingRequest = false;
  bool _checkingRequest = false;

  @override
  void initState() {
    super.initState();
    _loadPropertyData();
  }

  Future<void> _loadPropertyData() async {
    try {
      await _blockchainService.init();

      final property = await _blockchainService.getLandProperty(
        widget.blockchainPropertyId,
      );

      if (_blockchainService.isConnected) {
        final fractions = await _blockchainService.getUserFractions(
          _blockchainService.connectedAddress!,
          widget.blockchainPropertyId,
        );
        _userFractions = fractions;
      }

      await _checkExistingRequest();

      setState(() {
        _propertyData = property;
        _loading = false;
      });
    } catch (e) {
      print('Error loading property: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _checkExistingRequest() async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _checkingRequest = true);

    try {
      final existing = await _db
          .collection('fraction_requests')
          .where('assetId', isEqualTo: widget.assetId)
          .where('buyerUid', isEqualTo: user.uid)
          .where('status', whereIn: ['pending', 'approved'])
          .limit(1)
          .get();

      setState(() {
        _hasExistingRequest = existing.docs.isNotEmpty;
        _checkingRequest = false;
      });
    } catch (_) {
      setState(() => _checkingRequest = false);
    }
  }

  /// Sends a fraction purchase request to the supplier via Firestore.
  /// Creates two linked documents:
  ///   1. fraction_requests — the canonical fraction request record
  ///   2. transactions      — mirrors status so supplier's TransactionsScreen
  ///                          shows the request under the "Fractions" tab
  /// Both share the same document ID so they can be kept in sync.
  Future<void> _sendPurchaseRequest() async {
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to continue')),
      );
      return;
    }

    if (_propertyData == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fractions requested: $_selectedFractions'),
            Text(
              'Price per fraction: ${_formatPrice(_propertyData!['pricePerFraction'])} MATIC',
            ),
            const SizedBox(height: 8),
            Text(
              'Total: ${_formatPrice(_calculateTotal())} MATIC',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'A purchase request will be sent to the supplier. '
                  'The blockchain transaction will only proceed once the '
                  'supplier approves your request.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send Request'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);

    try {
      // Fetch asset to get supplier (seller) UID
      final assetDoc =
      await _db.collection('assets').doc(widget.assetId).get();
      final sellerUid =
          assetDoc.data()?['ownerId'] ?? assetDoc.data()?['ownerUid'];

      if (sellerUid == null) {
        throw Exception('Could not find the asset owner.');
      }

      // Use the same document ID for both collections so they are trivially
      // linked without needing a foreign key lookup.
      final sharedId = _db.collection('fraction_requests').doc().id;

      final batch = _db.batch();

      // 1. Canonical fraction request
      batch.set(
        _db.collection('fraction_requests').doc(sharedId),
        {
          'assetId': widget.assetId,
          'blockchainPropertyId': widget.blockchainPropertyId,
          'buyerUid': user.uid,
          'sellerUid': sellerUid,
          'fractionsRequested': _selectedFractions,
          'pricePerFraction': _propertyData!['pricePerFraction'].toString(),
          'totalCost': _calculateTotal().toString(),
          'status': 'pending',
          // Store the transactionId so FractionRequestsPanel and
          // _ApprovedFractionTransferButton can mirror updates into transactions.
          'transactionId': sharedId,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );

      // 2. Mirrored transaction so supplier's TransactionsScreen shows it
      batch.set(
        _db.collection('transactions').doc(sharedId),
        {
          'transactionId': sharedId,
          'assetId': widget.assetId,
          'buyerUid': user.uid,
          'sellerUid': sellerUid,
          'status': 'pending',
          'category': 'land',
          'requestType': 'fraction_purchase',
          'fractionsRequested': _selectedFractions,
          'blockchainTokenId': widget.blockchainPropertyId,
          // Store propertyId explicitly so TransactionsScreen can pass it
          // straight to TransferScreen without an extra Firestore read.
          'blockchainPropertyId': widget.blockchainPropertyId,
          'createdAt': FieldValue.serverTimestamp(),
        },
      );

      await batch.commit();

      setState(() {
        _hasExistingRequest = true;
        _loading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✅ Request sent! You will be notified once the supplier responds.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending request: $e')),
        );
      }
    }
  }

  BigInt _calculateTotal() {
    final pricePerFraction = _propertyData!['pricePerFraction'] as BigInt;
    return pricePerFraction * BigInt.from(_selectedFractions);
  }

  String _formatPrice(BigInt wei) {
    return _blockchainService.weiToEther(wei);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Request Fractions')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_propertyData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Request Fractions')),
        body: const Center(child: Text('Failed to load property data')),
      );
    }

    final totalFractions = _propertyData!['totalFractions'] as int;
    final availableFractions = totalFractions - _userFractions;
    final canRequest = availableFractions > 0 && !_hasExistingRequest;

    return Scaffold(
      appBar: AppBar(title: const Text('Request Fractions')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Property info card ────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _propertyData!['location'],
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('${_propertyData!['city']}'),
                    Text(
                      '${_propertyData!['totalArea']} ${_propertyData!['areaUnit']}',
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Total Fractions',
                              style: TextStyle(color: Colors.grey),
                            ),
                            Text(
                              '$totalFractions',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Your Fractions',
                              style: TextStyle(color: Colors.grey),
                            ),
                            Text(
                              '$_userFractions',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Existing request banner ───────────────────────────────
            if (_hasExistingRequest) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.hourglass_empty, color: Colors.orange),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'You already have a pending request for this property. '
                            'Please wait for the supplier to respond.',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ── Fraction selector ─────────────────────────────────────
            const Text(
              'Select Fractions to Request',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            if (availableFractions <= 0)
              const Center(
                child: Text('You already own all available fractions.'),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: canRequest
                        ? Slider(
                      value: _selectedFractions.toDouble(),
                      min: 1,
                      max: availableFractions.toDouble(),
                      divisions: availableFractions > 1
                          ? availableFractions - 1
                          : null,
                      label: _selectedFractions.toString(),
                      onChanged: (value) {
                        setState(
                              () => _selectedFractions = value.toInt(),
                        );
                      },
                    )
                        : Padding(
                      padding:
                      const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _hasExistingRequest
                            ? 'Awaiting supplier approval.'
                            : 'You already own all available fractions.',
                        style:
                        const TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      '$_selectedFractions',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 24),

            // ── Price summary ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Price per fraction:'),
                      Text(
                        '${_formatPrice(_propertyData!['pricePerFraction'])} MATIC',
                        style:
                        const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Fractions:'),
                      Text('$_selectedFractions'),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Estimated Total:',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_formatPrice(_calculateTotal())} MATIC',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── After-approval preview ────────────────────────────────
            if (canRequest) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'If Approved:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Your total fractions:'),
                        Text(
                          '${_userFractions + _selectedFractions}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Ownership percentage:'),
                        Text(
                          '${((_userFractions + _selectedFractions) / totalFractions * 100).toStringAsFixed(2)}%',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // ── CTA button ────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _checkingRequest ? null : _sendPurchaseRequest,
                  icon: const Icon(Icons.send),
                  label: const Text(
                    'Request to Purchase Fractions',
                    style: TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'ℹ️ No payment or wallet transaction will occur now. '
                    'Your request will be reviewed by the supplier. '
                    'The blockchain transaction will only happen after approval.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ] else if (availableFractions > 0 && _hasExistingRequest) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.access_time, color: Colors.orange),
                    SizedBox(width: 12),
                    Text(
                      'Request pending supplier approval',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 12),
                    Text(
                      'You own 100% of this property!',
                      style: TextStyle(
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
}