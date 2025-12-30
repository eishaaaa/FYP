// lib/screens/supplier_screens.dart
// COMPLETE MERGE: UI + Firestore + IPFS + Blockchain + WalletConnect
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
import 'chat_screen.dart';
import 'shared_screens.dart';
import 'chat_list_screen.dart';
import 'qr_generator_screen.dart';
import 'qr_scanner_enhanced.dart';
import '../blockchain/blockchain_service.dart';
import '../blockchain/ipfs_service.dart';

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;
const uuid = Uuid();

extension _Cap on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

/// Compress image aggressively for Firestore (Speed optimization)
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
      return _storeSmallFile(bytes, fileName, fileType, originalSize);
    } else if (originalSize <= mediumFileLimit) {
      return await _storeMediumFile(bytes, fileName, fileType, originalSize);
    } else {
      return await _storeLargeFile(bytes, fileName, fileType, originalSize);
    }
  }

  static Map<String, dynamic> _storeSmallFile(
      Uint8List bytes, String fileName, String fileType, int originalSize) {
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
      Uint8List bytes, String fileName, String fileType, int originalSize) async {
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
        'compressionRatio': originalSize > 0 ? compressedBytes.length / originalSize : 1.0,
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
      Uint8List bytes, String fileName, String fileType, int originalSize) async {
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
          'compressionRatio': originalSize > 0 ? compressedBytes.length / originalSize : 1.0,
          'requiresChunks': false,
          'chunkCount': 1,
        };
      }
    }
    return await _splitIntoChunks(bytes, fileName, fileType, originalSize);
  }

  static Future<Map<String, dynamic>> _splitIntoChunks(
      Uint8List bytes, String fileName, String fileType, int originalSize) async {
    final base64Str = base64Encode(bytes);
    final chunks = <String>[];
    final chunkSize = (maxChunkSize * 0.8).toInt();

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
      const QRScannerEnhanced(),
      const MyAssetsScreen(), // Shared screen
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
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton(
              heroTag: 'chat_fab',
              mini: true,
              child: const Icon(Icons.chat),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatListScreen())),
            ),
            const SizedBox(height: 12),
            FloatingActionButton(
              heroTag: 'add_asset_fab',
              child: const Icon(Icons.add),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddAssetScreen(type: type))),
            ),
          ],
        ),
      ),
    );
  }
}

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
        leading: CircleAvatar(backgroundColor: color, child: Icon(icon, color: Colors.white)),
        title: Text(title),
        trailing: Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: db.collection('assets').where('ownerId', isEqualTo: uid).snapshots(),
            builder: (context, snap) {
              final count = snap.data?.docs.length ?? 0;
              return _statCard('Total Assets', Icons.inventory_2, count, Colors.blue);
            },
          ),
          // Additional stats can be added here
        ],
      ),
    );
  }
}

// ✅ UPDATED: AssetManagementScreen with Rent Distribution Logic
class AssetManagementScreen extends StatelessWidget {
  final String type;
  const AssetManagementScreen({super.key, required this.type});

