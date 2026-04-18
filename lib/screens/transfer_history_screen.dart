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

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() { _loading = true; _error = null; });

    try {
      // ── 1. Try transfers collection first ──────────────────────────
      List<Map<String, dynamic>> results = [];

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

      // ── 2. Fallback: read from transactions collection ──────────────
      if (results.isEmpty) {
        final txSnap = await _firestore
            .collection('transactions')
            .where('assetId', isEqualTo: widget.assetId)
            .where('status', whereIn: ['completed', 'transferred', 'done'])
            .get();

        // Fetch asset price once
        String assetPrice = '';
        try {
          final assetSnap = await _firestore
              .collection('assets')
              .doc(widget.assetId)
              .get();
          if (assetSnap.exists) {
            final p = assetSnap.data()?['price'];
            if (p != null) assetPrice = 'PKR $p';
          }
        } catch (_) {}

        for (final doc in txSnap.docs) {
          final t = doc.data();

          // Resolve seller name
          String sellerName = t['sellerUid'] ?? '';
          final sellerUid = t['sellerUid'] as String?;
          if (sellerUid != null && sellerUid.isNotEmpty) {
            try {
              final snap = await _firestore.collection('users').doc(sellerUid).get();
              if (snap.exists) {
                sellerName = snap.data()?['name'] ?? snap.data()?['email'] ?? sellerUid;
              }
            } catch (_) {}
          }

          // Resolve buyer name
          String buyerName = t['buyerUid'] ?? '';
          final buyerUid = t['buyerUid'] as String?;
          if (buyerUid != null && buyerUid.isNotEmpty) {
            try {
              final snap = await _firestore.collection('users').doc(buyerUid).get();
              if (snap.exists) {
                buyerName = snap.data()?['name'] ?? snap.data()?['email'] ?? buyerUid;
              }
            } catch (_) {}
          }

          results.add({
            'from'        : sellerName,
            'to'          : buyerName,
            'assetType'   : t['category'] ?? t['assetType'] ?? 'electronics',
            'txHash'      : t['blockchainTxHash'] ?? t['txHash'] ?? '',
            'status'      : 'confirmed',
            'transferType': 'resale',
            'pricePaid'   : assetPrice,
            'timestamp'   : t['completedAt'] ?? t['updatedAt'] ?? t['createdAt'],
            'amount'      : t['fractions'] ?? t['amount'] ?? 1,
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
      appBar: AppBar(
        title: const Text('Transfer History'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : _transfers.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('No transfers yet',
                style: TextStyle(fontSize: 16, color: Colors.grey[500])),
          ],
        ),
      )
          : ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _transfers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _buildCard(_transfers[index]),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> data) {
    final from         = data['from']         as String? ?? '';
    final to           = data['to']           as String? ?? '';
    final amount       = data['amount']       ?? 1;
    final assetType    = data['assetType']    as String? ?? '';
    final txHash       = data['txHash']       as String? ?? '';
    final status       = data['status']       as String? ?? 'confirmed';
    final pricePaid    = data['pricePaid']    as String?;
    final transferType = data['transferType'] as String?;
    final ts           = data['timestamp']    as Timestamp?;

    final isResale    = transferType == 'resale';
    final accentColor = isResale ? Colors.orange : Colors.green;

    String display(String val) {
      if (val.startsWith('0x') && val.length > 12) {
        return _transferService.shortenAddress(val);
      }
      return val;
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: accentColor.withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Header ──────────────────────────────────────────────
            Row(
              children: [
                Icon(
                  assetType == 'electronics' ? Icons.devices : Icons.landscape,
                  size: 18, color: Colors.blue,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    assetType == 'electronics'
                        ? 'Electronics Transfer'
                        : 'Land Fraction Transfer',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                if (transferType != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: accentColor.withOpacity(0.45)),
                    ),
                    child: Text(
                      isResale ? 'RESALE' : 'ORIGINAL',
                      style: TextStyle(
                        fontSize: 10,
                        color: accentColor[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const Divider(height: 16),

            // ── From / To ───────────────────────────────────────────
            _infoRow(Icons.arrow_upward,   'From', display(from), Colors.red),
            const SizedBox(height: 6),
            _infoRow(Icons.arrow_downward, 'To',   display(to),   Colors.green),

            // ── Fractions (land only) ────────────────────────────────
            if (assetType == 'land') ...[
              const SizedBox(height: 6),
              _infoRow(Icons.pie_chart, 'Fractions', '$amount fractions', Colors.blue),
            ],

            // ── Price ───────────────────────────────────────────────
            if (pricePaid != null && pricePaid.isNotEmpty) ...[
              const SizedBox(height: 6),
              _infoRow(Icons.payments_outlined, 'Price Paid', pricePaid, Colors.purple),
            ],

            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // ── Explorer link + timestamp ────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (txHash.isNotEmpty)
                  GestureDetector(
                    onTap: () async {
                      final url = Uri.parse('https://amoy.polygonscan.com/tx/$txHash');
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    },
                    child: Row(
                      children: [
                        const Icon(Icons.open_in_new, size: 14, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(
                          'View on Explorer',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[700],
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox(),

                Text(
                  _formatTimestamp(ts),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ],
            ),

          ],   // ← Column children closes here
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color iconColor) {
    return Row(
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 6),
        Text('$label: ', style: const TextStyle(color: Colors.grey, fontSize: 13)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  static String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return '';
    final d      = ts.toDate();
    final hour   = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    final period = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.day}/${d.month}/${d.year}  $hour:$minute $period';
  }
}