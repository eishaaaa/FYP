// lib/screens/admin_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_screens.dart';
import '../blockchain/blockchain_service.dart';
import '../theme.dart';

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;

// Brand colors removed - using AppTheme
ThemeData get adminTheme => ThemeData(
  useMaterial3: true,
  fontFamily: 'Poppins',
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppTheme.primaryStart,
    primary: AppTheme.primaryStart,
    secondary: AppTheme.accent,
    surface: AppTheme.background,
  ),
  scaffoldBackgroundColor: AppTheme.background,
  appBarTheme: const AppBarTheme(
    backgroundColor: AppTheme.primaryStart,
    foregroundColor: Colors.white,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: TextStyle(
      fontFamily: 'Poppins',
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    ),
  ),
  cardTheme: CardThemeData(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
    margin: EdgeInsets.zero,
  ),
  bottomNavigationBarTheme: BottomNavigationBarThemeData(
    backgroundColor: Colors.white,
    selectedItemColor: AppTheme.primaryStart,
    unselectedItemColor: Colors.grey,
    selectedLabelStyle: AppTheme.body(11, weight: FontWeight.w600),
    unselectedLabelStyle: AppTheme.body(11),
    elevation: 12,
    type: BottomNavigationBarType.fixed,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppTheme.primaryStart,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(vertical: 14),
      textStyle: AppTheme.body(14, weight: FontWeight.w600),
    ),
  ),
  chipTheme: ChipThemeData(
    selectedColor: AppTheme.primaryStart,
    backgroundColor: AppTheme.surface,
    labelStyle: AppTheme.body(13, weight: FontWeight.w500),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    side: BorderSide.none,
  ),
);

// ─── Admin Home ───────────────────────────────────────────────────────────────
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

  final List<String> _titles = [
    'Dashboard',
    'Users',
    'Properties',
    'Transactions',
  ];

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: adminTheme,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(_titles[_selectedIndex]),
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: AppTheme.primaryGradient,
            ),
          ),
          actions: [
            Container(
              margin: const EdgeInsets.only(right: 12),
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.logout_rounded, size: 20),
                ),
                onPressed: () async {
                  await auth.signOut();
                  if (context.mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                          (_) => false,
                    );
                  }
                },
              ),
            ),
          ],
        ),
        body: _pages[_selectedIndex],
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: BottomNavigationBar(
            currentIndex: _selectedIndex,
            onTap: (i) => setState(() => _selectedIndex = i),
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.grid_view_rounded),
                label: 'Dashboard',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.people_alt_rounded),
                label: 'Users',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.apartment_rounded),
                label: 'Properties',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.receipt_long_rounded),
                label: 'Transactions',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Admin Dashboard ──────────────────────────────────────────────────────────