  void _showDistributeRentDialog(BuildContext context, String docId, int propertyId) {
    final TextEditingController _rentCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Distribute Rent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter amount in MATIC to distribute to all fraction holders.'),
            TextField(
              controller: _rentCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount (MATIC)', suffixText: 'MATIC'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (_rentCtrl.text.isEmpty) return;
              Navigator.pop(ctx);

              try {
                final service = BlockchainServiceEnhanced();
                await service.init();

                // Ensure wallet is connected
                if (!service.isConnected) {
                  await service.connectWallet(context);
                }

                final amountEth = double.parse(_rentCtrl.text);
                final amountWei = service.etherToWei(amountEth);

                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Confirm transaction in wallet...')));

                await service.distributeLandRent(propertyId: propertyId, amount: amountWei);

                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rent Distributed Successfully!'), backgroundColor: Colors.green));
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
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
      stream: db.collection('assets')
          .where('ownerId', isEqualTo: auth.currentUser!.uid)
          .where('category', isEqualTo: type)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;

        if (docs.isEmpty) return const Center(child: Text("No assets found"));

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final tokenId = data['blockchainTokenId'] as int?;

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  ListTile(
                    title: Text(data['title'] ?? 'Untitled'),
                    subtitle: Text('Price: ${data['price']}'),
                    trailing: tokenId != null
                        ? const Chip(label: Text('NFT Minted'), backgroundColor: Colors.greenAccent)
                        : const Chip(label: Text('Draft')),
                  ),
                  ButtonBar(
                    children: [
                      // Distribute Rent Button for Landlords
                      if (type == 'land' && tokenId != null)
                        TextButton.icon(
                          icon: const Icon(Icons.monetization_on, color: Colors.amber),
                          label: const Text('Distribute Rent'),
                          onPressed: () => _showDistributeRentDialog(context, doc.id, tokenId),
                        ),
                      TextButton(
                        child: const Text('QR Code'),
                        onPressed: () => Navigator.push(
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
                    ],
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }
}


/// ENHANCED Asset Form with Smart Document Upload & Blockchain Fields
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

  // Track warnings and errors
  final List<String> _warnings = [];
  final List<String> _errors = [];

  late final TextEditingController _titleCtrl = TextEditingController(text: widget.initialData?['title'] ?? '');
  late final TextEditingController _descCtrl = TextEditingController(text: widget.initialData?['description'] ?? '');
  late final TextEditingController _priceCtrl = TextEditingController(text: widget.initialData?['price']?.toString() ?? '');
  late final TextEditingController _plotCtrl = TextEditingController(text: widget.initialData?['plotArea']?.toString() ?? '');
  late final TextEditingController _cityCtrl = TextEditingController(text: widget.initialData?['city'] ?? '');
  late final TextEditingController _brandCtrl = TextEditingController(text: widget.initialData?['brand'] ?? '');
  late final TextEditingController _modelCtrl = TextEditingController(text: widget.initialData?['model'] ?? '');
  late final TextEditingController _serialCtrl = TextEditingController(text: widget.initialData?['serial'] ?? '');
  late final TextEditingController _warrantyCtrl = TextEditingController(text: widget.initialData?['warranty'] ?? '');

  // New field for blockchain land
  late final TextEditingController _fractionsCtrl = TextEditingController(text: widget.initialData?['totalFractions']?.toString() ?? '100');

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
      _images.add(b);
    }
    setState(() {});
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final XFile? photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 800);
    if (photo != null) {
      final bytes = await photo.readAsBytes();
      setState(() => _images.add(bytes));
    }
  }

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
        if (file.bytes == null) {
          skippedFiles.add('${file.name} (no data)');
          continue;
        }

        if (file.size > 5 * 1024 * 1024) {
          _errors.add('${file.name} exceeds 5MB limit');
          skippedFiles.add('${file.name} (too large >5MB)');
          continue;
        }

        final totalSize = _calculateTotalSize(newDocuments) + file.size;
        if (totalSize > 10 * 1024 * 1024) {
          _errors.add('Total documents size would exceed 10MB limit');
          break;
        }

        newDocuments.add({
          'bytes': file.bytes!,
          'name': file.name,
          'type': file.extension ?? 'unknown',
          'size': file.size,
          'originalSize': file.size,
        });
      }

      if (newDocuments.isNotEmpty) {
        setState(() {
          _documents.addAll(newDocuments);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✓ ${newDocuments.length} document(s) added successfully'), backgroundColor: Colors.green),
          );
        }
      }

