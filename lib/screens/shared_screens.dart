// lib/screens/shared_screens.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:image/image.dart' as img;

import 'auth_screens.dart';
import 'chatbot_screen.dart';

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;
final _uuid = const Uuid();

/// Helper: fetch current role
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

/// Utility: try decode base64
Uint8List? _tryBase64Decode(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    final cleaned = s.startsWith('data:') ? s.split(',').last : s;
    return base64Decode(cleaned);
  } catch (_) {
    return null;
  }
}

/// Utility: build image from base64 or URL
Widget buildAssetImage(String? s, {BoxFit fit = BoxFit.cover, double width = 80, double height = 80}) {
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

/// Asset Detail Screen (Bug 5 Fix: Display owner name instead of ID)
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

    // Bug 5 Fix: Fetch owner name
    String ownerName = 'Unknown';
    if (assetSnap.exists) {
      final ownerId = assetSnap.data()?['ownerId'] ?? assetSnap.data()?['ownerUid'];
      if (ownerId != null) {
        try {
          final ownerSnap = await db.collection('users').doc(ownerId).get();
          if (ownerSnap.exists) {
            ownerName = ownerSnap.data()?['name'] ?? ownerSnap.data()?['email'] ?? 'Unknown';
          }
        } catch (_) {}
      }
    }

    return {'assetSnap': assetSnap, 'role': role, 'ownerName': ownerName};
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic?>>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final assetSnap = snapshot.data!['assetSnap'] as DocumentSnapshot<Map<String, dynamic>>;
          final role = (snapshot.data!['role'] as String?) ?? 'user';
          final ownerName = (snapshot.data!['ownerName'] as String?) ?? 'Unknown';

          if (!assetSnap.exists) return const Center(child: Text('Asset not found'));
          final data = assetSnap.data() ?? <String, dynamic>{};

          db.collection('assets').doc(widget.assetId).update({'views': FieldValue.increment(1)}).catchError((_) {});

          final images = (data['images'] as List?)?.cast<String>() ?? [];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                  Container(
                    height: 220,
                    color: Colors.grey[200],
                    child: const Center(child: Icon(Icons.image, size: 80)),
                  ),
                const SizedBox(height: 12),
                Text(
                  data['title'] ?? data['name'] ?? '',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'PKR ${data['price'] ?? 0}',
                  style: const TextStyle(fontSize: 18, color: Colors.green),
                ),
                const SizedBox(height: 12),
                Text(data['description'] ?? ''),
                const SizedBox(height: 12),

                // Bug 5 Fix: Display owner name
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Owner'),
                  subtitle: Text(ownerName),
                  leading: const SizedBox(width: 56, height: 56, child: Icon(Icons.person)),
                ),

                if (data['category'] == 'land') ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Plot Area'),
                    subtitle: Text('${data['plotArea'] ?? '—'}'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('City'),
                    subtitle: Text(data['city'] ?? '—'),
                  ),
                ],
                if (data['category'] == 'electronics') ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Brand'),
                    subtitle: Text(data['brand'] ?? '—'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Condition'),
                    subtitle: Text(data['condition'] ?? '—'),
                  ),
                ],
                const SizedBox(height: 12),

                if (data['documents'] is List && (data['documents'] as List).isNotEmpty) ...[
                  const Text('Documents', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  ...((data['documents'] as List).map((d) {
                    final title = (d is Map && d['name'] != null) ? d['name'] : 'Document';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(title.toString()),
                      trailing: const Icon(Icons.description),
                    );
                  }).toList()),
                  const SizedBox(height: 12),
                ],

                Center(child: QrImageView(data: 'asset://${widget.assetId}', size: 140)),
                const SizedBox(height: 12),

                if (!role.toLowerCase().contains('supplier')) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _requestToBuy(
                            context,
                            widget.assetId,
                            data['ownerId'] ?? data['ownerUid'],
                          ),
                          icon: const Icon(Icons.shopping_cart),
                          label: const Text('Request to Buy'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _toggleFavorite(context, widget.assetId),
                        icon: const Icon(Icons.favorite_border),
                        label: const Text('Favorite'),
                      ),
                    ],
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _verifyAsset(context, widget.assetId),
                          icon: const Icon(Icons.verified),
                          label: const Text('Verify Asset'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _transferOwnership(context, widget.assetId),
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Transfer'),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 18),
                const Text('Related Items', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                RelatedItemsList(type: data['category'] ?? data['type'], city: data['city']),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        mini: true,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChatbotScreen()),
          );
        },
        child: const Icon(Icons.chat_bubble_outline),
      ),
    );
  }

  Future<void> _requestToBuy(BuildContext ctx, String assetId, String? sellerId) async {
    final user = auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please login to request')));
      return;
    }

    final existing = await db
        .collection('transactions')
        .where('assetId', isEqualTo: assetId)
        .where('buyerUid', isEqualTo: user.uid)
        .where('status', whereIn: ['pending', 'approved', 'completed'])
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('You already have a request for this asset')),
      );
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

    await db.collection('chats').doc(txId).set({
      'transactionId': txId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Request Sent')));
    }
  }

  Future<void> _verifyAsset(BuildContext ctx, String assetId) async {
    await db.collection('assets').doc(assetId).update({'verified': true});
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Asset marked verified')));
    }
  }

  Future<void> _transferOwnership(BuildContext ctx, String assetId) async {
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        const SnackBar(content: Text('Transfer ownership - not implemented')),
      );
    }
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
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Removed from favorites')));
      }
    } else {
      await favRef.set({'assetId': assetId, 'createdAt': FieldValue.serverTimestamp()});
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Added to favorites')));
      }
    }
  }
}

/// QR Scanner Screen
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Asset not found')));
        }
        return;
      }

      final role = await fetchCurrentRole();
      if (role.toLowerCase().contains('supplier')) {
        await db.collection('assets').doc(id).update({'verifications': FieldValue.increment(1)});
      }

      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: id)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Scan error: $e')));
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final code = capture.barcodes.first.rawValue;
              if (code != null) _handleCode(code);
            },
          ),
          if (_processing)
            const Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
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
                              icon: const Icon(Icons.chat_bubble_outline),
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => ChatScreen(transactionId: id)),
                              ),
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

/// Chat Screen
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
    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatRef = db
        .collection('chats')
        .doc(widget.transactionId)
        .collection('messages')
        .orderBy('createdAt', descending: false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
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
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Type a message',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: _send, child: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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