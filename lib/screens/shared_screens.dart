// lib/screens/shared_screens.dart
// B1-FULL
// Shared screens used by both user and supplier.
// Role is read from Firestore user doc: users/{uid}.role
// Robust image handling (URL or base64), constrained leading widgets,
// Request-to-buy deduplication, and simple chat per-transaction.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:uuid/uuid.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import 'auth_screens.dart';

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;
final _uuid = Uuid();

/// Helper: fetch current role from Firestore user document.
/// Returns 'user' if anything goes wrong or no doc exists.
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

/// Utility: try decode base64, return null on error
Uint8List? _tryBase64Decode(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    // If string contains a data: prefix, remove it
    final cleaned = s.startsWith('data:') ? s.split(',').last : s;
    return base64Decode(cleaned);
  } catch (_) {
    return null;
  }
}

/// Utility widget: build an image from either a network URL or a base64 string.
/// It returns a Widget with constrained size and proper errorBuilder.
Widget buildAssetImage(String? s, {BoxFit fit = BoxFit.cover, double width = 80, double height = 80}) {
  if (s == null || s.isEmpty) {
    return Container(width: width, height: height, color: Colors.grey[200], child: const Icon(Icons.image, size: 36));
  }

  // If it looks like a URL
  if (s.startsWith('http://') || s.startsWith('https://')) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        s,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => Container(width: width, height: height, color: Colors.grey[200], child: const Icon(Icons.broken_image)),
      ),
    );
  }

  // Try base64
  final bytes = _tryBase64Decode(s);
  if (bytes != null) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(bytes, width: width, height: height, fit: fit, errorBuilder: (_, __, ___) => Container(width: width, height: height, color: Colors.grey[200], child: const Icon(Icons.broken_image))),
    );
  }

  // fallback: show placeholder
  return Container(width: width, height: height, color: Colors.grey[200], child: const Icon(Icons.image));
}

/// -------------------- ASSET DETAIL (ROLE-AWARE) --------------------
class AssetDetailScreen extends StatefulWidget {
  final String assetId;
  const AssetDetailScreen({super.key, required this.assetId});

  @override
  State<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends State<AssetDetailScreen> {
  late Future<Map<String, dynamic?>> _loadFuture;

  Future<Map<String, dynamic?>> _load() async {
    final assetSnap = await db.collection('assets').doc(widget.assetId).get();
    final role = await fetchCurrentRole();
    return {'assetSnap': assetSnap, 'role': role};
  }

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Asset Detail')),
      body: FutureBuilder<Map<String, dynamic?>>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final assetSnap = snapshot.data!['assetSnap'] as DocumentSnapshot<Map<String, dynamic>>;
          final role = (snapshot.data!['role'] as String?) ?? 'user';

          if (!assetSnap.exists) return const Center(child: Text('Asset not found'));
          final data = assetSnap.data() ?? <String, dynamic>{};

          // Increment view count (non-blocking)
          db.collection('assets').doc(widget.assetId).update({'views': FieldValue.increment(1)}).catchError((_) {});

          final images = (data['images'] as List?)?.cast<String>() ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // images carousel or placeholder
              if (images.isNotEmpty)
                CarouselSlider(
                  options: CarouselOptions(height: 220, autoPlay: true),
                  items: images.map((img) {
                    return SizedBox(
                      width: double.infinity,
                      child: buildAssetImage(img, width: double.infinity, height: 220, fit: BoxFit.cover),
                    );
                  }).toList(),
                )
              else
                Container(height: 220, color: Colors.grey[200], child: const Center(child: Icon(Icons.image, size: 80))),
              const SizedBox(height: 12),
              Text(data['title'] ?? data['name'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('PKR ${data['price'] ?? 0}', style: const TextStyle(fontSize: 18, color: Colors.green)),
              const SizedBox(height: 12),
              Text(data['description'] ?? ''),
              const SizedBox(height: 12),

              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Owner'),
                subtitle: Text(data['ownerEmail'] ?? data['ownerId'] ?? 'Unknown'),
                leading: const SizedBox(width: 56, height: 56, child: Icon(Icons.person)),
              ),

              if (data['category'] == 'land') ...[
                ListTile(contentPadding: EdgeInsets.zero, title: const Text('Plot Area'), subtitle: Text('${data['plotArea'] ?? '—'}')),
                ListTile(contentPadding: EdgeInsets.zero, title: const Text('City'), subtitle: Text(data['city'] ?? '—')),
              ],
              if (data['category'] == 'electronics') ...[
                ListTile(contentPadding: EdgeInsets.zero, title: const Text('Brand'), subtitle: Text(data['brand'] ?? '—')),
                ListTile(contentPadding: EdgeInsets.zero, title: const Text('Condition'), subtitle: Text(data['condition'] ?? '—')),
              ],
              const SizedBox(height: 12),

              // Documents (if any)
              if (data['documents'] is List && (data['documents'] as List).isNotEmpty) ...[
                const Text('Documents', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...((data['documents'] as List).map((d) {
                  final title = (d is Map && d['name'] != null) ? d['name'] : 'Document';
                  final url = (d is Map && d['url'] != null) ? d['url'] : d;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(title.toString()),
                    trailing: IconButton(icon: const Icon(Icons.open_in_new), onPressed: () => _openDocument(context, url.toString())),
                  );
                }).toList()),
                const SizedBox(height: 12),
              ],

              // QR
              Center(child: QrImageView(data: 'asset://${widget.assetId}', size: 140)),
              const SizedBox(height: 12),

              // Actions: role-aware (suppliers should not see Request/Favorite)
              if (!role.toLowerCase().contains('supplier')) ...[
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _requestToBuy(context, widget.assetId, data['ownerId'] ?? data['ownerUid']),
                      icon: const Icon(Icons.shopping_cart),
                      label: const Text('Request to Buy'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                      onPressed: () => _toggleFavorite(context, widget.assetId), icon: const Icon(Icons.favorite_border), label: const Text('Favorite')),
                ]),
              ] else ...[
                // Supplier view
                Row(children: [
                  Expanded(child: ElevatedButton.icon(onPressed: () => _verifyAsset(context, widget.assetId), icon: const Icon(Icons.verified), label: const Text('Verify Asset'))),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(onPressed: () => _transferOwnership(context, widget.assetId), icon: const Icon(Icons.swap_horiz), label: const Text('Transfer')),
                ]),
              ],

