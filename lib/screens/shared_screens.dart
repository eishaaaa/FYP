// lib/screens/shared_screens.dart
// Complete shared screens with blockchain, IPFS, and all integrations
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:uuid/uuid.dart';
import 'auth_screens.dart';
import 'chat_screen.dart';
import 'review_screen.dart';
import 'reviews_list.dart';
import 'qr_generator_screen.dart';
import 'land_fractions_screen.dart';
import 'transfer_screen.dart';
// BuyerOwnershipAcceptScreen lives in transfer_screen.dart
import 'wallet_screen.dart';
import 'transaction_model.dart';
import 'transfer_history_screen.dart';
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

/// Shared helper to add a transaction to Firestore and update in-memory wallet lists
Future<void> addTransaction({
  required String userId,
  required String type,
  required String title,
  required String toAddress,
  String value = "0",
  String gas = "0",
}) async {
  final txHash = const Uuid().v4();
  final time = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

  await FirebaseFirestore.instance
      .collection("users")
      .doc(userId)
      .collection("transactions")
      .add({
    "type": type,
    "title": title,
    "to": toAddress,
    "value": value,
    "gas": gas,
    "hash": txHash,
    "time": time,
  });
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

// ─────────────────────────────────────────────────────────────────────────────
// FRACTION REQUEST STATUS WIDGET
// Shows a supplier the fraction requests for a specific asset and lets them
// approve or reject each one inline.
// ─────────────────────────────────────────────────────────────────────────────
class FractionRequestsPanel extends StatelessWidget {
  final String assetId;
  final int blockchainPropertyId;

  const FractionRequestsPanel({
    super.key,
    required this.assetId,
    required this.blockchainPropertyId,
  });

  Future<void> _updateRequest(
      BuildContext context,
      String requestId,
      String transactionId,
      String newStatus,
      ) async {
    final batch = db.batch();

    // Update fraction_requests doc
    batch.update(
      db.collection('fraction_requests').doc(requestId),
      {'status': newStatus, 'respondedAt': FieldValue.serverTimestamp()},
    );

    // Mirror status into the transactions doc so the buyer's
    // TransactionsScreen reflects the change immediately.
    if (transactionId.isNotEmpty) {
      batch.update(
        db.collection('transactions').doc(transactionId),
        {'status': newStatus == 'approved' ? 'approved' : 'rejected'},
      );
    }

    await batch.commit();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 'approved'
                ? '✅ Request approved. You can now execute the blockchain transfer.'
                : '❌ Request rejected.',
          ),
          backgroundColor:
          newStatus == 'approved' ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('fraction_requests')
          .where('assetId', isEqualTo: assetId)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const SizedBox.shrink(); // Nothing pending — hide the panel
        }

        final requests = snap.data!.docs;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.inbox, color: Colors.orange[700], size: 18),
                const SizedBox(width: 8),
                Text(
                  'Pending Fraction Requests (${requests.length})',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...requests.map((doc) {
              final r = doc.data();
              final fractionsRequested = r['fractionsRequested'] ?? 0;
              final totalCostWei = r['totalCost'] ?? '0';
              final buyerUid = r['buyerUid'] ?? '';
              // The mirrored transaction ID stored when the request was created
              final transactionId = r['transactionId'] ?? '';

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.orange[200]!),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Buyer info
                      FutureBuilder<DocumentSnapshot>(
                        future: db.collection('users').doc(buyerUid).get(),
                        builder: (ctx, userSnap) {
                          final name = userSnap.hasData && userSnap.data!.exists
                              ? (userSnap.data!.data()
                          as Map<String, dynamic>)['name'] ??
                              'Buyer'
                              : _shorten(buyerUid);
                          return Row(
                            children: [
                              const Icon(Icons.person_outline,
                                  size: 14, color: Colors.grey),
                              const SizedBox(width: 6),
                              Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Fractions: $fractionsRequested',
                              style: const TextStyle(fontSize: 13)),
                          Text(
                            'Est. total: ${_weiDisplay(totalCostWei)} MATIC',
                            style: const TextStyle(
                                fontSize: 13, color: Colors.green),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _updateRequest(
                                context,
                                doc.id,
                                transactionId,
                                'rejected',
                              ),
                              icon: const Icon(Icons.close,
                                  size: 16, color: Colors.red),
                              label: const Text('Reject',
                                  style: TextStyle(color: Colors.red)),
                              style: OutlinedButton.styleFrom(
                                side:
                                const BorderSide(color: Colors.red),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _updateRequest(
                                context,
                                doc.id,
                                transactionId,
                                'approved',
                              ),
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Approve'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  /// Display a Wei string as a readable MATIC amount (no BlockchainService needed)
  String _weiDisplay(String weiStr) {
    try {
      final wei = BigInt.tryParse(weiStr) ?? BigInt.zero;
      final ether = wei / BigInt.from(10).pow(18);
      return ether.toStringAsFixed(4);
    } catch (_) {
      return '—';
    }
  }

  String _shorten(String id) {
    if (id.length <= 10) return id;
    return '${id.substring(0, 6)}...${id.substring(id.length - 4)}';
  }
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

    // Find the active regular transaction (full purchase / electronics)
    Map<String, dynamic>? activeTx;
    if (role.toLowerCase().contains('supplier') && auth.currentUser != null) {
      final txQuery = await db
          .collection('transactions')
          .where('assetId', isEqualTo: widget.assetId)
          .where('sellerUid', isEqualTo: auth.currentUser!.uid)
          .where('status', whereIn: ['approved', 'accepted'])
          .limit(1)
          .get();

      if (txQuery.docs.isNotEmpty) {
        activeTx = txQuery.docs.first.data();
        activeTx!['transactionId'] = txQuery.docs.first.id;
      }
    }

    return {
      'assetSnap': assetSnap,
      'role': role,
      'ownerName': ownerName,
      'activeTx': activeTx,
    };
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
          final activeTx = snapshot.data!['activeTx'] as Map<String, dynamic>?;

          if (!assetSnap.exists) {
            return const Center(child: Text('Asset not found'));
          }

          final data = assetSnap.data() as Map<String, dynamic>;

          // Increment view count
          db.collection('assets')
              .doc(widget.assetId)
              .update({'views': FieldValue.increment(1)})
              .catchError((_) {});

          return _buildAssetDetails(context, data, role, ownerName, activeTx);
        },
      ),
    );
  }

  Widget _buildAssetDetails(
      BuildContext context,
      Map<String, dynamic> data,
      String role,
      String ownerName,
      Map<String, dynamic>? activeTx,
      ) {
    final images = (data['images'] as List?)?.cast<String>() ?? [];
    final hasBlockchainId = data['blockchainTokenId'] != null;
    final isLand = data['category'] == 'land';
    final isSupplier = role.toLowerCase().contains('supplier');

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
                        StreamBuilder<DocumentSnapshot>(
                          stream: db.collection('assets').doc(widget.assetId).snapshots(),
                          builder: (ctx, assetLive) {
                            if (!assetLive.hasData || !assetLive.data!.exists) {
                              return _buildDetailRow('Current Owner', ownerName);
                            }
                            final liveData = assetLive.data!.data() as Map<String, dynamic>;
                            final liveOwnerId = liveData['ownerId'] ?? liveData['ownerUid'];
                            if (liveOwnerId == null) {
                              return _buildDetailRow('Current Owner', ownerName);
                            }
                            return FutureBuilder<DocumentSnapshot>(
                              future: db.collection('users').doc(liveOwnerId).get(),
                              builder: (ctx2, userSnap) {
                                String displayName = ownerName;
                                if (userSnap.hasData && userSnap.data!.exists) {
                                  final ud = userSnap.data!.data() as Map<String, dynamic>;
                                  displayName = ud['name'] ?? ud['email'] ?? ownerName;
                                }
                                final isSold = liveOwnerId != (data['ownerId'] ?? data['ownerUid']);
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildDetailRow('Current Owner', displayName),
                                    if (isSold)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Row(
                                          children: [
                                            Icon(Icons.swap_horiz, size: 14, color: Colors.orange[700]),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Ownership recently transferred',
                                              style: TextStyle(fontSize: 11, color: Colors.orange[700]),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
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
                          if (data['warranty'] != null && data['warranty'].isNotEmpty)
                            _buildDetailRow('Warranty', data['warranty']),
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

                // ── Fraction requests panel (supplier + land only) ────────
                if (isSupplier &&
                    isLand &&
                    data['blockchainTokenId'] != null) ...[
                  FractionRequestsPanel(
                    assetId: widget.assetId,
                    blockchainPropertyId: data['blockchainTokenId'] as int,
                  ),
                  const SizedBox(height: 16),
                ],

                // Action buttons
                if (!isSupplier) ...[
                  _buildUserActions(context, data),
                ] else ...[
                  _buildSupplierActions(context, data, role, activeTx),
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
                _buildDetailRow('Brand', _blockchainData!['brand'] ?? '—'),
                _buildDetailRow('Model', _blockchainData!['model'] ?? '—'),
                _buildDetailRow('Serial No.', _blockchainData!['serialNumber'] ?? '—'),
                if (_blockchainData!['warrantyStart'] != null &&
                    _blockchainData!['warrantyStart'].toString().isNotEmpty)
                  _buildDetailRow(
                    'Warranty Start',
                    _blockchainData!['warrantyStart'].toString(),
                  ),
                if (_blockchainData!['originalOwner'] != null &&
                    _blockchainData!['originalOwner'].toString().isNotEmpty &&
                    _blockchainData!['originalOwner'] != '0x0000000000000000000000000000000000000000')
                  _buildDetailRow(
                    'Original Owner',
                    '${_blockchainData!['originalOwner'].toString().substring(0, 10)}...',
                  ),
                _buildDetailRow(
                  'Status',
                  _blockchainData!['isVerified'] == true ? '✅ Verified' : '⏳ Pending',
                ),
              ] else if (category == 'land') ...[
                _buildDetailRow('Location', _blockchainData!['location'] ?? '—'),
                _buildDetailRow('City', _blockchainData!['city'] ?? '—'),
                _buildDetailRow(
                  'Total Fractions',
                  _blockchainData!['totalFractions']?.toString() ?? '—',
                ),
                _buildDetailRow(
                  'Price per Fraction',
                  '${_blockchainService.weiToEther(_blockchainData!['pricePerFraction'])} MATIC',
                ),
                if (_blockchainData!['originalOwner'] != null &&
                    _blockchainData!['originalOwner'].toString().isNotEmpty &&
                    _blockchainData!['originalOwner'] != '0x0000000000000000000000000000000000000000')
                  _buildDetailRow(
                    'Original Owner',
                    '${_blockchainData!['originalOwner'].toString().substring(0, 10)}...',
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
                  data,
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
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NFTCertificateScreen(
                      assetId: widget.assetId,
                      assetData: data,
                    ),
                  ),
                ),
                icon: const Icon(Icons.verified_user),
                label: const Text('Certificate'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 50),
                  foregroundColor: Colors.green[700],
                  side: BorderSide(color: Colors.green[700]!),
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
                onPressed: () {},
                icon: const Icon(Icons.share),
                label: const Text('Share'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSupplierActions(
      BuildContext context,
      Map<String, dynamic> data,
      String role,
      Map<String, dynamic>? activeTx,
      ) {
    final isLand = data['category'] == 'land';
    final hasBlockchainId = data['blockchainTokenId'] != null;

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

        if (hasBlockchainId) ...[
          const SizedBox(height: 12),

          // ── For LAND: show approved fraction-transfer button ──────────
          if (isLand) ...[
            _ApprovedFractionTransferButton(
              assetId: widget.assetId,
              blockchainPropertyId: data['blockchainTokenId'] as int,
              assetData: data,
              onTransferComplete: () => setState(() {
                _loadFuture = _load();
              }),
            ),
            const SizedBox(height: 8),
          ],

          // ── For ELECTRONICS (or full land purchase): Transfer button ──
          if (!isLand || activeTx != null) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: activeTx == null
                    ? null
                    : () async {
                  int? maxAmount;
                  if (isLand) {
                    final bs = BlockchainServiceEnhanced();
                    await bs.init();
                    if (bs.isConnected) {
                      maxAmount = await bs.getUserFractions(
                        bs.connectedAddress!,
                        data['blockchainTokenId'],
                      );
                    }
                  }

                  if (context.mounted) {
                    final buyerDoc = await db
                        .collection('users')
                        .doc(activeTx!['buyerUid'])
                        .get();
                    final buyerName =
                        buyerDoc.data()?['name'] ?? 'Buyer';
                    final assetPrice =
                        data['price']?.toString() ?? '0';
                    final transactionId =
                    activeTx['transactionId'];
                    final buyerUid = activeTx['buyerUid'];
                    final sellerUid = auth.currentUser!.uid;

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) {
                          if (!isLand) {
                            return TransferScreen(
                              assetId: widget.assetId,
                              assetType: AssetType.electronics,
                              transactionId: transactionId,
                              buyerUid: buyerUid,
                              sellerUid: sellerUid,
                              tokenId: data['blockchainTokenId'],
                              assetPrice: assetPrice,
                              buyerName: buyerName,
                            );
                          } else {
                            return TransferScreen(
                              assetId: widget.assetId,
                              assetType: AssetType.land,
                              transactionId: transactionId,
                              buyerUid: buyerUid,
                              sellerUid: sellerUid,
                              propertyId: data['blockchainTokenId'],
                              fractionAmount: maxAmount,
                              assetPrice: assetPrice,
                              buyerName: buyerName,
                            );
                          }
                        },
                      ),
                    ).then((result) async {
                      if (result == true) {
                        final buyerUid = activeTx['buyerUid'];
                        final sellerUid = auth.currentUser!.uid;

                        await addTransaction(
                          userId: sellerUid,
                          type: "received",
                          title: data['title'] ?? "Asset",
                          toAddress: buyerUid,
                          value: data['price']?.toString() ?? "0",
                        );

                        await addTransaction(
                          userId: buyerUid,
                          type: "nft",
                          title: data['title'] ?? "Asset",
                          toAddress: sellerUid,
                        );

                        setState(() {
                          _loadFuture = _load();
                        });
                      }
                    });
                  }
                },
                icon: const Icon(Icons.send),
                label: Text(
                  activeTx == null
                      ? 'Waiting for Buyer Approval'
                      : 'Transfer Ownership',
                ),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange),
              ),
            ),
          ],

          const SizedBox(height: 8),

          // ── Transfer History ──────────────────────────────────────────
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

  Future<void> _requestToBuy(
      BuildContext ctx,
      String assetId,
      String? sellerId,
      Map<String, dynamic> assetData,
      ) async {
    final user = auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Please login')));
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
          content: const Text(
              'Would you like to purchase fractions of this property?'),
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
              child: const Text('Request Fractions'),
            ),
          ],
        ),
      );

      if (choice == 'fractions') {
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
        return;
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
          const SnackBar(
              content: Text('You already have a request for this asset')),
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

    await addTransaction(
      userId: user.uid,
      type: "sent",
      title: assetData['title'] ?? "Asset",
      toAddress: assetData['ownerUid'] ?? assetData['ownerId'],
      value: assetData['price']?.toString() ?? "0",
    );

    // Create chat document
    await db.collection('chats').doc(txId).set({
      'transactionId': txId,
      'assetId': assetId,
      'assetType': category,
      'buyerUid': user.uid,
      'sellerUid': sellerId,
      'participants': [user.uid, sellerId],
      'lastMessage': '',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(
          content: Text(
              '✅ Request sent! Chat will open when supplier approves.'),
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

// ─────────────────────────────────────────────────────────────────────────────
// _ApprovedFractionTransferButton
// Listens for approved fraction_requests for this asset and, when found,
// shows a button the supplier can tap to execute the blockchain transfer.
// After the transfer succeeds it marks the fraction_request as 'completed'
// and records wallet entries for both parties.
// ─────────────────────────────────────────────────────────────────────────────
class _ApprovedFractionTransferButton extends StatelessWidget {
  final String assetId;
  final int blockchainPropertyId;
  final Map<String, dynamic> assetData;
  final VoidCallback onTransferComplete;

  const _ApprovedFractionTransferButton({
    required this.assetId,
    required this.blockchainPropertyId,
    required this.assetData,
    required this.onTransferComplete,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('fraction_requests')
          .where('assetId', isEqualTo: assetId)
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final approvedRequests = snap.data!.docs;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[700], size: 16),
                const SizedBox(width: 6),
                Text(
                  'Approved Fraction Transfers (${approvedRequests.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...approvedRequests.map((doc) {
              final r = doc.data();
              final buyerUid = r['buyerUid'] ?? '';
              final fractionsRequested = r['fractionsRequested'] ?? 0;
              final transactionId = r['transactionId'] ?? doc.id;

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.green[200]!),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('users')
                            .doc(buyerUid)
                            .get(),
                        builder: (ctx, userSnap) {
                          final name = userSnap.hasData &&
                              userSnap.data!.exists
                              ? (userSnap.data!.data()
                          as Map<String, dynamic>)['name'] ??
                              'Buyer'
                              : buyerUid;
                          return Row(
                            children: [
                              const Icon(Icons.person,
                                  size: 14, color: Colors.grey),
                              const SizedBox(width: 6),
                              Text('Buyer: $name',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '$fractionsRequested fractions',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue[800]),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _executeFractionTransfer(
                            context,
                            doc.id,
                            buyerUid,
                            fractionsRequested,
                            transactionId,
                          ),
                          icon: const Icon(Icons.send, size: 16),
                          label:
                          const Text('Execute Fraction Transfer'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[700],
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ],
        );
      },
    );
  }

  Future<void> _executeFractionTransfer(
      BuildContext context,
      String fractionRequestId,
      String buyerUid,
      int fractionsRequested,
      String transactionId,
      ) async {
    final sellerUid = FirebaseAuth.instance.currentUser?.uid;
    if (sellerUid == null) return;

    // Fetch buyer name for the TransferScreen
    final buyerDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(buyerUid)
        .get();
    final buyerName = buyerDoc.data()?['name'] ?? 'Buyer';
    final assetPrice = assetData['price']?.toString() ?? '0';

    if (!context.mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TransferScreen(
          assetId: assetId,
          assetType: AssetType.land,
          transactionId: transactionId,
          buyerUid: buyerUid,
          sellerUid: sellerUid,
          propertyId: blockchainPropertyId,
          fractionAmount: fractionsRequested,
          assetPrice: assetPrice,
          buyerName: buyerName,
        ),
      ),
    );

    if (result == true) {
      final batch = FirebaseFirestore.instance.batch();

      // Mark fraction_request as completed
      batch.update(
        FirebaseFirestore.instance
            .collection('fraction_requests')
            .doc(fractionRequestId),
        {
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
        },
      );

      // Mark the mirrored transaction as completed
      if (transactionId.isNotEmpty) {
        batch.update(
          FirebaseFirestore.instance
              .collection('transactions')
              .doc(transactionId),
          {
            'status': 'completed',
            'completedAt': FieldValue.serverTimestamp(),
          },
        );
      }

      await batch.commit();

      // Record wallet history for both parties
      await addTransaction(
        userId: sellerUid,
        type: 'received',
        title: assetData['title'] ?? 'Asset',
        toAddress: buyerUid,
        value: assetPrice,
      );

      await addTransaction(
        userId: buyerUid,
        type: 'nft',
        title: assetData['title'] ?? 'Asset',
        toAddress: sellerUid,
      );

      onTransferComplete();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Fraction transfer completed successfully!'),
            backgroundColor: Colors.green,
          ),
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
    if (user == null)
      return const Scaffold(
          body: Center(child: Text('Not logged in')));

    return FutureBuilder<String>(
      future: fetchCurrentRole(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
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
                if (snap2.hasError)
                  return Center(child: Text('Error: ${snap2.error}'));
                if (!snap2.hasData)
                  return const Center(child: CircularProgressIndicator());
                final docs = snap2.data!.docs;
                if (docs.isEmpty)
                  return const Center(child: Text('No published assets'));
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i].data();
                    final id = docs[i].id;
                    final thumb = (d['images'] is List &&
                        (d['images'] as List).isNotEmpty)
                        ? (d['images'] as List)[0] as String?
                        : null;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: SizedBox(
                            width: 72,
                            height: 72,
                            child: buildAssetImage(thumb,
                                width: 72, height: 72)),
                        title: Text(
                          d['title'] ?? d['name'] ?? 'Untitled',
                          style:
                          const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(d['category'] ?? ''),
                        trailing: TextButton(
                          onPressed: () async {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Certificate generated')),
                            );
                          },
                          child: const Text('Cert'),
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  AssetDetailScreen(assetId: id)),
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
              .collection('assets')
              .where('ownerId', isEqualTo: user.uid);

          return Scaffold(
            backgroundColor: Colors.grey[100],
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
                if (snap2.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Error loading assets:\n${snap2.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  );
                }
                if (!snap2.hasData)
                  return const Center(child: CircularProgressIndicator());

                final docs = [...snap2.data!.docs];
                docs.sort((a, b) {
                  final aT = a.data()['transferredAt'];
                  final bT = b.data()['transferredAt'];
                  if (aT is Timestamp && bT is Timestamp) {
                    return bT.compareTo(aT);
                  }
                  if (aT is Timestamp) return -1;
                  if (bT is Timestamp) return 1;
                  return 0;
                });

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 72, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text('No owned assets yet',
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey[600])),
                        const SizedBox(height: 8),
                        Text(
                            'Assets transferred to you will appear here.',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[400])),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i].data();
                    final id = docs[i].id;
                    final category = d['category'] ?? 'electronics';
                    final isLand = category == 'land';
                    final img = (d['images'] is List &&
                        (d['images'] as List).isNotEmpty)
                        ? (d['images'] as List)[0] as String?
                        : null;
                    final hasNFT = d['blockchainTokenId'] != null;
                    final transferredAt = d['transferredAt'];

                    String transferDate = '';
                    if (transferredAt is Timestamp) {
                      final dt = transferredAt.toDate();
                      final dd = dt.day.toString().padLeft(2, '0');
                      final mm = dt.month.toString().padLeft(2, '0');
                      transferDate = '$dd/$mm/${dt.year}';
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  AssetDetailScreen(assetId: id)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius:
                                    BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 80,
                                      height: 80,
                                      child: buildAssetImage(img,
                                          width: 80, height: 80),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                d['title'] ?? 'Untitled',
                                                style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight:
                                                  FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            if (hasNFT)
                                              Container(
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                    horizontal: 8,
                                                    vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: Colors.green,
                                                  borderRadius:
                                                  BorderRadius.circular(
                                                      12),
                                                ),
                                                child: const Row(
                                                  mainAxisSize:
                                                  MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.verified,
                                                        color: Colors.white,
                                                        size: 12),
                                                    SizedBox(width: 3),
                                                    Text('NFT',
                                                        style: TextStyle(
                                                            color:
                                                            Colors.white,
                                                            fontSize: 11,
                                                            fontWeight:
                                                            FontWeight
                                                                .bold)),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets
                                              .symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isLand
                                                ? Colors.brown[100]
                                                : Colors.blue[100],
                                            borderRadius:
                                            BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            isLand
                                                ? '🏡 Land Property'
                                                : '📦 Electronics',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isLand
                                                  ? Colors.brown[800]
                                                  : Colors.blue[800],
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'PKR ${d['price'] ?? '—'}',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              const Divider(height: 1),
                              const SizedBox(height: 10),
                              if (!isLand) ...[
                                _assetDetailChip(
                                    Icons.business_outlined,
                                    '${d['brand'] ?? '—'} ${d['model'] ?? ''}'),
                                if (d['serial'] != null)
                                  _assetDetailChip(Icons.qr_code,
                                      'S/N: ${d['serial']}'),
                                if (d['warranty'] != null &&
                                    d['warranty'].toString().isNotEmpty)
                                  _assetDetailChip(
                                    Icons.shield_outlined,
                                    'Warranty: ${d['warranty']}',
                                    color: Colors.green[700],
                                  ),
                              ] else ...[
                                _assetDetailChip(
                                    Icons.location_on_outlined,
                                    '${d['location'] ?? ''}, ${d['city'] ?? ''}'),
                                if (d['plotArea'] != null)
                                  _assetDetailChip(Icons.straighten,
                                      'Area: ${d['plotArea']} ${d['plotUnit'] ?? ''}'),
                              ],
                              if (transferDate.isNotEmpty)
                                _assetDetailChip(
                                    Icons.swap_horiz,
                                    'Transferred: $transferDate',
                                    color: Colors.deepPurple[600]),
                              if (hasNFT)
                                _assetDetailChip(Icons.token_outlined,
                                    'Token ID: #${d['blockchainTokenId']}',
                                    color: Colors.teal[700]),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              NFTCertificateScreen(
                                                assetId: id,
                                                assetData: d,
                                              ),
                                        ),
                                      ),
                                      icon: const Icon(
                                          Icons.verified_user_outlined,
                                          size: 16),
                                      label:
                                      const Text('View Certificate'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor:
                                        Colors.green[700],
                                        side: BorderSide(
                                            color: Colors.green[700]!),
                                        padding: const EdgeInsets
                                            .symmetric(vertical: 8),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              AssetDetailScreen(
                                                  assetId: id),
                                        ),
                                      ),
                                      icon: const Icon(
                                          Icons.visibility_outlined,
                                          size: 16),
                                      label: const Text('View Asset'),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets
                                            .symmetric(vertical: 8),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
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

/// Helper chip widget for MyAssetsScreen asset detail rows
Widget _assetDetailChip(IconData icon, String label, {Color? color}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Icon(icon, size: 14, color: color ?? Colors.grey[600]),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
                fontSize: 12, color: color ?? Colors.grey[700]),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

/// Transactions Screen
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Four tabs: Pending | Accepted | Fraction Requests | Rejected
  final List<String> _tabs = [
    'Pending',
    'Accepted',
    'Fractions',
    'Rejected',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(String id, String newStatus) async {
    await db.collection('transactions').doc(id).update({'status': newStatus});
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'completed':
        return Colors.blue;
      default:
        return Colors.orange;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'approved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      case 'completed':
        return Icons.done_all;
      default:
        return Icons.hourglass_empty;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null)
      return const Scaffold(
          body: Center(child: Text('Not logged in')));

    return FutureBuilder<String>(
      future: fetchCurrentRole(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final role = snap.data ?? 'user';
        final isSupplier = role.toLowerCase().contains('supplier');

        return Scaffold(
          appBar: AppBar(
            title: const Text('Transactions'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              isScrollable: true,
              tabs: [
                _buildTab(Icons.hourglass_empty, 'Pending'),
                _buildTab(Icons.check_circle, 'Accepted'),
                _buildTab(Icons.pie_chart, 'Fractions'),
                _buildTab(Icons.cancel, 'Rejected'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              // ── Tab 0: Pending ──────────────────────────────────────
              _buildTransactionList(
                  user.uid, isSupplier, 'pending', context),
              // ── Tab 1: Accepted ─────────────────────────────────────
              _buildTransactionList(
                  user.uid, isSupplier, 'approved', context),
              // ── Tab 2: Fraction Requests ────────────────────────────
              _buildFractionRequestsTab(user.uid, isSupplier, context),
              // ── Tab 3: Rejected ─────────────────────────────────────
              _buildTransactionList(
                  user.uid, isSupplier, 'rejected', context),
            ],
          ),
        );
      },
    );
  }

  Tab _buildTab(IconData icon, String label) {
    return Tab(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
    );
  }

  // ── Fraction Requests Tab ───────────────────────────────────────────────────
  Widget _buildFractionRequestsTab(
      String uid, bool isSupplier, BuildContext context) {
    // Suppliers see requests on their assets; buyers see their own requests
    final query = isSupplier
        ? db
        .collection('fraction_requests')
        .where('sellerUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        : db
        .collection('fraction_requests')
        .where('buyerUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.pie_chart_outline,
                    size: 60, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text(
                  isSupplier
                      ? 'No fraction requests received'
                      : 'You have not requested any fractions',
                  style:
                  TextStyle(color: Colors.grey[500], fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final r = docs[i].data();
            final docId = docs[i].id;
            final status = r['status'] ?? 'pending';
            final fractionsRequested = r['fractionsRequested'] ?? 0;
            final totalCostWei = r['totalCost'] ?? '0';
            final buyerUid = r['buyerUid'] ?? '';
            final sellerUid = r['sellerUid'] ?? '';
            final assetId = r['assetId'] ?? '';
            final transactionId = r['transactionId'] ?? docId;
            final ts = r['createdAt'] as Timestamp?;
            final date = ts != null
                ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}'
                : '—';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: _statusColor(status).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status badge + date
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _statusBadge(status),
                        Text(date,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Asset title
                    FutureBuilder<DocumentSnapshot>(
                      future: db.collection('assets').doc(assetId).get(),
                      builder: (ctx, assetSnap) {
                        final title = assetSnap.hasData &&
                            assetSnap.data!.exists
                            ? (assetSnap.data!.data()
                        as Map<String, dynamic>)['title'] ??
                            'Asset'
                            : 'Loading…';
                        return Row(children: [
                          const Icon(Icons.home_work_outlined,
                              size: 16, color: Colors.grey),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]);
                      },
                    ),
                    const SizedBox(height: 4),
                    // Fractions + cost
                    Row(
                      children: [
                        Icon(Icons.pie_chart_outline,
                            size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 6),
                        Text(
                          '$fractionsRequested fractions  •  ${_weiDisplay(totalCostWei)} MATIC',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),

                    // Other party info
                    const SizedBox(height: 4),
                    FutureBuilder<DocumentSnapshot>(
                      future: db
                          .collection('users')
                          .doc(isSupplier ? buyerUid : sellerUid)
                          .get(),
                      builder: (ctx, userSnap) {
                        final name = userSnap.hasData &&
                            userSnap.data!.exists
                            ? (userSnap.data!.data()
                        as Map<String, dynamic>)['name'] ??
                            '—'
                            : '—';
                        return Row(children: [
                          Icon(
                            isSupplier
                                ? Icons.person_outline
                                : Icons.store_outlined,
                            size: 14,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isSupplier ? 'Buyer: $name' : 'Seller: $name',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[600]),
                          ),
                        ]);
                      },
                    ),

                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 8),

                    // Action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // View asset
                        TextButton.icon(
                          icon: const Icon(Icons.visibility_outlined,
                              size: 16),
                          label: const Text('View'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.blue,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8),
                          ),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    AssetDetailScreen(assetId: assetId)),
                          ),
                        ),

                        // Supplier: approve / reject pending requests
                        if (isSupplier && status == 'pending') ...[
                          TextButton.icon(
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Approve'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                            ),
                            onPressed: () => _updateFractionRequest(
                              context,
                              docId,
                              transactionId,
                              'approved',
                            ),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text('Reject'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                            ),
                            onPressed: () => _updateFractionRequest(
                              context,
                              docId,
                              transactionId,
                              'rejected',
                            ),
                          ),
                        ],

                        // Supplier: execute transfer once approved
                        if (isSupplier && status == 'approved') ...[
                          ElevatedButton.icon(
                            icon: const Icon(Icons.send, size: 14),
                            label: const Text('Transfer'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[700],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12),
                            ),
                            onPressed: () => _navigateToFractionTransfer(
                              context,
                              docId,
                              assetId,
                              buyerUid,
                              fractionsRequested,
                              transactionId,
                              r['blockchainPropertyId'] ??
                                  r['blockchainTokenId'],
                            ),
                          ),
                        ],

                        // Buyer: status-only for approved / completed
                        if (!isSupplier && status == 'approved') ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green),
                            ),
                            child: const Text(
                              'Approved — awaiting transfer',
                              style: TextStyle(
                                  color: Colors.green, fontSize: 12),
                            ),
                          ),
                        ],

                        if (!isSupplier && status == 'completed') ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue),
                            ),
                            child: const Text(
                              '✅ Transfer complete',
                              style: TextStyle(
                                  color: Colors.blue, fontSize: 12),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Regular transaction list (pending / approved / rejected) ─────────────
  Widget _buildTransactionList(
      String uid, bool isSupplier, String status, BuildContext context) {
    final query = db
        .collection('transactions')
        .where(isSupplier ? 'sellerUid' : 'buyerUid', isEqualTo: uid)
        .where('status', isEqualTo: status)
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap2) {
        if (snap2.hasError)
          return Center(child: Text('Error: ${snap2.error}'));
        if (!snap2.hasData)
          return const Center(child: CircularProgressIndicator());
        final docs = snap2.data!.docs;

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_statusIcon(status), size: 60, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text(
                  'No $status transactions',
                  style:
                  TextStyle(color: Colors.grey[500], fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final t = docs[i].data();
            final id = docs[i].id;
            final ts = t['createdAt'] as Timestamp?;
            final date = ts != null
                ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}'
                : '—';
            final txStatus = (t['status'] ?? '').toString();
            final allowChat =
                txStatus == 'approved' || txStatus == 'accepted';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: _statusColor(txStatus).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _statusBadge(txStatus),
                        Text(date,
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500])),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<DocumentSnapshot>(
                      future: db
                          .collection('assets')
                          .doc(t['assetId'])
                          .get(),
                      builder: (context, assetSnap) {
                        String title = 'Loading...';
                        if (assetSnap.hasData && assetSnap.data!.exists) {
                          title = (assetSnap.data!.data()
                          as Map<String, dynamic>)['title'] ??
                              'Unnamed Asset';
                        } else if (assetSnap.hasError) {
                          title = 'Asset ID: ${t['assetId'] ?? '—'}';
                        }
                        return Row(
                          children: [
                            const Icon(Icons.inventory_2_outlined,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(title,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          isSupplier
                              ? Icons.person_outline
                              : Icons.store_outlined,
                          size: 14,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isSupplier
                              ? 'Buyer: ${_shorten(t['buyerUid'] ?? '—')}'
                              : 'Seller: ${_shorten(t['sellerUid'] ?? '—')}',
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                    if (t['price'] != null) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.attach_money,
                            size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text('${t['price']}',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[600])),
                      ]),
                    ],
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.visibility_outlined,
                              size: 16),
                          label: const Text('View'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.blue,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8),
                          ),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AssetDetailScreen(
                                  assetId: t['assetId']),
                            ),
                          ),
                        ),
                        if (allowChat) ...[
                          const SizedBox(width: 4),
                          TextButton.icon(
                            icon: const Icon(Icons.chat_outlined,
                                size: 16),
                            label: const Text('Chat'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.teal,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                            ),
                            onPressed: () async {
                              final myUid = auth.currentUser!.uid;
                              final otherUid = isSupplier
                                  ? t['buyerUid']
                                  : t['sellerUid'];
                              await db
                                  .collection('chats')
                                  .doc(id)
                                  .set({
                                'participants': [myUid, otherUid],
                                'assetId': t['assetId'],
                                'assetType':
                                t['category'] ?? 'electronics',
                                'sellerUid': isSupplier
                                    ? myUid
                                    : otherUid,
                                'buyerUid': isSupplier
                                    ? otherUid
                                    : myUid,
                                'lastMessage': '',
                                'lastMessageTime':
                                FieldValue.serverTimestamp(),
                              }, SetOptions(merge: true));
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    chatId: id,
                                    otherUserId: otherUid,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                        if (isSupplier && txStatus == 'pending') ...[
                          const SizedBox(width: 4),
                          TextButton.icon(
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Accept'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                            ),
                            onPressed: () =>
                                _updateStatus(id, 'approved'),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text('Reject'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                            ),
                            onPressed: () =>
                                _updateStatus(id, 'rejected'),
                          ),
                        ],
                        if (!isSupplier &&
                            (txStatus == 'approved' ||
                                txStatus == 'pending')) ...[
                          const SizedBox(width: 4),
                          TextButton.icon(
                            icon: const Icon(
                                Icons.account_balance_wallet,
                                size: 16),
                            label: const Text('My Wallet'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.deepPurple,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                            ),
                            onPressed: () {
                              final category =
                                  t['category'] ?? 'electronics';
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      BuyerOwnershipAcceptScreen(
                                        assetId: t['assetId'] ?? '',
                                        transactionId: id,
                                        sellerName: _shorten(
                                            t['sellerUid'] ?? '—'),
                                        assetType: category == 'land'
                                            ? AssetType.land
                                            : AssetType.electronics,
                                      ),
                                ),
                              );
                            },
                          ),
                        ],
                        if (!isSupplier && txStatus == 'completed') ...[
                          const SizedBox(width: 4),
                          TextButton.icon(
                            icon: const Icon(Icons.move_to_inbox,
                                size: 16),
                            label: const Text('Ownership'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.teal,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                            ),
                            onPressed: () {
                              final category =
                                  t['category'] ?? 'electronics';
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      BuyerOwnershipAcceptScreen(
                                        assetId: t['assetId'] ?? '',
                                        transactionId: id,
                                        sellerName: _shorten(
                                            t['sellerUid'] ?? '—'),
                                        assetType: category == 'land'
                                            ? AssetType.land
                                            : AssetType.electronics,
                                      ),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _statusBadge(String status) {
    return Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor(status).withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(_statusIcon(status),
              size: 14, color: _statusColor(status)),
          const SizedBox(width: 4),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _statusColor(status),
            ),
          ),
        ],
      ),
    );
  }

  /// Update a fraction_request and mirror the status into transactions.
  Future<void> _updateFractionRequest(
      BuildContext context,
      String fractionRequestId,
      String transactionId,
      String newStatus,
      ) async {
    final batch = db.batch();

    batch.update(
      db.collection('fraction_requests').doc(fractionRequestId),
      {'status': newStatus, 'respondedAt': FieldValue.serverTimestamp()},
    );

    if (transactionId.isNotEmpty) {
      batch.update(
        db.collection('transactions').doc(transactionId),
        {'status': newStatus == 'approved' ? 'approved' : 'rejected'},
      );
    }

    await batch.commit();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newStatus == 'approved'
              ? '✅ Request approved'
              : '❌ Request rejected'),
          backgroundColor:
          newStatus == 'approved' ? Colors.green : Colors.red,
        ),
      );
    }
  }

  /// Navigate supplier to TransferScreen for a fraction transfer.
  Future<void> _navigateToFractionTransfer(
      BuildContext context,
      String fractionRequestId,
      String assetId,
      String buyerUid,
      int fractionsRequested,
      String transactionId,
      dynamic propertyId,
      ) async {
    final sellerUid = auth.currentUser?.uid;
    if (sellerUid == null) return;

    final assetDoc = await db.collection('assets').doc(assetId).get();
    final assetData = assetDoc.data() ?? {};
    final assetPrice = assetData['price']?.toString() ?? '0';

    final buyerDoc =
    await db.collection('users').doc(buyerUid).get();
    final buyerName = buyerDoc.data()?['name'] ?? 'Buyer';

    final blockchainPropertyId =
    propertyId is int ? propertyId : int.tryParse(propertyId.toString()) ?? 0;

    if (!context.mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TransferScreen(
          assetId: assetId,
          assetType: AssetType.land,
          transactionId: transactionId,
          buyerUid: buyerUid,
          sellerUid: sellerUid,
          propertyId: blockchainPropertyId,
          fractionAmount: fractionsRequested,
          assetPrice: assetPrice,
          buyerName: buyerName,
        ),
      ),
    );

    if (result == true) {
      final batch = db.batch();

      batch.update(
        db.collection('fraction_requests').doc(fractionRequestId),
        {
          'status': 'completed',
          'completedAt': FieldValue.serverTimestamp(),
        },
      );

      if (transactionId.isNotEmpty) {
        batch.update(
          db.collection('transactions').doc(transactionId),
          {
            'status': 'completed',
            'completedAt': FieldValue.serverTimestamp(),
          },
        );
      }

      await batch.commit();

      await addTransaction(
        userId: sellerUid,
        type: 'received',
        title: assetData['title'] ?? 'Asset',
        toAddress: buyerUid,
        value: assetPrice,
      );

      await addTransaction(
        userId: buyerUid,
        type: 'nft',
        title: assetData['title'] ?? 'Asset',
        toAddress: sellerUid,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
            Text('✅ Fraction transfer completed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  String _shorten(String id) {
    if (id.length <= 10) return id;
    return '${id.substring(0, 6)}...${id.substring(id.length - 4)}';
  }

  String _weiDisplay(String weiStr) {
    try {
      final wei = BigInt.tryParse(weiStr) ?? BigInt.zero;
      final ether = wei / BigInt.from(10).pow(18);
      return ether.toStringAsFixed(4);
    } catch (_) {
      return '—';
    }
  }
}

/// Related Items List
class RelatedItemsList extends StatelessWidget {
  final String? type;
  final String? city;
  const RelatedItemsList({super.key, this.type, this.city});

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q =
    db.collection('assets').withConverter<Map<String, dynamic>>(
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
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final img = (d['images'] is List &&
                  (d['images'] as List).isNotEmpty)
                  ? (d['images'] as List)[0] as String?
                  : null;
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          AssetDetailScreen(assetId: docs[i].id)),
                ),
                child: Container(
                  width: 160,
                  margin: const EdgeInsets.only(right: 8),
                  child: Column(
                    children: [
                      Expanded(
                        child: img != null
                            ? buildAssetImage(img,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover)
                            : Container(
                            color: Colors.grey[200],
                            child: const Icon(Icons.image)),
                      ),
                      const SizedBox(height: 6),
                      Text(d['title'] ?? d['name'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis)
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
    if (user == null)
      return const Scaffold(
          body: Center(child: Text('Not logged in')));

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
          if (snap.hasError)
            return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty)
            return const Center(child: Text('No favorites yet'));
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final assetId = docs[i].id;
              return FutureBuilder<
                  DocumentSnapshot<Map<String, dynamic>>>(
                future: db.collection('assets').doc(assetId).get(),
                builder: (context, assetSnap) {
                  if (!assetSnap.hasData)
                    return const ListTile(
                        title: Text('Loading...'));
                  final asset =
                      assetSnap.data!.data() ?? <String, dynamic>{};
                  final img = (asset['images'] is List &&
                      (asset['images'] as List).isNotEmpty)
                      ? (asset['images'] as List)[0] as String?
                      : null;
                  return ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: SizedBox(
                        width: 72,
                        height: 72,
                        child: buildAssetImage(img,
                            width: 72, height: 72)),
                    title: Text(
                        asset['title'] ?? asset['name'] ?? 'Asset'),
                    subtitle: Text('PKR ${asset['price'] ?? 'N/A'}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        db
                            .collection('users')
                            .doc(user.uid)
                            .collection('favorites')
                            .doc(assetId)
                            .delete();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content:
                              Text('Removed from favorites')),
                        );
                      },
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              AssetDetailScreen(assetId: assetId)),
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
    if (user == null)
      return const Scaffold(
          body: Center(child: Text('Not logged in')));

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
          if (snap.hasError)
            return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty)
            return const Center(child: Text('No notifications'));
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final n = docs[i].data();
              final ts = (n['createdAt'] as Timestamp?)?.toDate();
              return ListTile(
                contentPadding: const EdgeInsets.all(12),
                title: Text(n['title'] ?? 'Notification'),
                subtitle: Text(n['body'] ?? ''),
                trailing: ts != null
                    ? Text('${ts.year}-${ts.month}-${ts.day}')
                    : null,
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
  bool _lastSeenEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadUserSettings();
  }

  Future<void> _loadUserSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    setState(() {
      _darkMode = userDoc.data()?['darkMode'] ?? false;
      _lastSeenEnabled = userDoc.data()?['lastSeenEnabled'] ?? true;
    });
  }

  Future<void> _setLastSeen(bool val) async {
    setState(() => _lastSeenEnabled = val);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .update({'lastSeenEnabled': val});
  }

  Future<void> _setDarkMode(bool v) async {
    final user = auth.currentUser;
    if (user == null) return;
    await db
        .collection('users')
        .doc(user.uid)
        .update({'darkMode': v});
    setState(() => _darkMode = v);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preference saved')));
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
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    try {
      await db
          .collection('users')
          .doc(user.uid)
          .delete()
          .catchError((_) {});
      await user.delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account deleted')));
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: $e')));
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
              subtitle:
              const Text('Save preference to your account'),
              value: _darkMode,
              onChanged: (v) => _setDarkMode(v),
            ),
            SwitchListTile(
              title: const Text('Last Seen'),
              subtitle: const Text(
                  'Show others when you were last active'),
              value: _lastSeenEnabled,
              onChanged: (v) => _setLastSeen(v),
            ),
            const SizedBox(height: 12),
            ListTile(
              title: const Text('Help & Support'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const HelpScreen())),
            ),
            ListTile(
              title: const Text('Terms & Privacy'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const TermsScreen())),
            ),
            const SizedBox(height: 20),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red),
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
            Text('Contact',
                style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('For support, contact: support@digitalgoods.com'),
            SizedBox(height: 16),
            Text('FAQ',
                style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(
                '• How to buy?\n• How to sell?\n• How to verify assets?'),
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
  final VoidCallback? onBack;
  const ProfileScreen({super.key, this.onBack});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userDocStream;

  @override
  void initState() {
    super.initState();
    final user = auth.currentUser;
    if (user != null)
      _userDocStream =
          db.collection('users').doc(user.uid).snapshots();
  }

  Future<void> _sendResetPasswordEmail() async {
    final user = auth.currentUser;
    if (user == null) return;
    try {
      await auth.sendPasswordResetEmail(email: user.email ?? '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Reset password email sent')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error sending reset email: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null)
      return const Scaffold(
          body: Center(child: Text('Not logged in')));

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDocStream,
      builder: (context, snap) {
        final data = snap.hasData && snap.data!.data() != null
            ? snap.data!.data()!
            : <String, dynamic>{};
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
                const CircleAvatar(
                    radius: 40,
                    child: Icon(Icons.person, size: 40)),
                const SizedBox(height: 12),
                Text(
                  name.isNotEmpty ? name : displayEmail,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(displayEmail),
                const SizedBox(height: 12),
                Text('Role: $role'),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const FavoritesScreen()),
                  ),
                  icon: const Icon(Icons.favorite),
                  label: const Text('Favorites'),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                        const NotificationsScreen()),
                  ),
                  icon: const Icon(Icons.notifications),
                  label: const Text('Notifications'),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SettingsScreen()),
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
                    MaterialPageRoute(
                        builder: (_) => const TransactionsScreen()),
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
                      MaterialPageRoute(
                          builder: (_) => const LoginScreen()),
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

