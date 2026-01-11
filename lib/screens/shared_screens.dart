// lib/screens/shared_screens.dart
// Complete shared screens with blockchain, IPFS, and all integrations

import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:uuid/uuid.dart'; // Added for ID generation
import 'auth_screens.dart';
import 'chat_screen.dart';
import 'review_screen.dart';
import 'reviews_list.dart';
import 'qr_generator_screen.dart';
import 'land_fractions_screen.dart';
import 'transfer_screen.dart'; // Added: Transfer functionality
import 'transfer_history_screen.dart'; // Added: History functionality
import '../blockchain/blockchain_service.dart';
import '../blockchain/ipfs_service.dart';
final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;

/// Fetch current user role
Future<String> fetchCurrentRole() async {
  try {
    final user = auth.currentUser;
    if (user == null) return 'user';
    final snap = await db.collection('users').doc(user.uid).get();
    final r = snap.data()?['role'] as String?;
    if (r == null || r.isEmpty) return 'user';
    return r;
  } catch (_) {
    return 'user';
  }
}

/// Decode base64 image safely
Uint8List? _tryBase64Decode(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    final cleaned = s.startsWith('data:') ? s.split(',').last : s;
    return base64Decode(cleaned);
  } catch (_) {
    return null;
  }
}

/// Build asset image from base64 or URL
Widget buildAssetImage(
    String? s, {
      BoxFit fit = BoxFit.cover,
      double width = 80,
      double height = 80,
    }) {
  if (s == null || s.isEmpty) {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: const Icon(Icons.image, size: 36),
    );
  }

  if (s.startsWith('http://') || s.startsWith('https://')) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        s,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => Container(
          width: width,
          height: height,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image),
        ),
      ),
    );
  }

  final bytes = _tryBase64Decode(s);
  if (bytes != null) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => Container(
          width: width,
          height: height,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image),
        ),
      ),
    );
  }

  return Container(
    width: width,
    height: height,
    color: Colors.grey[200],
    child: const Icon(Icons.image),
  );
}

/// Get document icon
Widget _getDocumentIcon(String type) {
  switch (type.toLowerCase()) {
    case 'pdf':
      return const Icon(Icons.picture_as_pdf, color: Colors.red);
    case 'jpg':
    case 'jpeg':
    case 'png':
      return const Icon(Icons.image, color: Colors.blue);
    case 'doc':
    case 'docx':
      return const Icon(Icons.description, color: Colors.blue);
    default:
      return const Icon(Icons.insert_drive_file);
  }
}

/// Format file size
String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1048576).toStringAsFixed(1)} MB';
}

/// Complete Asset Detail Screen with Blockchain Integration
class AssetDetailScreen extends StatefulWidget {
  final String assetId;
  const AssetDetailScreen({super.key, required this.assetId});

