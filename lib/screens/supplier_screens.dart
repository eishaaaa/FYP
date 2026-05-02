// lib/screens/supplier_screens.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;

// Internal Imports
import 'chat_list_screen.dart';
import 'profile_screen.dart';
import 'asset_screen.dart';
import '../services/push_notification_service.dart';
import 'shared_screens.dart';
import 'qr_generator_screen.dart';
import '../theme.dart';
import 'qr_scanner_enhanced.dart';
import '../blockchain/blockchain_service.dart';
import '../blockchain/ipfs_service.dart';
import 'wallet_screen.dart';
import '../widgets/hand_help_tooltip.dart';
import 'package:shared_preferences/shared_preferences.dart';

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;
const uuid = Uuid();

extension _Cap on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

// -----------------------------------------------------------------------------
// UTILITIES (Compression & Storage)
// -----------------------------------------------------------------------------

Future<String> compressImageToBase64(
  Uint8List bytes, {
  int quality = 70,
}) async {
  final image = img.decodeImage(bytes);
  if (image == null) return base64Encode(bytes);

  img.Image resized = image;
  if (image.width > 800) {
    resized = img.copyResize(image, width: 800);
  }

  final compressed = img.encodeJpg(resized, quality: quality);
  final base64Str = base64Encode(compressed);

  if (base64Str.length > 900000) {
    return compressImageToBase64(bytes, quality: quality - 10);
  }

  return base64Str;
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1048576).toStringAsFixed(1)} MB';
}

class DocumentStorage {
  static const int smallFileLimit = 100 * 1024;
  static const int mediumFileLimit = 500 * 1024;
  static const int maxChunkSize = 900 * 1024;

  static Future<Map<String, dynamic>> storeDocument(
    Uint8List bytes,
    String fileName,
    String fileType,
  ) async {
    final originalSize = bytes.length;

    if (originalSize <= smallFileLimit) {
      return _storeSmallFile(bytes, fileName, fileType, originalSize);
    } else if (originalSize <= mediumFileLimit) {
      return await _storeMediumFile(bytes, fileName, fileType, originalSize);
    } else {
      return await _storeLargeFile(bytes, fileName, fileType, originalSize);
    }
  }

  static Map<String, dynamic> _storeSmallFile(
    Uint8List bytes,
    String fileName,
    String fileType,
    int originalSize,
  ) {
    final base64Str = base64Encode(bytes);
    return {
      'name': fileName,
      'type': fileType,
      'storageStrategy': 'direct_base64',
      'data': base64Str,
      'originalSize': originalSize,
      'compressedSize': base64Str.length,
      'requiresChunks': false,
      'chunkCount': 1,
    };
  }

  static Future<Map<String, dynamic>> _storeMediumFile(
    Uint8List bytes,
    String fileName,
    String fileType,
    int originalSize,
  ) async {
    final isImage = ['jpg', 'jpeg', 'png'].contains(fileType.toLowerCase());

    if (isImage) {
      final base64Str = await compressImageToBase64(bytes, quality: 60);
      final compressedBytes = base64Decode(base64Str);
      return {
        'name': fileName,
        'type': fileType,
        'storageStrategy': 'compressed_image',
        'data': base64Str,
        'originalSize': originalSize,
        'compressedSize': compressedBytes.length,
        'compressionRatio': originalSize > 0
            ? compressedBytes.length / originalSize
            : 1.0,
        'requiresChunks': false,
        'chunkCount': 1,
      };
    } else {
      final base64Str = base64Encode(bytes);
      if (base64Str.length <= maxChunkSize) {
        return {
          'name': fileName,
          'type': fileType,
          'storageStrategy': 'direct_base64',
          'data': base64Str,
          'originalSize': originalSize,
          'compressedSize': base64Str.length,
          'requiresChunks': false,
          'chunkCount': 1,
        };
      } else {
        return await _splitIntoChunks(bytes, fileName, fileType, originalSize);
      }
    }
  }

  static Future<Map<String, dynamic>> _storeLargeFile(
    Uint8List bytes,
    String fileName,
    String fileType,
    int originalSize,
  ) async {
    final isImage = ['jpg', 'jpeg', 'png'].contains(fileType.toLowerCase());

    if (isImage) {
      final base64Str = await compressImageToBase64(bytes, quality: 50);
      final compressedBytes = base64Decode(base64Str);

      if (base64Str.length <= maxChunkSize) {
        return {
          'name': fileName,
          'type': fileType,
          'storageStrategy': 'compressed_image',
          'data': base64Str,
          'originalSize': originalSize,
          'compressedSize': compressedBytes.length,
          'compressionRatio': originalSize > 0
              ? compressedBytes.length / originalSize
              : 1.0,
          'requiresChunks': false,
          'chunkCount': 1,
        };
      }
    }
    return await _splitIntoChunks(bytes, fileName, fileType, originalSize);
  }

