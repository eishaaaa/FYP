// lib/screens/supplier_screens.dart
// Complete file with enhanced document upload functionality
// Bug 6 Fix: Separate Marla and Kanal unit selection
// Bug 8 Fix: Multiple image upload support
// Bug 9 Fix: Visible back button and camera compression
// Document Upload: Smart storage based on file size (no GZIP)

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;

import 'shared_screens.dart';
import 'auth_screens.dart';

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;
const uuid = Uuid();

extension _Cap on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

/// Compress image aggressively for Firestore
Future<String> compressImageToBase64(Uint8List bytes, {int quality = 70}) async {
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

/// Format file size for display
String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1048576).toStringAsFixed(1)} MB';
}

/// Smart document storage based on size
class DocumentStorage {
  static const int smallFileLimit = 100 * 1024; // 100KB
  static const int mediumFileLimit = 500 * 1024; // 500KB
  static const int maxChunkSize = 900 * 1024; // 900KB safe for Firestore

  /// Store document based on its size
  static Future<Map<String, dynamic>> storeDocument(
      Uint8List bytes,
      String fileName,
      String fileType,
      ) async {
    final originalSize = bytes.length;

    // Strategy based on file size
    if (originalSize <= smallFileLimit) {
      // Small files: Store directly as Base64
      return _storeSmallFile(bytes, fileName, fileType, originalSize);
    } else if (originalSize <= mediumFileLimit) {
      // Medium files: Compress images, store others directly
      return await _storeMediumFile(bytes, fileName, fileType, originalSize);
    } else {
      // Large files: Split into chunks
      return await _storeLargeFile(bytes, fileName, fileType, originalSize);
    }
  }

  /// Small files (<100KB): Direct Base64 storage
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

