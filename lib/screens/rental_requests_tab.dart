import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import 'rent_distribution_screen.dart';

class RentalRequestsTab extends StatelessWidget {
  const RentalRequestsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Center(child: Text('Not logged in'));

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text('Rental Requests', style: AppTheme.heading(18, color: Colors.white)),
        backgroundColor: AppTheme.primaryStart,
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('transactions')
            .where('sellerUid', isEqualTo: uid)
            .where('requestType', isEqualTo: 'rental')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting) {
             return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.key_off_rounded, size: 72, color: AppTheme.primaryStart.withOpacity(0.1)),
                  const SizedBox(height: 20),
                  Text('No rental requests found', 
                      style: AppTheme.body(16, color: AppTheme.textSecondary, weight: FontWeight.w500)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final txId = docs[index].id;
              final data = docs[index].data() as Map<String, dynamic>;
              return _RentalRequestCard(txId: txId, data: data);
            },
          );
        },
      ),
    );
  }
}

class _RentalRequestCard extends StatelessWidget {
  final String txId;
  final Map<String, dynamic> data;

  const _RentalRequestCard({required this.txId, required this.data});

  @override
  Widget build(BuildContext context) {
    final status = data['status'] ?? 'pending';
    final assetId = data['assetId'];
    final buyerUid = data['buyerUid'];
    final fee = data['rentalFee'] ?? 0.0;
    final deposit = data['depositAmount'] ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: AppTheme.roundedBox(
        color: Colors.white,
        radius: 18,
        shadows: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            // Open Rent Distribution Screen for management
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => RentDistributionScreen(
                  assetId: assetId,
                  propertyId: (data['blockchainTokenId'] as num).toInt(),
                  isOwner: true,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _StatusBadge(status: status),
                    Text(
                      _formatDate(data['createdAt'] as Timestamp?),
                      style: AppTheme.body(12, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('assets').doc(assetId).get(),
                  builder: (context, assetSnap) {
                    final assetData = assetSnap.data?.data() as Map<String, dynamic>?;
                    final title = assetData?['title'] ?? 'Loading...';
                    return Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.home_work_rounded, color: AppTheme.primaryStart, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(title, 
                              style: AppTheme.heading(16, color: AppTheme.textPrimary),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _InfoItem(label: 'Monthly Fee', value: '$fee MATIC', icon: Icons.payments_outlined),
                    _InfoItem(label: 'Security Deposit', value: '$deposit MATIC', icon: Icons.security_outlined),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection('users').doc(buyerUid).get(),
                      builder: (context, userSnap) {
                        final name = (userSnap.data?.data() as Map<String, dynamic>?)?['name'] ?? '...';
                        return Text('Requester: $name', style: AppTheme.body(13, color: AppTheme.textSecondary));
                      },
                    ),
                    Text('View Details →', style: AppTheme.body(13, color: AppTheme.primaryStart, weight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '—';
    final d = ts.toDate();
    return '${d.day}/${d.month}/${d.year}';
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'pendingApproval': color = Colors.orange; break;
      case 'approved': color = Colors.blue; break;
      case 'active': color = Colors.green; break;
      case 'completed': color = AppTheme.accent; break;
      case 'rejected': color = Colors.red; break;
      default: color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(status.toUpperCase(), 
          style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _InfoItem({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 4),
            Text(label, style: AppTheme.body(11, color: AppTheme.textSecondary)),
          ],
        ),
        const SizedBox(height: 4),
        Text(value, style: AppTheme.heading(14, color: AppTheme.primaryStart)),
      ],
    );
  }
}
