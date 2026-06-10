// lib/screens/shared_screens.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
// import 'auth_screens.dart';
import 'asset_detail_screen.dart';
import 'chat_screen.dart';
import 'transfer_screen.dart';
import '../blockchain/blockchain_service.dart';
import '../theme.dart';

// Brand colors removed - using AppTheme

// ─────────────────────────────────────────────────────────────────────────────
// GLOBAL HELPERS
// ─────────────────────────────────────────────────────────────────────────────

String? _cachedRole; // 🚀 Speed Optimization

/// Fetch current user role
Future<String> fetchCurrentRole() async {
  try {
    final user = auth.currentUser;
    if (user == null) return '';

    // Return cached role if available
    if (_cachedRole != null) return _cachedRole!;

    final snap = await db.collection('users').doc(user.uid).get();
    if (!snap.exists) return ''; // 🚨 Fix: Don't default to 'user' if doc is missing

    final r = snap.data()?['role'] as String?;
    if (r == null || r.isEmpty) return 'user';

    _cachedRole = r; // Cache for next call
    return r;
  } catch (_) {
    return '';
  }
}

/// Reset role cache (call on logout)
void clearRoleCache() {
  _cachedRole = null;
}

/// Decode base64 image safely
Uint8List? tryBase64Decode(String? s) {
  if (s == null || s.isEmpty) return null;
  try {
    final cleaned = s.startsWith('data:') ? s.split(',').last : s;
    return base64Decode(cleaned);
  } catch (_) {
    return null;
  }
}

/// Shared helper to add a transaction to Firestore
Future<void> addTransaction({
  required String userId,
  required String type,
  required String title,
  required String toAddress,
  String value = '0',
  String gas   = '0',
}) async {
  final txHash = const Uuid().v4();
  final time   = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

  await FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('transactions')
      .add({
    'type'    : type,
    'title'   : title,
    'to'      : toAddress,
    'value'   : value,
    'gas'     : gas,
    'hash'    : txHash,
    'time'    : time,
  });
}

/// Build asset image from base64 or URL
Widget buildAssetImage(
    String? s, {
      BoxFit  fit    = BoxFit.cover,
      double  width  = 80,
      double  height = 80,
    }) {
  if (s == null || s.isEmpty) {
    return Container(
      width: width, height: height,
      color: AppTheme.primaryStart.withOpacity(0.05),
      child: Icon(Icons.image, size: 36, color: AppTheme.textMid),
    );
  }

  if (s.startsWith('http://') || s.startsWith('https://')) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        s, width: width, height: height, fit: fit,
        errorBuilder: (_, __, ___) => Container(
          width: width, height: height,
          color: AppTheme.primaryStart.withOpacity(0.05),
          child: Icon(Icons.broken_image, color: AppTheme.textMid),
        ),
      ),
    );
  }

  final bytes = tryBase64Decode(s);
  if (bytes != null) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        bytes, width: width, height: height, fit: fit,
        errorBuilder: (_, __, ___) => Container(
          width: width, height: height,
          color: AppTheme.primaryStart.withOpacity(0.05),
          child: Icon(Icons.broken_image, color: AppTheme.textMid),
        ),
      ),
    );
  }

  return Container(
    width: width, height: height,
    color: AppTheme.primaryStart.withOpacity(0.05),
    child: Icon(Icons.image, color: AppTheme.textMid),
  );
}

/// Get document icon
Widget getDocumentIcon(String type) {
  switch (type.toLowerCase()) {
    case 'pdf':
      return const Icon(Icons.picture_as_pdf, color: Colors.red);
    case 'jpg':
    case 'jpeg':
    case 'png':
      return const Icon(Icons.image, color: AppTheme.accent);
    case 'doc':
    case 'docx':
      return const Icon(Icons.description, color: AppTheme.accent);
    default:
      return const Icon(Icons.insert_drive_file);
  }
}

/// Format file size
String formatFileSize(int bytes) {
  if (bytes < 1024)    return '$bytes B';
  if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1048576).toStringAsFixed(1)} MB';
}

