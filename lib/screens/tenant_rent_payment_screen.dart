// lib/screens/tenant_rent_payment_screen.dart
//
// USAGE — navigate to this screen from your property detail or active-lease page:
//
//   Navigator.push(context, MaterialPageRoute(builder: (_) =>
//     TenantRentPaymentScreen(
//       propertyId: property.id,          // int — the on-chain property ID
//       leaseId: lease.id,                // String — Firestore lease document ID
//       monthlyRentMatic: 0.05,           // double — amount agreed in the lease
//       propertyLocation: 'Main Street',  // String — shown in the UI
//     ),
//   ));
//
// FIRESTORE STRUCTURE expected / written by this screen:
//
//   leases/{leaseId}
//     status        : 'active' | 'pending' | 'expired'
//     tenantUid     : String
//     ownerUid      : String
//     propertyId    : int
//     monthlyRent   : double   (MATIC)
//     nextDueDate   : Timestamp
//
//   leases/{leaseId}/payments/{paymentId}
//     txHash        : String
//     amountMatic   : double
//     paidAt        : Timestamp
//     status        : 'confirmed' | 'pending' | 'failed'
//     tenantAddress : String
//     propertyId    : int
//
// BLOCKCHAIN — calls BlockchainServiceEnhanced.payLandRent(propertyId, weiAmount)
// Make sure that method exists (see blockchain_service_additions.dart snippet).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../blockchain/blockchain_service.dart';

class TenantRentPaymentScreen extends StatefulWidget {
  final int propertyId;
  final String leaseId;
  final double monthlyRentMatic;
  final String propertyLocation;

  const TenantRentPaymentScreen({
    super.key,
    required this.propertyId,
    required this.leaseId,
    required this.monthlyRentMatic,
    required this.propertyLocation,
  });

  @override
  State<TenantRentPaymentScreen> createState() =>
      _TenantRentPaymentScreenState();
}