  /// Medium files (100KB-500KB): Compress images if applicable
  static Future<Map<String, dynamic>> _storeMediumFile(
      Uint8List bytes,
      String fileName,
      String fileType,
      int originalSize,
      ) async {
    final isImage = ['jpg', 'jpeg', 'png'].contains(fileType.toLowerCase());

    if (isImage) {
      // Compress images
      final base64Str = await compressImageToBase64(bytes, quality: 60);
      final compressedBytes = base64Decode(base64Str);

      return {
        'name': fileName,
        'type': fileType,
        'storageStrategy': 'compressed_image',
        'data': base64Str,
        'originalSize': originalSize,
        'compressedSize': compressedBytes.length,
        'compressionRatio': originalSize > 0 ? compressedBytes.length / originalSize : 1.0,
        'requiresChunks': false,
        'chunkCount': 1,
      };
    } else {
      // For non-images, store directly but check size
      final base64Str = base64Encode(bytes);

      // If still too large after base64, split it
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
        // Needs chunking
        return await _splitIntoChunks(bytes, fileName, fileType, originalSize);
      }
    }
  }

  /// Large files (>500KB): Split into chunks
  static Future<Map<String, dynamic>> _storeLargeFile(
      Uint8List bytes,
      String fileName,
      String fileType,
      int originalSize,
      ) async {
    // For large images, try compression first
    final isImage = ['jpg', 'jpeg', 'png'].contains(fileType.toLowerCase());

    if (isImage) {
      // Try aggressive compression for large images
      final base64Str = await compressImageToBase64(bytes, quality: 50);
      final compressedBytes = base64Decode(base64Str);

      // Check if compressed version fits in single chunk
      if (base64Str.length <= maxChunkSize) {
        return {
          'name': fileName,
          'type': fileType,
          'storageStrategy': 'compressed_image',
          'data': base64Str,
          'originalSize': originalSize,
          'compressedSize': compressedBytes.length,
          'compressionRatio': originalSize > 0 ? compressedBytes.length / originalSize : 1.0,
          'requiresChunks': false,
          'chunkCount': 1,
        };
      }
    }

    // Split into chunks
    return await _splitIntoChunks(bytes, fileName, fileType, originalSize);
  }

  /// Split file into chunks for Firestore
  static Future<Map<String, dynamic>> _splitIntoChunks(
      Uint8List bytes,
      String fileName,
      String fileType,
      int originalSize,
      ) async {
    final base64Str = base64Encode(bytes);

    // Split into chunks
    final chunks = <String>[];
    final chunkSize = (maxChunkSize * 0.8).toInt(); // 80% of max for safety

    for (int i = 0; i < base64Str.length; i += chunkSize) {
      final end = (i + chunkSize < base64Str.length) ? i + chunkSize : base64Str.length;
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

/// Supplier Home Screen with Bottom Navigation
class SupplierHomeScreen extends StatefulWidget {
  final String type;
  const SupplierHomeScreen({super.key, required this.type});

  @override
  State<SupplierHomeScreen> createState() => _SupplierHomeScreenState();
}

class _SupplierHomeScreenState extends State<SupplierHomeScreen> {
  int _selectedIndex = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = <Widget>[
      SupplierHome(type: widget.type),
      const QRScannerScreen(),
      const MyAssetsScreen(),
      const ProfileScreen(),
    ];
  }

  void _onTap(int idx) => setState(() => _selectedIndex = idx);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.type.capitalize()} Supplier')),
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onTap,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Scan'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: 'My Assets'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

/// Supplier Home with Dashboard and Asset Management Tabs
class SupplierHome extends StatelessWidget {
  final String type;
  const SupplierHome({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Dashboard'),
              Tab(text: 'Assets'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            SupplierDashboard(uid: auth.currentUser!.uid, type: type),
            AssetManagementScreen(type: type),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AddAssetScreen(type: type)),
          ),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

/// Supplier Dashboard
class SupplierDashboard extends StatelessWidget {
  final String uid;
  final String type;
  const SupplierDashboard({super.key, required this.uid, required this.type});

  Widget _statCard(String title, IconData icon, int value, Color color) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color,
          child: Icon(icon, color: Colors.white),
        ),
        title: Text(title),
        trailing: Text(
          '$value',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  int _toIntSafely(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Overview',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          StreamBuilder<QuerySnapshot>(
            stream: db.collection('assets').where('ownerId', isEqualTo: uid).snapshots(),
            builder: (context, snap) {
              final count = snap.data?.docs.length ?? 0;
              return _statCard('Total Assets', Icons.inventory_2, count, Colors.blue);
            },
          ),

          StreamBuilder<QuerySnapshot>(
            stream: db.collection('assets').where('ownerId', isEqualTo: uid).snapshots(),
            builder: (context, snap) {
              final docs = snap.data?.docs ?? [];
              final views = docs.fold<int>(0, (sum, docSnap) {
                final data = (docSnap.data() as Map<String, dynamic>?) ?? {};
                return sum + _toIntSafely(data['views']);
              });
              final verifs = docs.fold<int>(0, (sum, docSnap) {
                final data = (docSnap.data() as Map<String, dynamic>?) ?? {};
                return sum + _toIntSafely(data['verifications']);
              });

              return Column(
                children: [
                  _statCard('Total Views', Icons.visibility, views, Colors.green),
                  _statCard('Total Verifications', Icons.verified, verifs, Colors.orange),
                ],
              );
            },
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// Asset Management Screen
class AssetManagementScreen extends StatelessWidget {
  final String type;
  const AssetManagementScreen({super.key, required this.type});

  void _showDeleteConfirm(BuildContext ctx, String id) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Delete Asset'),
        content: const Text('Are you sure you want to delete this asset? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await db.collection('assets').doc(id).delete();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _imageWidget(String? base64img) {
    if (base64img == null || base64img.isEmpty) {
      return const Icon(Icons.image, size: 48, color: Colors.grey);
    }
    try {
      final bytes = base64Decode(base64img);
      return Image.memory(bytes, width: 60, height: 60, fit: BoxFit.cover);
    } catch (_) {
      return const Icon(Icons.image, size: 48, color: Colors.grey);
    }
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
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const Center(child: Text('No assets yet. Tap + to add.'));

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final img = (data['images'] as List?)?.isNotEmpty == true
                ? data['images']![0] as String?
                : null;
            final docCount = (data['documents'] as List?)?.length ?? 0;

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _imageWidget(img),
                ),
                title: Text(
                  data['title'] ?? 'No title',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PKR ${data['price'] ?? 0}'),
                    if (docCount > 0)
                      Text(
                        '$docCount document(s) attached',
                        style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                      ),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditAssetScreen(assetId: doc.id, type: type),
                        ),
                      );
                    } else if (v == 'delete') {
                      _showDeleteConfirm(context, doc.id);
                    } else if (v == 'view') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: doc.id)),
                      );
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'view', child: Text('View')),
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// ENHANCED Asset Form with Smart Document Upload
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

  // Track warnings and errors separately
  final List<String> _warnings = [];
  final List<String> _errors = [];

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

  @override
  void initState() {
    super.initState();
    _condition = widget.initialData?['condition']?.toString() ?? 'new';
    _plotUnit = widget.initialData?['plotUnit']?.toString() ?? 'marla';

    // Load existing documents if editing
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
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 80);
    if (picked.isEmpty) return;
    for (final p in picked) {
      final b = await p.readAsBytes();
      _images.add(b);
    }
    setState(() {});
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

  /// Smart document picker with size-based strategies
  Future<void> _pickDocuments() async {
    setState(() => _uploadingDocuments = true);
    _warnings.clear();
    _errors.clear();

    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
        allowMultiple: true,
        withData: true,
      );

      if (res == null || res.files.isEmpty) {
        setState(() => _uploadingDocuments = false);
        return;
      }

      final newDocuments = <Map<String, dynamic>>[];
      final skippedFiles = <String>[];

      for (final file in res.files) {
        // Check if file has bytes
        if (file.bytes == null) {
          skippedFiles.add('${file.name} (no data)');
          continue;
        }

        // Check file size limit (5MB absolute limit)
        if (file.size > 5 * 1024 * 1024) {
          _errors.add('${file.name} exceeds 5MB limit');
          skippedFiles.add('${file.name} (too large >5MB)');
          continue;
        }

        // Check total documents size (max 10MB total)
        final totalSize = _calculateTotalSize(newDocuments) + file.size;
        if (totalSize > 10 * 1024 * 1024) {
          _errors.add('Total documents size would exceed 10MB limit');
          break; // Stop adding more files
        }

        // Store file bytes for later processing
        newDocuments.add({
          'bytes': file.bytes!,
          'name': file.name,
          'type': file.extension ?? 'unknown',
          'size': file.size,
          'originalSize': file.size,
        });

        debugPrint('✓ Document added: ${file.name} (${_formatFileSize(file.size)})');
      }

      if (newDocuments.isNotEmpty) {
        setState(() {
          _documents.addAll(newDocuments);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✓ ${newDocuments.length} document(s) added successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }

      // Show warnings/errors only if there are any
      if (skippedFiles.isNotEmpty && mounted) {
        final message = skippedFiles.length == 1
            ? 'Skipped: ${skippedFiles.first}'
            : 'Skipped ${skippedFiles.length} files';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      if (_errors.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_errors.join('\n')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error picking documents: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking documents: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _uploadingDocuments = false);
    }
  }

  Future<Map<String, dynamic>> _collect() async {
    // Clear previous warnings
    _warnings.clear();
    _errors.clear();

    // Compress all images
    final compressedImages = <String>[];
    for (final imgBytes in _images) {
      final compressed = await compressImageToBase64(imgBytes);
      compressedImages.add(compressed);
    }

    // Process documents with smart storage
    final processedDocs = <Map<String, dynamic>>[];

    for (final doc in _documents) {
      final bytes = doc['bytes'] as Uint8List;
      final fileName = doc['name'] as String;
      final fileType = doc['type'] as String;
      final originalSize = doc['originalSize'] as int;

      try {
        final storedDoc = await DocumentStorage.storeDocument(
          bytes,
          fileName,
          fileType,
        );

        // Add warning if file is large
        if (originalSize > 500 * 1024) {
          _warnings.add('"$fileName" is large (${_formatFileSize(originalSize)}). It will be split into chunks.');
        } else if (originalSize > 100 * 1024) {
          _warnings.add('"$fileName" is medium-sized. It will be compressed if it\'s an image.');
        }

        processedDocs.add(storedDoc);
      } catch (e) {
        debugPrint('Error processing document $fileName: $e');
        _errors.add('Failed to process "$fileName"');
      }
    }

    // Prepare final data
    final Map<String, dynamic> out = {
      'title': _titleCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'price': double.tryParse(_priceCtrl.text) ?? 0.0,
      'images': compressedImages,
      'searchKeywords': _titleCtrl.text.trim().toLowerCase().split(RegExp(r'\s+')),
      'documents': processedDocs,
    };

    if (widget.type == 'land') {
      out['plotArea'] = _plotCtrl.text.trim();
      out['plotUnit'] = _plotUnit;
      out['city'] = _cityCtrl.text.trim();
    } else {
      out['brand'] = _brandCtrl.text.trim();
      out['model'] = _modelCtrl.text.trim();
      out['serial'] = _serialCtrl.text.trim();
      out['warranty'] = _warrantyCtrl.text.trim();
      out['condition'] = _condition;
    }

    // Log for debugging
    debugPrint('✓ Collecting data with ${processedDocs.length} documents');
    debugPrint('📄 Storage strategies: ${processedDocs.map((d) => d['storageStrategy']).join(", ")}');

    return out;
  }

  Widget _getDocumentIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pdf':
        return const Icon(Icons.picture_as_pdf, color: Colors.red, size: 24);
      case 'jpg':
      case 'jpeg':
      case 'png':
        return const Icon(Icons.image, color: Colors.blue, size: 24);
      case 'doc':
      case 'docx':
        return const Icon(Icons.description, color: Colors.blue, size: 24);
      default:
        return const Icon(Icons.insert_drive_file, size: 24);
    }
  }

  int _calculateTotalSize(List<Map<String, dynamic>> docs) {
    return docs.fold<int>(0, (sum, doc) {
      return (sum + (doc['size'] ?? 0)as int);
    });
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
            // Info Card (only shows when there are documents)
            if (_documents.isNotEmpty) ...[
              Card(
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Documents are stored securely in Firestore',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[900],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '• Small files (<100KB): Stored directly\n'
                                  '• Medium files (100KB-500KB): Compressed if image\n'
                                  '• Large files (>500KB): Split into chunks',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blue[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _priceCtrl,
              decoration: const InputDecoration(labelText: 'Price (PKR)'),
              keyboardType: TextInputType.number,
              validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),

            if (widget.type == 'land') ...[
              DropdownButtonFormField<String>(
                value: _plotUnit,
                items: const [
                  DropdownMenuItem(value: 'marla', child: Text('Marla')),
                  DropdownMenuItem(value: 'kanal', child: Text('Kanal')),
                ],
                onChanged: (v) => setState(() => _plotUnit = v ?? 'marla'),
                decoration: const InputDecoration(labelText: 'Plot Unit'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _plotCtrl,
                decoration: InputDecoration(
                  labelText: 'Plot Area ($_plotUnit)',
                  hintText: 'Enter area value',
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _cityCtrl,
                decoration: const InputDecoration(labelText: 'City / Address'),
              ),
              const SizedBox(height: 12),
            ] else ...[
              TextFormField(
                controller: _brandCtrl,
                decoration: const InputDecoration(labelText: 'Brand'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _modelCtrl,
                decoration: const InputDecoration(labelText: 'Model'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _serialCtrl,
                decoration: const InputDecoration(labelText: 'Serial / IMEI'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _warrantyCtrl,
                decoration: const InputDecoration(labelText: 'Warranty (months)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _condition,
                items: const [
                  DropdownMenuItem(value: 'new', child: Text('New')),
                  DropdownMenuItem(value: 'used', child: Text('Used')),
                ],
                onChanged: (v) => setState(() => _condition = v ?? 'new'),
                decoration: const InputDecoration(labelText: 'Condition'),
              ),
              const SizedBox(height: 12),
            ],

            // Image Upload Section
            const Divider(height: 32),
            Row(
              children: [
                const Icon(Icons.image, size: 20),
                const SizedBox(width: 8),
                const Text('Images', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (_images.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_images.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            ElevatedButton.icon(
              onPressed: _pickImages,
              icon: const Icon(Icons.photo_library),
              label: const Text('Pick Images from Gallery'),
            ),
            const SizedBox(height: 8),

            ElevatedButton.icon(
              onPressed: _takePhoto,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Take Photo'),
            ),

            // Document Upload Section
            const Divider(height: 32),
            Row(
              children: [
                const Icon(Icons.attach_file, size: 20),
                const SizedBox(width: 8),
                const Text('Documents', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (_documents.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_documents.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            ElevatedButton.icon(
              onPressed: _uploadingDocuments ? null : _pickDocuments,
              icon: _uploadingDocuments
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.file_upload),
              label: Text(_uploadingDocuments ? 'Loading...' : 'Attach Documents (PDF, Images, DOC)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Max 5MB per file, 10MB total • Supported: PDF, Images, DOC',
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),

            // Display Selected Documents
            if (_documents.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_documents.length} Document(s) Ready',
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Total size: ${_formatFileSize(_calculateTotalSize(_documents))}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._documents.asMap().entries.map((entry) {
                      final index = entry.key;
                      final doc = entry.value;
                      final size = doc['size'] as int;
                      final strategy = size <= 100 * 1024
                          ? 'Direct'
                          : size <= 500 * 1024
                          ? 'Compressed if image'
                          : 'Chunked';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 2,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          leading: _getDocumentIcon(doc['type'] ?? ''),
                          title: Text(
                            doc['name'] ?? 'Document ${index + 1}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${doc['type']?.toUpperCase() ?? 'FILE'} • ${_formatFileSize(size)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              if (size > 100 * 1024)
                                Text(
                                  'Storage: $strategy',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: size > 500 * 1024 ? Colors.orange : Colors.blue,
                                  ),
                                ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              setState(() {
                                _documents.removeAt(index);
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Removed: ${doc['name']}'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // Submit Button
            ElevatedButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;

                // Show warnings only when there are large files
                if (_warnings.isNotEmpty) {
                  final shouldContinue = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Large Files Detected'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            const Text(
                              'The following files are large and will be processed:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            ..._warnings.map((warning) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text('• $warning'),
                            )),
                            const SizedBox(height: 12),
                            const Text(
                              'This may take longer to upload. Continue?',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Continue'),
                        ),
                      ],
                    ),
                  );

                  if (shouldContinue != true) return;
                }

                // Show confirmation for documents
                if (_documents.isNotEmpty) {
                  final totalSize = _calculateTotalSize(_documents);
                  final largeFiles = _documents.where((d) => (d['size'] ?? 0) > 500 * 1024).length;

                  final shouldContinue = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Confirm Upload'),
                      content: Text(
                        'You are uploading ${_documents.length} document(s) (${_formatFileSize(totalSize)}).\n\n'
                            '${largeFiles > 0 ? '$largeFiles large file(s) will be split into chunks.\n' : ''}'
                            'Continue with upload?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Upload'),
                        ),
                      ],
                    ),
                  );

                  if (shouldContinue != true) return;
                }

                try {
                  final payload = await _collect();

                  // Check for errors in document processing
                  if (_errors.isNotEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Errors: ${_errors.join(", ")}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  await widget.onSubmit(payload);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error submitting: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: Colors.green[700],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.isEdit) ...[
                    const Icon(Icons.save, color: Colors.white),
                    const SizedBox(width: 8),
                    const Text('Save Changes', style: TextStyle(color: Colors.white)),
                  ] else ...[
                    const Icon(Icons.cloud_upload, color: Colors.white),
                    const SizedBox(width: 8),
                    const Text('Submit Asset', style: TextStyle(color: Colors.white)),
                    if (_documents.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_documents.length} doc(s)',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// Add Asset Screen
class AddAssetScreen extends StatefulWidget {
  final String type;
  const AddAssetScreen({super.key, required this.type});

  @override
  State<AddAssetScreen> createState() => _AddAssetScreenState();
}

class _AddAssetScreenState extends State<AddAssetScreen> {
  bool _loading = false;

  Future<void> _handleSubmit(Map<String, dynamic> data) async {
    setState(() => _loading = true);

    try {
      final id = uuid.v4();
      final user = auth.currentUser;

      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Prepare the payload
      final payload = {
        'assetId': id,
        'ownerId': user.uid,
        'ownerName': user.displayName ?? user.email?.split('@').first ?? 'Unknown',
        'ownerEmail': user.email ?? '',
        'category': widget.type,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'verified': false,
        'views': 0,
        'verifications': 0,
        ...data,
      };

      // Log document info
      final documents = data['documents'] as List<dynamic>? ?? [];
      final largeFiles = documents.where((doc) {
        final strategy = (doc as Map<String, dynamic>)['storageStrategy'] as String?;
        return strategy == 'chunked';
      }).length;

      debugPrint('📤 Uploading asset with ${documents.length} documents');
      debugPrint('📦 Large files requiring chunks: $largeFiles');

      await db.collection('assets').doc(id).set(payload);

      // Log success
      debugPrint('✅ Asset created successfully: $id');
      debugPrint('📊 Documents uploaded: ${documents.length}');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Asset added successfully with ${documents.length} document(s)',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      debugPrint('❌ Error adding asset: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add asset: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Asset'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Uploading asset and documents...'),
            SizedBox(height: 8),
            Text('Please wait', style: TextStyle(color: Colors.grey)),
          ],
        ),
      )
          : AssetForm(type: widget.type, onSubmit: _handleSubmit),
    );
  }
}

/// Edit Asset Screen
class EditAssetScreen extends StatefulWidget {
  final String assetId;
  final String type;
  const EditAssetScreen({super.key, required this.assetId, required this.type});

  @override
  State<EditAssetScreen> createState() => _EditAssetScreenState();
}

class _EditAssetScreenState extends State<EditAssetScreen> {
  Map<String, dynamic>? _initial;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = await db.collection('assets').doc(widget.assetId).get();
      if (doc.exists) {
        setState(() {
          _initial = doc.data() as Map<String, dynamic>?;
        });
      } else {
        debugPrint('❌ Asset not found: ${widget.assetId}');
      }
    } catch (e) {
      debugPrint('❌ Error loading asset: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _handleSave(Map<String, dynamic> data) async {
    setState(() => _saving = true);

    try {
      debugPrint('📝 Updating asset with ${(data['documents'] as List?)?.length ?? 0} documents');

      await db.collection('assets').doc(widget.assetId).update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Asset updated with ${(data['documents'] as List?)?.length ?? 0} document(s)',
          ),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      debugPrint('❌ Error updating asset: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Edit Asset'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading asset data...'),
            ],
          ),
        ),
      );
    }

    if (_initial == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Edit Asset'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red),
              SizedBox(height: 16),
              Text('Asset not found', style: TextStyle(fontSize: 18)),
              SizedBox(height: 8),
              Text('The asset may have been deleted', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Asset'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _saving ? null : () => Navigator.pop(context),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: AssetForm(
        type: widget.type,
        initialData: _initial,
        isEdit: true,
        onSubmit: _handleSave,
      ),
    );
  }
}