
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';

import 'shared_screens.dart'; // MUST export db, auth and shared screens

final _uuid = Uuid();

/// Utility: Safe base64 decode (null on error)
Uint8List? _tryBase64Decode(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    return base64Decode(s);
  } catch (_) {
    return null;
  }
}

/// Utility: Display image widget from either http-url or base64 string
Widget imageFromString(String? s, {BoxFit fit = BoxFit.cover, double? width, double? height}) {
  if (s == null || s.isEmpty) {
    return Container(color: Colors.grey[200], child: const Icon(Icons.image));
  }
  if (s.startsWith('http') || s.startsWith('https')) {
    return Image.network(s, fit: fit, width: width, height: height, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image));
  }
  final bytes = _tryBase64Decode(s);
  if (bytes != null) {
    return Image.memory(bytes, fit: fit, width: width, height: height);
  }
  return Container(color: Colors.grey[200], child: const Icon(Icons.image));
}

/// ---------------------------------------------------------------------------
/// SupplierHomeScreen - bottom navigation for supplier (Home / Scan / MyAssets / Profile)
/// ---------------------------------------------------------------------------
class SupplierHomeScreen extends StatefulWidget {
  final String type; // 'land' or 'electronics'
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
      appBar: AppBar(
        title: Text('${widget.type[0].toUpperCase()}${widget.type.substring(1)} Supplier'),
      ),
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

/// ---------------------------------------------------------------------------
/// SupplierHome - TabBar with Dashboard and Asset Management
/// ---------------------------------------------------------------------------
class SupplierHome extends StatelessWidget {
  final String type;
  const SupplierHome({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${type[0].toUpperCase()}${type.substring(1)} Supplier Home'),
          bottom: const TabBar(tabs: [Tab(text: 'Dashboard'), Tab(text: 'Assets')]),
        ),
        body: TabBarView(children: [
          SupplierDashboard(uid: auth.currentUser?.uid ?? '', type: type),
          AssetManagementScreen(type: type),
        ]),
        floatingActionButton: FloatingActionButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddAssetScreen(type: type))),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// SupplierDashboard - uses streams and safe numeric handling
/// ---------------------------------------------------------------------------
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
        leading: CircleAvatar(child: Icon(icon, color: Colors.white), backgroundColor: color),
        title: Text(title),
        trailing: Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
    if (uid.isEmpty) return const Center(child: Text('Please log in'));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),

        // Total assets
        StreamBuilder<QuerySnapshot>(
          stream: db.collection('assets').where('ownerId', isEqualTo: uid).snapshots(),
          builder: (context, snap) {
            final count = snap.data?.docs.length ?? 0;
            return _statCard('Total Assets', Icons.inventory_2, count, Colors.blue);
          },
        ),

        // Total views + verifications (safe folds)
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

            return Column(children: [
              _statCard('Total Views', Icons.visibility, views, Colors.green),
              _statCard('Total Verifications', Icons.verified, verifs, Colors.orange),
            ]);
          },
        ),

        const SizedBox(height: 20),

        ElevatedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddAssetScreen(type: type))),
          icon: const Icon(Icons.add),
          label: const Text('Add New Asset'),
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ]),
    );
  }
}

/// ---------------------------------------------------------------------------
/// AssetManagementScreen - list of supplier's assets (edit/delete/view)
/// ---------------------------------------------------------------------------
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

  Widget _imageWidget(String? img) {
    // Accept https urls or base64 strings
    if (img == null || img.isEmpty) return const Icon(Icons.image, size: 48, color: Colors.grey);
    if (img.startsWith('http')) {
      return Image.network(img, width: 60, height: 60, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image));
    }
    final bytes = _tryBase64Decode(img);
    if (bytes != null) return Image.memory(bytes, width: 60, height: 60, fit: BoxFit.cover);
    return const Icon(Icons.image, size: 48, color: Colors.grey);
  }

  @override
  Widget build(BuildContext context) {
    final uid = auth.currentUser?.uid;
    if (uid == null) return const Center(child: Text('Please log in'));

    // Keep query simple: filter by ownerId + category
    final stream = db.collection('assets').where('ownerId', isEqualTo: uid).where('category', isEqualTo: type).orderBy('createdAt', descending: true).snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const Center(child: Text('No assets yet. Tap + to add.'));

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final img = (data['images'] is List && (data['images'] as List).isNotEmpty) ? (data['images'][0] as String?) : null;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: _imageWidget(img)),
                title: Text(data['title'] ?? data['name'] ?? 'No title', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('PKR ${data['price'] ?? 0}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => EditAssetScreen(assetId: doc.id, type: type)));
                    } else if (v == 'delete') {
                      _showDeleteConfirm(context, doc.id);
                    } else if (v == 'view') {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: doc.id)));
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