class _TenantRentPaymentScreenState extends State<TenantRentPaymentScreen>
    with SingleTickerProviderStateMixin {
  // ── Services ────────────────────────────────────────────────────────────────
  final _blockchain = BlockchainServiceEnhanced();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // ── State ────────────────────────────────────────────────────────────────────
  bool _loading = true;
  bool _paying = false;
  Map<String, dynamic>? _leaseData;
  List<Map<String, dynamic>> _paymentHistory = [];
  String? _errorMessage;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // ── Lifecycle ────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim =
        Tween<double>(begin: 1.0, end: 1.05).animate(_pulseController);
    _init();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ── Data Loading ─────────────────────────────────────────────────────────────
  Future<void> _init() async {
    try {
      await _blockchain.init();

      // Connect wallet if not already connected
      if (!_blockchain.isConnected) {
        await _blockchain.connectWallet(context);
      }

      await Future.wait([_loadLease(), _loadPaymentHistory()]);
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadLease() async {
    final doc =
    await _firestore.collection('leases').doc(widget.leaseId).get();
    if (doc.exists) {
      _leaseData = doc.data();
    }
  }

  Future<void> _loadPaymentHistory() async {
    final snap = await _firestore
        .collection('leases')
        .doc(widget.leaseId)
        .collection('payments')
        .orderBy('paidAt', descending: true)
        .limit(10)
        .get();

    _paymentHistory =
        snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  bool get _isOverdue {
    if (_leaseData == null) return false;
    final due = (_leaseData!['nextDueDate'] as Timestamp?)?.toDate();
    return due != null && due.isBefore(DateTime.now());
  }

  DateTime? get _nextDueDate {
    final ts = _leaseData?['nextDueDate'] as Timestamp?;
    return ts?.toDate();
  }

  String _formatDate(DateTime dt) =>
      '${dt.day} ${_month(dt.month)} ${dt.year}';

  String _month(int m) => const [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ][m];

  // ── Payment Flow ─────────────────────────────────────────────────────────────
  Future<void> _payRent() async {
    final confirmed = await _showConfirmDialog();
    if (!confirmed) return;

    setState(() => _paying = true);

    // Firestore reference created early so we can update it on failure too
    final paymentRef = _firestore
        .collection('leases')
        .doc(widget.leaseId)
        .collection('payments')
        .doc();

    try {
      // 1. Make sure wallet is connected
      if (!_blockchain.isConnected) {
        await _blockchain.connectWallet(context);
        if (!_blockchain.isConnected) throw Exception('Wallet not connected');
      }

      final weiAmount =
      _blockchain.etherToWei(widget.monthlyRentMatic);

      // 2. Write a pending record first — gives the user proof even if the
      //    app crashes before confirmation arrives
      await paymentRef.set({
        'txHash': null,
        'amountMatic': widget.monthlyRentMatic,
        'paidAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'tenantAddress': _blockchain.connectedAddress,
        'propertyId': widget.propertyId,
        'tenantUid': _auth.currentUser?.uid,
      });

      // 3. Send the on-chain transaction
      //    payLandRent must be added to BlockchainServiceEnhanced — see
      //    blockchain_service_additions.dart
      final txHash = await _blockchain.payLandRent(
        propertyId: widget.propertyId,
        amount: weiAmount,
      );

      if (txHash == null) throw Exception('Transaction was rejected');

      // 4. Wait for on-chain confirmation
      final success = await _blockchain.waitForConfirmation(txHash);
      if (!success) throw Exception('Transaction failed on-chain');

      // 5. Mark payment confirmed in Firestore
      final batch = _firestore.batch();

      batch.update(paymentRef, {
        'txHash': txHash,
        'status': 'confirmed',
      });

      // Advance the next due date by ~30 days
      final nextDue = (_nextDueDate ?? DateTime.now())
          .add(const Duration(days: 30));

      batch.update(
        _firestore.collection('leases').doc(widget.leaseId),
        {'nextDueDate': Timestamp.fromDate(nextDue)},
      );

      await batch.commit();

      // 6. Refresh UI
      await Future.wait([_loadLease(), _loadPaymentHistory()]);

      if (mounted) {
        _showSuccessSheet(txHash);
      }
    } catch (e) {
      // Mark the pending record as failed so the owner / tenant can see it
      await paymentRef
          .update({'status': 'failed', 'error': e.toString()}).catchError(
              (_) {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment failed: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<bool> _showConfirmDialog() async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirm Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Property', widget.propertyLocation),
            const SizedBox(height: 8),
            _detailRow(
                'Amount', '${widget.monthlyRentMatic} MATIC'),
            const SizedBox(height: 8),
            _detailRow('Wallet', _blockchain.connectedAddress ?? '—'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.amber[700], size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'This transaction cannot be reversed.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B5E20),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Pay Now'),
          ),
        ],
      ),
    ) ??
        false;
  }

  void _showSuccessSheet(String txHash) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SuccessSheet(
        txHash: txHash,
        amountMatic: widget.monthlyRentMatic,
        propertyLocation: widget.propertyLocation,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F0),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Pay Rent',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              setState(() => _loading = true);
              _init();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(
          child: CircularProgressIndicator(color: Color(0xFF1B5E20)))
          : _errorMessage != null
          ? _ErrorView(
          message: _errorMessage!, onRetry: _init)
          : _Body(
        propertyLocation: widget.propertyLocation,
        monthlyRentMatic: widget.monthlyRentMatic,
        leaseData: _leaseData,
        paymentHistory: _paymentHistory,
        isOverdue: _isOverdue,
        nextDueDate: _nextDueDate,
        paying: _paying,
        pulseAnim: _pulseAnim,
        onPay: _payRent,
        formatDate: _formatDate,
        blockchain: _blockchain,
      ),
    );
  }

  Widget _detailRow(String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 64,
        child: Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 13)),
      ),
      Expanded(
        child: Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    ],
  );
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _Body extends StatelessWidget {
  final String propertyLocation;
  final double monthlyRentMatic;
  final Map<String, dynamic>? leaseData;
  final List<Map<String, dynamic>> paymentHistory;
  final bool isOverdue;
  final DateTime? nextDueDate;
  final bool paying;
  final Animation<double> pulseAnim;
  final VoidCallback onPay;
  final String Function(DateTime) formatDate;
  final BlockchainServiceEnhanced blockchain;

  const _Body({
    required this.propertyLocation,
    required this.monthlyRentMatic,
    required this.leaseData,
    required this.paymentHistory,
    required this.isOverdue,
    required this.nextDueDate,
    required this.paying,
    required this.pulseAnim,
    required this.onPay,
    required this.formatDate,
    required this.blockchain,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Overdue banner ─────────────────────────────────────────────────
          if (isOverdue)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.red[700],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Rent overdue since ${nextDueDate != null ? formatDate(nextDueDate!) : "—"}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

          // ── Payment card ───────────────────────────────────────────────────
          ScaleTransition(
            scale: paying ? pulseAnim : const AlwaysStoppedAnimation(1.0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1B5E20).withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.home_work_rounded,
                          color: Colors.white70, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          propertyLocation,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Monthly Rent Due',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        monthlyRentMatic.toStringAsFixed(4),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6, left: 8),
                        child: Text(
                          'MATIC',
                          style:
                          TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _InfoChip(
                        icon: Icons.calendar_today_rounded,
                        label: nextDueDate != null
                            ? 'Due ${formatDate(nextDueDate!)}'
                            : 'No due date',
                        overdue: isOverdue,
                      ),
                      const SizedBox(width: 8),
                      _InfoChip(
                        icon: Icons.account_balance_wallet_rounded,
                        label: blockchain.isConnected
                            ? _truncateAddress(
                            blockchain.connectedAddress ?? '')
                            : 'Not connected',
                        overdue: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: paying ? null : onPay,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1B5E20),
                        disabledBackgroundColor: Colors.white38,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: paying
                          ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0xFF1B5E20),
                        ),
                      )
                          : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send_rounded, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Pay Rent On-Chain',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),

          // ── Lease details ──────────────────────────────────────────────────
          if (leaseData != null) ...[
            const _SectionHeader(title: 'Lease Details'),
            const SizedBox(height: 12),
            _LeaseDetailsCard(leaseData: leaseData!),
            const SizedBox(height: 28),
          ],

          // ── Payment history ────────────────────────────────────────────────
          const _SectionHeader(title: 'Payment History'),
          const SizedBox(height: 12),
          paymentHistory.isEmpty
              ? const _EmptyHistory()
              : Column(
            children: paymentHistory
                .map((p) => _PaymentTile(payment: p))
                .toList(),
          ),

          const SizedBox(height: 24),

          // ── Info box ───────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue[100]!),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.shield_outlined,
                        size: 16, color: Colors.blueAccent),
                    SizedBox(width: 6),
                    Text(
                      'How On-Chain Rent Works',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                _InfoBullet('Payment is sent directly to the smart contract'),
                _InfoBullet(
                    'Owner receives funds automatically upon distribution'),
                _InfoBullet('Every transaction is immutable and traceable'),
                _InfoBullet(
                    'A Firestore record mirrors the on-chain state'),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static String _truncateAddress(String addr) =>
      addr.length > 10 ? '${addr.substring(0, 6)}…${addr.substring(addr.length - 4)}' : addr;
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool overdue;
  const _InfoChip(
      {required this.icon, required this.label, required this.overdue});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: overdue
            ? Colors.red[700]
            : Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1B5E20),
        letterSpacing: 0.3,
      ),
    );
  }
}