class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Good Morning 👋',
                        style: AppTheme.body(13, color: Colors.white70),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Admin Panel',
                        style: AppTheme.heading(22, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'System Overview',
                        style: AppTheme.body(13, color: Colors.white.withOpacity(0.8)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.apartment_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Statistics',
            style: AppTheme.heading(16, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 12),

          // Stats grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.1,
            children: [
              _StatCard(
                title: 'Total Users',
                collection: 'users',
                icon: Icons.people_alt_rounded,
                gradientColors: [AppTheme.primaryStart, AppTheme.primaryEnd],
              ),
              _StatCard(
                title: 'Properties',
                collection: 'assets',
                icon: Icons.apartment_rounded,
                gradientColors: [AppTheme.primaryEnd, AppTheme.primaryStart],
              ),
              _StatCard(
                title: 'Transactions',
                collection: 'transactions',
                icon: Icons.receipt_long_rounded,
                gradientColors: [AppTheme.accent, AppTheme.primaryStart],
              ),
              _StatCard(
                title: 'Reviews',
                collection: 'reviews',
                icon: Icons.star_rounded,
                gradientColors: [AppTheme.primaryStart, AppTheme.accent],
              ),
            ],
          ),

          const SizedBox(height: 28),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Properties',
                style: AppTheme.heading(16, color: AppTheme.textPrimary),
              ),
              TextButton(
                onPressed: () {},
                child: Text(
                  'See All',
                  style: AppTheme.heading(13, color: AppTheme.primaryStart),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          StreamBuilder<QuerySnapshot>(
            stream: db
                .collection('assets')
                .orderBy('createdAt', descending: true)
                .limit(5)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: AppTheme.primaryStart),
                  ),
                );
              }
              final docs = snapshot.data!.docs;
              return Column(
                children: docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final verified = data['verified'] == true;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryStart.withOpacity(0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.apartment_rounded,
                            color: AppTheme.primaryStart,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                data['title'] ?? 'New Property',
                                style: AppTheme.heading(14, color: AppTheme.textPrimary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${data['category'] ?? ''} • PKR ${data['price'] ?? 0}',
                                style: AppTheme.body(12, color: AppTheme.textMid),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: verified
                                ? Colors.green.withOpacity(0.12)
                                : Colors.orange.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            verified ? 'Verified' : 'Pending',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: verified ? Colors.green.shade700 : Colors.orange.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Stat Card ────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String title;
  final String collection;
  final IconData icon;
  final List<Color> gradientColors;

  const _StatCard({
    required this.title,
    required this.collection,
    required this.icon,
    required this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection(collection).snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradientColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: gradientColors.first.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count',
                    style: AppTheme.heading(26, color: Colors.white),
                  ),
                  Text(
                    title,
                    style: AppTheme.body(12, color: Colors.white.withOpacity(0.85), weight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── User Management ──────────────────────────────────────────────────────────
class UserManagement extends StatelessWidget {
  const UserManagement({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar
        Container(
          color: AppTheme.primaryStart,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search users...',
                hintStyle: AppTheme.body(14, color: AppTheme.textMid),
                prefixIcon: Icon(Icons.search_rounded, color: AppTheme.textMid),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),

        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: db
                .collection('users')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: AppTheme.primaryStart));
              }

              final users = snapshot.data!.docs;

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: users.length,
                itemBuilder: (context, index) {
                  final user = users[index].data() as Map<String, dynamic>;
                  final userId = users[index].id;
                  final name = user['name'] ?? 'Unknown';
                  final role = user['role'] ?? 'user';
                  final verified = user['verified'] == true;
                  final suspended = user['suspended'] == true;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryStart.withOpacity(0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.primaryStart,
                        radius: 24,
                        child: Text(
                          name[0].toUpperCase(),
                          style: AppTheme.heading(16, color: Colors.white),
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: AppTheme.heading(14, color: AppTheme.textPrimary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryLight,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              role.toUpperCase(),
                              style: AppTheme.heading(9, color: AppTheme.primaryStart),
                            ),
                          ),
                          if (verified)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: const Icon(Icons.verified_rounded,
                                  color: AppTheme.primaryStart, size: 16),
                            ),
                          if (suspended)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: const Icon(Icons.block_rounded,
                                  color: Colors.red, size: 16),
                            ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 3),
                          Text(
                            user['email'] ?? '',
                            style: AppTheme.body(12, color: AppTheme.textMid),
                          ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded,
                            color: Colors.grey),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        onSelected: (value) async {
                          if (value == 'verify') {
                            await db
                                .collection('users')
                                .doc(userId)
                                .update({'verified': true});
                            if (context.mounted) {
                              _showSnack(context, 'User verified ✓',
                                  color: Colors.green);
                            }
                          } else if (value == 'suspend') {
                            await db
                                .collection('users')
                                .doc(userId)
                                .update({'suspended': true});
                            if (context.mounted) {
                              _showSnack(context, 'User suspended',
                                  color: Colors.red);
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'verify',
                            child: Row(
                              children: [
                                Icon(Icons.verified_rounded,
                                    color: AppTheme.primaryStart, size: 18),
                                SizedBox(width: 10),
                                Text('Verify User'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'suspend',
                            child: Row(
                              children: [
                                Icon(Icons.block_rounded,
                                    color: Colors.red, size: 18),
                                SizedBox(width: 10),
                                Text('Suspend User'),
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
          ),
        ),
      ],
    );
  }

  void _showSnack(BuildContext context, String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color ?? AppTheme.primaryStart,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// ─── Asset Moderation ─────────────────────────────────────────────────────────
class AssetModeration extends StatefulWidget {
  const AssetModeration({super.key});

  @override
  State<AssetModeration> createState() => _AssetModerationState();
}

class _AssetModerationState extends State<AssetModeration> {
  bool _showVerified = false;
  final _blockchainService = BlockchainServiceEnhanced();


  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> query = db.collection('assets');
    if (!_showVerified) {
      query = query.where('verified', isEqualTo: false);
    }
    query = query.orderBy('createdAt', descending: true);

    return Column(
      children: [
        // Filter header
        Container(
          color: AppTheme.primaryStart,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Row(
            children: [
              _FilterChip(
                label: 'Pending',
                selected: !_showVerified,
                onTap: () => setState(() => _showVerified = false),
              ),
              const SizedBox(width: 10),
              _FilterChip(
                label: 'All Properties',
                selected: _showVerified,
                onTap: () => setState(() => _showVerified = true),
              ),
            ],
          ),
        ),

        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: query.snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryStart));
              }

              final assets = snapshot.data!.docs;

              if (assets.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_circle_rounded,
                            size: 48, color: AppTheme.primaryStart),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'All caught up!',
                        style: AppTheme.heading(16, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'No properties found for this filter',
                        style: AppTheme.body(13, color: AppTheme.textMid),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: assets.length,
                itemBuilder: (context, index) {
                  final asset = assets[index].data();
                  final assetId = assets[index].id;
                  final isVerified = asset['verified'] == true;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryStart.withOpacity(0.07),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Card header
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isVerified
                                  ? [AppTheme.primaryStartDark, AppTheme.primaryStart]
                                  : [const Color(0xFF2C3E50), const Color(0xFF4B79A1)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(18),
                              topRight: Radius.circular(18),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.apartment_rounded,
                                    color: Colors.white, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  asset['title'] ?? 'Untitled',
                                  style: AppTheme.heading(16, color: Colors.white),
                                ),
                              ),
                              if (isVerified)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: Colors.green.shade300),
                                  ),
                                  child: Text(
                                    '✓ Verified',
                                    style: AppTheme.heading(11, color: Colors.white),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Card body
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _InfoRow(
                                icon: Icons.category_rounded,
                                label: 'Category',
                                value: asset['category'] ?? '—',
                              ),
                              const SizedBox(height: 8),
                              _InfoRow(
                                icon: Icons.payments_rounded,
                                label: 'Price',
                                value: 'PKR ${asset['price'] ?? 0}',
                              ),
                              const SizedBox(height: 8),
                              _InfoRow(
                                icon: Icons.person_rounded,
                                label: 'Owner',
                                value: asset['ownerName'] ?? asset['ownerId'] ?? '—',
                              ),
                              if (asset['blockchainTokenId'] != null) ...[
                                const SizedBox(height: 8),
                                _InfoRow(
                                  icon: Icons.token_rounded,
                                  label: 'Token ID',
                                  value: '#${asset['blockchainTokenId']}',
                                ),
                              ],

                              const SizedBox(height: 16),

                              if (!isVerified)
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () =>
                                            _approveAsset(assetId, asset),
                                        icon: const Icon(Icons.check_rounded,
                                            size: 18),
                                        label: const Text('Approve'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.primaryStart,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                              BorderRadius.circular(12)),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _rejectAsset(assetId),
                                        icon: const Icon(Icons.close_rounded,
                                            size: 18),
                                        label: const Text('Reject'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red,
                                          side: const BorderSide(
                                              color: Colors.red),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                              BorderRadius.circular(12)),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 12),
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              else
                                SizedBox(
                                  width: double.infinity,
                                  child: Column(
                                    children: [
                                      if (asset['category']?.toString().toLowerCase() == 'electronics' && 
                                          (asset['currentOwnerAddress'] == null || asset['currentOwnerAddress'].toString().isEmpty))
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 10),
                                          child: SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton.icon(
                                              onPressed: () => _transferToSupplier(assetId, asset),
                                              icon: const Icon(Icons.local_shipping_rounded, size: 18),
                                              label: const Text('Transfer to Supplier'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.orange,
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                padding: const EdgeInsets.symmetric(vertical: 12),
                                              ),
                                            ),
                                          ),
                                        ),
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton.icon(
                                          onPressed: () => _revokeVerification(assetId),
                                          icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                                          label: const Text('Revoke Verification'),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.orange,
                                            side: const BorderSide(color: Colors.orange),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
          ),
        ),
      ],
    );
  }

  Future<void> _approveAsset(
      String assetId, Map<String, dynamic> assetData) async {
    try {
      // 1. Update Firebase
      await db.collection('assets').doc(assetId).update({
        'verified': true,
        'isMinted': true,
        'verifiedAt': FieldValue.serverTimestamp(),
      });

      // 2. Trigger Blockchain Verification (Fixes 'Pending' status)
      final tokenId = assetData['blockchainTokenId'];
      if (tokenId != null) {
        final category = assetData['category']?.toString().toLowerCase() ?? '';
        final id = (tokenId is int) ? tokenId : int.tryParse(tokenId.toString());
        
        if (id != null) {
          if (category == 'land') {
            await _blockchainService.verifyProperty(id);
          } else {
            await _blockchainService.verifyDevice(id);
          }
        }
      }

      if (mounted) {
        _showSnack('✅ Asset approved & verified on blockchain!', color: Colors.green);
      }
    } catch (e) {
      if (mounted) _showSnack('Error during verification: $e', color: Colors.red);
    }
  }

  Future<void> _rejectAsset(String assetId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reject Property', style: AppTheme.heading(20)),
        content: const Text(
            'Are you sure you want to reject this property listing?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: AppTheme.body(14, color: AppTheme.textMid)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await db.collection('assets').doc(assetId).delete();
      if (mounted) _showSnack('Property rejected', color: Colors.red);
    }
  }

  Future<void> _revokeVerification(String assetId) async {
    await db.collection('assets').doc(assetId).update({
      'verified': false,
      'isMinted': false,
    });
    if (mounted) _showSnack('Verification revoked', color: Colors.orange);
  }

  Future<void> _transferToSupplier(String assetId, Map<String, dynamic> assetData) async {
    // 1. Fetch Suppliers
    final suppliersQuery = await db.collection('users')
        .where('role', isGreaterThanOrEqualTo: 'supplier')
        .where('role', isLessThanOrEqualTo: 'supplier\uf8ff')
        .get();
    
    if (suppliersQuery.docs.isEmpty) {
      _showSnack('No suppliers found in the system.', color: Colors.orange);
      return;
    }

    if (!mounted) return;

    // 2. Show Picker
    final supplier = await showDialog<QueryDocumentSnapshot>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Supplier'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: suppliersQuery.docs.length,
            itemBuilder: (_, i) {
              final s = suppliersQuery.docs[i].data();
              return ListTile(
                title: Text(s['name'] ?? 'Unknown'),
                subtitle: Text(s['email'] ?? ''),
                onTap: () => Navigator.pop(ctx, suppliersQuery.docs[i]),
              );
            },
          ),
        ),
      ),
    );

    if (supplier == null) return;

    try {
      final sData = supplier.data() as Map<String, dynamic>;
      final address = sData['walletAddress'] ?? sData['address'];
      
      if (address == null || address.toString().isEmpty) {
        _showSnack('Supplier has no wallet address linked.', color: Colors.red);
        return;
      }

      final tokenId = assetData['blockchainTokenId'];
      if (tokenId == null) throw 'Missing Blockchain Token ID';

      _showSnack('⏳ Processing blockchain transfer...');
      
      // Execute Transfer
      final tx = await _blockchainService.transferElectronics(
        toAddress: address,
        tokenId: (tokenId is int) ? tokenId : int.parse(tokenId.toString()),
      );

      if (tx != null) {
        // Update Firestore
        await db.collection('assets').doc(assetId).update({
          'currentOwnerAddress': address,
          'supplierUid': supplier.id,
          'status': 'InTransit', // Moving from Dell to Supplier
        });
        
        _showSnack('✅ Successfully transferred to ${sData['name']}!', color: Colors.green);
      }
    } catch (e) {
      _showSnack('Transfer failed: $e', color: Colors.red);
    }
  }

  void _showSnack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color ?? AppTheme.primaryStart,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// ─── Transaction Monitor ──────────────────────────────────────────────────────
class TransactionMonitor extends StatelessWidget {
  const TransactionMonitor({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db
          .collection('transactions')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryStart));
        }

        final transactions = snapshot.data!.docs;

        if (transactions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.receipt_long_rounded,
                      size: 48, color: AppTheme.primaryStart),
                ),
                const SizedBox(height: 16),
                Text(
                  'No transactions yet',
                  style: AppTheme.heading(16, color: AppTheme.textPrimary),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: transactions.length,
          itemBuilder: (context, index) {
            final tx = transactions[index].data() as Map<String, dynamic>;
            final status = tx['status'] ?? 'pending';
            final timestamp = tx['createdAt'] as Timestamp?;

            Color statusColor;
            IconData statusIcon;
            String statusLabel;

            switch (status) {
              case 'completed':
                statusColor = Colors.green;
                statusIcon = Icons.check_circle_rounded;
                statusLabel = 'Completed';
                break;
              case 'approved':
                statusColor = AppTheme.primaryStart;
                statusIcon = Icons.pending_rounded;
                statusLabel = 'Approved';
                break;
              case 'rejected':
                statusColor = Colors.red;
                statusIcon = Icons.cancel_rounded;
                statusLabel = 'Rejected';
                break;
              default:
                statusColor = Colors.orange;
                statusIcon = Icons.hourglass_top_rounded;
                statusLabel = 'Pending';
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryStart.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(statusIcon, color: statusColor, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Property: ${tx['assetId'] ?? 'Unknown'}',
                            style: AppTheme.heading(14, color: AppTheme.textPrimary),
                          ),
                          const SizedBox(height: 6),
                          _TxInfo(
                              label: 'Buyer', value: tx['buyerUid'] ?? '—'),
                          _TxInfo(
                              label: 'Seller', value: tx['sellerUid'] ?? '—'),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (timestamp != null)
                      Text(
                        '${timestamp.toDate().day}/${timestamp.toDate().month}\n${timestamp.toDate().year}',
                        textAlign: TextAlign.right,
                        style: AppTheme.body(11, color: AppTheme.textMid),
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

// ─── Small reusable widgets ───────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
            style: AppTheme.heading(13, color: selected ? AppTheme.primaryStart : Colors.white),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.primaryStart),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: AppTheme.body(13, color: AppTheme.textMid),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTheme.heading(13, color: AppTheme.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _TxInfo extends StatelessWidget {
  final String label;
  final String value;

  const _TxInfo({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12),
          children: [
            TextSpan(
              text: '$label: ',
              style: AppTheme.body(12, color: AppTheme.textMid),
            ),
            TextSpan(
              text: value,
              style: AppTheme.heading(12, color: AppTheme.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}