  @override
  State<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends State<AssetDetailScreen> {
  final _blockchainService = BlockchainServiceEnhanced();
  final _ipfsService = IPFSService();
  final _uuid = const Uuid();

  late Future<Map<String, dynamic?>> _loadFuture;
  Map<String, dynamic>? _blockchainData;
  Map<String, dynamic>? _ipfsData;
  bool _verifyingBlockchain = false;

  Future<Map<String, dynamic?>> _load() async {
    final assetSnap = await db.collection('assets').doc(widget.assetId).get();
    final role = await fetchCurrentRole();

    String ownerName = 'Unknown';
    if (assetSnap.exists) {
      final ownerId = assetSnap.data()?['ownerId'] ?? assetSnap.data()?['ownerUid'];
      if (ownerId != null) {
        try {
          final ownerSnap = await db.collection('users').doc(ownerId).get();
          if (ownerSnap.exists) {
            ownerName = ownerSnap.data()?['name'] ??
                ownerSnap.data()?['email'] ??
                'Unknown';
          }
        } catch (_) {}
      }

      // Load blockchain data if available
      final blockchainId = assetSnap.data()?['blockchainTokenId'] as int?;
      if (blockchainId != null) {
        await _loadBlockchainData(assetSnap.data()!['category'], blockchainId);
      }
    }

    return {'assetSnap': assetSnap, 'role': role, 'ownerName': ownerName};
  }

  Future<void> _loadBlockchainData(String category, int tokenId) async {
    try {
      await _blockchainService.init();

      if (category == 'electronics') {
        _blockchainData = await _blockchainService.getDevice(tokenId);
      } else if (category == 'land') {
        _blockchainData = await _blockchainService.getLandProperty(tokenId);
      }

      // Load IPFS data
      if (_blockchainData != null) {
        final ipfsHash = _blockchainData!['ipfsMetadata'] ??
            _blockchainData!['tokenURI'];
        if (ipfsHash != null && ipfsHash.isNotEmpty) {
          final hash = _ipfsService.extractHashFromUrl(ipfsHash);
          if (hash != null) {
            _ipfsData = await _ipfsService.retrieveJSON(hash);
          }
        }
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading blockchain data: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asset Detail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code),
            onPressed: () => _showQRCode(context),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic?>>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                ],
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final assetSnap = snapshot.data!['assetSnap'] as DocumentSnapshot;
          final role = snapshot.data!['role'] as String;
          final ownerName = snapshot.data!['ownerName'] as String;

          if (!assetSnap.exists) {
            return const Center(child: Text('Asset not found'));
          }

          final data = assetSnap.data() as Map<String, dynamic>;

          // Increment view count
          db.collection('assets')
              .doc(widget.assetId)
              .update({'views': FieldValue.increment(1)})
              .catchError((_) {});

          return _buildAssetDetails(context, data, role, ownerName);
        },
      ),
    );
  }

  Widget _buildAssetDetails(
      BuildContext context,
      Map<String, dynamic> data,
      String role,
      String ownerName,
      ) {
    final images = (data['images'] as List?)?.cast<String>() ?? [];
    final hasBlockchainId = data['blockchainTokenId'] != null;
    final isLand = data['category'] == 'land';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image carousel
          if (images.isNotEmpty)
            CarouselSlider(
              options: CarouselOptions(
                height: 250,
                autoPlay: true,
                enlargeCenterPage: true,
              ),
              items: images.map((img) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  child: buildAssetImage(
                    img,
                    width: double.infinity,
                    height: 250,
                    fit: BoxFit.cover,
                  ),
                );
              }).toList(),
            )
          else
            Container(
              height: 250,
              color: Colors.grey[200],
              child: const Center(
                child: Icon(Icons.image, size: 80, color: Colors.grey),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and blockchain badge
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        data['title'] ?? 'Untitled',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (hasBlockchainId)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.verified, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text(
                              'NFT',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // Price
                Text(
                  'PKR ${data['price']}',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),

                const SizedBox(height: 16),

                // Description
                if (data['description'] != null) ...[
                  const Text(
                    'Description',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    data['description'],
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                ],

                // Blockchain verification section
                if (hasBlockchainId && _blockchainData != null) ...[
                  _buildBlockchainSection(data['category']),
                  const SizedBox(height: 16),
                ],

                // Category-specific details
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Details',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildDetailRow('Owner', ownerName),
                        if (isLand) ...[
                          _buildDetailRow(
                            'Plot Area',
                            '${data['plotArea']} ${data['plotUnit']}',
                          ),
                          _buildDetailRow('City', data['city'] ?? '—'),
                          _buildDetailRow('Location', data['location'] ?? '—'),
                        ] else ...[
                          _buildDetailRow('Brand', data['brand'] ?? '—'),
                          _buildDetailRow('Model', data['model'] ?? '—'),
                          _buildDetailRow('Condition', data['condition'] ?? '—'),
                          if (data['serial'] != null)
                            _buildDetailRow('Serial', data['serial']),
                          if (data['warranty'] != null)
                            _buildDetailRow(
                              'Warranty',
                              '${data['warranty']} months',
                            ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Documents
                if (data['documents'] is List &&
                    (data['documents'] as List).isNotEmpty) ...[
                  _buildDocumentsSection(data['documents'] as List),
                  const SizedBox(height: 16),
                ],

                // Action buttons
                if (!role.contains('supplier')) ...[
                  _buildUserActions(context, data),
                ] else ...[
                  _buildSupplierActions(context, data, role),
                ],

                const SizedBox(height: 24),

                // Reviews section
                const Text(
                  'Reviews',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReviewScreen(
                          assetId: widget.assetId,
                          blockchainTokenId: data['blockchainTokenId'] as int?,
                          assetType: data['category'] ?? 'electronics',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.rate_review),
                  label: const Text('Write a Review'),
                ),
                const SizedBox(height: 12),
                ReviewsList(assetId: widget.assetId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockchainSection(String category) {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user, color: Colors.blue[700]),
                const SizedBox(width: 8),
                const Text(
                  'Blockchain Verified',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_blockchainData != null) ...[
              if (category == 'electronics') ...[
                _buildDetailRow('Brand', _blockchainData!['brand']),
                _buildDetailRow('Model', _blockchainData!['model']),
                _buildDetailRow('Serial', _blockchainData!['serialNumber']),
                _buildDetailRow(
                  'Verified',
                  _blockchainData!['isVerified'] ? 'Yes' : 'Pending',
                ),
              ] else if (category == 'land') ...[
                _buildDetailRow('Location', _blockchainData!['location']),
                _buildDetailRow('City', _blockchainData!['city']),
                _buildDetailRow(
                  'Total Fractions',
                  _blockchainData!['totalFractions'].toString(),
                ),
                _buildDetailRow(
                  'Price per Fraction',
                  '${_blockchainService.weiToEther(_blockchainData!['pricePerFraction'])} MATIC',
                ),
              ],
              if (_ipfsData != null) ...[
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.cloud_done, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    const Text(
                      'Documents stored on IPFS',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentsSection(List documents) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Documents',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ...documents.map((doc) {
              final d = doc as Map<String, dynamic>;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _getDocumentIcon(d['type'] ?? 'file'),
                title: Text(d['name'] ?? 'Document'),
                subtitle: Text(
                  '${(d['type'] ?? 'FILE').toString().toUpperCase()} • ${_formatFileSize(d['size'] ?? 0)}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: () {
                    // Download document
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Downloading ${d['name']}...'),
                      ),
                    );
                  },
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildUserActions(BuildContext context, Map<String, dynamic> data) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _requestToBuy(
                  context,
                  widget.assetId,
                  data['ownerId'] ?? data['ownerUid'],
                  data, // Pass full data
                ),
                icon: const Icon(Icons.shopping_cart),
                label: Text(data['category'] == 'land' ? 'Purchase/Invest' : 'Request to Buy'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (data['blockchainTokenId'] != null)
              OutlinedButton.icon(
                onPressed: () async {
                  // Verify on blockchain
                  final blockchainService = BlockchainServiceEnhanced();
                  await blockchainService.init();

                  if (data['category'] == 'electronics') {
                    final device = await blockchainService.getDevice(data['blockchainTokenId']);
                    if (device != null) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Blockchain Verification'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Brand: ${device['brand']}'),
                              Text('Model: ${device['model']}'),
                              Text('Serial: ${device['serialNumber']}'),
                              Text('Verified: ${device['isVerified'] ? '✓' : '✗'}'),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    }
                  } else {
                    final property = await blockchainService.getLandProperty(data['blockchainTokenId']);
                    if (property != null) {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Blockchain Verification'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Location: ${property['location']}'),
                              Text('Area: ${property['totalArea']} ${property['areaUnit']}'),
                              Text('Fractions: ${property['totalFractions']}'),
                              Text('Verified: ${property['isVerified'] ? '✓' : '✗'}'),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.verified),
                label: const Text('Verify'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 50),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _toggleFavorite(context, widget.assetId),
                icon: const Icon(Icons.favorite_border),
                label: const Text('Favorite'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  // Share asset
                },
                icon: const Icon(Icons.share),
                label: const Text('Share'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSupplierActions(BuildContext context, Map<String, dynamic> data, String role) {
    final currentUserUid = FirebaseAuth.instance.currentUser!.uid;
    final sellerUid = currentUserUid;

    final sellerWallet =
        BlockchainServiceEnhanced().connectedAddress;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _verifyAsset(context, widget.assetId),
                icon: const Icon(Icons.verified),
                label: const Text('Verify'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QRGeneratorScreen(
                        assetId: widget.assetId,
                        category: data['category'],
                        blockchainTokenId: data['blockchainTokenId'],
                        title: data['title'] ?? 'Asset',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.qr_code_2),
                label: const Text('QR Code'),
              ),
            ),
          ],
        ),
        if (role.toLowerCase().contains('supplier') && data['blockchainTokenId'] != null) ...[
          const SizedBox(height: 12),
          // 1. Transfer Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                int? maxAmount;

                if (data['category'] == 'land') {
                  final bs = BlockchainServiceEnhanced();
                  if (bs.isConnected) {
                    maxAmount = await bs.getUserFractions(
                      bs.connectedAddress!,
                      data['blockchainTokenId'],
                    );
                  }
                }

                if (sellerWallet == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please connect your wallet')),
                  );
                  return;
                }

                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) {
                        final buyerWallet = data['buyerWallet'] ?? '';
                        final sellerUid = data['sellerUid'] ?? FirebaseAuth.instance.currentUser!.uid;
                        final sellerWallet = BlockchainServiceEnhanced().connectedAddress ?? '';

                        if (data['category'] == 'electronics') {
                          return TransferScreen(
                            assetId: widget.assetId,
                            assetType: AssetType.electronics,
                            buyerUid: data['buyerUid'], // make sure this exists in your data
                            buyerWallet: buyerWallet,
                            sellerUid: sellerUid,
                            sellerWallet: sellerWallet,
                            tokenId: data['blockchainTokenId'],
                          );
                        } else {
                          return TransferScreen(
                            assetId: widget.assetId,
                            assetType: AssetType.land,
                            buyerUid: data['buyerUid'],
                            buyerWallet: buyerWallet,
                            sellerUid: sellerUid,
                            sellerWallet: sellerWallet,
                            propertyId: data['propertyId'],
                            fractionAmount: maxAmount,
                          );
                        }
                      },
                    ),
                  ).then((result) {
                    if (result == true) {
                      setState(() {
                        _loadFuture = _load();
                      });
                    }
                  });
                }
              },
              icon: const Icon(Icons.send),
              label: const Text('Transfer Ownership'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            ),
          ),
          const SizedBox(height: 8),

          // 2. History Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TransferHistoryScreen(
                      assetId: widget.assetId,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.history),
              label: const Text('View Transfer History'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _showQRCode(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('QR Code')),
          body: Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Scan to verify',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.qr_code,
                      size: 200,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _requestToBuy(BuildContext ctx, String assetId, String? sellerId, Map<String, dynamic> assetData) async {
    final user = auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please login')));
      return;
    }

    final category = assetData['category'] ?? '';
    final blockchainTokenId = assetData['blockchainTokenId'] as int?;

    // For LAND: Show fractional purchase option
    if (category == 'land' && blockchainTokenId != null) {
      final choice = await showDialog<String>(
        context: ctx,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Purchase Options'),
          content: const Text('Would you like to purchase fractions of this property?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, 'cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, 'full'),
              child: const Text('Request Full Purchase'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, 'fractions'),
              child: const Text('Buy Fractions'),
            ),
          ],
        ),
      );

      if (choice == 'fractions') {
        // Navigate to fractional purchase screen
        if (ctx.mounted) {
          Navigator.push(
            ctx,
            MaterialPageRoute(
              builder: (_) => LandFractionsScreen(
                assetId: assetId,
                blockchainPropertyId: blockchainTokenId,
              ),
            ),
          );
        }
        return;
      } else if (choice != 'full') {
        return; // User cancelled
      }
    }

    // For ELECTRONICS or full land purchase: Create transaction request
    final existing = await db
        .collection('transactions')
        .where('assetId', isEqualTo: assetId)
        .where('buyerUid', isEqualTo: user.uid)
        .where('status', whereIn: ['pending', 'approved', 'completed'])
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('You already have a request for this asset')),
        );
      }
      return;
    }

    final txId = _uuid.v4();
    await db.collection('transactions').doc(txId).set({
      'transactionId': txId,
      'assetId': assetId,
      'buyerUid': user.uid,
      'sellerUid': sellerId,
      'status': 'pending',
      'category': category,
      'blockchainTokenId': blockchainTokenId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Create chat document
    await db.collection('chats').doc(txId).set({
      'transactionId': txId,
      'assetId': assetId,
      'buyerUid': user.uid,
      'sellerUid': sellerId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text('✅ Request sent! Chat will open when supplier approves.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _verifyAsset(BuildContext ctx, String assetId) async {
    await db.collection('assets').doc(assetId).update({'verified': true});
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Asset verified successfully')),
      );
      setState(() {
        _loadFuture = _load();
      });
    }
  }

  Future<void> _toggleFavorite(BuildContext ctx, String assetId) async {
    final user = auth.currentUser;
    if (user == null) return;

    final favRef = db
        .collection('users')
        .doc(user.uid)
        .collection('favorites')
        .doc(assetId);

    final doc = await favRef.get();
    if (doc.exists) {
      await favRef.delete();
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Removed from favorites')),
        );
      }
    } else {
      await favRef.set({
        'assetId': assetId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Added to favorites')),
        );
      }
    }
  }
}