              const SizedBox(height: 18),
              const Text('Related Items', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              RelatedItemsList(type: data['category'] ?? data['type'], city: data['city']),
            ]),
          );
        },
      ),
    );
  }

  void _openDocument(BuildContext ctx, String url) async {
    if (url.startsWith('http')) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Open URL in browser (not implemented)')));
    } else {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Unsupported document format')));
    }
  }

  Future<void> _requestToBuy(BuildContext ctx, String assetId, String? sellerId) async {
    final user = auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please login to request')));
      return;
    }

    // Ensure only one active transaction per buyer per asset (not rejected)
    final existing = await db
        .collection('transactions')
        .where('assetId', isEqualTo: assetId)
        .where('buyerUid', isEqualTo: user.uid)
        .where('status', whereIn: ['pending', 'approved', 'completed'])
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('You already have a request for this asset')));
      return;
    }

    final txId = _uuid.v4();
    await db.collection('transactions').doc(txId).set({
      'transactionId': txId,
      'assetId': assetId,
      'buyerUid': user.uid,
      'sellerUid': sellerId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    // create an empty chat doc for this transaction (will be used later)
    await db.collection('chats').doc(txId).set({
      'transactionId': txId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Request Sent')));
  }

  Future<void> _verifyAsset(BuildContext ctx, String assetId) async {
    await db.collection('assets').doc(assetId).update({'verified': true});
    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Asset marked verified')));
  }

  Future<void> _transferOwnership(BuildContext ctx, String assetId) async {
    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Transfer ownership - not implemented')));
  }

  Future<void> _toggleFavorite(BuildContext ctx, String assetId) async {
    final user = auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please login to favorite')));
      return;
    }
    final favRef = db.collection('users').doc(user.uid).collection('favorites').doc(assetId);
    final doc = await favRef.get();
    if (doc.exists) {
      await favRef.delete();
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Removed from favorites')));
    } else {
      await favRef.set({'assetId': assetId, 'createdAt': FieldValue.serverTimestamp()});
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Added to favorites')));
    }
  }
}

/// -------------------- QR SCANNER (shared) --------------------
class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});
  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final _controller = MobileScannerController();
  bool _processing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleCode(String code) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      final id = code.startsWith('asset://') ? code.split('://').last : code;
      final doc = await db.collection('assets').doc(id).get();
      if (!doc.exists) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Asset not found')));
        return;
      }

      // If supplier, increment verifications
      final role = await fetchCurrentRole();
      if (role.toLowerCase().contains('supplier')) {
        await db.collection('assets').doc(id).update({'verifications': FieldValue.increment(1)});
      }

      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: id)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan error: $e')));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR')),
      body: Stack(children: [
        MobileScanner(controller: _controller, onDetect: (capture) {
          final code = capture.barcodes.first.rawValue;
          if (code != null) _handleCode(code);
        }),
        if (_processing) const Align(alignment: Alignment.topCenter, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator())),
      ]),
    );
  }
}

