// lib/screens/admin_screen.dart
// Admin panel for Digital Goods (Synopsis Section 1.4)

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const AdminDashboard(),
    const UserManagement(),
    const AssetModeration(),
    const TransactionMonitor(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await auth.signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Users'),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: 'Assets'),
          BottomNavigationBarItem(icon: Icon(Icons.analytics), label: 'Transactions'),
        ],
      ),
    );
  }
}

/// Admin Dashboard
class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'System Overview',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Stats Cards
          Row(
            children: [
              Expanded(child: _StatCard(
                title: 'Total Users',
                collection: 'users',
                icon: Icons.people,
                color: Colors.blue,
              )),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(
                title: 'Total Assets',
                collection: 'assets',
                icon: Icons.inventory,
                color: Colors.green,
              )),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _StatCard(
                title: 'Transactions',
                collection: 'transactions',
                icon: Icons.swap_horiz,
                color: Colors.orange,
              )),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(
                title: 'Reviews',
                collection: 'reviews',
                icon: Icons.rate_review,
                color: Colors.purple,
              )),
            ],
          ),

          const SizedBox(height: 24),

          // Recent Activity
          const Text(
            'Recent Activity',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          StreamBuilder<QuerySnapshot>(
            stream: db.collection('assets')
                .orderBy('createdAt', descending: true)
                .limit(5)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const CircularProgressIndicator();

              final docs = snapshot.data!.docs;
              return Column(
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return ListTile(
                    leading: const Icon(Icons.fiber_new),
                    title: Text(data['title'] ?? 'New Asset'),
                    subtitle: Text('${data['category']} • PKR ${data['price']}'),
                    trailing: Text(_formatTimestamp(data['createdAt'])),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
    final dt = (timestamp as Timestamp).toDate();
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

/// Stat Card Widget
class _StatCard extends StatelessWidget {
  final String title;
  final String collection;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.collection,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection(collection).snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;

        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(icon, size: 40, color: color),
                const SizedBox(height: 8),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// User Management
class UserManagement extends StatelessWidget {
  const UserManagement({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('users').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final users = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index].data() as Map<String, dynamic>;
            final userId = users[index].id;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  child: Text((user['name'] ?? 'U')[0].toUpperCase()),
                ),
                title: Text(user['name'] ?? 'Unknown'),
                subtitle: Text('${user['email']}\nRole: ${user['role'] ?? 'user'}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'verify') {
                      await db.collection('users').doc(userId).update({
                        'verified': true,
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('User verified')),
                      );
                    } else if (value == 'suspend') {
                      await db.collection('users').doc(userId).update({
                        'suspended': true,
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('User suspended')),
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'verify', child: Text('Verify User')),
                    const PopupMenuItem(value: 'suspend', child: Text('Suspend User')),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Asset Moderation
class AssetModeration extends StatelessWidget {
  const AssetModeration({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('assets')
          .where('verified', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final assets = snapshot.data!.docs;

        if (assets.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, size: 64, color: Colors.green),
                SizedBox(height: 16),
                Text('All assets reviewed!'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: assets.length,
          itemBuilder: (context, index) {
            final asset = assets[index].data() as Map<String, dynamic>;
            final assetId = assets[index].id;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset['title'] ?? 'Untitled',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Category: ${asset['category']}'),
                    Text('Price: PKR ${asset['price']}'),
                    Text('Owner: ${asset['ownerName'] ?? asset['ownerId']}'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await db.collection('assets').doc(assetId).update({
                                'verified': true,
                                'verifiedAt': FieldValue.serverTimestamp(),
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✅ Asset approved'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            },
                            icon: const Icon(Icons.check),
                            label: const Text('Approve'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Reject Asset'),
                                  content: const Text(
                                    'Are you sure you want to reject this asset?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancel'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                      ),
                                      child: const Text('Reject'),
                                    ),
                                  ],
                                ),
                              );

                              if (confirmed == true) {
                                await db.collection('assets').doc(assetId).delete();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Asset rejected'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.close),
                            label: const Text('Reject'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                          ),
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
    );
  }
}

/// Transaction Monitor
class TransactionMonitor extends StatelessWidget {
  const TransactionMonitor({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('transactions')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final transactions = snapshot.data!.docs;

        if (transactions.isEmpty) {
          return const Center(child: Text('No transactions yet'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: transactions.length,
          itemBuilder: (context, index) {
            final tx = transactions[index].data() as Map<String, dynamic>;
            final status = tx['status'] ?? 'pending';
            final timestamp = tx['createdAt'] as Timestamp?;

            Color statusColor;
            IconData statusIcon;

            switch (status) {
              case 'completed':
                statusColor = Colors.green;
                statusIcon = Icons.check_circle;
                break;
              case 'approved':
                statusColor = Colors.blue;
                statusIcon = Icons.pending;
                break;
              case 'rejected':
                statusColor = Colors.red;
                statusIcon = Icons.cancel;
                break;
              default:
                statusColor = Colors.orange;
                statusIcon = Icons.hourglass_empty;
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(statusIcon, color: statusColor),
                title: Text('Asset: ${tx['assetId'] ?? 'Unknown'}'),
                subtitle: Text(
                  'Buyer: ${tx['buyerUid']}\n'
                      'Seller: ${tx['sellerUid']}\n'
                      'Status: $status',
                ),
                trailing: timestamp != null
                    ? Text(
                  '${timestamp.toDate().day}/${timestamp.toDate().month}',
                  style: const TextStyle(fontSize: 12),
                )
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}