  static Future<Map<String, dynamic>> _splitIntoChunks(
    Uint8List bytes,
    String fileName,
    String fileType,
    int originalSize,
  ) async {
    final base64Str = base64Encode(bytes);
    final chunks = <String>[];
    final chunkSize = (maxChunkSize * 0.8).toInt();

    for (int i = 0; i < base64Str.length; i += chunkSize) {
      final end = (i + chunkSize < base64Str.length)
          ? i + chunkSize
          : base64Str.length;
      chunks.add(base64Str.substring(i, end));
    }

    return {
      'name': fileName,
      'type': fileType,
      'storageStrategy': 'chunked',
      'chunks': chunks,
      'originalSize': originalSize,
      'compressedSize': base64Str.length,
      'requiresChunks': true,
      'chunkCount': chunks.length,
    };
  }
}

// -----------------------------------------------------------------------------
// MAIN SCREENS
// -----------------------------------------------------------------------------

class SupplierHomeScreen extends StatefulWidget {
  final String type;
  const SupplierHomeScreen({super.key, required this.type});

  @override
  State<SupplierHomeScreen> createState() => _SupplierHomeScreenState();
}

class _SupplierHomeScreenState extends State<SupplierHomeScreen> {
  int _selectedIndex = 0;
  late final List<Widget> _pages;
  bool _showHelp = false;

  @override
  void initState() {
    super.initState();
    _checkHelpStatus();
    _pages = <Widget>[
      SupplierHome(type: widget.type, showHelp: () => _showHelp),
      const QRScannerEnhanced(),
      const MyAssetsScreen(),
      const ProfileScreen(),
    ];
  }