/// Helper chip widget used in asset list cards
Widget assetDetailChip(IconData icon, String label, {Color? color}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Icon(icon, size: 14, color: color ?? Colors.grey[600]),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: AppTheme.body(12, color: color ?? AppTheme.textMid),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TRANSACTIONS SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isBuyingMode = true;
  bool _isSupplier   = false;
  bool _loadingRole  = true;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _uid = auth.currentUser?.uid;
    _resolveRole();
  }

  Future<void> _resolveRole() async {
    final role = await fetchCurrentRole();
    if (!mounted) return;
    setState(() {
      _isSupplier   = role.toLowerCase().contains('supplier');
      _isBuyingMode = !_isSupplier;
      _loadingRole  = false;
    });
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
      case 'accepted':
      case 'approved':  return AppTheme.accent;
      case 'rejected':  return AppTheme.error;
      case 'completed': return AppTheme.accent;
      default:          return Colors.orange;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'accepted':
      case 'approved':  return Icons.check_circle;
      case 'rejected':  return Icons.cancel;
      case 'completed': return Icons.done_all;
      default:          return Icons.hourglass_empty;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }
    if (_loadingRole) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isSellingMode = !_isBuyingMode;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.chevron_left, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isBuyingMode ? 'My Purchases' : 'My Sales',
          style: AppTheme.heading(17, color: AppTheme.textPrimary),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: () => setState(() => _isBuyingMode = !_isBuyingMode),
              icon: Icon(
                _isBuyingMode ? Icons.sell : Icons.shopping_cart,
                size: 16,
                color: AppTheme.primaryStart,
              ),
              label: Text(
                _isBuyingMode ? 'Switch to Selling' : 'Switch to Buying',
                style: AppTheme.body(12, color: AppTheme.primaryStart),
              ),
              style: TextButton.styleFrom(foregroundColor: AppTheme.primaryStart),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.primaryStart,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: AppTheme.primaryStart,
              unselectedLabelColor: AppTheme.primaryStart.withOpacity(0.45),
              labelStyle: AppTheme.heading(12, color: AppTheme.primaryStart),
              unselectedLabelStyle: AppTheme.body(12, color: AppTheme.primaryStart.withOpacity(0.45)),
              dividerColor: const Color(0xFFCAE8E8),
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                _buildTab(Icons.hourglass_empty_rounded, 'Pending'),
                _buildTab(Icons.check_circle_outline,    'Accepted'),
                _buildTab(Icons.pie_chart_outline,       'Fractions'),
                _buildTab(Icons.cancel_outlined,         'Rejected'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTransactionList(_uid!, isSellingMode, 'pending', context),
          _buildTransactionList(_uid!, isSellingMode, 'approved', context),
          _buildFractionRequestsTab(_uid!, isSellingMode, context),
          _buildTransactionList(_uid!, isSellingMode, 'rejected', context),
        ],
      ),
    );
  }

  Tab _buildTab(IconData icon, String label) {
    return Tab(
      height: 46,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      ),
    );
  }

  // ── Fraction Requests Tab ─────────────────────────────────────────────────
  Widget _buildFractionRequestsTab(
      String uid, bool isSupplier, BuildContext context) {
    final query = isSupplier
        ? db.collection('fraction_requests')
        .where('sellerUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        : db.collection('fraction_requests')
        .where('buyerUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: ValueKey('fractions_${uid}_$isSupplier'),
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData)  return const Center(child: CircularProgressIndicator());

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.pie_chart_outline, size: 60, color: AppTheme.primaryStart.withOpacity(0.15)),
                const SizedBox(height: 12),
                Text(
                  isSupplier
                      ? 'No fraction requests received'
                      : 'You have not requested any fractions',
                  style: AppTheme.body(16, color: AppTheme.textMid),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final r              = docs[i].data();
            final docId          = docs[i].id;
            final status         = r['status'] ?? 'pending';
            final fractionsReq   = r['fractionsRequested'] ?? 0;
            final totalCostWei   = r['totalCost'] ?? '0';
            final buyerUid       = r['buyerUid']  ?? '';
            final sellerUid      = r['sellerUid'] ?? '';
            final assetId        = r['assetId']   ?? '';
            final transactionId  = (r['transactionId'] ?? '').toString().trim();
            final ts             = r['createdAt'] as Timestamp?;
            final date = ts != null
                ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}'
                : '—';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: _statusColor(status).withOpacity(0.3),
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
                        _statusBadge(status),
                        Text(date,
                            style: AppTheme.body(12, color: AppTheme.textMid)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<DocumentSnapshot>(
                      future: db.collection('assets').doc(assetId).get(),
                      builder: (ctx, assetSnap) {
                        final data = assetSnap.hasData && assetSnap.data!.exists
                            ? assetSnap.data!.data() as Map<String, dynamic>?
                            : null;
                        final title = data?['title'] as String? ?? 'Asset';
                        return Row(children: [
                          const Icon(Icons.home_work_outlined, size: 16, color: AppTheme.primaryStart),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(title,
                                style: AppTheme.heading(15, color: AppTheme.textPrimary),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]);
                      },
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.pie_chart_outline, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '$fractionsReq fractions  •  ${_weiDisplay(totalCostWei)} MATIC',
                            style: AppTheme.body(13, color: AppTheme.textMid),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    FutureBuilder<DocumentSnapshot>(
                      future: db
                          .collection('users')
                          .doc(isSupplier ? buyerUid : sellerUid)
                          .get(),
                      builder: (ctx, userSnap) {
                        final userData = userSnap.hasData && userSnap.data!.exists
                            ? userSnap.data!.data() as Map<String, dynamic>?
                            : null;
                        final name = userData?['name'] as String? ?? '—';
                        return Row(children: [
                          Icon(
                            isSupplier ? Icons.person_outline : Icons.store_outlined,
                            size: 14, color: Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              isSupplier ? 'Buyer: $name' : 'Seller: $name',
                              style: AppTheme.body(13, color: AppTheme.textMid),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]);
                      },
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.visibility_outlined, size: 16),
                            label: const Text('View'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.accent,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => AssetDetailScreen(assetId: assetId)),
                            ),
                          ),
                          if (status == 'approved')
                            TextButton.icon(
                              icon: const Icon(Icons.chat_outlined, size: 16),
                              label: const Text('Chat'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.accent,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () => _openFractionChat(
                                context,
                                chatId: transactionId.isNotEmpty ? transactionId : docId,
                                assetId: assetId,
                                buyerUid: buyerUid,
                                sellerUid: sellerUid,
                              ),
                            ),
                          if (isSupplier && status == 'pending')
                            TextButton.icon(
                              icon: const Icon(Icons.check, size: 16),
                              label: const Text('Approve'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.accent,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () => _updateFractionRequest(
                                  context, docId, transactionId, 'approved'),
                            ),
                          if (isSupplier && status == 'pending')
                            TextButton.icon(
                              icon: const Icon(Icons.close, size: 16),
                              label: const Text('Reject'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () => _updateFractionRequest(
                                  context, docId, transactionId, 'rejected'),
                            ),
                          if (status == 'completed')
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width - 96,
                              ),
                              child: _statusChip('✅ Transfer complete'),
                            ),
                        ],
                      ),
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

  // ── Regular transaction list ───────────────────────────────────────────────
  Widget _buildTransactionList(
      String uid, bool isSupplier, String status, BuildContext context) {
    Query<Map<String, dynamic>> query = db
        .collection('transactions')
        .where(isSupplier ? 'sellerUid' : 'buyerUid', isEqualTo: uid);

    query = status == 'approved'
        ? query.where('status', whereIn: ['approved', 'accepted'])
        : query.where('status', isEqualTo: status);

    query = query.orderBy('createdAt', descending: true);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      key: ValueKey('transactions_${uid}_${isSupplier}_$status'),
      stream: query.snapshots(),
      builder: (context, snap2) {
        if (snap2.hasError) return Center(child: Text('Error: ${snap2.error}'));
        if (!snap2.hasData)  return const Center(child: CircularProgressIndicator());

        final docs = snap2.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(_statusIcon(status), size: 60, color: AppTheme.primaryStart.withOpacity(0.15)),
                const SizedBox(height: 12),
                Text('No $status transactions',
                    style: AppTheme.body(16, color: AppTheme.textMid)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final t        = docs[i].data();
            final id       = docs[i].id;
            final ts       = t['createdAt'] as Timestamp?;
            final date     = ts != null
                ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}'
                : '—';
            final txStatus = (t['status'] ?? '').toString();
            final allowChat = txStatus == 'approved' || txStatus == 'accepted';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: _statusColor(txStatus).withOpacity(0.3)),
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
                            style: AppTheme.body(12, color: AppTheme.textMid)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<DocumentSnapshot>(
                      future: db.collection('assets').doc(t['assetId']).get(),
                      builder: (context, assetSnap) {
                        String title = 'Loading...';
                        if (assetSnap.hasData && assetSnap.data!.exists) {
                          final data = assetSnap.data!.data() as Map<String, dynamic>?;
                          title = data?['title'] as String? ?? 'Unnamed Asset';
                        } else if (assetSnap.hasError) {
                          title = 'Asset ID: ${t['assetId'] ?? '—'}';
                        }
                        return Row(
                          children: [
                            Icon(Icons.inventory_2_outlined,
                                size: 16, color: AppTheme.textMid),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(title,
                                  style: AppTheme.heading(15, color: AppTheme.textPrimary),
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
                          isSupplier ? Icons.person_outline : Icons.store_outlined,
                          size: 14, color: AppTheme.textMid,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isSupplier
                              ? 'Buyer: ${_shorten(t['buyerUid'] ?? '—')}'
                              : 'Seller: ${_shorten(t['sellerUid'] ?? '—')}',
                          style: AppTheme.body(13, color: AppTheme.textMid),
                        ),
                      ],
                    ),
                    if (t['requestType'] == 'rental') ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.calendar_month_outlined, size: 14, color: AppTheme.textMid),
                        const SizedBox(width: 6),
                        Text('Monthly Rent: ${t['rentalFee'] ?? t['amount']} MATIC',
                            style: AppTheme.heading(13, color: AppTheme.primaryStart)),
                      ]),
                    ] else if (t['price'] != null) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        Text('${t['price']}',
                            style: AppTheme.body(13, color: AppTheme.textMid)),
                      ]),
                    ],
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.visibility_outlined, size: 16),
                          label: const Text('View'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.accent,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  AssetDetailScreen(assetId: t['assetId']),
                            ),
                          ),
                        ),
                        if (allowChat) ...[
                          const SizedBox(width: 4),
                          TextButton.icon(
                            icon: const Icon(Icons.chat_outlined, size: 16),
                            label: const Text('Chat'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.accent,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () async {
                              final myUid = auth.currentUser?.uid;
                              if (myUid == null) return;
                              final otherUid = isSupplier
                                  ? t['buyerUid']
                                  : t['sellerUid'];
                              await db.collection('chats').doc(id).set({
                                'participants'   : [myUid, otherUid],
                                'assetId'        : t['assetId'],
                                'assetType'      : t['category'] ?? 'electronics',
                                'sellerUid'      : isSupplier ? myUid  : otherUid,
                                'buyerUid'       : isSupplier ? otherUid : myUid,
                                'lastMessage'    : '',
                                'lastMessageTime': FieldValue.serverTimestamp(),
                              }, SetOptions(merge: true));
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                      chatId: id, otherUserId: otherUid),
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
                              foregroundColor: AppTheme.accent,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () {
                              if (t['requestType'] == 'rental') {
                                _acceptRentTransaction(context, id, t);
                              } else {
                                _updateStatus(id, 'approved');
                              }
                            },
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.close, size: 16),
                            label: const Text('Reject'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () {
                              if (t['requestType'] == 'rental') {
                                _updateRentRequestStatus(id, 'rejected');
                              } else {
                                _updateStatus(id, 'rejected');
                              }
                            },
                          ),
                        ],
                        if (!isSupplier &&
                            (txStatus == 'approved' || txStatus == 'pending')) ...[
                          const SizedBox(width: 4),
                          TextButton.icon(
                            icon: const Icon(Icons.account_balance_wallet, size: 16),
                            label: const Text('My Wallet'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.accent,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () {
                              final category = t['category'] ?? 'electronics';
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BuyerOwnershipAcceptScreen(
                                    assetId      : t['assetId'] ?? '',
                                    transactionId: id,
                                    sellerName   : _shorten(t['sellerUid'] ?? '—'),
                                    assetType    : category == 'land'
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
                            icon: const Icon(Icons.move_to_inbox, size: 16),
                            label: const Text('Ownership'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.accent,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () {
                              final category = t['category'] ?? 'electronics';
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BuyerOwnershipAcceptScreen(
                                    assetId      : t['assetId'] ?? '',
                                    transactionId: id,
                                    sellerName   : _shorten(t['sellerUid'] ?? '—'),
                                    assetType    : category == 'land'
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

  // ── Shared widgets ────────────────────────────────────────────────────────

  Widget _statusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor(status).withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(_statusIcon(status), size: 14, color: _statusColor(status)),
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

  Widget _statusChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryStart.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
      ),
      child: Text(
        label,
        softWrap: true,
        style: AppTheme.body(12, color: AppTheme.accent),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _openFractionChat(
      BuildContext context, {
        required String chatId,
        required String assetId,
        required String buyerUid,
        required String sellerUid,
      }) async {
    final myUid = auth.currentUser?.uid;
    if (myUid == null) return;

    final otherUid = myUid == sellerUid ? buyerUid : sellerUid;
    await db.collection('chats').doc(chatId).set({
      'transactionId': chatId,
      'participants': [buyerUid, sellerUid],
      'assetId': assetId,
      'assetType': 'land',
      'sellerUid': sellerUid,
      'buyerUid': buyerUid,
      'lastMessage': '',
      'lastMessageTime': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(chatId: chatId, otherUserId: otherUid),
      ),
    );
  }

  Future<String?> _existingTransactionId(String transactionId) async {
    final trimmedId = transactionId.trim();
    if (trimmedId.isEmpty) return null;

    final txSnap = await db.collection('transactions').doc(trimmedId).get();
    if (!txSnap.exists) {
      debugPrint(
        'Skipping missing transaction update for fraction request: $trimmedId',
      );
      return null;
    }
    return trimmedId;
  }

  Future<void> _updateFractionRequest(
      BuildContext context,
      String fractionRequestId,
      String transactionId,
      String newStatus,
      ) async {
    final existingTransactionId = await _existingTransactionId(transactionId);
    final batch = db.batch();
    batch.update(
      db.collection('fraction_requests').doc(fractionRequestId),
      {'status': newStatus, 'respondedAt': FieldValue.serverTimestamp()},
    );
    if (existingTransactionId != null) {
      batch.update(
        db.collection('transactions').doc(existingTransactionId),
        {'status': newStatus == 'approved' ? 'approved' : 'rejected'},
      );
    }
    await batch.commit();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newStatus == 'approved'
            ? '✅ Request approved'
            : '❌ Request rejected'),
        backgroundColor:
        newStatus == 'approved' ? AppTheme.accent : AppTheme.error,
      ));
    }
  }

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

    final assetDoc  = await db.collection('assets').doc(assetId).get();
    final assetData = assetDoc.data() ?? {};
    final assetPrice = assetData['price']?.toString() ?? '0';

    final buyerDoc  = await db.collection('users').doc(buyerUid).get();
    final buyerName = buyerDoc.data()?['name'] ?? 'Buyer';

    final blockchainPropertyId =
    propertyId is int ? propertyId : int.tryParse(propertyId.toString()) ?? 0;

    if (!context.mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TransferScreen(
          assetId      : assetId,
          assetType    : AssetType.land,
          transactionId: transactionId,
          buyerUid     : buyerUid,
          sellerUid    : sellerUid,
          propertyId   : blockchainPropertyId,
          fractionAmount: fractionsRequested,
          assetPrice   : assetPrice,
          buyerName    : buyerName,
        ),
      ),
    );

    if (result == true) {
      final existingTransactionId = await _existingTransactionId(transactionId);
      final batch = db.batch();
      batch.update(
        db.collection('fraction_requests').doc(fractionRequestId),
        {'status': 'completed', 'completedAt': FieldValue.serverTimestamp()},
      );
      if (existingTransactionId != null) {
        batch.update(
          db.collection('transactions').doc(existingTransactionId),
          {'status': 'completed', 'completedAt': FieldValue.serverTimestamp()},
        );
      }
      await batch.commit();

      await addTransaction(
        userId: sellerUid, type: 'received',
        title: assetData['title'] ?? 'Asset',
        toAddress: buyerUid, value: assetPrice,
      );
      await addTransaction(
        userId: buyerUid, type: 'nft',
        title: assetData['title'] ?? 'Asset',
        toAddress: sellerUid,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Fraction transfer completed successfully!'),
          backgroundColor: AppTheme.accent,
        ));
      }
    }
  }

  Future<void> _acceptRentTransaction(BuildContext context, String transactionId, Map<String, dynamic> t) async {
    final assetId = t['assetId'];
    final propertyId = t['blockchainPropertyId'];

    if (propertyId == null) return;

    try {
      final service = BlockchainServiceEnhanced();
      await service.init();

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Confirming on blockchain...')));

      final txHash = await service.acceptLandRentRequest(propertyId is int ? propertyId : int.parse(propertyId.toString()));
      if (txHash != null) {
        final ok = await service.waitForConfirmation(txHash);
        if (ok) {
          final batch = db.batch();
          batch.update(db.collection('transactions').doc(transactionId), {'status': 'approved'});

          // Fetch property to get current pending tenant address
          final prop = await service.getLandProperty(propertyId is int ? propertyId : int.parse(propertyId.toString()));

          batch.update(db.collection('assets').doc(assetId), {
            'isForRent': false,
            'currentTenant': t['buyerUid'],
            'currentTenantAddress': prop?['pendingTenant'] ?? '',
          });

          await batch.commit();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Rent request approved!'), backgroundColor: AppTheme.accent));
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error));
      }
    }
  }

  Future<void> _updateRentRequestStatus(String id, String status) async {
    final batch = db.batch();
    batch.update(db.collection('transactions').doc(id), {'status': status});
    await batch.commit();
  }

  String _shorten(String id) {
    if (id.length <= 10) return id;
    return '${id.substring(0, 6)}...${id.substring(id.length - 4)}';
  }

  String _weiDisplay(String weiStr) {
    try {
      final wei   = BigInt.tryParse(weiStr) ?? BigInt.zero;
      final ether = wei / BigInt.from(10).pow(18);
      return ether.toStringAsFixed(4);
    } catch (_) {
      return '—';
    }
  }
}
