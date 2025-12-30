// lib/screens/rent_distribution_screen.dart
import 'package:flutter/material.dart';
import '../blockchain/blockchain_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RentDistributionScreen extends StatefulWidget {
  final int propertyId;
  final bool isOwner;

  const RentDistributionScreen({
    super.key,
    required this.propertyId,
    this.isOwner = false,
  });

  @override
  State<RentDistributionScreen> createState() => _RentDistributionScreenState();
}

class _RentDistributionScreenState extends State<RentDistributionScreen> {
  final _blockchainService = BlockchainServiceEnhanced();
  final _amountController = TextEditingController();

  Map<String, dynamic>? _propertyData;
  BigInt _unclaimedRent = BigInt.zero;
  int _userFractions = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      await _blockchainService.init();

      final property = await _blockchainService.getLandProperty(widget.propertyId);

      if (_blockchainService.isConnected) {
        final unclaimed = await _blockchainService.getUnclaimedRent(
          _blockchainService.connectedAddress!,
          widget.propertyId,
        );
        _unclaimedRent = unclaimed;

        final fractions = await _blockchainService.getUserFractions(
          _blockchainService.connectedAddress!,
          widget.propertyId,
        );
        _userFractions = fractions;
      }
      setState(() {
        _propertyData = property;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }
  Future<void> _distributeRent() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }
    final weiAmount = _blockchainService.etherToWei(amount);
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
                Text('Distributing rent...'),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      if (!_blockchainService.isConnected) {
        await _blockchainService.connectWallet(context);
      }
      final txHash = await _blockchainService.distributeLandRent(
        propertyId: widget.propertyId,
        amount: weiAmount,
      );
      if (txHash != null) {
        final confirmed = await _blockchainService.waitForConfirmation(txHash);
        Navigator.pop(context);
        if (confirmed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Rent distributed successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          _amountController.clear();
          _loadData();
        }
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _claimRent() async {
    if (_unclaimedRent == BigInt.zero) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No rent to claim')),
      );
      return;
    }

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
                Text('Claiming rent...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final txHash = await _blockchainService.claimLandRent(widget.propertyId);

      if (txHash != null) {
        final confirmed = await _blockchainService.waitForConfirmation(txHash);
        Navigator.pop(context);

        if (confirmed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Claimed ${_blockchainService.weiToEther(_unclaimedRent)} MATIC!',
              ),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
        }
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Rent Management')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_propertyData == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Rent Management')),
        body: const Center(child: Text('Failed to load property data')),
      );
    }

    final totalFractions = _propertyData!['totalFractions'] as int;
    final ownershipPercent = totalFractions > 0
        ? (_userFractions / totalFractions * 100).toStringAsFixed(2)
        : '0.00';

    return Scaffold(
      appBar: AppBar(title: const Text('Rent Management')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Property info
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
                            const Text('Your Fractions', style: TextStyle(color: Colors.grey)),
                            Text('$_userFractions', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Ownership', style: TextStyle(color: Colors.grey)),
                            Text('$ownershipPercent%', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Unclaimed rent
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green[400]!, Colors.green[600]!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Icon(Icons.account_balance_wallet, color: Colors.white, size: 40),
                  const SizedBox(height: 12),
                  const Text(
                    'Unclaimed Rent',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_blockchainService.weiToEther(_unclaimedRent)} MATIC',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _unclaimedRent > BigInt.zero ? _claimRent : null,
                      icon: const Icon(Icons.download),
                      label: const Text('Claim Rent'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.green[700],
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Distribute rent section (owner only)
            if (widget.isOwner) ...[
              const Text(
                'Distribute Rent',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'As the property owner, you can distribute rent to all fraction holders.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'Amount (MATIC)',
                  hintText: 'Enter amount to distribute',
                  prefixIcon: const Icon(Icons.monetization_on),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _distributeRent,
                  icon: const Icon(Icons.upload),
                  label: const Text('Distribute Rent'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Rent will be distributed proportionally to all fraction holders.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 32),

            // Info section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      const Text(
                        'How Rent Distribution Works',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('• Rent is distributed proportionally based on fraction ownership'),
                  const SizedBox(height: 4),
                  const Text('• You can claim your share anytime'),
                  const SizedBox(height: 4),
                  const Text('• All transactions are recorded on blockchain'),
                  const SizedBox(height: 4),
                  Text('• Your share: $ownershipPercent% of total rent'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}