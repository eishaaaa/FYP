// lib/screens/transfer_history_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../blockchain/transfer_service.dart';


class TransferHistoryScreen extends StatefulWidget {
  final String assetId;
  const TransferHistoryScreen({super.key, required this.assetId});

  @override
  State<TransferHistoryScreen> createState() => _TransferHistoryScreenState();
}

class _TransferHistoryScreenState extends State<TransferHistoryScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _transferService = TransferService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _transfers = [];

  // ── Design tokens ────────────────────────────────────────────
  static const _surface = Color(0xFFF8F9FE);
  static const _cardRadius = 16.0;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      List<Map<String, dynamic>> results = [];

      // ── 1. Try transfers collection first ──────────────────────
      try {
        final snap = await _firestore
            .collection('transfers')
            .where('assetId', isEqualTo: widget.assetId)
            .orderBy('timestamp', descending: true)
            .get();
        results = snap.docs.map((d) => d.data()).toList();
      } catch (e) {
        debugPrint('transfers collection error: $e');
      }

      // ── 2. Fallback: transactions collection ───────────────────
      if (results.isEmpty) {
        final txSnap = await _firestore
            .collection('transactions')
            .where('assetId', isEqualTo: widget.assetId)
            .where('status', whereIn: ['completed', 'transferred', 'done']).get();

        String assetPrice = '';
        try {
          final assetSnap =
          await _firestore.collection('assets').doc(widget.assetId).get();
          if (assetSnap.exists) {
            final p = assetSnap.data()?['price'];
            if (p != null) assetPrice = 'PKR $p';
          }
        } catch (_) {}

        for (final doc in txSnap.docs) {
          final t = doc.data();

          String sellerName = t['sellerUid'] ?? '';
          final sellerUid = t['sellerUid'] as String?;
          if (sellerUid != null && sellerUid.isNotEmpty) {
            try {
              final snap =
              await _firestore.collection('users').doc(sellerUid).get();
              if (snap.exists) {
                sellerName = snap.data()?['name'] ??
                    snap.data()?['email'] ??
                    sellerUid;
              }
            } catch (_) {}
          }

          String buyerName = t['buyerUid'] ?? '';
          final buyerUid = t['buyerUid'] as String?;
          if (buyerUid != null && buyerUid.isNotEmpty) {
            try {
              final snap =
              await _firestore.collection('users').doc(buyerUid).get();
              if (snap.exists) {
                buyerName = snap.data()?['name'] ??
                    snap.data()?['email'] ??
                    buyerUid;
              }
            } catch (_) {}
          }

          results.add({
            'from': sellerName,
            'to': buyerName,
            'assetType': t['category'] ?? t['assetType'] ?? 'electronics',
            'txHash': t['blockchainTxHash'] ?? t['txHash'] ?? '',
            'status': 'confirmed',
            'transferType': 'resale',
            'pricePaid': assetPrice,
            'timestamp': t['completedAt'] ?? t['updatedAt'] ?? t['createdAt'],
            'amount': t['fractions'] ?? t['amount'] ?? 1,
          });
        }
      }

      if (mounted) setState(() { _transfers = results; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surface,
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
          'Transfer History',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            color: Colors.black54,
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildErrorView()
          : _transfers.isEmpty
          ? _buildEmptyView()
          : _buildList(),
    );
  }

  // ── Error view ───────────────────────────────────────────────
  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 14),
            Text(
              'Something went wrong',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700]),
            ),
            const SizedBox(height: 6),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _loadHistory,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.grey[300]!),
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty view ───────────────────────────────────────────────
  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.history_rounded, size: 52, color: Colors.grey[350]),
          ),
          const SizedBox(height: 16),
          Text(
            'No transfers yet',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600]),
          ),
          const SizedBox(height: 6),
          Text(
            'Transfer activity for this asset will appear here.',
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── List ─────────────────────────────────────────────────────
  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: _transfers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildCard(_transfers[index], index),
    );
  }

  Widget _buildCard(Map<String, dynamic> data, int index) {
    final from = data['from'] as String? ?? '';
    final to = data['to'] as String? ?? '';
    final amount = data['amount'] ?? 1;
    final assetType = data['assetType'] as String? ?? '';
    final txHash = data['txHash'] as String? ?? '';
    final status = data['status'] as String? ?? 'confirmed';
    final pricePaid = data['pricePaid'] as String?;
    final transferType = data['transferType'] as String?;
    final ts = data['timestamp'] as Timestamp?;

    final isResale = transferType == 'resale';
    final isLand = assetType == 'land';

    final accentColor = isResale ? Colors.orange : Colors.green;
    final typeLabel = isResale ? 'RESALE' : 'ORIGINAL';

    String display(String val) {
      if (val.startsWith('0x') && val.length > 12) {
        return _transferService.shortenAddress(val);
      }
      return val;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
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

          // ── Card header strip ──────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(_cardRadius)),
            ),
            child: Row(
              children: [
                // Asset type icon + label
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Icon(
                    isLand ? Icons.landscape_rounded : Icons.devices_rounded,
                    size: 16,
                    color: const Color(0xFF3D5CFF),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isLand ? 'Land Fraction Transfer' : 'Electronics Transfer',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // Transfer type badge
                if (transferType != null)
                  _badge(typeLabel, accentColor),
                const SizedBox(width: 6),
                // Status badge
                _badge(status.toUpperCase(), Colors.green),
              ],
            ),
          ),

          // ── Body ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // From → To
                _transferArrow(display(from), display(to)),
                const SizedBox(height: 14),

                // Details row
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (isLand)
                      _detailChip(
                        icon: Icons.pie_chart_rounded,
                        label: '$amount fractions',
                        color: Colors.blue,
                      ),
                    if (pricePaid != null && pricePaid.isNotEmpty)
                      _detailChip(
                        icon: Icons.payments_rounded,
                        label: pricePaid,
                        color: Colors.purple,
                      ),
                  ],
                ),

                const SizedBox(height: 14),
                Divider(color: Colors.grey[100], height: 1),
                const SizedBox(height: 12),

                // Footer: explorer link + timestamp
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (txHash.isNotEmpty)
                      GestureDetector(
                        onTap: () async {
                          final url = Uri.parse(
                              'https://amoy.polygonscan.com/tx/$txHash');
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                        child: Row(
                          children: [
                            const Icon(Icons.open_in_new_rounded,
                                size: 13, color: Color(0xFF3D5CFF)),
                            const SizedBox(width: 4),
                            Text(
                              'View on Explorer',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue[700],
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.blue[700],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      const SizedBox(),

                    Text(
                      _formatTimestamp(ts),
                      style:
                      TextStyle(fontSize: 11, color: Colors.grey[400]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── From → To arrow layout ───────────────────────────────────
  Widget _transferArrow(String from, String to) {
    return Row(
      children: [
        Expanded(
          child: _participantTile(
            label: 'From',
            name: from,
            icon: Icons.arrow_upward_rounded,
            iconColor: Colors.red[400]!,
            bgColor: Colors.red[50]!,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            children: [
              Icon(Icons.arrow_forward_rounded,
                  size: 20, color: Colors.grey[400]),
            ],
          ),
        ),
        Expanded(
          child: _participantTile(
            label: 'To',
            name: to,
            icon: Icons.arrow_downward_rounded,
            iconColor: Colors.green[600]!,
            bgColor: Colors.green[50]!,
          ),
        ),
      ],
    );
  }

  Widget _participantTile({
    required String label,
    required String name,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: iconColor),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: iconColor,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            name.isEmpty ? '—' : name,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── Detail chip ──────────────────────────────────────────────
  Widget _detailChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // ── Badge ────────────────────────────────────────────────────
  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: Color(0xFF1976D2),
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  static String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    final period = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.day}/${d.month}/${d.year}  $hour:$minute $period';
  }
}