/// -------------------- MY ASSETS (role-aware) --------------------
class MyAssetsScreen extends StatelessWidget {
  const MyAssetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Not logged in')));

    // Fetch role first
    return FutureBuilder<String>(
      future: fetchCurrentRole(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final role = snap.data ?? 'user';
        if (role.toLowerCase().contains('supplier')) {
          final q = db.collection('assets').where('ownerId', isEqualTo: user.uid).orderBy('createdAt', descending: true);
          return Scaffold(
            appBar: AppBar(title: const Text('My Published Assets')),
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
                    final thumb = (d['images'] is List && (d['images'] as List).isNotEmpty) ? (d['images'] as List)[0] as String? : null;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(12),
                        leading: SizedBox(width: 72, height: 72, child: buildAssetImage(thumb, width: 72, height: 72)),
                        title: Text(d['title'] ?? d['name'] ?? 'Untitled', style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(d['category'] ?? ''),
                        trailing: TextButton(
                            onPressed: () async {
                              final pdf = pw.Document();
                              pdf.addPage(pw.Page(build: (ctx) => pw.Center(child: pw.Text('Ownership Certificate\n${d['title'] ?? d['name']}\nOwner: ${user.email}'))));
                              final dir = await getTemporaryDirectory();
                              final file = File('${dir.path}/cert_${id}.pdf');
                              await file.writeAsBytes(await pdf.save());
                              await Share.shareXFiles([XFile(file.path)], text: 'Certificate for ${d['title'] ?? d['name']}');
                            },
                            child: const Text('Cert')),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: id))),
                      ),
                    );
                  },
                );
              },
            ),
          );
        } else {
          // user purchased assets
          final q = db.collection('transactions').where('buyerUid', isEqualTo: user.uid).where('status', isEqualTo: 'completed');
          return Scaffold(
            appBar: AppBar(title: const Text('My Assets')),
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
                        final img = (asset['images'] is List && (asset['images'] as List).isNotEmpty) ? (asset['images'] as List)[0] as String? : null;
                        return ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: SizedBox(width: 72, height: 72, child: buildAssetImage(img, width: 72, height: 72)),
                          title: Text(asset['title'] ?? asset['name'] ?? 'Asset'),
                          subtitle: Text('PKR ${asset['price'] ?? 'N/A'}'),
                          trailing: IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: () async {
                            final pdf = pw.Document();
                            pdf.addPage(pw.Page(build: (ctx) => pw.Center(child: pw.Text('Ownership Certificate\n${asset['name']}\nOwner: ${user.email}'))));
                            final dir = await getTemporaryDirectory();
                            final file = File('${dir.path}/cert_${txn['assetId']}.pdf');
                            await file.writeAsBytes(await pdf.save());
                            await Share.shareXFiles([XFile(file.path)]);
                          }),
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: txn['assetId']))),
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

/// -------------------- TRANSACTIONS (ROLE-AWARE + CHAT) --------------------
class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Not logged in')));

    return FutureBuilder<String>(
      future: fetchCurrentRole(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final role = snap.data ?? 'user';

        late Query<Map<String, dynamic>> q;
        if (role.toLowerCase().contains('supplier')) {
          q = db.collection('transactions').where('sellerUid', isEqualTo: user.uid).orderBy('createdAt', descending: true);
        } else {
          q = db.collection('transactions').where('buyerUid', isEqualTo: user.uid).orderBy('createdAt', descending: true);
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Transactions')),
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

                  // Determine allowed actions: suppliers can approve/reject pending; when status is approved/completed allow chat
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
                            IconButton(icon: const Icon(Icons.check, color: Colors.green), onPressed: () => _updateStatus(id, 'approved')),
                            IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => _updateStatus(id, 'rejected')),
                          ],
                          if (allowChat) IconButton(icon: const Icon(Icons.chat_bubble_outline), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(transactionId: id)))),
                        ],
                      ),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: t['assetId']))),
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

