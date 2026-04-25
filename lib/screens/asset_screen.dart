// lib/screens/asset_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'shared_screens.dart';
import 'asset_detail_screen.dart';

const Color _teal = Color(0xFF00695C);
const Color _tealBg = Color(0xFFE0F2F1);
const Color _dark = Color(0xFF1A1A2E);
const Color _grey = Color(0xFF8A9AAF);

// ─────────────────────────────────────────────────────────────────────────────
// MY ASSETS SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class MyAssetsScreen extends StatefulWidget {
  const MyAssetsScreen({super.key});

  @override
  State<MyAssetsScreen> createState() => _MyAssetsScreenState();
}

class _MyAssetsScreenState extends State<MyAssetsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
            body: Center(child: CircularProgressIndicator(color: _teal)),
          );
        }
        final role = snap.data ?? 'user';

        // ── Supplier view ─────────────────────────────────────────────────
        if (role.toLowerCase().contains('supplier')) {
          return _SupplierAssetsView(userId: user.uid);
        }

        // ── Regular user view ─────────────────────────────────────────────
        return Scaffold(
          backgroundColor: Colors.grey.shade50,
          appBar: _buildAppBar('My Assets'),
          body: Column(
            children: [
              _SearchBar(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
              ),
              Expanded(
                child: _MergedOwnerAssetsBuilder(
                  userId: user.uid,
                  sortField: 'transferredAt',
                  builder: (docs) {
                    var filteredDocs = docs;
                    if (_query.isNotEmpty) {
                      filteredDocs = docs.where((d) {
                        final data = d.data();
                        final title = (data['title'] ?? '')
                            .toString()
                            .toLowerCase();
                        final cat = (data['category'] ?? '')
                            .toString()
                            .toLowerCase();
                        return title.contains(_query) || cat.contains(_query);
                      }).toList();
                    }

                    if (filteredDocs.isEmpty) {
                      return _EmptyView(
                        icon: Icons.inventory_2_outlined,
                        title: 'No owned assets yet',
                        subtitle: 'Assets transferred to you will appear here.',
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: filteredDocs.length,
                      itemBuilder: (context, i) {
                        final d = filteredDocs[i].data();
                        final id = filteredDocs[i].id;
                        final category = d['category'] ?? 'electronics';
                        final isLand = category == 'land';
                        final img = _firstImage(d);
                        final hasNFT = d['blockchainTokenId'] != null;
                        final transferredAt = d['transferredAt'];

                        String transferDate = '';
                        if (transferredAt is Timestamp) {
                          final dt = transferredAt.toDate();
                          transferDate =
                              '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
                        }

                        return _AssetCard(
                          image: img,
                          title: d['title'] ?? 'Untitled',
                          badge: hasNFT ? 'NFT' : null,
                          categoryLabel: isLand ? '🏡 Land' : '📦 Electronics',
                          price: 'PKR ${d['price'] ?? '—'}',
                          detail1: isLand
                              ? '${d['location'] ?? ''}, ${d['city'] ?? ''}'
                              : '${d['brand'] ?? '—'} ${d['model'] ?? ''}',
                          detail2: isLand
                              ? (d['plotArea'] != null
                                    ? '${d['plotArea']} ${d['plotUnit'] ?? ''}'
                                    : null)
                              : (d['serial'] != null
                                    ? 'S/N: ${d['serial']}'
                                    : null),
                          transferDate: transferDate,
                          tokenId: hasNFT ? '#${d['blockchainTokenId']}' : null,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AssetDetailScreen(assetId: id),
                            ),
                          ),
                          primaryAction: _ActionButton(
                            label: 'Full Certificate',
                            icon: Icons.verified_user_outlined,
                            outlined: true,
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => NFTCertificateScreen(
                                  assetId: id,
                                  assetData: d,
                                ),
                              ),
                            ),
                          ),
                          secondaryAction: _ActionButton(
                            label: 'Resale',
                            icon: Icons.sell_outlined,
                            outlined: false,
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AssetDetailScreen(assetId: id),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUPPLIER ASSETS VIEW
// ─────────────────────────────────────────────────────────────────────────────
class _SupplierAssetsView extends StatefulWidget {
  final String userId;
  const _SupplierAssetsView({required this.userId});

  @override
  State<_SupplierAssetsView> createState() => _SupplierAssetsViewState();
}

class _SupplierAssetsViewState extends State<_SupplierAssetsView> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildAppBar('My Published Assets'),
      body: Column(
        children: [
          _SearchBar(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v.toLowerCase()),
          ),
          Expanded(
            child: _MergedOwnerAssetsBuilder(
              userId: widget.userId,
              sortField: 'createdAt',
              builder: (docs) {
                var filtered = docs;
                if (_query.isNotEmpty) {
                  filtered = docs.where((d) {
                    final data = d.data();
                    final title = (data['title'] ?? '')
                        .toString()
                        .toLowerCase();
                    final cat = (data['category'] ?? '')
                        .toString()
                        .toLowerCase();
                    return title.contains(_query) || cat.contains(_query);
                  }).toList();
                }

                if (filtered.isEmpty) {
                  return _EmptyView(
                    icon: Icons.store_outlined,
                    title: 'No published assets',
                    subtitle: 'Assets you publish will appear here.',
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final d = filtered[i].data();
                    final id = filtered[i].id;
                    final isLand = (d['category'] ?? '') == 'land';
                    final img = _firstImage(d);
                    final hasNFT = d['blockchainTokenId'] != null;

                    return _AssetCard(
                      image: img,
                      title: d['title'] ?? d['name'] ?? 'Untitled',
                      badge: hasNFT ? 'NFT' : null,
                      categoryLabel: isLand ? '🏡 Land' : '📦 Electronics',
                      price: 'PKR ${d['price'] ?? '—'}',
                      detail1: isLand
                          ? '${d['location'] ?? ''}, ${d['city'] ?? ''}'
                          : '${d['brand'] ?? '—'} ${d['model'] ?? ''}',
                      detail2: isLand
                          ? (d['plotArea'] != null
                                ? '${d['plotArea']} ${d['plotUnit'] ?? ''}'
                                : null)
                          : (d['serial'] != null
                                ? 'S/N: ${d['serial']}'
                                : null),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AssetDetailScreen(assetId: id),
                        ),
                      ),
                      primaryAction: _ActionButton(
                        label: 'Full Certificate',
                        icon: Icons.verified_user_outlined,
                        outlined: true,
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Certificate generated'),
                              backgroundColor: _teal,
                            ),
                          );
                        },
                      ),
                      secondaryAction: _ActionButton(
                        label: 'View Asset',
                        icon: Icons.visibility_outlined,
                        outlined: false,
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AssetDetailScreen(assetId: id),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE CARD
// ─────────────────────────────────────────────────────────────────────────────
class _AssetCard extends StatelessWidget {
  final String? image;
  final String title;
  final String? badge;
  final String categoryLabel;
  final String price;
  final String? detail1;
  final String? detail2;
  final String? transferDate;
  final String? tokenId;
  final VoidCallback onTap;
  final _ActionButton primaryAction;
  final _ActionButton secondaryAction;

  const _AssetCard({
    required this.image,
    required this.title,
    this.badge,
    required this.categoryLabel,
    required this.price,
    this.detail1,
    this.detail2,
    this.transferDate,
    this.tokenId,
    required this.onTap,
    required this.primaryAction,
    required this.secondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.07),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image ──────────────────────────────────────
            // SizedBox outside ClipRRect gives Stack concrete height bounds.
            // StackFit.expand fills every child into the 180px slot.
            SizedBox(
              height: 180,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    image != null
                        ? buildAssetImage(
                            image,
                            width: double.infinity,
                            height: 180,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: const Color(0xFFE8F4F6),
                            child: const Center(
                              child: Icon(
                                Icons.image_outlined,
                                size: 48,
                                color: _grey,
                              ),
                            ),
                          ),
                    // Badge
                    if (badge != null)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _teal,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.verified,
                                color: Colors.white,
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                badge!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Category chip
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          categoryLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Body ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _dark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),

                  // Detail rows
                  if (detail1 != null && detail1!.isNotEmpty)
                    _DetailRow(
                      icon: Icons.location_on_outlined,
                      text: detail1!,
                    ),
                  if (detail2 != null && detail2!.isNotEmpty)
                    _DetailRow(icon: Icons.straighten_outlined, text: detail2!),
                  if (transferDate != null && transferDate!.isNotEmpty)
                    _DetailRow(
                      icon: Icons.swap_horiz_outlined,
                      text: 'Transferred: $transferDate',
                      color: _teal,
                    ),
                  if (tokenId != null)
                    _DetailRow(
                      icon: Icons.token_outlined,
                      text: 'Token $tokenId',
                      color: _teal,
                    ),

                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFF0F0F0)),
                  const SizedBox(height: 12),

                  // Price + actions
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          price,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _teal,
                          ),
                        ),
                      ),
                      primaryAction,
                      const SizedBox(width: 8),
                      secondaryAction,
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL HELPERS
// ─────────────────────────────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool outlined;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.outlined,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final style = outlined
        ? OutlinedButton.styleFrom(
            foregroundColor: _teal,
            side: const BorderSide(color: _teal, width: 1.4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          )
        : ElevatedButton.styleFrom(
            backgroundColor: _teal,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          );

    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 14), const SizedBox(width: 4), Text(label)],
    );

    return outlined
        ? OutlinedButton(onPressed: onPressed, style: style, child: child)
        : ElevatedButton(onPressed: onPressed, style: style, child: child);
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _DetailRow({
    required this.icon,
    required this.text,
    this.color = _grey,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: const TextStyle(fontSize: 14, color: _dark),
                decoration: InputDecoration(
                  hintText: 'Search assets…',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: Colors.grey.shade400,
                    size: 20,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _teal,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: _teal.withOpacity(0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

AppBar _buildAppBar(String title) {
  return AppBar(
    backgroundColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    leadingWidth: 72,
    leading: Builder(
      builder: (context) => IconButton(
        icon: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(Icons.chevron_left_rounded, color: _dark, size: 24),
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ),
    title: Text(
      title,
      style: const TextStyle(
        color: _dark,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
    ),
    centerTitle: true,
  );
}

class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyView({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _tealBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 40, color: _teal),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: _dark,
            ),
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: _grey)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Error: $error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
      ),
    );
  }
}

String? _firstImage(Map<String, dynamic> d) =>
    (d['images'] is List && (d['images'] as List).isNotEmpty)
    ? (d['images'] as List)[0] as String?
    : null;

// ─────────────────────────────────────────────────────────────────────────────
// RELATED ITEMS LIST  (unchanged logic, cleaner card)
// ─────────────────────────────────────────────────────────────────────────────
class RelatedItemsList extends StatelessWidget {
  final String? type;
  final String? city;
  const RelatedItemsList({super.key, this.type, this.city});

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> q = db
        .collection('assets')
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snap, _) => snap.data() ?? <String, dynamic>{},
          toFirestore: (m, _) => m,
        );
    if (type != null) q = q.where('category', isEqualTo: type);
    if (city != null) q = q.where('city', isEqualTo: city);
    q = q.limit(6);

    return SizedBox(
      height: 150,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: _teal));
          }
          final docs = snap.data!.docs;
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final img = _firstImage(d);
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AssetDetailScreen(assetId: docs[i].id),
                  ),
                ),
                child: Container(
                  width: 140,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: SizedBox(
                          height: 90,
                          width: double.infinity,
                          child: img != null
                              ? buildAssetImage(
                                  img,
                                  width: double.infinity,
                                  height: 90,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color: const Color(0xFFE8F4F6),
                                  child: const Icon(
                                    Icons.image_outlined,
                                    color: _grey,
                                  ),
                                ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          d['title'] ?? d['name'] ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _dark,
                          ),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAVORITES SCREEN
// ─────────────────────────────────────────────────────────────────────────────
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Not logged in')));
    }

    final q = db
        .collection('users')
        .doc(user.uid)
        .collection('favorites')
        .orderBy('createdAt', descending: true);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildAppBar('Favorites'),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _ErrorView(error: snap.error.toString());
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: _teal));
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return _EmptyView(
              icon: Icons.favorite_border_outlined,
              title: 'No favorites yet',
              subtitle: 'Assets you save will appear here.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final favorite = docs[i].data();
              final assetId = (favorite['assetId'] ?? docs[i].id)
                  .toString()
                  .trim();

              if (assetId.isEmpty) {
                return _InlineStatusCard(
                  icon: Icons.bookmark_remove_outlined,
                  title: 'This favorite is missing asset data',
                  subtitle: 'Remove it to keep your favorites list clean.',
                  actionLabel: 'Remove',
                  onAction: () {
                    db
                        .collection('users')
                        .doc(user.uid)
                        .collection('favorites')
                        .doc(docs[i].id)
                        .delete();
                  },
                );
              }

              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: db.collection('assets').doc(assetId).get(),
                builder: (context, assetSnap) {
                  if (assetSnap.connectionState == ConnectionState.waiting) {
                    return const _FavoriteSkeletonCard();
                  }
                  if (assetSnap.hasError) {
                    return _InlineStatusCard(
                      icon: Icons.error_outline_rounded,
                      title: 'Could not load this favorite',
                      subtitle: 'Please remove it and add it again if needed.',
                      actionLabel: 'Remove',
                      onAction: () {
                        db
                            .collection('users')
                            .doc(user.uid)
                            .collection('favorites')
                            .doc(docs[i].id)
                            .delete();
                      },
                    );
                  }
                  if (!assetSnap.hasData || !assetSnap.data!.exists) {
                    return _InlineStatusCard(
                      icon: Icons.inventory_2_outlined,
                      title: 'This asset is no longer available',
                      subtitle: 'You can remove it from your favorites list.',
                      actionLabel: 'Remove',
                      onAction: () {
                        db
                            .collection('users')
                            .doc(user.uid)
                            .collection('favorites')
                            .doc(docs[i].id)
                            .delete();
                      },
                    );
                  }
                  final asset = assetSnap.data!.data() ?? <String, dynamic>{};
                  final img = _firstImage(asset);

                  return _AssetCard(
                    image: img,
                    title: asset['title'] ?? asset['name'] ?? 'Asset',
                    categoryLabel: (asset['category'] ?? '') == 'land'
                        ? '🏡 Land'
                        : '📦 Electronics',
                    price: 'PKR ${asset['price'] ?? 'N/A'}',
                    detail1: asset['location'] != null
                        ? '${asset['location']}, ${asset['city'] ?? ''}'
                        : null,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AssetDetailScreen(assetId: assetId),
                      ),
                    ),
                    primaryAction: _ActionButton(
                      label: 'Remove',
                      icon: Icons.delete_outline,
                      outlined: true,
                      onPressed: () {
                        db
                            .collection('users')
                            .doc(user.uid)
                            .collection('favorites')
                            .doc(docs[i].id)
                            .delete();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Removed from favorites'),
                            backgroundColor: _teal,
                          ),
                        );
                      },
                    ),
                    secondaryAction: _ActionButton(
                      label: 'View',
                      icon: Icons.visibility_outlined,
                      outlined: false,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AssetDetailScreen(assetId: assetId),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _MergedOwnerAssetsBuilder extends StatelessWidget {
  final String userId;
  final String sortField;
  final Widget Function(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs)
  builder;

  const _MergedOwnerAssetsBuilder({
    required this.userId,
    required this.sortField,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final assetsRef = db.collection('assets');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: assetsRef.where('ownerId', isEqualTo: userId).snapshots(),
      builder: (context, ownerIdSnap) {
        if (ownerIdSnap.hasError) {
          return _ErrorView(error: ownerIdSnap.error.toString());
        }
        if (!ownerIdSnap.hasData) {
          return const Center(child: CircularProgressIndicator(color: _teal));
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: assetsRef.where('ownerUid', isEqualTo: userId).snapshots(),
          builder: (context, ownerUidSnap) {
            final primaryDocs = ownerIdSnap.data!.docs;

            if (ownerUidSnap.hasError && primaryDocs.isEmpty) {
              return _ErrorView(error: ownerUidSnap.error.toString());
            }
            if (!ownerUidSnap.hasData && primaryDocs.isEmpty) {
              return const Center(
                child: CircularProgressIndicator(color: _teal),
              );
            }

            final docs = _mergeAssetDocs(
              primaryDocs,
              ownerUidSnap.data?.docs ??
                  const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
              sortField: sortField,
            );

            return builder(docs);
          },
        );
      },
    );
  }
}

List<QueryDocumentSnapshot<Map<String, dynamic>>> _mergeAssetDocs(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> primary,
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> secondary, {
  required String sortField,
}) {
  final merged = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  final seenIds = <String>{};

  for (final doc in [...primary, ...secondary]) {
    if (seenIds.add(doc.id)) {
      merged.add(doc);
    }
  }

  merged.sort((a, b) {
    final aTs = a.data()[sortField];
    final bTs = b.data()[sortField];
    if (aTs is Timestamp && bTs is Timestamp) {
      return bTs.compareTo(aTs);
    }
    if (aTs is Timestamp) return -1;
    if (bTs is Timestamp) return 1;
    return 0;
  });

  return merged;
}

class _FavoriteSkeletonCard extends StatelessWidget {
  const _FavoriteSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Container(
              height: 180,
              width: double.infinity,
              color: Colors.grey.shade100,
              child: const Center(
                child: CircularProgressIndicator(color: _teal, strokeWidth: 2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  width: 160,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 11,
                  width: 220,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 11,
                  width: 180,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineStatusCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  const _InlineStatusCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE3EBEE)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _tealBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: _teal),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _dark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: _grey,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: _teal,
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    actionLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
