// lib/screens/transfer_history_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../blockchain/transfer_service.dart';

class TransferHistoryScreen extends StatelessWidget {
  final String assetId;

  const TransferHistoryScreen({super.key, required this.assetId});

  @override
  Widget build(BuildContext context) {
    final transferService = TransferService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer History'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: transferService.getAssetTransferHistory(assetId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  Text(
                    'No transfers yet',
                    style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          final transfers = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: transfers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final data = transfers[index].data() as Map<String, dynamic>;
              final from = data['from'] ?? '';
              final to = data['to'] ?? '';
              final amount = data['amount'] ?? 1;
              final assetType = data['assetType'] ?? '';
              final txHash = data['txHash'] ?? '';
              final status = data['status'] ?? 'confirmed';
              final ts = data['timestamp'] as Timestamp?;

              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.green.withOpacity(0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header row ──
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(
                                assetType == 'electronics'
                                    ? Icons.devices
                                    : Icons.landscape,
                                size: 18,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                assetType == 'electronics'
                                    ? 'Electronics Transfer'
                                    : 'Land Fraction Transfer',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const Divider(height: 16),

                      // ── From / To ──
                      _infoRow(Icons.arrow_upward, 'From',
                          transferService.shortenAddress(from), Colors.red),
                      const SizedBox(height: 6),
                      _infoRow(Icons.arrow_downward, 'To',
                          transferService.shortenAddress(to), Colors.green),

                      if (assetType == 'land') ...[
                        const SizedBox(height: 6),
                        _infoRow(Icons.pie_chart, 'Fractions',
                            '$amount fractions', Colors.blue),
                      ],

                      const SizedBox(height: 8),
                      const Divider(height: 1),
                      const SizedBox(height: 8),

                      // ── TX Hash + date ──
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
                                  const Icon(Icons.open_in_new,
                                      size: 14, color: Colors.blue),
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
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]),
                          ),
                        ],
                      ),
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

  Widget _infoRow(
      IconData icon, String label, String value, Color iconColor) {
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
    final d = ts.toDate();
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    final period = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.day}/${d.month}/${d.year} $hour:$minute $period';
  }
}