      if (skippedFiles.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Skipped ${skippedFiles.length} files'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      debugPrint('Error picking documents: $e');
    } finally {
      setState(() => _uploadingDocuments = false);
    }
  }

  Future<Map<String, dynamic>> _collect() async {
    _warnings.clear();
    _errors.clear();

    // 1. Process Images for Firestore
    final compressedImages = <String>[];
    for (final imgBytes in _images) {
      final compressed = await compressImageToBase64(imgBytes);
      compressedImages.add(compressed);
    }

    // 2. Process Documents for Firestore (Chunk/Smart Store)
    final processedDocs = <Map<String, dynamic>>[];
    for (final doc in _documents) {
      // If it has 'bytes', it's a new file. If not, it's an existing one from Firestore.
      if (doc.containsKey('bytes')) {
        final bytes = doc['bytes'] as Uint8List;
        final fileName = doc['name'] as String;
        final fileType = doc['type'] as String;
        final originalSize = doc['originalSize'] as int;

        try {
          final storedDoc = await DocumentStorage.storeDocument(bytes, fileName, fileType);

          if (originalSize > 500 * 1024) {
            _warnings.add('"$fileName" is large. It will be split into chunks.');
          }

          processedDocs.add(storedDoc);
        } catch (e) {
          _errors.add('Failed to process "$fileName"');
        }
      } else {
        processedDocs.add(doc);
      }
    }

    // 3. Prepare Payload
    final Map<String, dynamic> out = {
      'title': _titleCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'price': double.tryParse(_priceCtrl.text) ?? 0.0,
      'images': compressedImages,
      'searchKeywords': _titleCtrl.text.trim().toLowerCase().split(RegExp(r'\s+')),
      'documents': processedDocs,

      // Pass RAW data for IPFS (these will be removed before saving to Firestore)
      'rawImages': _images,
      'rawDocuments': _documents.where((d) => d.containsKey('bytes')).toList(),
    };

    if (widget.type == 'land') {
      out['plotArea'] = _plotCtrl.text.trim();
      out['plotUnit'] = _plotUnit;
      out['city'] = _cityCtrl.text.trim();
      out['totalFractions'] = int.tryParse(_fractionsCtrl.text) ?? 100;
    } else {
      out['brand'] = _brandCtrl.text.trim();
      out['model'] = _modelCtrl.text.trim();
      out['serial'] = _serialCtrl.text.trim();
      out['warranty'] = _warrantyCtrl.text.trim();
      out['condition'] = _condition;
    }

    return out;
  }

  Widget _getDocumentIcon(String type) {
    switch (type.toLowerCase()) {
      case 'pdf': return const Icon(Icons.picture_as_pdf, color: Colors.red, size: 24);
      case 'jpg':
      case 'jpeg':
      case 'png': return const Icon(Icons.image, color: Colors.blue, size: 24);
      case 'doc':
      case 'docx': return const Icon(Icons.description, color: Colors.blue, size: 24);
      default: return const Icon(Icons.insert_drive_file, size: 24);
    }
  }

  int _calculateTotalSize(List<Map<String, dynamic>> docs) {
    return docs.fold<int>(0, (sum, doc) => (sum + (doc['size'] ?? 0) as int));
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
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue[900]),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '• Small files (<100KB): Stored directly\n• Medium files (100KB-500KB): Compressed if image\n• Large files (>500KB): Split into chunks',
                              style: TextStyle(fontSize: 11, color: Colors.blue[800]),
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

            TextFormField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Title'), validator: (v) => (v ?? '').isEmpty ? 'Required' : null),
            const SizedBox(height: 8),
            TextFormField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Description'), maxLines: 3),
            const SizedBox(height: 8),
            TextFormField(controller: _priceCtrl, decoration: const InputDecoration(labelText: 'Price (PKR)'), keyboardType: TextInputType.number, validator: (v) => (v ?? '').isEmpty ? 'Required' : null),
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
              TextFormField(controller: _plotCtrl, decoration: InputDecoration(labelText: 'Plot Area ($_plotUnit)'), keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              TextFormField(controller: _cityCtrl, decoration: const InputDecoration(labelText: 'City / Address')),
              const SizedBox(height: 8),
              TextFormField(controller: _fractionsCtrl, decoration: const InputDecoration(labelText: 'Total Fractions (Default 100)'), keyboardType: TextInputType.number),
              const SizedBox(height: 12),
            ] else ...[
              TextFormField(controller: _brandCtrl, decoration: const InputDecoration(labelText: 'Brand')),
              const SizedBox(height: 8),
              TextFormField(controller: _modelCtrl, decoration: const InputDecoration(labelText: 'Model')),
              const SizedBox(height: 8),
              TextFormField(controller: _serialCtrl, decoration: const InputDecoration(labelText: 'Serial / IMEI')),
              const SizedBox(height: 8),
              TextFormField(controller: _warrantyCtrl, decoration: const InputDecoration(labelText: 'Warranty (months)'), keyboardType: TextInputType.number),
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

            // Image Upload
            const Divider(height: 32),
            Row(children: [
              const Icon(Icons.image, size: 20),
              const SizedBox(width: 8),
              const Text('Images', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              if (_images.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(12)),
                  child: Text('${_images.length}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ],
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: ElevatedButton.icon(onPressed: _pickImages, icon: const Icon(Icons.photo_library), label: const Text('Gallery'))),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton.icon(onPressed: _takePhoto, icon: const Icon(Icons.camera_alt), label: const Text('Camera'))),
            ]),

            // Document Upload
            const Divider(height: 32),
            Row(children: [
              const Icon(Icons.attach_file, size: 20),
              const SizedBox(width: 8),
              const Text('Documents', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              if (_documents.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(12)),
                  child: Text('${_documents.length}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ],
            ]),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _uploadingDocuments ? null : _pickDocuments,
              icon: _uploadingDocuments ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.file_upload),
              label: Text(_uploadingDocuments ? 'Loading...' : 'Attach Documents (PDF, Images, DOC)'),
            ),
            const SizedBox(height: 4),
            Text('Max 5MB per file, 10MB total', style: TextStyle(fontSize: 11, color: Colors.grey[600]), textAlign: TextAlign.center),

            // Document List
            if (_documents.isNotEmpty) ...[
              const SizedBox(height: 12),
              ..._documents.asMap().entries.map((entry) {
                final index = entry.key;
                final doc = entry.value;
                final size = doc['size'] as int;
                return Card(
                  child: ListTile(
                    leading: _getDocumentIcon(doc['type'] ?? ''),
                    title: Text(doc['name'] ?? 'Doc'),
                    subtitle: Text('${_formatFileSize(size)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _documents.removeAt(index)),
                    ),
                  ),
                );
              }),
            ],

            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;

                if (_warnings.isNotEmpty) {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Large Files'),
                      content: Column(mainAxisSize: MainAxisSize.min, children: _warnings.map((w) => Text('• $w')).toList()),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                }

                if (_documents.isNotEmpty) {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Confirm Upload'),
                      content: Text('Upload ${_documents.length} documents?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Upload')),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                }

                final payload = await _collect();
                if (_errors.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errors: ${_errors.join(", ")}'), backgroundColor: Colors.red));
                  return;
                }
                await widget.onSubmit(payload);
              },
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: Colors.green[700]),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_upload, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(widget.isEdit ? 'Save Changes' : 'Mint NFT & Submit', style: const TextStyle(color: Colors.white)),
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