/// -------------------- SIMPLE CHAT (per-transaction) --------------------
class ChatScreen extends StatefulWidget {
  final String transactionId;
  const ChatScreen({super.key, required this.transactionId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final txt = _msgCtrl.text.trim();
    final user = auth.currentUser;
    if (txt.isEmpty || user == null) return;
    final doc = db.collection('chats').doc(widget.transactionId).collection('messages').doc();
    await doc.set({
      'text': txt,
      'senderUid': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });
    _msgCtrl.clear();
    // scroll to bottom after small delay so stream can update
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatRef = db.collection('chats').doc(widget.transactionId).collection('messages').orderBy('createdAt', descending: false);
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: chatRef.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs;
              if (docs.isEmpty) return const Center(child: Text('No messages yet'));
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final m = docs[i].data();
                  final text = m['text'] ?? '';
                  final sender = m['senderUid'] ?? '';
                  final mine = sender == auth.currentUser?.uid;
                  return Align(
                    alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: mine ? Colors.green[200] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(text),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Expanded(child: TextField(controller: _msgCtrl, decoration: const InputDecoration(hintText: 'Type a message', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)))),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _send, child: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// -------------------- RELATED ITEMS --------------------
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
              final img = (d['images'] is List && (d['images'] as List).isNotEmpty) ? (d['images'] as List)[0] as String? : null;
              return GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: docs[i].id))),
                child: Container(
                  width: 160,
                  margin: const EdgeInsets.only(right: 8),
                  child: Column(children: [
                    Expanded(child: img != null ? buildAssetImage(img, width: double.infinity, height: double.infinity, fit: BoxFit.cover) : Container(color: Colors.grey[200], child: const Icon(Icons.image))),
                    const SizedBox(height: 6),
                    Text(d['title'] ?? d['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis)
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// -------------------- PDF VIEWER --------------------
class PDFViewerScreen extends StatelessWidget {
  final File file;
  const PDFViewerScreen({super.key, required this.file});
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Document')), body: PDFView(filePath: file.path));
  }
}

/// -------------------- FAVORITES (shared) --------------------
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Not logged in')));

    final q = db.collection('users').doc(user.uid).collection('favorites').orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
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
                  final img = (asset['images'] is List && (asset['images'] as List).isNotEmpty) ? (asset['images'] as List)[0] as String? : null;
                  return ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: SizedBox(width: 72, height: 72, child: buildAssetImage(img, width: 72, height: 72)),
                    title: Text(asset['title'] ?? asset['name'] ?? 'Asset'),
                    subtitle: Text('PKR ${asset['price'] ?? 'N/A'}'),
                    trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () {
                      db.collection('users').doc(user.uid).collection('favorites').doc(assetId).delete();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed from favorites')));
                    }),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: assetId))),
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

/// -------------------- NOTIFICATIONS (shared) --------------------
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Not logged in')));

    final q = db.collection('users').doc(user.uid).collection('notifications').orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
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

/// -------------------- SETTINGS (shared) --------------------
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
            'This will delete your Firebase account and (optionally) your user document. '
                'This requires recent login. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
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
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SwitchListTile(
            title: const Text('Dark mode'),
            subtitle: const Text('Save preference to your account'),
            value: _darkMode,
            onChanged: (v) => _setDarkMode(v),
          ),
          const SizedBox(height: 12),
          ListTile(title: const Text('Help & Support'), trailing: const Icon(Icons.open_in_new), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpScreen()))),
          ListTile(title: const Text('Terms & Privacy'), trailing: const Icon(Icons.open_in_new), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsScreen()))),
          const SizedBox(height: 20),
          _loading ? const Center(child: CircularProgressIndicator()) : ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: _deleteAccount, child: const Text('Delete account')),
        ]),
      ),
    );
  }
}

/// -------------------- HELP & TERMS --------------------
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Help & Support')), body: Padding(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
      Text('Contact', style: TextStyle(fontWeight: FontWeight.bold)),
      SizedBox(height: 8),
      Text('For support, contact: support@example.com'),
      SizedBox(height: 16),
      Text('FAQ', style: TextStyle(fontWeight: FontWeight.bold)),
      SizedBox(height: 8),
      Text('• How to buy?\n• How to sell?\n• How to verify assets?'),
    ])));
  }
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Terms & Privacy')), body: SingleChildScrollView(padding: const EdgeInsets.all(16.0), child: const Text('Your terms and privacy policy content goes here. Replace this placeholder with your real legal text.')));
  }
}