/// My Assets Screen
class MyAssetsScreen extends StatelessWidget {
  const MyAssetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Not logged in')));

    return FutureBuilder<String>(
      future: fetchCurrentRole(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final role = snap.data ?? 'user';
        if (role.toLowerCase().contains('supplier')) {
          final q = db
              .collection('assets')
              .where('ownerId', isEqualTo: user.uid)
              .orderBy('createdAt', descending: true);
          return Scaffold(
            appBar: AppBar(
              title: const Text('My Published Assets'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: q.snapshots(),
              builder: (context, snap2) {
                if (snap2.hasError) return Center(child: Text('Error: ${snap2.error}'));
                if (!snap2.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap2.data!.docs;
                if (docs.isEmpty) return const Center(child: Text('No published assets'));
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i].data();
                    final id = docs[i].id;
                    final thumb = (d['images'] is List && (d['images'] as List).isNotEmpty)
                        ? (d['images'] as List)[0] as String?
                        : null;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: SizedBox(width: 72, height: 72, child: buildAssetImage(thumb, width: 72, height: 72)),
                        title: Text(
                          d['title'] ?? d['name'] ?? 'Untitled',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(d['category'] ?? ''),
                        trailing: TextButton(
                          onPressed: () async {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Certificate generated')),
                            );
                          },
                          child: const Text('Cert'),
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: id)),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          );
        } else {
          final q = db
              .collection('transactions')
              .where('buyerUid', isEqualTo: user.uid)
              .where('status', isEqualTo: 'completed');
          return Scaffold(
            appBar: AppBar(
              title: const Text('My Assets'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: q.snapshots(),
              builder: (context, snap2) {
                if (snap2.hasError) return Center(child: Text('Error: ${snap2.error}'));
                if (!snap2.hasData) return const Center(child: CircularProgressIndicator());
                final txns = snap2.data!.docs;
                if (txns.isEmpty) return const Center(child: Text('No purchases yet'));
                return ListView.builder(
                  itemCount: txns.length,
                  itemBuilder: (context, i) {
                    final txn = txns[i].data();
                    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: db.collection('assets').doc(txn['assetId']).get(),
                      builder: (context, assetSnap) {
                        if (!assetSnap.hasData) return const ListTile(title: Text('Loading...'));
                        final asset = assetSnap.data!.data() ?? <String, dynamic>{};
                        final img = (asset['images'] is List && (asset['images'] as List).isNotEmpty)
                            ? (asset['images'] as List)[0] as String?
                            : null;
                        return ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: SizedBox(width: 72, height: 72, child: buildAssetImage(img, width: 72, height: 72)),
                          title: Text(asset['title'] ?? asset['name'] ?? 'Asset'),
                          subtitle: Text('PKR ${asset['price'] ?? 'N/A'}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.picture_as_pdf),
                            onPressed: () async {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Certificate downloaded')),
                              );
                            },
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: txn['assetId'])),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          );
        }
      },
    );
  }
}

/// Transactions Screen
class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Not logged in')));

    return FutureBuilder<String>(
      future: fetchCurrentRole(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final role = snap.data ?? 'user';

        late Query<Map<String, dynamic>> q;
        if (role.toLowerCase().contains('supplier')) {
          q = db
              .collection('transactions')
              .where('sellerUid', isEqualTo: user.uid)
              .orderBy('createdAt', descending: true);
        } else {
          q = db
              .collection('transactions')
              .where('buyerUid', isEqualTo: user.uid)
              .orderBy('createdAt', descending: true);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Transactions'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: q.snapshots(),
            builder: (context, snap2) {
              if (snap2.hasError) return Center(child: Text('Error: ${snap2.error}'));
              if (!snap2.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap2.data!.docs;
              if (docs.isEmpty) return const Center(child: Text('No transactions found'));

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final t = docs[i].data();
                  final id = docs[i].id;

                  final ts = t['createdAt'] as Timestamp?;
                  final time = ts != null ? "${ts.toDate().year}-${ts.toDate().month}-${ts.toDate().day}" : "";
                  final status = (t['status'] ?? '').toString();

                  final allowChat = !(status == 'pending' || status == 'rejected');

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      title: Text("Asset: ${t['assetId']}"),
                      subtitle: Text("Status: $status\nDate: $time"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (role.toLowerCase().contains('supplier') && status == 'pending') ...[
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.green),
                              onPressed: () => _updateStatus(id, 'approved'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => _updateStatus(id, 'rejected'),
                            ),
                          ],
                          if (allowChat)
                            IconButton(
                              icon: const Icon(Icons.chat),
                              onPressed: () async {
                                final myUid = auth.currentUser!.uid;

                                // decide who is the other user
                                final otherUid = role.toLowerCase().contains('supplier')
                                    ? t['buyerUid']
                                    : t['sellerUid'];

                                final chatId = id; // transaction document id

                                await db.collection('chats').doc(chatId).set({
                                  'participants': [myUid, otherUid],
                                  'lastMessage': '',
                                  'lastMessageTime': FieldValue.serverTimestamp(),
                                }, SetOptions(merge: true));

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ChatScreen(
                                      chatId: chatId,
                                      otherUserId: otherUid,
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: t['assetId'])),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _updateStatus(String id, String newStatus) async {
    await db.collection('transactions').doc(id).update({'status': newStatus});
  }
}

/// Related Items List
class RelatedItemsList extends StatelessWidget {
  final String? type;
  final String? city;
  const RelatedItemsList({super.key, this.type, this.city});

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q = db.collection('assets').withConverter<Map<String, dynamic>>(
      fromFirestore: (snap, _) => snap.data() ?? <String, dynamic>{},
      toFirestore: (m, _) => m,
    );
    if (type != null) q = q.where('category', isEqualTo: type);
    if (city != null) q = q.where('city', isEqualTo: city);
    q = q.limit(6);
    return SizedBox(
      height: 140,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final img = (d['images'] is List && (d['images'] as List).isNotEmpty)
                  ? (d['images'] as List)[0] as String?
                  : null;
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: docs[i].id)),
                ),
                child: Container(
                  width: 160,
                  margin: const EdgeInsets.only(right: 8),
                  child: Column(
                    children: [
                      Expanded(
                        child: img != null
                            ? buildAssetImage(img, width: double.infinity, height: double.infinity, fit: BoxFit.cover)
                            : Container(color: Colors.grey[200], child: const Icon(Icons.image)),
                      ),
                      const SizedBox(height: 6),
                      Text(d['title'] ?? d['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis)
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Favorites Screen
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Not logged in')));

    final q = db
        .collection('users')
        .doc(user.uid)
        .collection('favorites')
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorites'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('No favorites yet'));
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final assetId = docs[i].id;
              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: db.collection('assets').doc(assetId).get(),
                builder: (context, assetSnap) {
                  if (!assetSnap.hasData) return const ListTile(title: Text('Loading...'));
                  final asset = assetSnap.data!.data() ?? <String, dynamic>{};
                  final img = (asset['images'] is List && (asset['images'] as List).isNotEmpty)
                      ? (asset['images'] as List)[0] as String?
                      : null;
                  return ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: SizedBox(width: 72, height: 72, child: buildAssetImage(img, width: 72, height: 72)),
                    title: Text(asset['title'] ?? asset['name'] ?? 'Asset'),
                    subtitle: Text('PKR ${asset['price'] ?? 'N/A'}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        db.collection('users').doc(user.uid).collection('favorites').doc(assetId).delete();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Removed from favorites')),
                        );
                      },
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: assetId)),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Notifications Screen
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Not logged in')));

    final q = db
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('No notifications'));
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final n = docs[i].data();
              final ts = (n['createdAt'] as Timestamp?)?.toDate();
              return ListTile(
                contentPadding: const EdgeInsets.all(12),
                title: Text(n['title'] ?? 'Notification'),
                subtitle: Text(n['body'] ?? ''),
                trailing: ts != null ? Text("${ts.year}-${ts.month}-${ts.day}") : null,
                onTap: () {
                  docs[i].reference.update({'read': true});
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Settings Screen
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _loading = false;
  bool _darkMode = false;

  @override
  void initState() {
    super.initState();
    _loadUserSettings();
  }

  Future<void> _loadUserSettings() async {
    final user = auth.currentUser;
    if (user == null) return;
    final doc = await db.collection('users').doc(user.uid).get();
    if (!doc.exists) return;
    final data = doc.data()!;
    setState(() {
      _darkMode = (data['darkMode'] == true);
    });
  }

  Future<void> _setDarkMode(bool v) async {
    final user = auth.currentUser;
    if (user == null) return;
    await db.collection('users').doc(user.uid).update({'darkMode': v});
    setState(() => _darkMode = v);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preference saved')));
  }

  Future<void> _deleteAccount() async {
    final user = auth.currentUser;
    if (user == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete account'),
        content: const Text(
          'This will delete your Firebase account and user document. '
              'This requires recent login. Are you sure?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    try {
      await db.collection('users').doc(user.uid).delete().catchError((_) {});
      await user.delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account deleted')));
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              title: const Text('Dark mode'),
              subtitle: const Text('Save preference to your account'),
              value: _darkMode,
              onChanged: (v) => _setDarkMode(v),
            ),
            const SizedBox(height: 12),
            ListTile(
              title: const Text('Help & Support'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpScreen())),
            ),
            ListTile(
              title: const Text('Terms & Privacy'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsScreen())),
            ),
            const SizedBox(height: 20),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: _deleteAccount,
              child: const Text('Delete account'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Help Screen
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: const Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Contact', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('For support, contact: support@digitalgoods.com'),
            SizedBox(height: 16),
            Text('FAQ', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('• How to buy?\n• How to sell?\n• How to verify assets?'),
          ],
        ),
      ),
    );
  }
}

/// Terms Screen
class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms & Privacy'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'Your terms and privacy policy content goes here. '
              'Replace this placeholder with your real legal text.',
        ),
      ),
    );
  }
}

/// Profile Screen
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userDocStream;

  @override
  void initState() {
    super.initState();
    final user = auth.currentUser;
    if (user != null) _userDocStream = db.collection('users').doc(user.uid).snapshots();
  }

  Future<void> _sendResetPasswordEmail() async {
    final user = auth.currentUser;
    if (user == null) return;
    try {
      await auth.sendPasswordResetEmail(email: user.email ?? '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reset password email sent')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error sending reset email: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Not logged in')));

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDocStream,
      builder: (context, snap) {
        final data = snap.hasData && snap.data!.data() != null ? snap.data!.data()! : <String, dynamic>{};
        final displayEmail = user.email ?? '';
        final name = data['name'] ?? user.displayName ?? '';
        final role = data['role'] ?? 'user';

        return Scaffold(
          appBar: AppBar(
            title: const Text('Profile'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
                const SizedBox(height: 12),
                Text(
                  name.isNotEmpty ? name : displayEmail,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(displayEmail),
                const SizedBox(height: 12),
                Text('Role: $role'),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FavoritesScreen()),
                  ),
                  icon: const Icon(Icons.favorite),
                  label: const Text('Favorites'),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                  ),
                  icon: const Icon(Icons.notifications),
                  label: const Text('Notifications'),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                  icon: const Icon(Icons.settings),
                  label: const Text('Settings'),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _sendResetPasswordEmail,
                  icon: const Icon(Icons.lock_reset),
                  label: const Text('Reset Password'),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TransactionsScreen()),
                  ),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Transactions'),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () async {
                    await auth.signOut();
                    if (!context.mounted) return;
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (_) => false,
                    );
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}