/// Add Asset Screen: Handles Blockchain/IPFS + Firestore Logic
class AddAssetScreen extends StatefulWidget {
  final String type;
  const AddAssetScreen({super.key, required this.type});
  @override
  State<AddAssetScreen> createState() => _AddAssetScreenState();
}

class _AddAssetScreenState extends State<AddAssetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  // Electronics
  final _serialCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _warrantyCtrl = TextEditingController();
  // Land
  final _locationCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _fractionsCtrl = TextEditingController();

  bool _uploading = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _uploading = true);

    try {
      final blockchain = BlockchainServiceEnhanced();
      await blockchain.init();
      // ✅ FIX: Pass context
      if (!blockchain.isConnected) await blockchain.connectWallet(context);

      String? txHash;
      String ipfsHash = "QmHashPlaceholder"; // In real app, use IPFSService to upload image

      if (widget.type == 'electronics') {
        txHash = await blockchain.mintElectronics(
          toAddress: blockchain.connectedAddress!,
          serialNumber: _serialCtrl.text,
          brand: _brandCtrl.text,
          model: _modelCtrl.text,
          warrantyExpiry: _warrantyCtrl.text,
          tokenURI: "ipfs://$ipfsHash",
        );
      } else {
        txHash = await blockchain.createLandProperty(
          location: _locationCtrl.text,
          city: _cityCtrl.text,
          totalArea: int.parse(_areaCtrl.text),
          areaUnit: "Marla",
          totalFractions: int.parse(_fractionsCtrl.text),
          pricePerFraction: blockchain.etherToWei(double.parse(_priceCtrl.text)),
          ipfsMetadata: "ipfs://$ipfsHash",
        );
      }

      if (txHash != null) {
        // Save to Firestore for display
        await FirebaseFirestore.instance.collection('assets').add({
          'title': _titleCtrl.text,
          'price': double.parse(_priceCtrl.text),
          'category': widget.type,
          'ownerId': FirebaseAuth.instance.currentUser!.uid,
          'blockchainTx': txHash,
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (mounted) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Asset Minted Successfully!")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Add ${widget.type}")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(controller: _titleCtrl, decoration: const InputDecoration(labelText: "Title"), validator: (v) => v!.isEmpty ? "Required" : null),
              TextFormField(controller: _priceCtrl, decoration: const InputDecoration(labelText: "Price"), keyboardType: TextInputType.number),

              if (widget.type == 'electronics') ...[
                TextFormField(controller: _serialCtrl, decoration: const InputDecoration(labelText: "Serial Number")),
                TextFormField(controller: _brandCtrl, decoration: const InputDecoration(labelText: "Brand")),
                TextFormField(controller: _modelCtrl, decoration: const InputDecoration(labelText: "Model")),
                TextFormField(controller: _warrantyCtrl, decoration: const InputDecoration(labelText: "Warranty Date")),
              ],

              if (widget.type == 'land') ...[
                TextFormField(controller: _locationCtrl, decoration: const InputDecoration(labelText: "Location")),
                TextFormField(controller: _cityCtrl, decoration: const InputDecoration(labelText: "City")),
                TextFormField(controller: _areaCtrl, decoration: const InputDecoration(labelText: "Area (Marla)"), keyboardType: TextInputType.number),
                TextFormField(controller: _fractionsCtrl, decoration: const InputDecoration(labelText: "Total Fractions"), keyboardType: TextInputType.number),
              ],

              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _uploading ? null : _submit,
                child: _uploading ? const CircularProgressIndicator() : const Text("Mint on Blockchain"),
              ),
            ],
          ),
        ),
      ),
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
      }
    } catch (e) {
      debugPrint('Error loading asset: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _handleSave(Map<String, dynamic> data) async {
    setState(() => _saving = true);
    try {
      // Remove raw bytes (no need for re-upload on simple edit)
      data.remove('rawImages');
      data.remove('rawDocuments');

      await db.collection('assets').doc(widget.assetId).update({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Asset updated'), backgroundColor: Colors.green));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_initial == null) return const Scaffold(body: Center(child: Text('Asset not found')));

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Asset')),
      body: _saving
          ? const Center(child: CircularProgressIndicator())
          : AssetForm(type: widget.type, initialData: _initial, isEdit: true, onSubmit: _handleSave),
    );
  }
}