/// -------------------- PROFILE (role-aware, extended with photo & reset password) --------------------
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _uploading = false;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _userDocStream;

  @override
  void initState() {
    super.initState();
    final user = auth.currentUser;
    if (user != null) _userDocStream = db.collection('users').doc(user.uid).snapshots();
  }

  Future<void> _pickImage(ImageSource src) async {
    try {
      final permission = src == ImageSource.camera ? Permission.camera : Permission.photos;
      final status = await permission.request();
      if (!status.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission not granted')));
        return;
      }

      final XFile? file = await _picker.pickImage(source: src, maxWidth: 1200, maxHeight: 1200, imageQuality: 80);
      if (file == null) return;

      setState(() => _uploading = true);
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);

      final user = auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      await db.collection('users').doc(user.uid).set({'profilePhotoBase64': b64}, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile photo updated')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removePhoto() async {
    final user = auth.currentUser;
    if (user == null) return;
    await db.collection('users').doc(user.uid).update({'profilePhotoBase64': FieldValue.delete()});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile photo removed')));
  }

  void _showPickOptions() {
    showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Wrap(children: [
      ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Take Photo'), onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.camera); }),
      ListTile(leading: const Icon(Icons.photo_library), title: const Text('Pick From Gallery'), onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); }),
      ListTile(leading: const Icon(Icons.delete_forever), title: const Text('Remove Photo'), onTap: () { Navigator.pop(ctx); _removePhoto(); }),
      ListTile(leading: const Icon(Icons.close), title: const Text('Cancel'), onTap: () => Navigator.pop(ctx)),
    ])));
  }

  Widget _buildAvatar(String? base64data, String? email) {
    if (_uploading) return const CircleAvatar(radius: 40, child: CircularProgressIndicator());
    if (base64data != null && base64data.isNotEmpty) {
      try {
        final bytes = base64Decode(base64data);
        return CircleAvatar(radius: 40, backgroundImage: MemoryImage(bytes));
      } catch (_) {}
    }
    if (email != null && email.isNotEmpty) return CircleAvatar(radius: 40, child: Text(email.substring(0, 1).toUpperCase()));
    return const CircleAvatar(radius: 40, child: Icon(Icons.person));
  }

  Future<void> _sendResetPasswordEmail() async {
    final user = auth.currentUser;
    if (user == null) return;
    try {
      await auth.sendPasswordResetEmail(email: user.email ?? '');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reset password email sent')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error sending reset email: $e')));
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
        final b64 = data['profilePhotoBase64'] as String? ?? '';
        final displayEmail = user.email ?? '';
        final name = data['name'] ?? user.displayName ?? '';
        final role = data['role'] ?? 'user';

        return Scaffold(
          appBar: AppBar(title: const Text('Profile')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              GestureDetector(
                onTap: _showPickOptions,
                child: Stack(alignment: Alignment.bottomRight, children: [
                  _buildAvatar(b64, displayEmail),
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: _showPickOptions,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: const Icon(Icons.edit, size: 18),
                        ),
                      ),
                    ),
                  )
                ]),
              ),
              const SizedBox(height: 12),
              Text(name.isNotEmpty ? name : displayEmail, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(displayEmail),
              const SizedBox(height: 12),
              Text('Role: $role'),
              const SizedBox(height: 20),

              ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesScreen())), icon: const Icon(Icons.favorite), label: const Text('Favorites')),
              const SizedBox(height: 8),
              ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())), icon: const Icon(Icons.notifications), label: const Text('Notifications')),
              const SizedBox(height: 8),
              ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())), icon: const Icon(Icons.settings), label: const Text('Settings')),
              const SizedBox(height: 12),

              // Reset password button
              ElevatedButton.icon(onPressed: _sendResetPasswordEmail, icon: const Icon(Icons.lock_reset), label: const Text('Reset Password')),
              const SizedBox(height: 20),

              // Transactions - show Transactions for supplier too (role-aware)
              ElevatedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TransactionsScreen())),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Transactions'),
              ),
              const SizedBox(height: 12),

              ElevatedButton.icon(
                onPressed: () async {
                  await auth.signOut();
                  if (!context.mounted) return;
                  Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
                },
                icon: const Icon(Icons.logout),
                label: const Text('Logout'),
              ),
            ]),
          ),
        );
      },
    );
  }
}
