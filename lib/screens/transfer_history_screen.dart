// lib/screens/transfer_history_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../blockchain/transfer_service.dart';

class TransferHistoryScreen extends StatelessWidget {
  final String assetId;

  const TransferHistoryScreen({
    super.key,
    required this.assetId,
  });

  @override
  Widget build(BuildContext context) {
    final transferService = TransferService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer History'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: transferService.getAssetTransferHistory(assetId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'No transfers found',
                style: TextStyle(fontSize: 16),
              ),
            );
          }

          final transfers = snapshot.data!.docs;

          return ListView.separated(
            itemCount: transfers.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final data =
              transfers[index].data() as Map<String, dynamic>;

              final from = data['from'] ?? '';
              final to = data['to'] ?? '';
              final amount = data['amount'] ?? 0;
              final assetType = data['assetType'] ?? '';
              final txHash = data['txHash'] ?? '';
              final ts = data['timestamp'] as Timestamp?;

              return ListTile(
                leading: Icon(
                  assetType == 'electronics'
                      ? Icons.devices
                      : Icons.landscape,
                ),
                title: Text(
                  assetType == 'electronics'
                      ? 'Electronics Transfer'
                      : 'Land Fraction Transfer',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      'From: ${transferService.shortenAddress(from)}',
                    ),
                    Text(
                      'To: ${transferService.shortenAddress(to)}',
                    ),
                    if (assetType == 'land')
                      Text('Amount: $amount fractions'),
                    if (txHash.isNotEmpty)
                      Text(
                        'Tx: ${transferService.shortenAddress(txHash)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
                trailing: Text(
                  _formatTimestamp(ts),
                  style: const TextStyle(fontSize: 12),
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Format timestamp like: 1/7/2026 at 10:30 AM
  static String _formatTimestamp(Timestamp? ts) {
    if (ts == null) return '';

    final d = ts.toDate();
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    final period = d.hour >= 12 ? 'PM' : 'AM';

    return '${d.day}/${d.month}/${d.year} at $hour:$minute $period';
  }
}
