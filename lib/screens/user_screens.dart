// lib/screens/user_screens.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'shared_screens.dart';

final db = FirebaseFirestore.instance;

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  int _bottomIndex = 0;
  String _tab = "land";
  String _query = "";
  Map<String, dynamic> _filters = {};

  void _openFilters() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (_, controller) =>
            FilterSheet(tab: _tab, controller: controller),
      ),
    );

    if (result != null) setState(() => _filters = result);
  }

  void _onNavTap(int index) {
    if (index == 1) {
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const QRScannerScreen()));
      return;
    }
    setState(() => _bottomIndex = index);
  }

  Widget _buildBody() {
    if (_bottomIndex == 2) return const MyAssetsScreen();
    if (_bottomIndex == 3) return const ProfileScreen();

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: "Search title, city, price",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                    icon: const Icon(Icons.filter_list),
                    onPressed: _openFilters),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),

          // Tabs
          SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text("Land"),
                  selected: _tab == "land",
                  onSelected: (_) => setState(() => _tab = "land"),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text("Electronics"),
                  selected: _tab == "electronics",
                  onSelected: (_) => setState(() => _tab = "electronics"),
                ),
                const Spacer(),
                IconButton(icon: const Icon(Icons.tune), onPressed: _openFilters)
              ],
            ),
          ),

          const SizedBox(height: 8),

          Expanded(
            child:
            AssetListView(tab: _tab, query: _query, filters: _filters),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Digital Goods Marketplace")),
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _bottomIndex,
        type: BottomNavigationBarType.fixed,
        onTap: _onNavTap,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_scanner), label: "Scan"),
          BottomNavigationBarItem(
              icon: Icon(Icons.inventory), label: "My Assets"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const TransactionsScreen())),
        child: const Icon(Icons.swap_horiz),
      ),
    );
  }
}

// ============================================================================
// ASSET LIST
// ============================================================================

class AssetListView extends StatelessWidget {
  final String tab;
  final String query;
  final Map<String, dynamic> filters;

  const AssetListView({
    super.key,
    required this.tab,
    required this.query,
    required this.filters,
  });

  // Firestore SAFE query
  Query _buildQuery() {
    return db
        .collection("assets")
        .where("category", isEqualTo: tab)
        .orderBy("__name__", descending: false);   // SAFE — no index needed
  }

  bool _matchesText(Map<String, dynamic> data) {
    if (query.isEmpty) return true;

    final q = query.toLowerCase();
    return (data["title"] ?? "").toString().toLowerCase().contains(q) ||
        (data["city"] ?? "").toString().toLowerCase().contains(q) ||
        (data["price"] ?? "").toString().contains(q) ||
        ((data["searchKeywords"] ?? []) as List)
            .join(" ")
            .toLowerCase()
            .contains(q);
  }

  bool _matchesFilters(Map<String, dynamic> d) {
    if (filters.containsKey("city") &&
        d["city"]?.toLowerCase() != filters["city"].toLowerCase()) {
      return false;
    }
    if (filters.containsKey("brand") &&
        d["brand"]?.toLowerCase() != filters["brand"].toLowerCase()) {
      return false;
    }
    if (filters.containsKey("condition") &&
        d["condition"]?.toLowerCase() !=
            filters["condition"].toLowerCase()) {
      return false;
    }

    // Price range (local filter)
    final price = (d["price"] ?? 0).toDouble();
    final min = (filters["minPrice"] ?? 0).toDouble();
    final max = (filters["maxPrice"] ?? 999999999).toDouble();
    return price >= min && price <= max;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _buildQuery().snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;

        // Apply text search + filters locally
        final finalList = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return _matchesText(data) && _matchesFilters(data);
        }).toList();

        if (finalList.isEmpty) {
          return const Center(child: Text("No listings found"));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: finalList.length,
          itemBuilder: (_, i) {
            final data = finalList[i].data() as Map<String, dynamic>;
            return AssetCard(id: finalList[i].id, data: data);
          },
        );
      },
    );
  }
}

// ============================================================================
// ASSET CARD
// ============================================================================

class AssetCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;

  const AssetCard({super.key, required this.id, required this.data});

  @override
  Widget build(BuildContext context) {
    final img = (data["images"] is List && data["images"].isNotEmpty)
        ? data["images"][0]
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AssetDetailScreen(assetId: id)),
        ),
        child: Row(
          children: [
            Container(
              width: 110,
              height: 80,
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(10),
              ),
              child: img != null
                  ? Image.network(img, fit: BoxFit.cover)
                  : const Icon(Icons.image),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data["title"] ?? "Untitled",
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(data["city"] ?? "",
                        style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 6),
                    Text("₨ ${data["price"]}",
                        style: const TextStyle(
                            fontSize: 16,
                            color: Colors.green,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// FILTER SHEET
// ============================================================================

class FilterSheet extends StatefulWidget {
  final String tab;
  final ScrollController controller;

  const FilterSheet({super.key, required this.tab, required this.controller});

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  final _city = TextEditingController();
  final _brand = TextEditingController();
  final _condition = TextEditingController();

  double _minPrice = 0;
  double _maxPrice = 100000000;

  @override
  Widget build(BuildContext context) {
    final isLand = widget.tab == "land";

    return SingleChildScrollView(
      controller: widget.controller,
      padding:
      EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Text("Filters",
                    style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),

            TextField(
                controller: _city,
                decoration: const InputDecoration(labelText: "City")),

            if (!isLand) ...[
              const SizedBox(height: 12),
              TextField(
                  controller: _brand,
                  decoration: const InputDecoration(labelText: "Brand")),
              const SizedBox(height: 12),
              TextField(
                  controller: _condition,
                  decoration: const InputDecoration(
                      labelText: "Condition (New/Used)")),
            ],

            const SizedBox(height: 20),
            const Text("Price Range"),
            RangeSlider(
              values: RangeValues(_minPrice, _maxPrice),
              min: 0,
              max: 100000000,
              onChanged: (v) {
                setState(() {
                  _minPrice = v.start;
                  _maxPrice = v.end;
                });
              },
            ),

            ElevatedButton(
              child: const Text("Apply"),
              onPressed: () {
                final out = <String, dynamic>{};

                if (_city.text.isNotEmpty) out["city"] = _city.text.trim();
                if (!isLand && _brand.text.isNotEmpty)
                  out["brand"] = _brand.text.trim();
                if (!isLand && _condition.text.isNotEmpty)
                  out["condition"] = _condition.text.trim();

                out["minPrice"] = _minPrice;
                out["maxPrice"] = _maxPrice;

                Navigator.pop(context, out);
              },
            )
          ],
        ),
      ),
    );
  }
}