/// ---------------------------------------------------------------------------
/// Shared Asset Form (used by Add and Edit)
/// - Stores images as base64 strings by default (Option A)
/// - Accepts file attachments (pdf) as base64
/// ---------------------------------------------------------------------------
class AssetForm extends StatefulWidget {
  final String type; // 'land' or 'electronics'
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
  final List<Uint8List> _pickedImages = [];
  String? _existingImagePreview; // optional preview for editing if existing images present
  String? _docBase64;
  String _condition = 'new';

  late final TextEditingController _titleCtrl = TextEditingController(text: widget.initialData?['title']?.toString() ?? '');
  late final TextEditingController _descCtrl = TextEditingController(text: widget.initialData?['description']?.toString() ?? '');
  late final TextEditingController _priceCtrl = TextEditingController(text: widget.initialData?['price']?.toString() ?? '');
  late final TextEditingController _plotCtrl = TextEditingController(text: widget.initialData?['plotArea']?.toString() ?? '');
  late final TextEditingController _cityCtrl = TextEditingController(text: widget.initialData?['city']?.toString() ?? '');
  late final TextEditingController _brandCtrl = TextEditingController(text: widget.initialData?['brand']?.toString() ?? '');
  late final TextEditingController _modelCtrl = TextEditingController(text: widget.initialData?['model']?.toString() ?? '');
  late final TextEditingController _serialCtrl = TextEditingController(text: widget.initialData?['serial']?.toString() ?? '');
  late final TextEditingController _warrantyCtrl = TextEditingController(text: widget.initialData?['warranty']?.toString() ?? '');

  @override
  void initState() {
    super.initState();
    _condition = widget.initialData?['condition']?.toString() ?? 'new';
    // If initialData has images, keep a single preview (first) for UX
    if ((widget.initialData?['images'] as List?)?.isNotEmpty == true) {
      final first = (widget.initialData!['images'] as List)[0] as String?;
      if (first != null) _existingImagePreview = first;
    }
    // If initialData has document, keep note
    if (widget.initialData?['document'] != null) {
      _docBase64 = widget.initialData?['document']?.toString();
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
      final bytes = await p.readAsBytes();
      _pickedImages.add(bytes);
    }
    setState(() {});
  }