// ─────────────────────────────────────────────────────────────────────────────
// NFT Certificate Screen
// ─────────────────────────────────────────────────────────────────────────────
class NFTCertificateScreen extends StatefulWidget {
  final String assetId;
  final Map<String, dynamic> assetData;

  const NFTCertificateScreen({
    super.key,
    required this.assetId,
    required this.assetData,
  });

  @override
  State<NFTCertificateScreen> createState() =>
      _NFTCertificateScreenState();
}

class _NFTCertificateScreenState extends State<NFTCertificateScreen> {
  final _blockchainService = BlockchainServiceEnhanced();

  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _chainData;

  int _priorTransferCount = 0;
  bool _isReportedStolen = false;
  String _originalOwnerWallet = '';
  String _originalOwnerName = 'Unknown';
  String _warrantyStart = '—';

  @override
  void initState() {
    super.initState();
    _loadCertificateData();
  }

  Future<void> _loadCertificateData() async {
    try {
      final tokenId = widget.assetData['blockchainTokenId'] as int?;
      final category = widget.assetData['category'] ?? 'electronics';

      if (tokenId != null) {
        await _blockchainService.init();
        if (category == 'electronics') {
          _chainData = await _blockchainService.getDevice(tokenId);
        } else {
          _chainData =
          await _blockchainService.getLandProperty(tokenId);
        }
      }

      if (_chainData != null) {
        final raw = _chainData!['originalOwner']?.toString() ?? '';
        if (raw.isNotEmpty &&
            raw !=
                '0x0000000000000000000000000000000000000000') {
          _originalOwnerWallet = raw;
        }

        final ws = _chainData!['warrantyStart'];
        if (ws != null) {
          if (ws is int && ws > 0) {
            final dt =
            DateTime.fromMillisecondsSinceEpoch(ws * 1000);
            _warrantyStart =
            '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
          } else if (ws is String && ws.isNotEmpty) {
            _warrantyStart = ws;
          }
        }

        if (_warrantyStart == '—') {
          final fw =
              widget.assetData['warranty']?.toString() ?? '';
          if (fw.isNotEmpty) _warrantyStart = fw;
        }
      }

      final ownerId =
          widget.assetData['ownerId'] ?? widget.assetData['ownerUid'];
      if (ownerId != null) {
        try {
          final ownerSnap = await db
              .collection('users')
              .doc(ownerId as String)
              .get();
          if (ownerSnap.exists) {
            _originalOwnerName = ownerSnap.data()?['name'] ??
                ownerSnap.data()?['email'] ??
                'Unknown';
          }
        } catch (_) {}
      }

      try {
        final txSnap = await db
            .collection('transactions')
            .where('assetId', isEqualTo: widget.assetId)
            .where('status',
            whereIn: ['completed', 'transferred', 'done'])
            .get();
        _priorTransferCount = txSnap.docs.length;
      } catch (_) {}

      try {
        final assetSnap =
        await db.collection('assets').doc(widget.assetId).get();
        if (assetSnap.exists) {
          final d = assetSnap.data()!;
          _isReportedStolen = d['isStolen'] == true ||
              d['reportedStolen'] == true ||
              d['stolenReported'] == true;
        }
      } catch (_) {}

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.assetData['category'] ?? 'electronics';
    final isElectronics = category == 'electronics';

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('NFT Certificate'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                  'Failed to load certificate: $_error',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _loadCertificateData();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildCertificateHeader(),
            const SizedBox(height: 16),
            _buildModelDetailsCard(isElectronics),
            const SizedBox(height: 12),
            _buildVerificationChecksCard(),
            const SizedBox(height: 12),
            _buildBuyerConfirmationBanner(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildCertificateHeader() {
    final isVerified = _chainData?['isVerified'] == true;
    return Container(
      width: double.infinity,
      padding:
      const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isVerified
              ? [Colors.green[700]!, Colors.green[400]!]
              : [Colors.orange[700]!, Colors.orange[400]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            isVerified ? Icons.verified_user : Icons.pending,
            size: 56,
            color: Colors.white,
          ),
          const SizedBox(height: 10),
          Text(
            isVerified
                ? 'Blockchain Verified Certificate'
                : 'Verification Pending',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Token ID: ${widget.assetData['blockchainTokenId'] ?? '—'}  •  Polygon Amoy',
            style:
            const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildModelDetailsCard(bool isElectronics) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _certSectionTitle(
              icon: Icons.info_outline,
              label: isElectronics
                  ? 'Device Details'
                  : 'Property Details',
            ),
            const Divider(height: 20),
            if (isElectronics) ...[
              _certRow('Brand',
                  _chainData?['brand'] ?? widget.assetData['brand'] ?? '—'),
              _certRow('Model',
                  _chainData?['model'] ?? widget.assetData['model'] ?? '—'),
              _certRow(
                  'Serial Number',
                  _chainData?['serialNumber'] ??
                      widget.assetData['serial'] ??
                      '—'),
              _certRow(
                  'Condition', widget.assetData['condition'] ?? '—'),
              _certRow('Warranty Start / Expiry', _warrantyStart),
            ] else ...[
              _certRow(
                  'Location',
                  _chainData?['location'] ??
                      widget.assetData['location'] ??
                      '—'),
              _certRow(
                  'City',
                  _chainData?['city'] ??
                      widget.assetData['city'] ??
                      '—'),
              _certRow(
                  'Plot Area',
                  '${widget.assetData['plotArea'] ?? '—'} ${widget.assetData['plotUnit'] ?? ''}'),
              _certRow('Total Fractions',
                  _chainData?['totalFractions']?.toString() ?? '—'),
            ],
            const Divider(height: 20),
            _certSectionTitle(
              icon: Icons.person_outline,
              label: 'Original Owner',
            ),
            const SizedBox(height: 8),
            _certRow('Name', _originalOwnerName),
            if (_originalOwnerWallet.isNotEmpty)
              _certRow(
                'Wallet',
                '${_originalOwnerWallet.substring(0, 12)}...${_originalOwnerWallet.substring(_originalOwnerWallet.length - 6)}',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationChecksCard() {
    final notResold = _priorTransferCount == 0;
    final notStolen = !_isReportedStolen;
    final isVerified = _chainData?['isVerified'] == true;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _certSectionTitle(
              icon: Icons.checklist,
              label: 'Authenticity Checks',
            ),
            const Divider(height: 20),
            _checkRow(
              label: 'Blockchain Verified',
              passed: isVerified,
              passText: 'Confirmed on Polygon Amoy',
              failText: 'Verification pending',
            ),
            const SizedBox(height: 10),
            _checkRow(
              label: 'Resale History',
              passed: notResold,
              passText: 'Never previously resold',
              failText:
              'Resold $_priorTransferCount time${_priorTransferCount == 1 ? '' : 's'} before',
            ),
            const SizedBox(height: 10),
            _checkRow(
              label: 'Stolen Report',
              passed: notStolen,
              passText: 'No stolen reports found',
              failText: '⚠️ This unit has been reported stolen!',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBuyerConfirmationBanner() {
    final allClear =
        !_isReportedStolen && _priorTransferCount == 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: allClear ? Colors.green[50] : Colors.red[50],
        border: Border.all(
          color: allClear ? Colors.green : Colors.red,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            allClear
                ? Icons.thumb_up_alt_outlined
                : Icons.warning_amber,
            color:
            allClear ? Colors.green[700] : Colors.red[700],
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allClear
                      ? 'This unit is safe to purchase'
                      : 'Caution before purchasing',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: allClear
                        ? Colors.green[800]
                        : Colors.red[800],
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  allClear
                      ? 'This asset has not been previously resold and has no stolen reports. The certificate above is recorded immutably on the blockchain.'
                      : 'One or more checks above did not pass. Please review the details carefully before proceeding with any purchase.',
                  style: TextStyle(
                    color: allClear
                        ? Colors.green[900]
                        : Colors.red[900],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _certSectionTitle(
      {required IconData icon, required String label}) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.green[700]),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.green[800])),
      ],
    );
  }

  Widget _certRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style:
              TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkRow({
    required String label,
    required bool passed,
    required String passText,
    required String failText,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: passed ? Colors.green[100] : Colors.red[100],
            shape: BoxShape.circle,
          ),
          child: Icon(
            passed ? Icons.check : Icons.close,
            size: 16,
            color: passed ? Colors.green[700] : Colors.red[700],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text(
                passed ? passText : failText,
                style: TextStyle(
                  fontSize: 12,
                  color: passed
                      ? Colors.green[700]
                      : Colors.red[700],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}