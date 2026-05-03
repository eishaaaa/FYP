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
// TRANSACTIONS SCREEN  (drop-in replacement inside shared_screens.dart)
// ─────────────────────────────────────────────────────────────────────────────
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool? _isBuyingMode;

  @override
  void initState() {
    super.initState();
    // 5 tabs: Pending | Accepted | Fractions | Rent Requests | Rejected
    _tabController = TabController(length: 5, vsync: this);
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
      case 'approved':  return AppTheme.accent;
      case 'rejected':  return AppTheme.error;
      case 'completed': return AppTheme.accent;
      case 'active':    return Colors.green;
      case 'ended':     return Colors.grey;
      default:          return Colors.orange;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'approved':  return Icons.check_circle;
      case 'rejected':  return Icons.cancel;
      case 'completed': return Icons.done_all;
      case 'active':    return Icons.key_rounded;
      case 'ended':     return Icons.meeting_room_outlined;
      default:          return Icons.hourglass_empty;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    return FutureBuilder<String>(
      future: fetchCurrentRole(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final role       = snap.data ?? 'user';
        final isSupplier = role.toLowerCase().contains('supplier');
        _isBuyingMode ??= !isSupplier;

        return Scaffold(
          backgroundColor: const Color(0xFFF5F7FA),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            automaticallyImplyLeading: false,
            title: Text(
              _isBuyingMode! ? 'My Purchases' : 'My Sales',
              style: const TextStyle(
                  color: Color(0xFF1A1A2E),
                  fontSize: 17,
                  fontWeight: FontWeight.w600),
            ),
            leading: IconButton(
              icon: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: const Color(0xFFF0F4F4),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.chevron_left_rounded,
                    color: Color(0xFF1A1A2E), size: 24),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed: () =>
                      setState(() => _isBuyingMode = !_isBuyingMode!),
                  icon: Icon(
                      _isBuyingMode! ? Icons.sell : Icons.shopping_cart,
                      size: 18,
                      color: Colors.black),
                  label: Text(
                    _isBuyingMode! ? 'Switch to Selling' : 'Switch to Buying',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.black),
                  ),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: AppTheme.primaryStart,
              indicatorWeight: 3,
              labelColor: AppTheme.primaryStart,
              unselectedLabelColor: Colors.grey,
              labelStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 12),
              isScrollable: true,
              tabs: const [
                Tab(
                  child: Row(children: [
                    Icon(Icons.hourglass_empty, size: 15),
                    SizedBox(width: 4),
                    Text('Pending'),
                  ]),
                ),
                Tab(
                  child: Row(children: [
                    Icon(Icons.check_circle, size: 15),
                    SizedBox(width: 4),
                    Text('Accepted'),
                  ]),
                ),
                Tab(
                  child: Row(children: [
                    Icon(Icons.pie_chart, size: 15),
                    SizedBox(width: 4),
                    Text('Fractions'),
                  ]),
                ),
                Tab(
                  child: Row(children: [
                    Icon(Icons.key_rounded, size: 15),
                    SizedBox(width: 4),
                    Text('Rent Requests'),
                  ]),
                ),
                Tab(
                  child: Row(children: [
                    Icon(Icons.cancel, size: 15),
                    SizedBox(width: 4),
                    Text('Rejected'),
                  ]),
                ),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildTransactionList(
                  user.uid, isSupplier && !_isBuyingMode!, 'pending', context),
              _buildTransactionList(
                  user.uid, isSupplier && !_isBuyingMode!, 'approved', context),
              _buildFractionRequestsTab(
                  user.uid, isSupplier && !_isBuyingMode!, context),
              _buildRentRequestsTab(
                  user.uid, isSupplier && !_isBuyingMode!, context),
              _buildTransactionList(
                  user.uid, isSupplier && !_isBuyingMode!, 'rejected', context),
            ],
          ),
        );
      },
    );
  }

  // ── RENT REQUESTS TAB ─────────────────────────────────────────────────────
  Widget _buildRentRequestsTab(
      String uid, bool isSupplier, BuildContext context) {
    // Suppliers see requests where they are the asset owner (sellerUid).
    // Tenants/buyers see requests they sent (buyerUid).
   // AFTER — no orderBy, avoids composite index requirement
final query = isSupplier
    ? db
        .collection('transactions')
        .where('sellerUid', isEqualTo: uid)
        .where('requestType', isEqualTo: 'rental')
    : db
        .collection('transactions')
        .where('buyerUid', isEqualTo: uid)
        .where('requestType', isEqualTo: 'rental');
        
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
                Icon(Icons.key_off_outlined,
                    size: 64,
                    color: AppTheme.primaryStart.withOpacity(0.15)),
                const SizedBox(height: 16),
                Text(
                  isSupplier
                      ? 'No rent requests received yet'
                      : 'You have not sent any rent requests',
                  style: AppTheme.body(16, color: AppTheme.textMid),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
  isSupplier
      ? 'Rent requests from tenants will appear here'
      : 'Browse land assets and request to rent',
  style: AppTheme.body(13, color: Colors.grey[400]!),
  textAlign: TextAlign.center,
),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final t      = docs[i].data();
            final docId  = docs[i].id;
            final status = (t['status'] ?? 'pending').toString();
            final ts     = t['createdAt'] as Timestamp?;
            final date   = ts != null
                ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}'
                : '—';

            // Rental-specific fields
            final rentalFee      = t['rentalFee']?.toString()      ?? t['amount']?.toString() ?? '—';
            final startDate      = t['startDate']?.toString()      ?? '—';
            final endDate        = t['endDate']?.toString()        ?? '—';
            final duration       = t['rentalDurationMonths']?.toString() ?? '—';
            final assetId        = t['assetId']                    ?? '';
            final buyerUid       = t['buyerUid']                   ?? '';
            final sellerUid      = t['sellerUid']                  ?? '';
            final propertyId     = t['blockchainPropertyId']       ?? t['blockchainTokenId'];
            final tenantAddress  = t['tenantWalletAddress']        ?? t['buyerAddress'] ?? '';

            return Card(
              margin: const EdgeInsets.only(bottom: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: _statusColor(status).withOpacity(0.3),
                  width: 1,
                ),
              ),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header strip ────────────────────────────────────────
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withOpacity(0.06),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(14)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _statusBadge(status),
                        Row(children: [
                          const Icon(Icons.calendar_today_outlined,
                              size: 12, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(date,
                              style: AppTheme.body(12, color: AppTheme.textMid)),
                        ]),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Asset name ─────────────────────────────────────
                        FutureBuilder<DocumentSnapshot>(
                          future: db.collection('assets').doc(assetId).get(),
                          builder: (ctx, assetSnap) {
                            final data = assetSnap.hasData && assetSnap.data!.exists
                                ? assetSnap.data!.data() as Map<String, dynamic>
                                : <String, dynamic>{};
                            final title  = data['title']    ?? 'Loading…';
                            final city   = data['city']     ?? '';
                            final area   = data['plotArea'] != null
                                ? '${data['plotArea']} ${data['plotUnit'] ?? ''}'
                                : '';
                            final images = data['images'] as List?;
                            final imgStr = images != null && images.isNotEmpty
                                ? images.first as String
                                : null;

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Thumbnail
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: imgStr != null
                                      ? Image.memory(
                                          base64Decode(imgStr),
                                          width: 60,
                                          height: 60,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              _assetPlaceholder(),
                                        )
                                      : _assetPlaceholder(),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(title,
                                          style: AppTheme.heading(15,
                                              color: AppTheme.textPrimary),
                                          overflow: TextOverflow.ellipsis),
                                      if (city.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Row(children: [
                                          const Icon(
                                              Icons.location_on_outlined,
                                              size: 13,
                                              color: Colors.grey),
                                          const SizedBox(width: 3),
                                          Text(city,
                                              style: AppTheme.body(12,
                                                  color: AppTheme.textMid)),
                                        ]),
                                      ],
                                      if (area.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Row(children: [
                                          const Icon(Icons.crop_square_rounded,
                                              size: 13, color: Colors.grey),
                                          const SizedBox(width: 3),
                                          Text(area,
                                              style: AppTheme.body(12,
                                                  color: AppTheme.textMid)),
                                        ]),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 12),
                        const Divider(height: 1, color: Color(0xFFF0F0F0)),
                        const SizedBox(height: 12),

                        // ── Rental details grid ────────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: _rentInfoTile(
                                icon: Icons.payments_outlined,
                                label: 'Monthly Rent',
                                value: '$rentalFee MATIC',
                                valueColor: AppTheme.primaryStart,
                              ),
                            ),
                            Expanded(
                              child: _rentInfoTile(
                                icon: Icons.date_range_outlined,
                                label: 'Duration',
                                value: duration != '—'
                                    ? '$duration months'
                                    : '—',
                              ),
                            ),
                          ],
                        ),
                        if (startDate != '—' || endDate != '—') ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _rentInfoTile(
                                  icon: Icons.play_circle_outline,
                                  label: 'Start Date',
                                  value: startDate,
                                ),
                              ),
                              Expanded(
                                child: _rentInfoTile(
                                  icon: Icons.stop_circle_outlined,
                                  label: 'End Date',
                                  value: endDate,
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 10),

                        // ── Tenant / Landlord row ──────────────────────────
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
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F7FA),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(children: [
                                Icon(
                                  isSupplier
                                      ? Icons.person_outline
                                      : Icons.store_outlined,
                                  size: 16,
                                  color: AppTheme.primaryStart,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isSupplier
                                      ? 'Tenant: $name'
                                      : 'Landlord: $name',
                                  style: AppTheme.body(13,
                                      color: AppTheme.textPrimary),
                                ),
                                if (tenantAddress.isNotEmpty) ...[
                                  const Spacer(),
                                  Text(
                                    _shorten(tenantAddress),
                                    style: AppTheme.body(11,
                                        color: AppTheme.textMid),
                                  ),
                                ],
                              ]),
                            );
                          },
                        ),

                        const SizedBox(height: 12),
                        const Divider(height: 1, color: Color(0xFFF0F0F0)),
                        const SizedBox(height: 8),

                        // ── Action buttons ─────────────────────────────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // View asset button (always)
                            _outlinedAction(
                              icon: Icons.visibility_outlined,
                              label: 'View',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      AssetDetailScreen(assetId: assetId),
                                ),
                              ),
                            ),

                            // Supplier: pending → can Accept or Reject
                            if (isSupplier && status == 'pending') ...[
                              const SizedBox(width: 6),
                              _filledAction(
                                icon: Icons.check_rounded,
                                label: 'Accept',
                                color: AppTheme.accent,
                                onTap: () => _acceptRentTransaction(
                                    context, docId, t),
                              ),
                              const SizedBox(width: 6),
                              _filledAction(
                                icon: Icons.close_rounded,
                                label: 'Reject',
                                color: AppTheme.error,
                                onTap: () =>
                                    _rejectRentRequest(context, docId),
                              ),
                            ],

                            // Supplier: approved & active → can end the rental
                            if (isSupplier && status == 'approved') ...[
                              const SizedBox(width: 6),
                              _filledAction(
                                icon: Icons.meeting_room_outlined,
                                label: 'End Rental',
                                color: Colors.orange[700]!,
                                onTap: () =>
                                    _endRental(context, docId, assetId),
                              ),
                            ],

                            // Tenant: pending — waiting chip
                            if (!isSupplier && status == 'pending')
                              _statusChip('Awaiting landlord approval'),

                            // Tenant: approved — active rental chip
                            if (!isSupplier && status == 'approved')
                              _statusChip('✅ Rental active'),

                            // Both sides: completed/ended
                            if (status == 'completed' || status == 'ended')
                              _statusChip('Rental ended'),

                            // Tenant: rejected
                            if (!isSupplier && status == 'rejected')
                              _statusChip('❌ Request rejected'),
                          ],
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

  // ── Rent request helpers ──────────────────────────────────────────────────

  Future<void> _rejectRentRequest(BuildContext context, String docId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Rent Request'),
        content: const Text(
            'Are you sure you want to reject this rent request?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reject',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    await db
        .collection('transactions')
        .doc(docId)
        .update({'status': 'rejected'});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Rent request rejected'),
          backgroundColor: Colors.red));
    }
  }

  Future<void> _endRental(
      BuildContext context, String docId, String assetId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('End Rental'),
        content: const Text(
            'This will mark the rental as ended and free the asset for new rentals.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('End Rental')),
        ],
      ),
    );
    if (confirmed != true) return;

    final batch = db.batch();
    batch.update(db.collection('transactions').doc(docId), {
      'status': 'ended',
      'endedAt': FieldValue.serverTimestamp(),
    });
    batch.update(db.collection('assets').doc(assetId), {
      'isForRent': true,
      'currentTenant': null,
      'currentTenantAddress': null,
    });
    await batch.commit();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Rental ended. Asset is available again.'),
          backgroundColor: Colors.orange));
    }
  }

  // ── Small UI helpers ──────────────────────────────────────────────────────

  Widget _rentInfoTile({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: AppTheme.body(11, color: AppTheme.textMid)),
              Text(value,
                  style: AppTheme.heading(13,
                      color: valueColor ?? AppTheme.textPrimary),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }

  Widget _outlinedAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.accent,
        side: BorderSide(color: AppTheme.accent.withOpacity(0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _filledAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _assetPlaceholder() {
    return Container(
      width: 60,
      height: 60,
      color: AppTheme.primaryStart.withOpacity(0.06),
      child: Icon(Icons.landscape_rounded,
          size: 28, color: AppTheme.primaryStart.withOpacity(0.35)),
    );
  }

  // ── FRACTION REQUESTS TAB (unchanged) ────────────────────────────────────
  Widget _buildFractionRequestsTab(
      String uid, bool isSupplier, BuildContext context) {
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
        if (snap.hasError)
          return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData)
          return const Center(child: CircularProgressIndicator());

        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.pie_chart_outline,
                    size: 60,
                    color: AppTheme.primaryStart.withOpacity(0.15)),
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
            final r             = docs[i].data();
            final docId         = docs[i].id;
            final status        = r['status'] ?? 'pending';
            final fractionsReq  = r['fractionsRequested'] ?? 0;
            final totalCostWei  = r['totalCost'] ?? '0';
            final buyerUid      = r['buyerUid']  ?? '';
            final sellerUid     = r['sellerUid'] ?? '';
            final assetId       = r['assetId']   ?? '';
            final transactionId = r['transactionId'] ?? docId;
            final ts            = r['createdAt'] as Timestamp?;
            final date = ts != null
                ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}'
                : '—';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                    color: _statusColor(status).withOpacity(0.3)),
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
                            style:
                                AppTheme.body(12, color: AppTheme.textMid)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<DocumentSnapshot>(
                      future: db.collection('assets').doc(assetId).get(),
                      builder: (ctx, assetSnap) {
                        final title = assetSnap.hasData
                            ? (assetSnap.data!.data()
                                    as Map<String, dynamic>)['title'] ??
                                'Asset'
                            : 'Loading…';
                        return Row(children: [
                          const Icon(Icons.home_work_outlined,
                              size: 16, color: AppTheme.primaryStart),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(title,
                                style: AppTheme.heading(15,
                                    color: AppTheme.textPrimary),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ]);
                      },
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.pie_chart_outline,
                            size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 6),
                        Text(
                          '$fractionsReq fractions  •  ${_weiDisplay(totalCostWei)} MATIC',
                          style:
                              AppTheme.body(13, color: AppTheme.textMid),
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
                            style:
                                AppTheme.body(13, color: AppTheme.textMid),
                          ),
                        ]);
                      },
                    ),
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
                            foregroundColor: AppTheme.accent,
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
                        if (isSupplier && status == 'pending') ...[
                          TextButton.icon(
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Approve'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.accent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                            ),
                            onPressed: () => _updateFractionRequest(
                                context, docId, transactionId, 'approved'),
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
                                context, docId, transactionId, 'rejected'),
                          ),
                        ],
                        if (isSupplier && status == 'approved')
                          ElevatedButton.icon(
                            icon: const Icon(Icons.send, size: 14),
                            label: const Text('Transfer'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A4F5C),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12),
                            ),
                            onPressed: () => _navigateToFractionTransfer(
                              context,
                              docId,
                              assetId,
                              buyerUid,
                              fractionsReq,
                              transactionId,
                              r['blockchainPropertyId'] ??
                                  r['blockchainTokenId'],
                            ),
                          ),
                        if (!isSupplier && status == 'approved')
                          _statusChip('Approved — awaiting transfer'),
                        if (!isSupplier && status == 'completed')
                          _statusChip('✅ Transfer complete'),
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

  // ── Regular transaction list (unchanged) ──────────────────────────────────
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
                Icon(_statusIcon(status),
                    size: 60,
                    color: AppTheme.primaryStart.withOpacity(0.15)),
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
            final txStatus  = (t['status'] ?? '').toString();
            final allowChat = txStatus == 'approved' || txStatus == 'accepted';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                    color: _statusColor(txStatus).withOpacity(0.3)),
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
                            style:
                                AppTheme.body(12, color: AppTheme.textMid)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<DocumentSnapshot>(
                      future:
                          db.collection('assets').doc(t['assetId']).get(),
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
                            Icon(Icons.inventory_2_outlined,
                                size: 16, color: AppTheme.textMid),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(title,
                                  style: AppTheme.heading(15,
                                      color: AppTheme.textPrimary),
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
                          color: AppTheme.textMid,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isSupplier
                              ? 'Buyer: ${_shorten(t['buyerUid'] ?? '—')}'
                              : 'Seller: ${_shorten(t['sellerUid'] ?? '—')}',
                          style:
                              AppTheme.body(13, color: AppTheme.textMid),
                        ),
                      ],
                    ),
                    if (t['requestType'] == 'rental') ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.calendar_month_outlined,
                            size: 14, color: AppTheme.textMid),
                        const SizedBox(width: 6),
                        Text(
                            'Monthly Rent: ${t['rentalFee'] ?? t['amount']} MATIC',
                            style: AppTheme.heading(
                                13, color: AppTheme.primaryStart)),
                      ]),
                    ] else if (t['price'] != null) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        Text('${t['price']}',
                            style:
                                AppTheme.body(13, color: AppTheme.textMid)),
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
                            foregroundColor: AppTheme.accent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8),
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                            ),
                            onPressed: () async {
                              final myUid    = auth.currentUser!.uid;
                              final otherUid = isSupplier
                                  ? t['buyerUid']
                                  : t['sellerUid'];
                              await db.collection('chats').doc(id).set({
                                'participants'   : [myUid, otherUid],
                                'assetId'        : t['assetId'],
                                'assetType'      : t['category'] ?? 'electronics',
                                'sellerUid'      : isSupplier ? myUid    : otherUid,
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
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
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
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
                            (txStatus == 'approved' ||
                                txStatus == 'pending')) ...[
                          const SizedBox(width: 4),
                          TextButton.icon(
                            icon: const Icon(
                                Icons.account_balance_wallet,
                                size: 16),
                            label: const Text('My Wallet'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.accent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                            ),
                            onPressed: () {
                              final category =
                                  t['category'] ?? 'electronics';
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BuyerOwnershipAcceptScreen(
                                    assetId      : t['assetId'] ?? '',
                                    transactionId: id,
                                    sellerName   : _shorten(
                                        t['sellerUid'] ?? '—'),
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
                            icon: const Icon(Icons.move_to_inbox,
                                size: 16),
                            label: const Text('Ownership'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppTheme.accent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8),
                            ),
                            onPressed: () {
                              final category =
                                  t['category'] ?? 'electronics';
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => BuyerOwnershipAcceptScreen(
                                    assetId      : t['assetId'] ?? '',
                                    transactionId: id,
                                    sellerName   : _shorten(
                                        t['sellerUid'] ?? '—'),
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

  Widget _statusChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primaryStart.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
      ),
      child: Text(label, style: AppTheme.body(12, color: AppTheme.accent)),
    );
  }

  // ── All helper methods ────────────────────────────────────────────────────

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

    final assetDoc   = await db.collection('assets').doc(assetId).get();
    final assetData  = assetDoc.data() ?? {};
    final assetPrice = assetData['price']?.toString() ?? '0';

    final buyerDoc  = await db.collection('users').doc(buyerUid).get();
    final buyerName = buyerDoc.data()?['name'] ?? 'Buyer';

    final blockchainPropertyId = propertyId is int
        ? propertyId
        : int.tryParse(propertyId.toString()) ?? 0;

    if (!context.mounted) return;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TransferScreen(
          assetId       : assetId,
          assetType     : AssetType.land,
          transactionId : transactionId,
          buyerUid      : buyerUid,
          sellerUid     : sellerUid,
          propertyId    : blockchainPropertyId,
          fractionAmount: fractionsRequested,
          assetPrice    : assetPrice,
          buyerName     : buyerName,
        ),
      ),
    );

    if (result == true) {
      final batch = db.batch();
      batch.update(
        db.collection('fraction_requests').doc(fractionRequestId),
        {'status': 'completed', 'completedAt': FieldValue.serverTimestamp()},
      );
      if (transactionId.isNotEmpty) {
        batch.update(
          db.collection('transactions').doc(transactionId),
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

  Future<void> _acceptRentTransaction(
      BuildContext context, String transactionId, Map<String, dynamic> t) async {
    final assetId    = t['assetId'];
    final propertyId = t['blockchainPropertyId'];

    if (propertyId == null) return;

    try {
      final service = BlockchainServiceEnhanced();
      await service.init();

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Confirming on blockchain...')));

      final txHash = await service.acceptLandRentRequest(
          propertyId is int ? propertyId : int.parse(propertyId.toString()));

      if (txHash != null) {
        final ok = await service.waitForConfirmation(txHash);
        if (ok) {
          final batch = db.batch();
          batch.update(db.collection('transactions').doc(transactionId),
              {'status': 'approved'});

          final prop = await service.getLandProperty(propertyId is int
              ? propertyId
              : int.parse(propertyId.toString()));

          batch.update(db.collection('assets').doc(assetId), {
            'isForRent'           : false,
            'currentTenant'       : t['buyerUid'],
            'currentTenantAddress': prop?['pendingTenant'] ?? '',
          });

          await batch.commit();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('✅ Rent request approved!'),
                backgroundColor: AppTheme.accent));
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'), backgroundColor: AppTheme.error));
      }
    }
  }

  Future<void> _updateRentRequestStatus(String id, String status) async {
    await db
        .collection('transactions')
        .doc(id)
        .update({'status': status});
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