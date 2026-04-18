// lib/screens/user_screens.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'shared_screens.dart';
import 'chat_list_screen.dart';
import 'wallet_screen.dart';
import 'qr_scanner_enhanced.dart';
import '../blockchain/blockchain_service.dart';
import '../services/resale_service.dart';
import 'resale_listing_sheet.dart';

final db = FirebaseFirestore.instance;

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  int _index = 0;
  String _category = "land";
  String _search = "";
  Map<String, dynamic> _filters = {};

  void _openFilters() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        maxChildSize: 0.95,
        initialChildSize: 0.75,
        builder: (_, controller) => FilterSheet(
          category: _category,
          controller: controller,
          existing: _filters,
        ),
      ),
    );
    if (result != null) setState(() => _filters = result);
  }

  void _nav(int i) {
    if (i == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const QRScannerEnhanced()),
      );
      return;
    }
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _index == 3
          ? null
          : _index == 2
          ? AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() => _index = 0),
        ),
        title: const Text("My Assets"),
      )
          : AppBar(
        title: const Text("Marketplace"),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
          ),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where('receiverId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
                .where('isRead', isEqualTo: false)
                .snapshots(),
            builder: (context, snapshot) {
              int unreadCount = snapshot.data?.docs.length ?? 0;
              return Badge(
                label: Text(unreadCount.toString()),
                isLabelVisible: unreadCount > 0,
                offset: const Offset(-4, 4),
                child: IconButton(
                  icon: const Icon(Icons.notifications_none_rounded),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: _index == 0 ? FloatingActionButton(
        heroTag: 'chat_fab',
        child: const Icon(Icons.chat),
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChatListScreen()),
          );
        },
      ) : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _nav,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: "Scan"),
          BottomNavigationBarItem(icon: Icon(Icons.inventory), label: "My Assets"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          _mainMarketplaceBody(),
          const SizedBox(), // Placeholder for Scan (handled by nav)
          const MyAssetsScreen(),
          ProfileScreen(onBack: () => setState(() => _index = 0)),
        ],
      ),
    );
  }

  Widget _mainMarketplaceBody() {
    return SafeArea(
      child: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: "Search assets...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: _openFilters,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
          ),

          // Category selector
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text("Land"),
                  selected: _category == "land",
                  onSelected: (_) => setState(() {
                    _category = "land";
                    _filters = {};
                  }),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text("Electronics"),
                  selected: _category == "electronics",
                  onSelected: (_) => setState(() {
                    _category = "electronics";
                    _filters = {};
                  }),
                ),
              ],
            ),
          ),

          // Asset list
          Expanded(
            child: AssetListView(
              category: _category,
              search: _search,
              filters: _filters,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// MY ASSETS SCREEN (Integrated)
// ═══════════════════════════════════════════════════════════

class MyAssetsScreen extends StatefulWidget {
  const MyAssetsScreen({super.key});

  @override
  State<MyAssetsScreen> createState() => _MyAssetsScreenState();
}

class _MyAssetsScreenState extends State<MyAssetsScreen> {
  final BlockchainServiceEnhanced _blockchain = BlockchainServiceEnhanced();
  final ResaleService _resaleSvc = ResaleService();
  bool _loading = false;

  // ── Owned-asset state ────────────────────────────────────────
  // Subscriptions are created once in initState and cancelled in dispose.
  // We keep the latest snapshot from each query and merge on every update.
  List<QueryDocumentSnapshot> _ownedAssets = [];
  bool  _assetsLoading = true;
  String? _assetsError;

  QuerySnapshot? _snap1; // ownerId  query
  QuerySnapshot? _snap2; // ownerUid query
  StreamSubscription? _sub1;
  StreamSubscription? _sub2;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) _subscribeToAssets(uid);
  }

  void _subscribeToAssets(String uid) {
    // Query 1 — ownerId  (written by _finalizeOwnership on every transfer)
    _sub1 = db
        .collection('assets')
        .where('ownerId', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      _snap1 = snap;
      _mergeAndSetState();
    }, onError: (e) {
      if (mounted) setState(() { _assetsError = e.toString(); _assetsLoading = false; });
    });

    // Query 2 — ownerUid (used by some supplier upload flows)
    _sub2 = db
        .collection('assets')
        .where('ownerUid', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      _snap2 = snap;
      _mergeAndSetState();
    }, onError: (e) {
      if (mounted) setState(() { _assetsError = e.toString(); _assetsLoading = false; });
    });
  }

  void _mergeAndSetState() {
    // Emit as soon as EITHER query resolves — don't wait for both.
    final seen = <String>{};
    final merged = <QueryDocumentSnapshot>[];
    for (final snap in [_snap1, _snap2]) {
      if (snap == null) continue;
      for (final doc in snap.docs) {
        if (seen.add(doc.id)) merged.add(doc);
      }
    }
    if (mounted) {
      setState(() {
        _ownedAssets  = merged;
        _assetsLoading = false;
        _assetsError  = null;
      });
    }
  }

  @override
  void dispose() {
    _sub1?.cancel();
    _sub2?.cancel();
    super.dispose();
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  Future<void> _ensureWalletConnected() async {
    if (!_blockchain.isConnected) await _blockchain.connectWallet(context);
  }

  Future<void> _claimRent(int propertyId) async {
    setState(() => _loading = true);
    try {
      await _ensureWalletConnected();
      final tx = await _blockchain.claimLandRent(propertyId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transaction Sent! Waiting for confirmation...')));
      if (tx != null) {
        await _blockchain.waitForConfirmation(tx);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Rent Claimed Successfully!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Resale helpers ────────────────────────────────────────────────────────
  Future<void> _listForResale(
      String assetId, Map<String, dynamic> asset) async {
    final listed = await ResaleListingSheet.show(
      context,
      assetId   : assetId,
      assetData : asset,
    );
    if (listed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content         : Text('Asset listed for resale on marketplace!'),
          backgroundColor : Colors.green,
        ),
      );
    }
  }

  Future<void> _removeListing(String assetId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title  : const Text('Remove Listing'),
        content: const Text(
            'This will hide the asset from the marketplace. You can re-list it at any time.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style    : ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child    : const Text('Remove',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _resaleSvc.removeListing(assetId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Listing removed. Asset hidden from marketplace.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _submitReview(int tokenId) async {
    final txtCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Submit Blockchain Review"),
        content: TextField(controller: txtCtrl,
            decoration: const InputDecoration(hintText: "Enter your review..."), maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (txtCtrl.text.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await _ensureWalletConnected();
                await _blockchain.submitElectronicsReview(tokenId: tokenId, reviewText: txtCtrl.text);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Review Transaction Sent!"), backgroundColor: Colors.green));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
              }
            },
            child: const Text("Submit"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Login required"));

    // ── Loading ──────────────────────────────────────────────
    if (_assetsLoading) return const Center(child: CircularProgressIndicator());

    // ── Error ────────────────────────────────────────────────
    if (_assetsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('Could not load assets:\n$_assetsError',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    // ── Empty ────────────────────────────────────────────────
    if (_ownedAssets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text("No assets owned yet"),
            TextButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Go to Home tab to buy assets"))),
              child: const Text("Browse Marketplace"),
            ),
          ],
        ),
      );
    }

    // ── Asset list ───────────────────────────────────────────
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _ownedAssets.length,
      itemBuilder: (context, index) {
        final assetDoc = _ownedAssets[index];
        final asset    = assetDoc.data() as Map<String, dynamic>;
        final assetId  = assetDoc.id;

        final tokenId          = asset['blockchainTokenId'] as int?;
        final title            = (asset['title'] as String?) ?? 'Unknown Asset';
        final imgList          = asset['images'] as List?;

        // Safe: first element might be a String, a Map, or anything else
        String? firstImg;
        if (imgList != null && imgList.isNotEmpty) {
          final raw = imgList.first;
          if (raw is String) firstImg = raw;
        }

        final resolvedCategory = (asset['category'] as String?) ?? 'land';
        final transferredAt    = asset['transferredAt'] as Timestamp?;
        final warrantyActivatedAt = resolvedCategory == 'electronics' ? transferredAt : null;
        final fractionAmount   = asset['fractionAmount'] as int?;

        // Wrap each card in an ErrorWidget boundary so one bad item
        // never crashes the whole list.
        return _SafeCard(
          key: ValueKey(assetId),
          child: Card(
            elevation: 3,
            margin: const EdgeInsets.only(bottom: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: assetId))),
              child: Column(
                children: [
                  // ── Header ──────────────────────────────────────
                  ListTile(
                    contentPadding: const EdgeInsets.all(10),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: buildAssetImage(firstImg, width: 60, height: 60),
                    ),
                    title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      resolvedCategory == 'land' ? 'Fractional Land Ownership' : 'Electronic Device',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    trailing: tokenId != null
                        ? Chip(
                      avatar: const Icon(Icons.verified, size: 14, color: Colors.white),
                      label: const Text('NFT', style: TextStyle(color: Colors.white, fontSize: 11)),
                      backgroundColor: Colors.green[700],
                      visualDensity: VisualDensity.compact,
                    )
                        : const Chip(label: Text('Pending'), visualDensity: VisualDensity.compact),
                  ),

                  const Divider(height: 1),

                  // ── Category panel ───────────────────────────────
                  if (resolvedCategory == 'land') ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                      child: Row(
                        children: [
                          Icon(Icons.pie_chart, size: 16, color: Colors.teal[700]),
                          const SizedBox(width: 6),
                          Text(
                            fractionAmount != null ? 'Fractions Owned: $fractionAmount' : 'Fractional Owner',
                            style: TextStyle(color: Colors.teal[800], fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    if (tokenId != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Flexible prevents unconstrained-width layout error
                            Flexible(
                              child: FutureBuilder<BigInt>(
                                future: _blockchain.getUnclaimedRent(user.uid, tokenId),
                                builder: (c, s) {
                                  if (s.hasError) return const Text('Rent: —', style: TextStyle(fontSize: 12));
                                  final rent = s.data ?? BigInt.zero;
                                  return Text(
                                    'Unclaimed: ${_blockchain.weiToEther(rent)} MATIC',
                                    style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold, fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Button must NOT use Size.fromHeight inside a Row
                            ElevatedButton.icon(
                              icon: _loading
                                  ? const SizedBox(width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.monetization_on, size: 15),
                              label: const Text('Claim Rent', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                // Explicit non-infinite minimumSize overrides any theme Size.fromHeight()
                                minimumSize: const Size(0, 36),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: _loading ? null : () => _claimRent(tokenId),
                            ),
                          ],
                        ),
                      ),
                  ] else ...[
                    if (warrantyActivatedAt != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.verified_user, size: 16, color: Colors.blue[700]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Warranty Activated',
                                        style: TextStyle(fontWeight: FontWeight.bold,
                                            color: Colors.blue[800], fontSize: 12)),
                                    Text(_formatDate(warrantyActivatedAt.toDate()),
                                        style: TextStyle(color: Colors.blue[700], fontSize: 11)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (tokenId != null)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.rate_review, size: 16),
                            label: const Text('Write Immutable Review', style: TextStyle(fontSize: 13)),
                            onPressed: () => _submitReview(tokenId),
                          ),
                        ),
                      ),
                  ],

                  const SizedBox(height: 4),

                  // ── Resale status + actions ──────────────────────────
                  const Divider(height: 1),
                  _buildResaleRow(assetId, asset),
                ],
              ),
            ),
          ), // end Card
        ); // end _SafeCard
      },
    );
  }


// ── Resale action row ─────────────────────────────────────────────────────
  Widget _buildResaleRow(String assetId, Map<String, dynamic> asset) {
    final isListed = asset['isListedForResale'] == true;
    final resalePrice = asset['resalePrice'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Status chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color       : isListed ? Colors.orange[50] : Colors.green[50],
              borderRadius: BorderRadius.circular(20),
              border      : Border.all(
                  color: isListed ? Colors.orange[300]! : Colors.green[300]!),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isListed ? Icons.storefront : Icons.inventory_2_outlined,
                  size : 13,
                  color: isListed ? Colors.orange[700] : Colors.green[700],
                ),
                const SizedBox(width: 4),
                Text(
                  isListed
                      ? (resalePrice != null
                      ? 'Listed · PKR $resalePrice'
                      : 'Listed for Resale')
                      : 'In Portfolio',
                  style: TextStyle(
                    fontSize   : 11,
                    fontWeight : FontWeight.w600,
                    color      : isListed ? Colors.orange[700] : Colors.green[700],
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Action button
          if (isListed)
            TextButton.icon(
              onPressed : () => _removeListing(assetId),
              icon      : const Icon(Icons.remove_circle_outline, size: 15),
              label     : const Text('Remove Listing', style: TextStyle(fontSize: 12)),
              style     : TextButton.styleFrom(
                foregroundColor : Colors.red[700],
                visualDensity   : VisualDensity.compact,
                padding         : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            )
          else
            TextButton.icon(
              onPressed : () => _listForResale(assetId, asset),
              icon      : const Icon(Icons.sell_outlined, size: 15),
              label     : const Text('List for Resale', style: TextStyle(fontSize: 12)),
              style     : TextButton.styleFrom(
                foregroundColor : Colors.blue[700],
                visualDensity   : VisualDensity.compact,
                padding         : const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Error-boundary wrapper — prevents one bad card from crashing the list ──
class _SafeCard extends StatelessWidget {
  final Widget child;
  const _SafeCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    try {
      return child;
    } catch (e) {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.broken_image, color: Colors.grey),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Could not display asset',
                    style: TextStyle(color: Colors.grey[600])),
              ),
            ],
          ),
        ),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════
// ASSET LIST VIEW (Search/Filter Logic)
// ═══════════════════════════════════════════════════════════

class AssetListView extends StatelessWidget {
  final String category;
  final String search;
  final Map<String, dynamic> filters;

  const AssetListView({
    super.key,
    required this.category,
    required this.search,
    required this.filters,
  });

  Query _buildQuery() {
    // 1. FIXED QUERY: Changed 'verified' to 'isMinted' to match supplier upload
    Query q = db
        .collection("assets")
        .where("category", isEqualTo: category)
        .where("isMinted", isEqualTo: true);

    if (filters["minPrice"] != null) {
      q = q.where("price", isGreaterThanOrEqualTo: (filters["minPrice"] as num).toInt());
    }

    if (filters["maxPrice"] != null) {
      q = q.where(
        "price",
        isLessThanOrEqualTo: (filters["maxPrice"] as num).toInt(),
      );
    }

    return q.orderBy("price").orderBy("createdAt", descending: true);
  }

  bool _matchesSearch(Map<String, dynamic> d) {
    if (search.isEmpty) return true;
    final title = (d["title"] ?? "").toString().toLowerCase();
    final city = (d["city"] ?? "").toString().toLowerCase();
    final brand = (d["brand"] ?? "").toString().toLowerCase();
    return title.contains(search) || brand.contains(search);
  }

  bool _matchesFilters(Map<String, dynamic> d) {

    // Brand filter (electronics)
    if (filters["brand"] != null && filters["brand"].toString().isNotEmpty) {
      if ((d["brand"] ?? "").toString().toLowerCase() !=
          filters["brand"].toString().toLowerCase()) {
        return false;
      }
    }

    // City / Location filter (land)
    if (filters["city"] != null && filters["city"].toString().isNotEmpty) {
      if ((d["city"] ?? "").toString().toLowerCase() !=
          filters["city"].toString().toLowerCase()) {
        return false;
      }
    }

    // 🔹 Electronics Specifications
    if (category == "electronics") {

      if (filters["ram"] != null && filters["ram"].toString().isNotEmpty) {
        if ((d["ram"] ?? "").toString() != filters["ram"].toString()) {
          return false;
        }
      }

      if (filters["storage"] != null && filters["storage"].toString().isNotEmpty) {
        if ((d["storage"] ?? "").toString() != filters["storage"].toString()) {
          return false;
        }
      }

      if (filters["condition"] != null && filters["condition"].toString().isNotEmpty) {
        if ((d["condition"] ?? "").toString().toLowerCase() !=
            filters["condition"].toString().toLowerCase()) {
          return false;
        }
      }
    }

    // 🔹 Land Specifications
    if (category == "land") {

      if (filters["area"] != null && filters["area"].toString().isNotEmpty) {
        if ((d["area"] ?? "").toString() != filters["area"].toString()) {
          return false;
        }
      }

      if (filters["landType"] != null && filters["landType"].toString().isNotEmpty) {
        if ((d["landType"] ?? "").toString().toLowerCase() !=
            filters["landType"].toString().toLowerCase()) {
          return false;
        }
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _buildQuery().snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text("Error: ${snap.error}"));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snap.data!.docs;
        final filtered = docs.where((e) {
          final data = e.data() as Map<String, dynamic>;
          return _matchesFilters(data) && _matchesSearch(data);
        }).toList();

        // ── Step 5: Only show assets that are actively listed for sale ──
        //
        // Two cases to handle:
        //   A) Original supplier listing (never purchased):
        //      → previousOwnerId is null, isListedForResale may be null (legacy) or true (new).
        //      → Show unless explicitly set to false.
        //   B) Asset that was purchased by a user:
        //      → previousOwnerId is set by _finalizeOwnership on every transfer.
        //      → Only show if isListedForResale == true (owner explicitly re-listed it).
        //      → This correctly hides legacy purchased assets even if isListedForResale is null.
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        final visible = filtered.where((doc) {
          final d     = doc.data() as Map<String, dynamic>;
          final owner = (d['ownerId'] ?? d['ownerUid']) as String?;

          // Always hide from the owner — they use My Assets tab instead.
          if (currentUid != null && owner == currentUid) return false;

          final isListedForResale = d['isListedForResale'];
          final wasPurchased      = d['previousOwnerId'] != null;

          if (wasPurchased) {
            // Purchased asset: must be explicitly re-listed to appear.
            return isListedForResale == true;
          } else {
            // Original supplier listing: visible unless explicitly hidden.
            return isListedForResale != false;
          }
        }).toList();

        if (visible.isEmpty) {
          return const Center(child: Text("No assets found matching criteria"));
        }

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: visible.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.75,
          ),
          itemBuilder: (_, i) {
            final doc = visible[i];
            return AssetGridCard(
              id: doc.id,
              data: doc.data() as Map<String, dynamic>,
              currentUserId: FirebaseAuth.instance.currentUser!.uid,
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════
// FILTER SHEET & ASSET GRID CARD
// ═══════════════════════════════════════════════════════════

class AssetGridCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  final String currentUserId;

  const AssetGridCard({super.key, required this.id, required this.data, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    final imgList = data["images"] as List?;
    String? firstImg;
    if (imgList != null && imgList.isNotEmpty && imgList[0] is String) {
      firstImg = imgList[0] as String;
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: id)),
      ),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: buildAssetImage(firstImg, width: double.infinity, height: double.infinity),
                  ),
                  // ── Resale badge ─────────────────────────────────────
                  if (data['isListedForResale'] == true)
                    Positioned(
                      top: 6, right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color       : Colors.orange[700],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Resale',
                          style: TextStyle(
                            color     : Colors.white,
                            fontSize  : 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              // 3. FIXED OVERFLOW: Added Flexible/overflow protection
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      data['title'] ?? 'Asset',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(height: 4),
                  Text(
                      "PKR ${data['price'] ?? 0}",
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600)
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class FilterSheet extends StatefulWidget {
  final String category;
  final ScrollController controller;
  final Map<String, dynamic> existing;

  const FilterSheet({
    super.key,
    required this.category,
    required this.controller,
    required this.existing,
  });

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {

  double minPrice = 0;
  double maxPrice = 10000000;

  TextEditingController _minPrice = TextEditingController();
  TextEditingController _maxPrice = TextEditingController();

  String? selectedCity = "None";
  String? selectedArea = "None";

  final List<String> cities = [
    "None",
    "Lahore",
    "Karachi",
    "Islamabad",
    "Rawalpindi",
  ];

  final List<String> areas = [
    "None",
    "5 Marla",
    "10 Marla",
    "1 Kanal",
  ];

  @override
  void initState() {
    super.initState();
    _minPrice.text = "0";
    _maxPrice.text = "0";
    selectedCity = widget.existing["city"] ?? "None";
    selectedArea = widget.existing["area"] ?? "None";;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: ListView(
        controller: widget.controller,
        children: [

          const Text(
            "FILTERS",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),

          const SizedBox(height: 25),

          /// ================= PRICE DROPDOWN =================
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 10),
            title: const Text(
              "By Price",
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _minPrice,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: "Min",
                        prefixText: "Rs ",
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade400),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Colors.black87,
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextFormField(
                      controller: _maxPrice,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: "Max",
                        prefixText: "Rs ",
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade400),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Colors.black87,
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          /// ================= CITY DROPDOWN =================
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              "By City",
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            children: [
              DropdownButtonFormField<String>(
                value: selectedCity,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade400),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: Colors.black87,
                      width: 1.4,
                    ),
                  ),
                ),
                items: cities.map((city) {
                  return DropdownMenuItem(
                    value: city,
                    child: Text(city),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => selectedCity = value);
                },
              ),
              const SizedBox(height: 15),
            ],
          ),

          /// ================= AREA DROPDOWN (LAND ONLY) =================
          if (widget.category == "land")
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text(
                "By Area",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              children: [
                DropdownButtonFormField<String>(
                  value: selectedArea,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade400),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Colors.black87,
                        width: 1.4,
                      ),
                    ),
                  ),
                  items: areas.map((area) {
                    return DropdownMenuItem(
                      value: area,
                      child: Text(area),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() => selectedArea = value);
                  },
                ),
                const SizedBox(height: 15),
              ],
            ),

          const SizedBox(height: 35),

          /// ================= APPLY BUTTON =================
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                final min = double.tryParse(_minPrice.text);
                final max = double.tryParse(_maxPrice.text);

                Navigator.pop(context, {
                  if (min != null) "minPrice": min,
                  if (max != null) "maxPrice": max,
                  if (selectedCity != null && selectedCity != "None")
                    "city": selectedCity,
                  if (selectedArea != null && selectedArea != "None")
                    "area": selectedArea,
                });
              },
              child: const Text(
                "View Results",
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}