  Future<void> _pickDoc() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (res?.files.single.bytes != null) {
      _docBase64 = base64Encode(res!.files.single.bytes!);
      setState(() {});
    }
  }

  Map<String, dynamic> _collect() {
    final imagesList = <String>[];
    // If user picked new images, use them as base64
    if (_pickedImages.isNotEmpty) {
      imagesList.addAll(_pickedImages.map((b) => base64Encode(b)));
    } else {
      // otherwise preserve existing images from initialData (if any)
      final existing = widget.initialData?['images'] as List?;
      if (existing != null && existing.isNotEmpty) {
        imagesList.addAll(existing.map((e) => e.toString()));
      }
    }

    final out = <String, dynamic>{
      'title': _titleCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'price': double.tryParse(_priceCtrl.text) ?? 0.0,
      'images': imagesList,
      'document': _docBase64,
      'searchKeywords': (_titleCtrl.text.trim().toLowerCase()).split(RegExp(r'\s+')),
    };

    if (widget.type == 'land') {
      out['plotArea'] = _plotCtrl.text.trim();
      out['city'] = _cityCtrl.text.trim();
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
    final isLand = widget.type == 'land';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(controller: _titleCtrl, decoration: const InputDecoration(labelText: 'Title'), validator: (v) => (v ?? '').isEmpty ? 'Required' : null),
          const SizedBox(height: 8),
          TextFormField(controller: _descCtrl, decoration: const InputDecoration(labelText: 'Description'), maxLines: 3),
          const SizedBox(height: 8),
          TextFormField(controller: _priceCtrl, decoration: const InputDecoration(labelText: 'Price (PKR)'), keyboardType: TextInputType.number, validator: (v) => (v ?? '').isEmpty ? 'Required' : null),
          const SizedBox(height: 12),

          if (isLand) ...[
            TextFormField(controller: _plotCtrl, decoration: const InputDecoration(labelText: 'Plot Area (e.g., 10 marla)')),
            const SizedBox(height: 8),
            TextFormField(controller: _cityCtrl, decoration: const InputDecoration(labelText: 'City / Address')),
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

          Row(
            children: [
              ElevatedButton.icon(onPressed: _pickImages, icon: const Icon(Icons.image), label: const Text('Pick Images')),
              const SizedBox(width: 12),
              TextButton(onPressed: () {
                // Allow user to enter an image URL manually
                showDialog(context: context, builder: (ctx){
                  final ctrl = TextEditingController();
                  return AlertDialog(
                    title: const Text('Add image URL'),
                    content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'https://...')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      ElevatedButton(onPressed: () {
                        final url = ctrl.text.trim();
                        if (url.isNotEmpty) {
                          // convert to a base64-like string? we store url as-is
                          // if user added URL, we put it into _existingImagePreview for UX and will include in images list through initialData preserving
                          setState(() {
                            _existingImagePreview = url;
                            // We'll save it by adding one element to pickedImages as null; instead, store it on widget.initialData if not editing: we keep a temporary list in doc by using _docBase64? simpler:
                            // Instead we'll add to list by creating a "virtual" base64 list — but we can't mutate widget.initialData here.
                            // To keep logic simple, we append a url to _pickedImages as bytes? That's awkward.
                            // We'll store url in _existingImagePreview and later on collect() we will include existing images from initialData and preview.
                          });
                        }
                        Navigator.pop(ctx);
                      }, child: const Text('Add')),
                    ],
                  );
                });
              }, child: const Text('Add image URL')),
            ],
          ),
          const SizedBox(height: 8),

          // preview row
          SizedBox(
            height: 80,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                if (_existingImagePreview != null)
                  Container(margin: const EdgeInsets.only(right: 8), width: 80, height: 80, child: imageFromString(_existingImagePreview)),
                ..._pickedImages.map((b) => Container(margin: const EdgeInsets.only(right: 8), width: 80, height: 80, child: Image.memory(b, fit: BoxFit.cover))),
              ],
            ),
          ),

          const SizedBox(height: 12),
          ElevatedButton.icon(onPressed: _pickDoc, icon: const Icon(Icons.attach_file), label: const Text('Attach PDF (optional)')),
          if (_docBase64 != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('PDF attached', style: const TextStyle(color: Colors.green))),
          const SizedBox(height: 20),

          ElevatedButton(
            onPressed: () async {
              if (!_formKey.currentState!.validate()) return;
              final payload = _collect();

              // If user used image URL via _existingImagePreview (and it isn't already in images), add it:
              if (_existingImagePreview != null && payload['images'] is List) {
                final list = payload['images'] as List;
                if (!list.contains(_existingImagePreview)) {
                  list.insert(0, _existingImagePreview);
                }
              }

              await widget.onSubmit(payload);
            },
            child: Text(widget.isEdit ? 'Save Changes' : 'Submit Asset'),
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// AddAssetScreen
/// ---------------------------------------------------------------------------
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
    final id = _uuid.v4();
    final user = auth.currentUser!;
    final payload = <String, dynamic>{
      'assetId': id,
      'ownerId': user.uid,
      'ownerEmail': user.email ?? '',
      'category': widget.type,
      'createdAt': FieldValue.serverTimestamp(),
      'verified': false,
      'views': 0,
      'verifications': 0,
      // Add title fallback: if 'title' missing add from 'searchKeywords' or ''
      'title': data['title'] ?? '',
      ...data,
    };

    try {
      await db.collection('assets').doc(id).set(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Asset added')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add asset: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Asset')),
      body: _loading ? const Center(child: CircularProgressIndicator()) : AssetForm(type: widget.type, onSubmit: _handleSubmit),
    );
  }
}

/// ---------------------------------------------------------------------------
/// EditAssetScreen
/// ---------------------------------------------------------------------------
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
    final doc = await db.collection('assets').doc(widget.assetId).get();
    setState(() {
      _initial = doc.data() as Map<String, dynamic>?;
      _loading = false;
    });
  }

  Future<void> _handleSave(Map<String, dynamic> data) async {
    // remove empty / unchanged keys to avoid overwriting
    data.removeWhere((k, v) => v == null || (v is String && v.isEmpty) || (v is List && v.isEmpty));
    try {
      await db.collection('assets').doc(widget.assetId).update(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Asset updated')));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_initial == null) return const Scaffold(body: Center(child: Text('Asset not found')));

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Asset')),
      body: AssetForm(type: widget.type, initialData: _initial, isEdit: true, onSubmit: _handleSave),
    );
  }
}