  Future<void> _checkHelpStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('seen_supplier_help') ?? false;
    if (!seen) {
      if (mounted) setState(() => _showHelp = true);
      await prefs.setBool('seen_supplier_help', true);
    }
  }

  void _onTap(int idx) => setState(() => _selectedIndex = idx);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      //  appBar: AppBar(title: Text('${widget.type.capitalize()} Supplier')),
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onTap,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory),
            label: 'My Assets',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class SupplierHome extends StatelessWidget {
  final String type;
  final bool Function() showHelp;
  const SupplierHome({super.key, required this.type, required this.showHelp});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primaryStart.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.store_rounded,
                color: AppTheme.primaryStart,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${type.capitalize()} Supplier',
                  style: AppTheme.heading(15, color: AppTheme.textPrimary),
                ),
                Text(
                  'My Assets',
                  style: AppTheme.body(12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            color: Colors.black54,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WalletScreen()),
            ),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where(
                  'receiverId',
                  isEqualTo: FirebaseAuth.instance.currentUser?.uid,
                )
                .where('isRead', isEqualTo: false)
                .snapshots(),
            builder: (context, snapshot) {
              int unreadCount = snapshot.data?.docs.length ?? 0;
              return Badge(
                label: Text(unreadCount.toString()),
                isLabelVisible: unreadCount > 0,
                offset: const Offset(-4, 4),
                child: IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  color: Colors.black54,
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationsScreen(),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AssetManagementScreen(type: type),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'chat_fab',
            backgroundColor: Colors.white,
            foregroundColor: AppTheme.primaryStart,
            elevation: 2,
            child: const Icon(Icons.chat_bubble_outline_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatListScreen()),
            ),
          ),
          const SizedBox(height: 12),
          HandHelpTooltip(
            message: 'Click here to add your first asset!',
            show: showHelp(),
            offset: const Offset(-100, -10),
            child: FloatingActionButton.extended(
              heroTag: 'add_asset_fab',
              backgroundColor: AppTheme.primaryStart,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'Add Asset',
                style: AppTheme.button(14),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AddAssetScreen(type: type)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AssetManagementScreen extends StatelessWidget {
  final String type;
  const AssetManagementScreen({super.key, required this.type});

  void _showDistributeRentDialog(
    BuildContext context,
    String docId,
    int propertyId,
  ) {
    final TextEditingController _rentCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Distribute Rent', style: AppTheme.heading(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter amount in MATIC to distribute to all fraction holders.',
            ),
            TextField(
              controller: _rentCtrl,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount (MATIC)',
                labelStyle: AppTheme.body(14),
                suffixText: 'MATIC',
                suffixStyle: AppTheme.body(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              // 1. INPUT VALIDATION: Check numbers BEFORE blocking call
              final textAmount = _rentCtrl.text.trim().replaceAll(',', '');
              if (textAmount.isEmpty) return;

              final amountEth = double.tryParse(textAmount);
              if (amountEth == null || amountEth <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Invalid Amount: Please enter a number like 0.1 or 10',
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(ctx);

              try {
                final service = BlockchainServiceEnhanced();
                await service.init();

                if (!service.isConnected) {
                  await service.connectWallet(context);
                }

                if (!context.mounted) return;

                final amountWei = service.etherToWei(amountEth);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Confirm transaction in wallet...'),
                  ),
                );

                await service.distributeLandRent(
                  propertyId: propertyId,
                  amount: amountWei,
                );

                if (!context.mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Rent Distributed Successfully!'),
                    backgroundColor: AppTheme.primaryStart,
                  ),
                );
              } catch (e) {
                if (context.mounted) {
                  // Display exact error from Blockchain Service
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Error'),
                      content: Text(e.toString()),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                }
              }
            },
            child: const Text('Distribute'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db
          .collection('assets')
          .where('ownerId', isEqualTo: auth.currentUser!.uid)
          .where('category', isEqualTo: type)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryStart.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    type == 'land'
                        ? Icons.landscape_rounded
                        : Icons.devices_rounded,
                    size: 48,
                    color: AppTheme.primaryStart,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'No assets yet',
                  style: AppTheme.heading(16, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap + Add Asset to mint your first NFT',
                  style: AppTheme.body(13, color: AppTheme.textMid),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final rawTokenId = data['blockchainTokenId'];
            final tokenId = rawTokenId != null
                ? (rawTokenId is int
                      ? rawTokenId
                      : int.tryParse(rawTokenId.toString()))
                : null;
            final isMinted = tokenId != null;
            final title = data['title'] ?? 'Untitled';
            final price = data['price']?.toString() ?? '—';

            // Asset thumbnail image
            final images = data['images'] as List?;
            final hasImage = images != null && images.isNotEmpty;

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Thumbnail image ───────────────────────────────
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: hasImage
                        ? Image.memory(
                            base64Decode(images.first as String),
                            width: double.infinity,
                            height: 160,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _imageFallback(type),
                          )
                        : _imageFallback(type),
                  ),

                  // ── Title + badge row ─────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: AppTheme.heading(15, color: AppTheme.textPrimary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isMinted
                                ? AppTheme.primaryStart.withOpacity(0.1)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isMinted
                                  ? AppTheme.primaryStart.withOpacity(0.3)
                                  : Colors.grey[300]!,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isMinted
                                    ? Icons.verified_rounded
                                    : Icons.edit_note_rounded,
                                size: 11,
                                color: isMinted
                                    ? AppTheme.primaryStart
                                    : Colors.grey[500],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isMinted ? 'NFT Minted' : 'Draft',
                                style: AppTheme.heading(10, color: isMinted
                                      ? AppTheme.primaryStart
                                      : AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Price + token row ─────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.payments_outlined,
                          size: 14,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'PKR $price',
                          style: AppTheme.heading(13, color: AppTheme.textPrimary),
                        ),
                        if (isMinted) ...[
                          const Spacer(),
                          Text(
                            'Token #$tokenId',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[400],
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  Divider(height: 1, color: Colors.grey[100]),

                  // ── Action buttons — two rows for land, one row for electronics ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: type == 'land' && isMinted
                        ? Column(
                            children: [
                              // Row 1: Distribute Rent (full width)
                              _actionButton(
                                icon: Icons.monetization_on_rounded,
                                label: 'Distribute Rent',
                                color: Colors.amber[700]!,
                                bgColor: Colors.amber[50]!,
                                onTap: () => _showDistributeRentDialog(
                                  context,
                                  doc.id,
                                  tokenId,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Row 2: QR Code + Edit
                              Row(
                                children: [
                                  Expanded(
                                    child: _actionButton(
                                      icon: Icons.qr_code_rounded,
                                      label: 'QR Code',
                                      color: AppTheme.primaryStart,
                                      bgColor: const Color(
                                        0xFF2A7F8F,
                                      ).withOpacity(0.08),
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => QRGeneratorScreen(
                                            assetId: doc.id,
                                            category: type,
                                            blockchainTokenId: tokenId,
                                            title: data['title'] ?? 'Asset',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _actionButton(
                                      icon: Icons.edit_rounded,
                                      label: 'Edit',
                                      color: Colors.indigo[600]!,
                                      bgColor: Colors.indigo[50]!,
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => EditAssetScreen(
                                            assetId: doc.id,
                                            type: type,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: _actionButton(
                                  icon: Icons.qr_code_rounded,
                                  label: 'QR Code',
                                  color: AppTheme.primaryStart,
                                  bgColor: const Color(
                                    0xFF2A7F8F,
                                  ).withOpacity(0.08),
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => QRGeneratorScreen(
                                        assetId: doc.id,
                                        category: type,
                                        blockchainTokenId: tokenId,
                                        title: data['title'] ?? 'Asset',
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _actionButton(
                                  icon: Icons.edit_rounded,
                                  label: 'Edit',
                                  color: Colors.indigo[600]!,
                                  bgColor: Colors.indigo[50]!,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => EditAssetScreen(
                                        assetId: doc.id,
                                        type: type,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: AppTheme.heading(12, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageFallback(String type) {
    return Container(
      width: double.infinity,
      height: 160,
      color: AppTheme.primaryStart.withOpacity(0.06),
      child: Icon(
        type == 'land' ? Icons.landscape_rounded : Icons.devices_rounded,
        size: 48,
        color: AppTheme.primaryStart.withOpacity(0.35),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// ASSET FORM (The Core UI for Data Entry)
// -----------------------------------------------------------------------------

class AssetForm extends StatefulWidget {
  final String type;
  final Map<String, dynamic>? initialData;
  final bool isEdit;
  final Future<void> Function(Map<String, dynamic> data) onSubmit;

  const AssetForm({
    super.key,
    required this.type,
    this.initialData,
    this.isEdit = false,
    required this.onSubmit,
  });

  @override
  State<AssetForm> createState() => _AssetFormState();
}

class _AssetFormState extends State<AssetForm> {
  final _formKey = GlobalKey<FormState>();
  final List<Uint8List> _images = [];
  List<Map<String, dynamic>> _documents = [];
  String _condition = 'new';
  String _plotUnit = 'marla';
  bool _uploadingDocuments = false;

  // ✅ SAFE INITIALIZATION: Using .toString() to handle numeric or null values from Firestore
  late final TextEditingController _titleCtrl = TextEditingController(
    text: widget.initialData?['title']?.toString() ?? '',
  );
  late final TextEditingController _descCtrl = TextEditingController(
    text: widget.initialData?['description']?.toString() ?? '',
  );
  late final TextEditingController _priceCtrl = TextEditingController(
    text: widget.initialData?['price']?.toString() ?? '',
  );
  late final TextEditingController _plotCtrl = TextEditingController(
    text: widget.initialData?['plotArea']?.toString() ?? '',
  );
  late final TextEditingController _cityCtrl = TextEditingController(
    text: widget.initialData?['city']?.toString() ?? '',
  );
  late final TextEditingController _brandCtrl = TextEditingController(
    text: widget.initialData?['brand']?.toString() ?? '',
  );
  late final TextEditingController _modelCtrl = TextEditingController(
    text: widget.initialData?['model']?.toString() ?? '',
  );
  late final TextEditingController _serialCtrl = TextEditingController(
    text: widget.initialData?['serial']?.toString() ?? '',
  );
  late final TextEditingController _warrantyCtrl = TextEditingController(
    text: widget.initialData?['warranty']?.toString() ?? '',
  );
  late final TextEditingController _fractionsCtrl = TextEditingController(
    text: widget.initialData?['totalFractions']?.toString() ?? '100',
  );

  @override
  void initState() {
    super.initState();
    _condition = widget.initialData?['condition']?.toString() ?? 'new';
    _plotUnit = widget.initialData?['plotUnit']?.toString() ?? 'marla';

    if (widget.initialData?['documents'] != null) {
      final docs = widget.initialData!['documents'] as List<dynamic>;
      _documents = docs.cast<Map<String, dynamic>>();
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _plotCtrl.dispose();
    _cityCtrl.dispose();
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _serialCtrl.dispose();
    _warrantyCtrl.dispose();
    _fractionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 80);
    if (picked.isEmpty) return;
    for (final p in picked) {
      final b = await p.readAsBytes();
      setState(() => _images.add(b));
    }
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 800,
    );
    if (photo != null) {
      final bytes = await photo.readAsBytes();
      setState(() => _images.add(bytes));
    }
  }

  Future<void> _pickDocuments() async {
    setState(() => _uploadingDocuments = true);
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
        allowMultiple: true,
        withData: true,
      );

      if (res != null) {
        for (final file in res.files) {
          if (file.bytes != null) {
            setState(() {
              _documents.add({
                'bytes': file.bytes!,
                'name': file.name,
                'type': file.extension ?? 'unknown',
                'size': file.size,
                'originalSize': file.size,
              });
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      setState(() => _uploadingDocuments = false);
    }
  }

  Future<Map<String, dynamic>?> _collect() async {
    final price = double.tryParse(_priceCtrl.text.replaceAll(',', ''));
    if (price == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid Price Format')));
      return null;
    }

    // 1. Process Images for Firestore
    final compressedImages = <String>[];
    for (final imgBytes in _images) {
      compressedImages.add(await compressImageToBase64(imgBytes));
    }

    // 2. Process Documents for Firestore
    final processedDocs = <Map<String, dynamic>>[];
    for (final doc in _documents) {
      if (doc.containsKey('bytes')) {
        final bytes = doc['bytes'] as Uint8List;
        final processed = await DocumentStorage.storeDocument(
          bytes,
          doc['name'],
          doc['type'],
        );
        processedDocs.add(processed);
      } else {
        processedDocs.add(doc);
      }
    }

    final Map<String, dynamic> out = {
      'title': _titleCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'price': price,
      'images': compressedImages,
      'searchKeywords': _titleCtrl.text.trim().toLowerCase().split(
        RegExp(r'\s+'),
      ),
      'documents': processedDocs,
      'rawImages': _images,
      'rawDocuments': _documents.where((d) => d.containsKey('bytes')).toList(),
    };

    if (widget.type == 'land') {
      final area = int.tryParse(_plotCtrl.text.replaceAll(',', ''));
      final fracs = int.tryParse(_fractionsCtrl.text.replaceAll(',', ''));
      if (area == null || fracs == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid Plot Area or Fractions')),
        );
        return null;
      }
      out['plotArea'] = area; // Store as int
      out['plotUnit'] = _plotUnit;
      out['city'] = _cityCtrl.text.trim();
      out['totalFractions'] = fracs; // Store as int
    } else {
      out['brand'] = _brandCtrl.text.trim();
      out['model'] = _modelCtrl.text.trim();
      out['serial'] = _serialCtrl.text.trim();
      out['warranty'] = _warrantyCtrl.text.trim();
      out['condition'] = _condition;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: 'Title',
                labelStyle: AppTheme.body(14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) => v!.isEmpty ? 'Required' : null,
              style: AppTheme.body(14),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descCtrl,
              decoration: InputDecoration(
                labelText: 'Description',
                labelStyle: AppTheme.body(14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              maxLines: 3,
              style: AppTheme.body(14),
            ),
            const SizedBox(height: 16),
            // FIX: Using decimal input type
            TextFormField(
              controller: _priceCtrl,
              decoration: InputDecoration(
                labelText: 'Price',
                labelStyle: AppTheme.body(14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppTheme.body(14),
            ),
            const SizedBox(height: 16),
            const SizedBox(height: 12),

            if (widget.type == 'land') ...[
              DropdownButtonFormField<String>(
                value: _plotUnit,
                items: const [
                  DropdownMenuItem(value: 'marla', child: Text('Marla')),
                  DropdownMenuItem(value: 'kanal', child: Text('Kanal')),
                ],
                onChanged: (v) => setState(() => _plotUnit = v!),
                decoration: InputDecoration(
                  labelText: 'Plot Unit',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _plotCtrl,
                decoration: InputDecoration(
                  labelText: 'Plot Area (Integer)',
                  labelStyle: AppTheme.body(14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                keyboardType: TextInputType.number,
                style: AppTheme.body(14),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _cityCtrl,
                decoration: InputDecoration(
                  labelText: 'City / Address',
                  labelStyle: AppTheme.body(14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                style: AppTheme.body(14),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _fractionsCtrl,
                decoration: InputDecoration(
                  labelText: 'Total Fractions (Default 100)',
                  labelStyle: AppTheme.body(14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                keyboardType: TextInputType.number,
                style: AppTheme.body(14),
              ),
            ] else ...[
              TextFormField(
                controller: _brandCtrl,
                decoration: InputDecoration(
                  labelText: 'Brand',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _modelCtrl,
                decoration: InputDecoration(
                  labelText: 'Model',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _serialCtrl,
                decoration: InputDecoration(
                  labelText: 'Serial / IMEI',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _warrantyCtrl,
                decoration: InputDecoration(
                  labelText: 'Warranty (Date/Months)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _condition,
                items: const [
                  DropdownMenuItem(value: 'new', child: Text('New')),
                  DropdownMenuItem(value: 'used', child: Text('Used')),
                ],
                onChanged: (v) => setState(() => _condition = v!),
                decoration: InputDecoration(
                  labelText: 'Condition',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],

            const Divider(height: 32),
            const Text('Images', style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(
              children: _images
                  .map(
                    (bytes) => Padding(
                      padding: const EdgeInsets.only(right: 8, top: 8),
                      child: Image.memory(
                        bytes,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                  .toList(),
            ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Add Gallery'),
                ),
                TextButton.icon(
                  onPressed: _takePhoto,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
              ],
            ),

            const Divider(height: 32),
            const Text(
              'Documents (Attached to IPFS & Secure Storage)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (_documents.isNotEmpty)
              Column(
                children: _documents
                    .map(
                      (d) => ListTile(
                        leading: const Icon(Icons.description),
                        title: Text(d['name']),
                        subtitle: Text(_formatFileSize(d['size'] ?? 0)),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _documents.remove(d)),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ElevatedButton.icon(
              onPressed: _uploadingDocuments ? null : _pickDocuments,
              icon: _uploadingDocuments
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryStart))
                  : const Icon(Icons.file_upload, color: AppTheme.primaryStart),
              label: Text('Attach Documents', style: AppTheme.body(14, weight: FontWeight.w500, color: AppTheme.primaryStart)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryStart.withOpacity(0.1),
                foregroundColor: AppTheme.primaryStart,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),

            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                if (_formKey.currentState!.validate()) {
                  final payload = await _collect();
                  if (payload != null) {
                    await widget.onSubmit(payload);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: AppTheme.primaryStart,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 2,
              ),
              child: Text(
                widget.isEdit ? 'Save Changes' : 'Mint NFT & Upload to IPFS',
                style: AppTheme.button(16, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// ADD ASSET SCREEN (Logic Wrapper: Firestore + IPFS + Blockchain)

class AddAssetScreen extends StatefulWidget {
  final String type;
  const AddAssetScreen({super.key, required this.type});

  @override
  State<AddAssetScreen> createState() => _AddAssetScreenState();
}

class _AddAssetScreenState extends State<AddAssetScreen> {
  bool _isLoading = false;
  String _statusMessage = '';

  Future<void> _handleCreate(Map<String, dynamic> data) async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Initializing...';
    });

    try {
      final blockchain = BlockchainServiceEnhanced();
      // Initialize services
      await blockchain.init();
      final ipfs = IPFSService();

      // ---------------------------------------------------------
      // STEP 1: WALLET CONNECTION
      // ---------------------------------------------------------
      if (!blockchain.isConnected) {
        setState(() => _statusMessage = 'Waiting for Wallet Connection...');

        // This opens MetaMask. When you return, it waits up to 30s for the address.
        await blockchain.connectWallet(context);
      }

      if (!mounted) return;

      // Critical Check: Did the connection actually succeed?
      if (!blockchain.isConnected) {
        throw Exception(
          'Wallet connection failed or timed out. Please make sure you are on the Amoy Testnet.',
        );
      }

      // ---------------------------------------------------------
      // STEP 2: UPLOAD IMAGE TO IPFS (Optimized)
      // ---------------------------------------------------------
      String? imageHash;
      if (data['rawImages'] != null && (data['rawImages'] as List).isNotEmpty) {
        setState(() => _statusMessage = 'Compressing & Uploading Image...');

        // FIX: Compress image before upload to prevent infinite loading on large files
        final rawBytes = (data['rawImages'] as List)[0] as Uint8List;
        final compressedBase64 = await compressImageToBase64(
          rawBytes,
          quality: 60,
        );
        final compressedBytes = base64Decode(compressedBase64);

        final res = await ipfs.uploadFile(
          fileBytes: compressedBytes,
          fileName: 'nft_image.jpg',
        );

        if (!res.success) throw Exception('Image Upload Failed: ${res.error}');
        imageHash = res.ipfsHash;
      }

      if (!mounted) return;

      // ---------------------------------------------------------
      // STEP 3: UPLOAD DOCUMENTS
      // ---------------------------------------------------------
      String? primaryDocHash;
      if (data['rawDocuments'] != null) {
        setState(() => _statusMessage = 'Uploading Documents to IPFS...');
        final rawDocs = data['rawDocuments'] as List<Map<String, dynamic>>;

        for (var doc in rawDocs) {
          final res = await ipfs.uploadFile(
            fileBytes: doc['bytes'],
            fileName: doc['name'],
          );
          if (res.success) {
            primaryDocHash ??= res.ipfsHash;
            // Update the firestore data structure with IPFS links
            final fsDocs = data['documents'] as List<Map<String, dynamic>>;
            final match = fsDocs.firstWhere(
              (d) => d['name'] == doc['name'],
              orElse: () => {},
            );
            if (match.isNotEmpty) {
              match['ipfsHash'] = res.ipfsHash;
              match['ipfsUrl'] = res.ipfsUrl;
            }
          }
        }
      }

      if (!mounted) return;

      // ---------------------------------------------------------
      // STEP 4: PREPARE METADATA
      // ---------------------------------------------------------
      setState(() => _statusMessage = 'Generating Metadata...');
      Map<String, dynamic> metadata;

      final safeTitle = data['title']?.toString() ?? 'Asset';
      final safeCity = data['city']?.toString() ?? 'Unknown';

      if (widget.type == 'electronics') {
        metadata = ipfs.createElectronicsMetadata(
          brand: data['brand'] ?? 'Unknown',
          model: data['model'] ?? 'Unknown',
          serialNumber: data['serial'] ?? 'Unknown',
          warrantyExpiry: data['warranty'] ?? 'Unknown',
          condition: data['condition'] ?? 'New',
          imageHash: imageHash,
          warrantyDocHash: primaryDocHash,
        );
      } else {
        final plotAreaInt = data['plotArea'] as int? ?? 0;
        final totalFractionsInt = data['totalFractions'] as int? ?? 100;
        final priceDouble = data['price'] as double? ?? 0.0;

        metadata = ipfs.createLandMetadata(
          location: safeTitle,
          city: safeCity,
          totalArea: plotAreaInt,
          areaUnit: data['plotUnit'] ?? 'marla',
          totalFractions: totalFractionsInt,
          pricePerFraction: priceDouble.toString(),
          imageHash: imageHash,
          deedHash: primaryDocHash,
        );
      }

      // ---------------------------------------------------------
      // STEP 5: UPLOAD METADATA
      // ---------------------------------------------------------
      setState(() => _statusMessage = 'Uploading Metadata to IPFS...');
      final metaRes = await ipfs.uploadJSON(
        jsonData: metadata,
        name: '${safeTitle}_metadata',
      );
      if (!metaRes.success) throw Exception('Metadata Upload Failed');
      final metadataHash = metaRes.ipfsHash!;

      if (!mounted) return;

      // ---------------------------------------------------------
      // STEP 6: MINT ON BLOCKCHAIN
      // ---------------------------------------------------------
      setState(
        () => _statusMessage = 'Please Confirm Transaction in Wallet...',
      );
      String? txHash;

      if (widget.type == 'electronics') {
        txHash = await blockchain.mintElectronics(
          toAddress: blockchain.connectedAddress!,
          serialNumber: data['serial'] ?? '000',
          brand: data['brand'] ?? 'Unknown',
          model: data['model'] ?? 'Unknown',
          warrantyExpiry: data['warranty'] ?? 'Unknown',
          tokenURI: 'ipfs://$metadataHash',
        );
      } else {
        final plotAreaInt = data['plotArea'] as int? ?? 0;
        final totalFractionsInt = data['totalFractions'] as int? ?? 100;
        final priceDouble = data['price'] as double? ?? 0.0;

        txHash = await blockchain.createLandProperty(
          location: safeTitle,
          city: safeCity,
          totalArea: plotAreaInt,
          areaUnit: data['plotUnit'] ?? 'marla',
          totalFractions: totalFractionsInt,
          pricePerFraction: blockchain.etherToWei(priceDouble),
          ipfsMetadata: 'ipfs://$metadataHash',
        );
      }
      // ---------------------------------------------------------
      // STEP 7: SAVE TO DATABASE
      // ---------------------------------------------------------

      if (txHash == null) throw Exception('Transaction failed or rejected');
      setState(() => _statusMessage = 'Waiting for blockchain confirmation...');

      // Wait for the transaction to be mined (up to ~60 seconds)
      await blockchain.waitForConfirmation(txHash, retries: 30);

      // Query the contract to get the newly minted token ID
      setState(() => _statusMessage = 'Retrieving Token ID...');
      int? newTokenId;
      if (widget.type == 'electronics') {
        newTokenId = await blockchain.getLastElectronicsTokenId();
      } else {
        newTokenId = await blockchain.getLastLandPropertyId();
      }
      debugPrint('✅ New blockchain Token ID: $newTokenId');

      setState(() => _statusMessage = 'Saving to Database...');

      data.remove('rawImages');
      data.remove('rawDocuments');

      await db.collection('assets').add({
        ...data,
        'category': widget.type,
        'ownerId': auth.currentUser!.uid,
        'ownerUid': auth.currentUser!.uid,
        'supplierId': auth.currentUser!.uid,
        'createdBy': auth.currentUser!.uid,
        'blockchainTx': txHash,
        'blockchainTokenId': newTokenId, // ← now correctly saved
        'ipfsMetadataHash': metadataHash,
        'isMinted': true,
        'verified': false, // ← pending admin approval
        'isListedForResale': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Success! Asset Minted & Uploaded.'),
          backgroundColor: AppTheme.primaryStart,
        ),
      );
      await addTransaction(
        userId: auth.currentUser!.uid,
        type: "nft",
        title: data['title'] ?? "Asset",
        toAddress: "self",
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Error'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: const SizedBox(),
          title: Text(
            'Add ${widget.type.capitalize()}',
            style: AppTheme.heading(17, color: AppTheme.textPrimary),
          ),
          centerTitle: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryStart.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const CircularProgressIndicator(
                    color: AppTheme.primaryStart,
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  _statusMessage,
                  style: AppTheme.body(15, weight: FontWeight.w500, color: AppTheme.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Please do not close this screen',
                  style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryStart,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.primaryGradient)),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Add ${widget.type.capitalize()}',
          style: AppTheme.heading(18, color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: AssetForm(type: widget.type, onSubmit: _handleCreate),
    );
  }
}

// -----------------------------------------------------------------------------
// EDIT SCREEN
// -----------------------------------------------------------------------------

class EditAssetScreen extends StatefulWidget {
  final String assetId;
  final String type;
  const EditAssetScreen({super.key, required this.assetId, required this.type});

  @override
  State<EditAssetScreen> createState() => _EditAssetScreenState();
}

class _EditAssetScreenState extends State<EditAssetScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _saving = false;

  // Editable off-chain controllers
  late TextEditingController _priceCtrl;
  late TextEditingController _descCtrl;
  List<Map<String, dynamic>> _documents = [];
  final List<Uint8List> _newImages = [];

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final doc = await db.collection('assets').doc(widget.assetId).get();
      if (doc.exists) {
        final d = doc.data()!;
        setState(() {
          _data = d;
          _priceCtrl.text = d['price']?.toString() ?? '';
          _descCtrl.text = d['description']?.toString() ?? '';
          if (d['documents'] != null) {
            _documents = (d['documents'] as List).cast<Map<String, dynamic>>();
          }
        });
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickNewImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 80);
    for (final p in picked) {
      final b = await p.readAsBytes();
      setState(() => _newImages.add(b));
    }
  }

  Future<void> _pickDocuments() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
      allowMultiple: true,
      withData: true,
    );
    if (res != null) {
      for (final file in res.files) {
        if (file.bytes != null) {
          setState(() {
            _documents.add({
              'bytes': file.bytes!,
              'name': file.name,
              'type': file.extension ?? 'unknown',
              'size': file.size,
            });
          });
        }
      }
    }
  }

  Future<void> _save() async {
    final price = double.tryParse(_priceCtrl.text.replaceAll(',', ''));
    if (price == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid price format')));
      return;
    }

    setState(() => _saving = true);
    try {
      // Process any new images
      final List<String> existingImages =
          (_data?['images'] as List?)?.cast<String>() ?? [];
      for (final bytes in _newImages) {
        existingImages.add(await compressImageToBase64(bytes));
      }

      // Process documents
      final processedDocs = <Map<String, dynamic>>[];
      for (final doc in _documents) {
        if (doc.containsKey('bytes')) {
          final processed = await DocumentStorage.storeDocument(
            doc['bytes'],
            doc['name'],
            doc['type'],
          );
          processedDocs.add(processed);
        } else {
          processedDocs.add(doc);
        }
      }

      // Only update off-chain fields — never touch blockchain-origin fields
      await db.collection('assets').doc(widget.assetId).update({
        'price': price,
        'description': _descCtrl.text.trim(),
        'images': existingImages,
        'documents': processedDocs,
        'lastEditedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Asset updated successfully'),
            backgroundColor: AppTheme.primaryStart,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _lockedField(String label, String? value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F4F6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: AppTheme.primaryStart),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value?.isNotEmpty == true ? value! : '—',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.lock_outline, size: 14, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
    Color? titleColor,
    IconData? icon,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 16,
                    color: titleColor ?? AppTheme.primaryStart,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: titleColor ?? AppTheme.primaryStartDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.chevron_left, size: 28),
            color: Colors.black87,
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Edit Asset',
            style: TextStyle(
              color: Colors.black87,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final d = _data ?? {};
    final isMinted = d['blockchainTokenId'] != null;
    final title = d['title']?.toString() ?? 'Asset';
    final category = (d['category'] ?? widget.type).toString();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          // ── App Bar ───────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: AppTheme.background,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.chevron_left, size: 28),
              color: Colors.black87,
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Edit Asset',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerTitle: true,
            expandedHeight: 120,
            flexibleSpace: FlexibleSpaceBar(
              background: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Text(
                              category.toUpperCase(),
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (isMinted) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryStart.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: const Color(
                                    0xFF2A7F8F,
                                  ).withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.verified_rounded,
                                    color: AppTheme.primaryStart,
                                    size: 10,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Token #${d['blockchainTokenId']}',
                                    style: const TextStyle(
                                      color: AppTheme.primaryStart,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.black87),
          ),

          // ── Body ─────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Blockchain locked section ─────────────────────────
                if (isMinted) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.amber[50]!, Colors.orange[50]!],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.orange[700],
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '🔒 Fields below are recorded on the blockchain and are permanently immutable.',
                            style: TextStyle(fontSize: 12, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),

                  _sectionCard(
                    title: 'Blockchain Record',
                    icon: Icons.link,
                    child: Column(
                      children: widget.type == 'electronics'
                          ? [
                              _lockedField(
                                'Brand',
                                d['brand']?.toString(),
                                Icons.business_outlined,
                              ),
                              _lockedField(
                                'Model',
                                d['model']?.toString(),
                                Icons.phone_android_outlined,
                              ),
                              _lockedField(
                                'Serial / IMEI',
                                d['serial']?.toString(),
                                Icons.tag_outlined,
                              ),
                              _lockedField(
                                'Warranty',
                                d['warranty']?.toString(),
                                Icons.shield_outlined,
                              ),
                              _lockedField(
                                'Condition',
                                d['condition']?.toString(),
                                Icons.star_outline,
                              ),
                            ]
                          : [
                              _lockedField(
                                'Location / Title',
                                d['title']?.toString(),
                                Icons.location_on_outlined,
                              ),
                              _lockedField(
                                'City',
                                d['city']?.toString(),
                                Icons.location_city_outlined,
                              ),
                              _lockedField(
                                'Plot Area',
                                '${d['plotArea']} ${d['plotUnit'] ?? ''}'
                                    .trim(),
                                Icons.square_foot_outlined,
                              ),
                              _lockedField(
                                'Total Fractions',
                                d['totalFractions']?.toString(),
                                Icons.pie_chart_outline,
                              ),
                            ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Editable fields ───────────────────────────────────
                _sectionCard(
                  title: 'Editable Details',
                  icon: Icons.edit_outlined,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _priceCtrl,
                        decoration: InputDecoration(
                          labelText: 'Price (PKR)',
                          filled: true,
                          fillColor: const Color(0xFFF5F7F8),
                          prefixIcon: const Icon(
                            Icons.monetization_on_outlined,
                            color: AppTheme.primaryStart,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descCtrl,
                        decoration: InputDecoration(
                          labelText: 'Description',
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: const Color(0xFFF5F7F8),
                          prefixIcon: const Icon(
                            Icons.description_outlined,
                            color: AppTheme.primaryStart,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                        ),
                        maxLines: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Images ────────────────────────────────────────────
                _sectionCard(
                  title: 'Images',
                  icon: Icons.image_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Existing images
                      if ((d['images'] as List?)?.isNotEmpty == true)
                        SizedBox(
                          height: 100,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: (d['images'] as List).length,
                            itemBuilder: (_, i) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  base64Decode((d['images'] as List)[i]),
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // New images with delete
                      if (_newImages.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'New images:',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          height: 100,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _newImages.length,
                            itemBuilder: (_, i) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.memory(
                                      _newImages[i],
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: GestureDetector(
                                      onTap: () => setState(
                                        () => _newImages.removeAt(i),
                                      ),
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        padding: const EdgeInsets.all(3),
                                        child: const Icon(
                                          Icons.close,
                                          color: Colors.white,
                                          size: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _pickNewImages,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: const Text('Add Images'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryStart,
                          side: const BorderSide(
                            color: AppTheme.primaryStart,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Documents ─────────────────────────────────────────
                _sectionCard(
                  title: 'Documents',
                  icon: Icons.folder_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_documents.isEmpty)
                        Text(
                          'No documents attached.',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 13,
                          ),
                        ),
                      ..._documents.map(
                        (doc) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F4F6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.insert_drive_file,
                                size: 18,
                                color: AppTheme.primaryStart,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  doc['name'] ?? 'Document',
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _documents.remove(doc)),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _pickDocuments,
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Attach Documents'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryStart,
                          side: const BorderSide(
                            color: AppTheme.primaryStart,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Save Button ───────────────────────────────────────
                Container(
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _saving
                          ? [Colors.grey[400]!, Colors.grey[400]!]
                          : [AppTheme.primaryStartDark, AppTheme.primaryStart],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _saving
                        ? []
                        : [
                            BoxShadow(
                              color: AppTheme.primaryStart.withOpacity(0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _saving ? null : _save,
                      child: Center(
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.save_outlined,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Save Changes',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
