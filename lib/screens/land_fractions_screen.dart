// lib/screens/land_fractions_screen.dart
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
  Map<String, dynamic>? _propertyData;
  int _selectedFractions = 1;
  bool _loading = true;
  int _userFractions = 0;

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

      setState(() {
        _propertyData = property;
        _loading = false;
      });
    } catch (e) {
      print('Error loading property: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _purchaseFractions() async {
    if (_propertyData == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Purchase'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fractions: $_selectedFractions'),
            Text('Price per fraction: ${_formatPrice(_propertyData!['pricePerFraction'])} MATIC'),
            const SizedBox(height: 8),
            Text(
              'Total: ${_formatPrice(_calculateTotal())} MATIC',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 12),
            const Text(
              'This will execute a blockchain transaction. You will need to confirm in your wallet.',
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
            child: const Text('Purchase'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Processing transaction...'),
                SizedBox(height: 8),
                Text(
                  'Please confirm in your wallet',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      if (!_blockchainService.isConnected) {
        final address = await _blockchainService.connectWallet(context);
        if (address == null) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to connect wallet')),
          );
          return;
        }
      }

      final txHash = await _blockchainService.purchaseLandFractions(
        propertyId: widget.blockchainPropertyId,
        amount: _selectedFractions,
        totalCost: _calculateTotal(),
      );

      if (txHash != null) {
        final confirmed = await _blockchainService.waitForConfirmation(txHash);

        Navigator.pop(context);

        if (confirmed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Purchase successful! TX: ${txHash.substring(0, 10)}...'),
              backgroundColor: Colors.green,
            ),
          );

          _loadPropertyData();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transaction failed'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction rejected')),
        );
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
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
        appBar: AppBar(title: const Text('Purchase Fractions')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_propertyData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Purchase Fractions')),
        body: const Center(child: Text('Failed to load property data')),
      );
    }

    final totalFractions = _propertyData!['totalFractions'] as int;
    final availableFractions = totalFractions - _userFractions;

    return Scaffold(
      appBar: AppBar(title: const Text('Purchase Fractions')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                    Text('${_propertyData!['totalArea']} ${_propertyData!['areaUnit']}'),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Fractions', style: TextStyle(color: Colors.grey)),
                            Text('$totalFractions', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Your Fractions', style: TextStyle(color: Colors.grey)),
                            Text('$_userFractions', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              'Select Fractions to Purchase',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _selectedFractions.toDouble(),
                    min: 1,
                    max: availableFractions.toDouble(),
                    divisions: availableFractions - 1,
                    label: _selectedFractions.toString(),
                    onChanged: (value) {
                      setState(() => _selectedFractions = value.toInt());
                    },
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    '$_selectedFractions',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

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
                        style: const TextStyle(fontWeight: FontWeight.bold),
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
                        'Total Cost:',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                    'After Purchase:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Your total fractions:'),
                      Text(
                        '${_userFractions + _selectedFractions}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
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

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _purchaseFractions,
                icon: const Icon(Icons.shopping_cart),
                label: const Text(
                  'Purchase Fractions',
                  style: TextStyle(fontSize: 18),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              '⚠️ This transaction will be executed on Polygon blockchain. '
                  'Make sure you have enough MATIC for gas fees.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}