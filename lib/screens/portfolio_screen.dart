// lib/screens/portfolio_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
import '../blockchain/blockchain_service.dart';
import 'rent_distribution_screen.dart';
import 'shared_screens.dart';
import 'dart:convert';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  final _blockchainService = BlockchainServiceEnhanced();
  bool _loading = true;
  List<PortfolioItem> _holdings = [];
  double _totalValue = 0;
  double _totalUnclaimedRent = 0;

  @override
  void initState() {
    super.initState();
    _loadPortfolio();
  }

  Future<void> _loadPortfolio() async {
    setState(() => _loading = true);

    try {
      await _blockchainService.init();

      // Connect wallet if not connected
      if (!_blockchainService.isConnected) {
        await _blockchainService.connectWallet(context);
      }

      if (!_blockchainService.isConnected) {
        setState(() => _loading = false);
        return;
      }

      final userAddress = _blockchainService.connectedAddress!;

      // Get all land assets from Firebase
      final assetsQuery = await FirebaseFirestore.instance
          .collection('assets')
          .where('category', isEqualTo: 'land')
          .where('blockchainTokenId', isNotEqualTo: null)
          .get();

      final holdings = <PortfolioItem>[];
      double totalValue = 0;
      double totalRent = 0;

      for (final doc in assetsQuery.docs) {
        final data = doc.data();
        final propertyId = data['blockchainTokenId'] as int?;

        if (propertyId == null) continue;

        // Check user's fraction balance
        final fractions = await _blockchainService.getUserFractions(
          userAddress,
          propertyId,
        );

        if (fractions > 0) {
          // Get property details from blockchain
          final property = await _blockchainService.getLandProperty(propertyId);

          if (property != null) {
            final totalFractions = property['totalFractions'] as int;
            final pricePerFraction = property['pricePerFraction'] as BigInt;
            final ownershipPercent = (fractions / totalFractions) * 100;

            // Calculate value
            final value = _blockchainService.weiToEther(
              pricePerFraction * BigInt.from(fractions),
            );
            totalValue += double.tryParse(value) ?? 0;

            // Get unclaimed rent
            final unclaimedRent = await _blockchainService.getUnclaimedRent(
              userAddress,
              propertyId,
            );
            final rentValue = _blockchainService.weiToEther(unclaimedRent);
            totalRent += double.tryParse(rentValue) ?? 0;

            holdings.add(PortfolioItem(
              assetId: doc.id,
              propertyId: propertyId,
              title: data['title'] ?? 'Unknown Property',
              location: property['location'],
              city: property['city'],
              totalArea: property['totalArea'],
              areaUnit: property['areaUnit'],
              fractions: fractions,
              totalFractions: totalFractions,
              ownershipPercent: ownershipPercent,
              valueInMatic: double.tryParse(value) ?? 0,
              unclaimedRent: unclaimedRent,
              imageUrl: (data['images'] as List?)?.isNotEmpty == true
                  ? data['images'][0]
                  : null,
            ));
          }
        }
      }

      setState(() {
        _holdings = holdings;
        _totalValue = totalValue;
        _totalUnclaimedRent = totalRent;
        _loading = false;
      });
    } catch (e) {
      print('Error loading portfolio: $e');
      setState(() => _loading = false);
    }
  }

  // NEW: Transfer Dialog
  Future<void> _showTransferDialog(PortfolioItem holding) async {
    final addressController = TextEditingController();
    final amountController = TextEditingController(text: '1');
    bool transferring = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Transfer ${holding.title}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'You own ${holding.fractions} fractions',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Recipient Address (0x...)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.wallet),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Amount to Transfer',
                  border: const OutlineInputBorder(),
                  helperText: 'Max: ${holding.fractions}',
                ),
              ),
              if (transferring) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
                const Text('Please confirm in wallet...',
                    style: TextStyle(fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: transferring ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: transferring
                  ? null
                  : () async {
                final to = addressController.text.trim();
                final amount = int.tryParse(amountController.text) ?? 0;

                if (to.isEmpty || !to.startsWith('0x')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid Address')),
                  );
                  return;
                }
                if (amount <= 0 || amount > holding.fractions) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid Amount')),
                  );
                  return;
                }

                setState(() => transferring = true);

                try {
                  final tx = await _blockchainService.transferLandFraction(
                    toAddress: to,
                    propertyId: holding.propertyId,
                    amount: amount,
                  );

                  if (mounted) Navigator.pop(context);

                  if (tx != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content:
                        Text('Transfer initiated! TX: ${tx.substring(0, 8)}...'),
                      ),
                    );
                    // Refresh portfolio after delay
                    Future.delayed(
                        const Duration(seconds: 5), _loadPortfolio);
                  }
                } catch (e) {
                  if (mounted) {
                    setState(() => transferring = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              child: const Text('Transfer'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Portfolio'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPortfolio,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _holdings.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
        onRefresh: _loadPortfolio,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary cards
              _buildSummaryCards(),
              const SizedBox(height: 24),

              // Holdings list
              const Text(
                'Land Holdings',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              ..._holdings.map((holding) => _buildHoldingCard(holding)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 80, color: Colors.grey[400]),
            const SizedBox(height: 24),
            Text(
              'No Holdings Yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Start investing in fractionalized land properties',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                // Navigate to browse land
                Navigator.pop(context);
              },
              icon: const Icon(Icons.explore),
              label: const Text('Browse Properties'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        Expanded(
          child: Card(
            color: Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_balance, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      const Text(
                        'Total Value',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_totalValue.toStringAsFixed(4)} MATIC',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${_holdings.length} Properties',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            color: Colors.green[50],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.monetization_on, color: Colors.green[700]),
                      const SizedBox(width: 8),
                      const Text(
                        'Unclaimed Rent',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_totalUnclaimedRent.toStringAsFixed(4)} MATIC',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const Text(
                    'Available to claim',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHoldingCard(PortfolioItem holding) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AssetDetailScreen(assetId: holding.assetId),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Image thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: holding.imageUrl != null
                    ? Image.memory(
                  base64Decode(holding.imageUrl!),
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholderImage(),
                )
                    : _placeholderImage(),
              ),
              const SizedBox(width: 12),

              // Property details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      holding.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${holding.city} • ${holding.totalArea} ${holding.areaUnit}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildBadge(
                          '${holding.ownershipPercent.toStringAsFixed(2)}%',
                          Colors.blue,
                        ),
                        const SizedBox(width: 8),
                        _buildBadge(
                          '${holding.fractions}/${holding.totalFractions}',
                          Colors.grey,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${holding.valueInMatic.toStringAsFixed(4)} MATIC',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        if (holding.unclaimedRent > BigInt.zero)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.notifications,
                                    size: 12, color: Colors.orange[900]),
                                const SizedBox(width: 4),
                                Text(
                                  'Rent',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange[900],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Action buttons (Transfer & Rent)
              Column(
                children: [
                  IconButton(
                    icon: const Icon(Icons.send, size: 20, color: Colors.blue),
                    tooltip: 'Transfer',
                    onPressed: () => _showTransferDialog(holding),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, size: 16),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RentDistributionScreen(
                            propertyId: holding.propertyId,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholderImage() {
    return Container(
      width: 80,
      height: 80,
      color: Colors.grey[200],
      child: const Icon(Icons.home, size: 40, color: Colors.grey),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

class PortfolioItem {
  final String assetId;
  final int propertyId;
  final String title;
  final String location;
  final String city;
  final int totalArea;
  final String areaUnit;
  final int fractions;
  final int totalFractions;
  final double ownershipPercent;
  final double valueInMatic;
  final BigInt unclaimedRent;
  final String? imageUrl;

  PortfolioItem({
    required this.assetId,
    required this.propertyId,
    required this.title,
    required this.location,
    required this.city,
    required this.totalArea,
    required this.areaUnit,
    required this.fractions,
    required this.totalFractions,
    required this.ownershipPercent,
    required this.valueInMatic,
    required this.unclaimedRent,
    this.imageUrl,
  });
}