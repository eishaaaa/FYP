// lib/screens/user_screens.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'shared_screens.dart';
import 'chat_list_screen.dart';
import 'portfolio_screen.dart';
import 'qr_scanner_enhanced.dart';
import '../blockchain/blockchain_service.dart';

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
      appBar: AppBar(
        title: const Text("Digital Goods Marketplace"),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PortfolioScreen()),
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
          const ProfileScreen(),
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
  bool _loading = false;

  Future<void> _ensureWalletConnected() async {
    if (!_blockchain.isConnected) {
      await _blockchain.connectWallet(context);
    }
  }

  Future<void> _claimRent(int propertyId) async {
    setState(() => _loading = true);
    try {
      await _ensureWalletConnected();
      final tx = await _blockchain.claimLandRent(propertyId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Transaction Sent! Waiting for confirmation...'),
        ));
      }

      if (tx != null) {
        await _blockchain.waitForConfirmation(tx);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Rent Claimed Successfully!'),
            backgroundColor: Colors.green,
          ));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitReview(int tokenId) async {
    final txtCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Submit Blockchain Review"),
        content: TextField(
          controller: txtCtrl,
          decoration: const InputDecoration(hintText: "Enter your review..."),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (txtCtrl.text.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await _ensureWalletConnected();
                final tx = await _blockchain.submitElectronicsReview(
                    tokenId: tokenId,
                    reviewText: txtCtrl.text
                );

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("Review Transaction Sent!"),
                    backgroundColor: Colors.green,
                  ));
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
              }
            },
            child: const Text("Submit"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Login required"));

    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('orders').where('buyerId', isEqualTo: user.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final orders = snapshot.data!.docs;

        if (orders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text("No assets owned yet"),
                TextButton(
                  onPressed: () {
                    // This is just a visual hint, real nav is via tabs
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Go to Home tab to buy assets")));
                  },
                  child: const Text("Browse Marketplace"),
                )
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index].data() as Map<String, dynamic>;
            final assetId = order['assetId'];
            final category = order['category'] ?? 'land';

            return FutureBuilder<DocumentSnapshot>(
              future: db.collection('assets').doc(assetId).get(),
              builder: (ctx, assetSnap) {
                if (!assetSnap.hasData) return const SizedBox();
                if (!assetSnap.data!.exists) return const SizedBox();

                final asset = assetSnap.data!.data() as Map<String, dynamic>;
                final tokenId = asset['blockchainTokenId'] as int?;
                final title = asset['title'] ?? 'Unknown Asset';
                final imgList = asset['images'] as List?;
                final firstImg = (imgList != null && imgList.isNotEmpty) ? imgList.first : null;

                return Card(
                  elevation: 3,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      // Header with Image
                      ListTile(
                        contentPadding: const EdgeInsets.all(8),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: firstImg != null
                              ? Image.memory(base64Decode(firstImg), width: 60, height: 60, fit: BoxFit.cover)
                              : Container(width: 60, height: 60, color: Colors.grey[200], child: const Icon(Icons.image)),
                        ),
                        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(category == 'land' ? 'Fractional Ownership' : 'Electronic Device'),
                        trailing: tokenId != null
                            ? const Chip(label: Text('NFT'), backgroundColor: Colors.greenAccent, visualDensity: VisualDensity.compact)
                            : const Chip(label: Text('Pending'), visualDensity: VisualDensity.compact),
                      ),

                      const Divider(height: 1),

                      // Actions Area
                      if (tokenId != null && category == 'land')
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              FutureBuilder<BigInt>(
                                future: _blockchain.getUnclaimedRent(user.uid, tokenId),
                                builder: (c, s) {
                                  if (s.hasError) return const Text('Rent: Err');
                                  final rent = s.data ?? BigInt.zero;
                                  return Text('Unclaimed: ${_blockchain.weiToEther(rent)} MATIC',
                                      style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold));
                                },
                              ),
                              ElevatedButton.icon(
                                icon: _loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.monetization_on, size: 16),
                                label: const Text("Claim Rent"),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                onPressed: _loading ? null : () => _claimRent(tokenId),
                              )
                            ],
                          ),
                        ),

                      if (tokenId != null && category == 'electronics')
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.rate_review, size: 18),
                              label: const Text("Write Immutable Review"),
                              onPressed: () => _submitReview(tokenId),
                            ),
                          ),
                        )
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
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
      q = q.where("price", isGreaterThanOrEqualTo: filters["minPrice"]);
    }
    if (filters["maxPrice"] != null) {
      q = q.where("price", isLessThanOrEqualTo: filters["maxPrice"]);
    }

    return q.orderBy("price").orderBy("createdAt", descending: true);
  }

  bool _matchesSearch(Map<String, dynamic> d) {
    if (search.isEmpty) return true;
    final title = (d["title"] ?? "").toString().toLowerCase();
    final city = (d["city"] ?? "").toString().toLowerCase();
    final brand = (d["brand"] ?? "").toString().toLowerCase();
    return title.contains(search) || city.contains(search) || brand.contains(search);
  }

  bool _matchesFilters(Map<String, dynamic> d) {
    if (filters["city"] != null && filters["city"].isNotEmpty) {
      if (!(d["city"] ?? "").toString().toLowerCase().contains(filters["city"].toLowerCase())) return false;
    }
    if (filters["brand"] != null && filters["brand"].isNotEmpty) {
      if ((d["brand"] ?? "").toString().toLowerCase() != filters["brand"].toLowerCase()) return false;
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

        if (filtered.isEmpty) {
          return const Center(child: Text("No assets found matching criteria"));
        }

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: filtered.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            // 2. FIXED ALIGNMENT: Adjusted ratio for better fit
            childAspectRatio: 0.75,
          ),
          itemBuilder: (_, i) {
            final doc = filtered[i];
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
    final firstImg = (imgList != null && imgList.isNotEmpty) ? imgList[0] : null;

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
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: firstImg != null
                    ? Image.memory(base64Decode(firstImg), width: double.infinity, fit: BoxFit.cover)
                    : Container(color: Colors.grey[200], child: const Center(child: Icon(Icons.image))),
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

  const FilterSheet({super.key, required this.category, required this.controller, required this.existing});

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late TextEditingController _city;
  late TextEditingController _brand;
  late TextEditingController _minPrice;
  late TextEditingController _maxPrice;

  @override
  void initState() {
    super.initState();
    _city = TextEditingController(text: widget.existing["city"] ?? "");
    _brand = TextEditingController(text: widget.existing["brand"] ?? "");
    _minPrice = TextEditingController(text: widget.existing["minPrice"]?.toString() ?? "");
    _maxPrice = TextEditingController(text: widget.existing["maxPrice"]?.toString() ?? "");
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: ListView(
        controller: widget.controller,
        children: [
          const Text("Filters", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: TextField(controller: _minPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Min Price", border: OutlineInputBorder()))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _maxPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Max Price", border: OutlineInputBorder()))),
            ],
          ),
          const SizedBox(height: 12),
          TextField(controller: _city, decoration: const InputDecoration(labelText: "City", border: OutlineInputBorder())),
          if (widget.category == "electronics") ...[
            const SizedBox(height: 10),
            TextField(controller: _brand, decoration: const InputDecoration(labelText: "Brand", border: OutlineInputBorder())),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              final min = double.tryParse(_minPrice.text);
              final max = double.tryParse(_maxPrice.text);
              Navigator.pop(context, {
                "city": _city.text.trim(),
                "brand": _brand.text.trim(),
                if (min != null) "minPrice": min,
                if (max != null) "maxPrice": max,
              });
            },
            child: const Text("Apply Filters"),
          )
        ],
      ),
    );
  }
}