class _LeaseDetailsCard extends StatelessWidget {
  final Map<String, dynamic> leaseData;
  const _LeaseDetailsCard({required this.leaseData});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _Row('Status', (leaseData['status'] ?? '—').toString().toUpperCase()),
            const Divider(height: 20),
            _Row('Monthly Rent',
                '${leaseData['monthlyRent'] ?? '—'} MATIC'),
            const Divider(height: 20),
            _Row('Tenant UID', leaseData['tenantUid'] ?? '—'),
          ],
        ),
      ),
    );
  }

  static Widget _Row(String label, String value) => Row(
    children: [
      Expanded(
        flex: 2,
        child: Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 13)),
      ),
      Expanded(
        flex: 3,
        child: Text(
          value,
          style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: 13),
          textAlign: TextAlign.end,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

class _PaymentTile extends StatelessWidget {
  final Map<String, dynamic> payment;
  const _PaymentTile({required this.payment});

  @override
  Widget build(BuildContext context) {
    final status = payment['status'] as String? ?? 'pending';
    final paidAt = (payment['paidAt'] as Timestamp?)?.toDate();
    final txHash = payment['txHash'] as String?;

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'confirmed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'failed':
        statusColor = Colors.red;
        statusIcon = Icons.cancel_rounded;
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_top_rounded;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: Colors.white,
      child: ListTile(
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.1),
          child: Icon(statusIcon, color: statusColor, size: 20),
        ),
        title: Text(
          '${payment['amountMatic'] ?? '—'} MATIC',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: txHash != null
            ? GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: txHash));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Tx hash copied')),
            );
          },
          child: Text(
            '${txHash.substring(0, 10)}… (tap to copy)',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        )
            : const Text('Pending confirmation',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              status.toUpperCase(),
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
            if (paidAt != null)
              Text(
                '${paidAt.day}/${paidAt.month}/${paidAt.year}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 40, color: Colors.grey),
          SizedBox(height: 12),
          Text('No payments yet',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
        ],
      ),
    );
  }
}

class _InfoBullet extends StatelessWidget {
  final String text;
  const _InfoBullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Colors.blueAccent)),
          Expanded(
            child: Text(text,
                style:
                const TextStyle(fontSize: 12, color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}

class _SuccessSheet extends StatelessWidget {
  final String txHash;
  final double amountMatic;
  final String propertyLocation;

  const _SuccessSheet({
    required this.txHash,
    required this.amountMatic,
    required this.propertyLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.green[50],
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: Colors.green, size: 44),
          ),
          const SizedBox(height: 16),
          const Text(
            'Payment Successful!',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            '$amountMatic MATIC paid for $propertyLocation',
            style: const TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: txHash));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tx hash copied')),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_outlined,
                      size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      txHash,
                      style: const TextStyle(
                          fontSize: 11, fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.copy_rounded,
                      size: 14, color: Colors.grey),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Done',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
