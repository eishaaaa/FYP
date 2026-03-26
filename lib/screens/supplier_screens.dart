// lib/screens/supplier_screens.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;

// Internal Imports
import 'chat_screen.dart';
import 'shared_screens.dart';
import 'chat_list_screen.dart';
import 'qr_generator_screen.dart';
import 'qr_scanner_enhanced.dart';
import '../blockchain/blockchain_service.dart';
import '../blockchain/ipfs_service.dart';
import 'wallet_screen.dart';
import 'transaction_model.dart';

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;
const uuid = Uuid();

extension _Cap on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}

// -----------------------------------------------------------------------------
// UTILITIES (Compression & Storage)
// -----------------------------------------------------------------------------

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

  @override
  void initState() {
    super.initState();
    _pages = <Widget>[
      SupplierHome(type: widget.type),
      const QRScannerEnhanced(),
      const MyAssetsScreen(),
      const ProfileScreen(),
    ];
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
    return  Scaffold(
        appBar: AppBar(
          toolbarHeight: 80, //
          automaticallyImplyLeading: false,
          title: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Colors.white24,
                child: Icon(Icons.store, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${type.capitalize()} Supplier',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Text(
                    'My Assets',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
            ),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .where('receiverId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                  .where('isRead', isEqualTo: false)
                  .snapshots(),
              builder: (context, snapshot) {
                int unreadCount = snapshot.data?.docs.length ?? 0;
                return Badge(
                  label: Text(unreadCount.toString()),
                  isLabelVisible: unreadCount > 0,
                  offset: const Offset(-4, 4),
                  child: IconButton(
                    icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(width: 4),
          ],
        ),
        body:
            AssetManagementScreen(type: type),
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
      );
  }
}


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
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount (MATIC)', suffixText: 'MATIC'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              // 1. INPUT VALIDATION: Check numbers BEFORE blocking call
              final textAmount = _rentCtrl.text.trim().replaceAll(',', '');
              if (textAmount.isEmpty) return;

              final amountEth = double.tryParse(textAmount);
              if (amountEth == null || amountEth <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid Amount: Please enter a number like 0.1 or 10'), backgroundColor: Colors.red));
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

                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Confirm transaction in wallet...')));

                await service.distributeLandRent(propertyId: propertyId, amount: amountWei);

                if (!context.mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rent Distributed Successfully!'), backgroundColor: Colors.green));
              } catch (e) {
                if (context.mounted) {
                  // Display exact error from Blockchain Service
                  showDialog(context: context, builder: (_) => AlertDialog(
                      title: const Text('Error'),
                      content: Text(e.toString()),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]
                  ));
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
                        : const Chip(label: Text('Draft'), backgroundColor: Colors.grey),
                  ),
                  ButtonBar(
                    children: [
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
                      TextButton(
                        child: const Text('Edit'),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EditAssetScreen(assetId: doc.id, type: type),
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
      text: widget.initialData?['title']?.toString() ?? ''
  );
  late final TextEditingController _descCtrl = TextEditingController(
      text: widget.initialData?['description']?.toString() ?? ''
  );
  late final TextEditingController _priceCtrl = TextEditingController(
      text: widget.initialData?['price']?.toString() ?? ''
  );
  late final TextEditingController _plotCtrl = TextEditingController(
      text: widget.initialData?['plotArea']?.toString() ?? ''
  );
  late final TextEditingController _cityCtrl = TextEditingController(
      text: widget.initialData?['city']?.toString() ?? ''
  );
  late final TextEditingController _brandCtrl = TextEditingController(
      text: widget.initialData?['brand']?.toString() ?? ''
  );
  late final TextEditingController _modelCtrl = TextEditingController(
      text: widget.initialData?['model']?.toString() ?? ''
  );
  late final TextEditingController _serialCtrl = TextEditingController(
      text: widget.initialData?['serial']?.toString() ?? ''
  );
  late final TextEditingController _warrantyCtrl = TextEditingController(
      text: widget.initialData?['warranty']?.toString() ?? ''
  );
  late final TextEditingController _fractionsCtrl = TextEditingController(
      text: widget.initialData?['totalFractions']?.toString() ?? '100'
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
    _titleCtrl.dispose(); _descCtrl.dispose(); _priceCtrl.dispose(); _plotCtrl.dispose();
    _cityCtrl.dispose(); _brandCtrl.dispose(); _modelCtrl.dispose(); _serialCtrl.dispose();
    _warrantyCtrl.dispose(); _fractionsCtrl.dispose();
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
    final XFile? photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 70, maxWidth: 800);
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid Price Format')));
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
        final processed = await DocumentStorage.storeDocument(bytes, doc['name'], doc['type']);
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
      'searchKeywords': _titleCtrl.text.trim().toLowerCase().split(RegExp(r'\s+')),
      'documents': processedDocs,
      'rawImages': _images,
      'rawDocuments': _documents.where((d) => d.containsKey('bytes')).toList(),
    };

    if (widget.type == 'land') {
      final area = int.tryParse(_plotCtrl.text.replaceAll(',', ''));
      final fracs = int.tryParse(_fractionsCtrl.text.replaceAll(',', ''));
      if (area == null || fracs == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid Plot Area or Fractions')));
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
            TextFormField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Title'), validator: (v) => v!.isEmpty ? 'Required' : null),
            TextFormField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Description'), maxLines: 3),
            // FIX: Using decimal input type
            TextFormField(controller: _priceCtrl, decoration: const InputDecoration(labelText: 'Price'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            const SizedBox(height: 12),

            if (widget.type == 'land') ...[
              DropdownButtonFormField<String>(
                value: _plotUnit,
                items: const [DropdownMenuItem(value: 'marla', child: Text('Marla')), DropdownMenuItem(value: 'kanal', child: Text('Kanal'))],
                onChanged: (v) => setState(() => _plotUnit = v!),
                decoration: const InputDecoration(labelText: 'Plot Unit'),
              ),
              TextFormField(controller: _plotCtrl, decoration: const InputDecoration(labelText: 'Plot Area (Integer)'), keyboardType: TextInputType.number),
              TextFormField(controller: _cityCtrl, decoration: const InputDecoration(labelText: 'City / Address')),
              TextFormField(controller: _fractionsCtrl, decoration: const InputDecoration(labelText: 'Total Fractions (Default 100)'), keyboardType: TextInputType.number),
            ] else ...[
              TextFormField(controller: _brandCtrl, decoration: const InputDecoration(labelText: 'Brand')),
              TextFormField(controller: _modelCtrl, decoration: const InputDecoration(labelText: 'Model')),
              TextFormField(controller: _serialCtrl, decoration: const InputDecoration(labelText: 'Serial / IMEI')),
              TextFormField(controller: _warrantyCtrl, decoration: const InputDecoration(labelText: 'Warranty (Date/Months)')),
              DropdownButtonFormField<String>(
                value: _condition,
                items: const [DropdownMenuItem(value: 'new', child: Text('New')), DropdownMenuItem(value: 'used', child: Text('Used'))],
                onChanged: (v) => setState(() => _condition = v!),
                decoration: const InputDecoration(labelText: 'Condition'),
              ),
            ],

            const Divider(height: 32),
            const Text('Images', style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(children: _images.map((bytes) => Padding(padding: const EdgeInsets.only(right: 8, top: 8), child: Image.memory(bytes, width: 80, height: 80, fit: BoxFit.cover))).toList()),
            Row(children: [
              TextButton.icon(onPressed: _pickImages, icon: const Icon(Icons.photo_library), label: const Text('Add Gallery')),
              TextButton.icon(onPressed: _takePhoto, icon: const Icon(Icons.camera_alt), label: const Text('Camera')),
            ]),

            const Divider(height: 32),
            const Text('Documents (Attached to IPFS & Secure Storage)', style: TextStyle(fontWeight: FontWeight.bold)),
            if (_documents.isNotEmpty)
              Column(children: _documents.map((d) => ListTile(
                leading: const Icon(Icons.description),
                title: Text(d['name']),
                subtitle: Text(_formatFileSize(d['size'] ?? 0)),
                trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _documents.remove(d))),
              )).toList()),
            ElevatedButton.icon(
              onPressed: _uploadingDocuments ? null : _pickDocuments,
              icon: _uploadingDocuments ? const CircularProgressIndicator() : const Icon(Icons.file_upload),
              label: const Text('Attach Documents'),
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
              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: Colors.indigo),
              child: Text(widget.isEdit ? 'Save Changes' : 'Mint NFT & Upload to IPFS', style: const TextStyle(color: Colors.white, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// ADD ASSET SCREEN (Logic Wrapper: Firestore + IPFS + Blockchain)
// -----------------------------------------------------------------------------

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
        throw Exception('Wallet connection failed or timed out. Please make sure you are on the Amoy Testnet.');
      }

      // ---------------------------------------------------------
      // STEP 2: UPLOAD IMAGE TO IPFS (Optimized)
      // ---------------------------------------------------------
      String? imageHash;
      if (data['rawImages'] != null && (data['rawImages'] as List).isNotEmpty) {
        setState(() => _statusMessage = 'Compressing & Uploading Image...');

        // FIX: Compress image before upload to prevent infinite loading on large files
        final rawBytes = (data['rawImages'] as List)[0] as Uint8List;
        final compressedBase64 = await compressImageToBase64(rawBytes, quality: 60);
        final compressedBytes = base64Decode(compressedBase64);

        final res = await ipfs.uploadFile(
            fileBytes: compressedBytes,
            fileName: 'nft_image.jpg'
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
            final match = fsDocs.firstWhere((d) => d['name'] == doc['name'], orElse: () => {});
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
      final metaRes = await ipfs.uploadJSON(jsonData: metadata, name: '${safeTitle}_metadata');
      if (!metaRes.success) throw Exception('Metadata Upload Failed');
      final metadataHash = metaRes.ipfsHash!;

      if (!mounted) return;

      // ---------------------------------------------------------
      // STEP 6: MINT ON BLOCKCHAIN
      // ---------------------------------------------------------
      setState(() => _statusMessage = 'Please Confirm Transaction in Wallet...');
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
      setState(() => _statusMessage = 'Saving to Database...');

      data.remove('rawImages');
      data.remove('rawDocuments');

      await db.collection('assets').add({
        ...data,
        'category': widget.type,
        'ownerId': auth.currentUser!.uid,
        'blockchainTx': txHash,
        'ipfsMetadataHash': metadataHash,
        'isMinted': true,
        'verified': true,
        'createdAt': FieldValue.serverTimestamp(),
      });


      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Success! Asset Minted & Uploaded.'),
          backgroundColor: Colors.green
      ));
      await addTransaction(
        userId: auth.currentUser!.uid,
        type: "nft",
        title: data['title'] ?? "Asset",
        toAddress: "self",
      );
      Navigator.pop(context);

    } catch (e) {
      if (mounted) {
        showDialog(context: context, builder: (_) => AlertDialog(
          title: const Text('Error'),
          content: Text(e.toString()),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(_statusMessage, style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text("Add ${widget.type.capitalize()}")),
      body: AssetForm(
        type: widget.type,
        onSubmit: _handleCreate,
      ),
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
  Map<String, dynamic>? _initial;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final doc = await db.collection('assets').doc(widget.assetId).get();
      if (doc.exists) setState(() => _initial = doc.data());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _handleSave(Map<String, dynamic> data) async {
    data.remove('rawImages');
    data.remove('rawDocuments');
    await db.collection('assets').doc(widget.assetId).update(data);
    if(mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Asset')),
      body: AssetForm(type: widget.type, initialData: _initial, isEdit: true, onSubmit: _handleSave),
    );
  }
}