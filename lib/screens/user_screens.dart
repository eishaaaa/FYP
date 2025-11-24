// user_screens.dart
// Professional Marketplace UI (2 items per row grid)
// Fully fixed filters + search + Firestore-safe queries

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'shared_screens.dart'; // provides db, auth, AssetDetailScreen, QRScannerScreen, MyAssetsScreen, ProfileScreen

Uint8List? _decodeImage(String? b64) {
  if (b64 == null || b64.isEmpty) return null;
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

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
      Navigator.push(context, MaterialPageRoute(builder: (_) => const QRScannerScreen()));
      return;
    }
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Digital Goods Marketplace")),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.swap_horiz),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const TransactionsScreen()),
        ),
      ),
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
      body: _index == 2
          ? const MyAssetsScreen()
          : _index == 3
          ? const ProfileScreen()
          : _mainBody(),
    );
  }

  Widget _mainBody() {
    return SafeArea(
      child: Column(
        children: [
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
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
            ),
          ),
          SizedBox(
            height: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text("Land"),
                  selected: _category == "land",
                  onSelected: (_) => setState(() => _category = "land"),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text("Electronics"),
                  selected: _category == "electronics",
                  onSelected: (_) => setState(() => _category = "electronics"),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.tune),
                  onPressed: _openFilters,
                )
              ],
            ),
          ),
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

// ---------------------------------------------------------------------------
// ASSET LIST VIEW (GRID)
// ---------------------------------------------------------------------------

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

  Query _query() {
    Query q = db
        .collection("assets")
        .where("category", isEqualTo: category)
        .orderBy("createdAt", descending: true);

    if (filters["minPrice"] != null) {
      q = q.where("price", isGreaterThanOrEqualTo: filters["minPrice"]);
    }
    if (filters["maxPrice"] != null) {
      q = q.where("price", isLessThanOrEqualTo: filters["maxPrice"]);
    }

    return q;
  }

  bool _matchesSearch(Map<String, dynamic> d) {
    if (search.isEmpty) return true;
    final title = (d["title"] ?? "").toString().toLowerCase();
    final city = (d["city"] ?? "").toString().toLowerCase();
    final price = (d["price"] ?? "").toString();
    final keywords = (d["searchKeywords"] as List?)
        ?.map((e) => e.toString().toLowerCase())
        .join(" ") ??
        "";

    return title.contains(search) ||
        city.contains(search) ||
        price.contains(search) ||
        keywords.contains(search);
  }

  bool _matchesFilters(Map<String, dynamic> d) {
    if (filters["city"] != null &&
        !d["city"].toString().toLowerCase().contains(filters["city"].toLowerCase())) {
      return false;
    }
    if (filters["brand"] != null &&
        d["brand"]?.toString().toLowerCase() != filters["brand"].toLowerCase()) {
      return false;
    }
    if (filters["condition"] != null &&
        d["condition"]?.toString().toLowerCase() != filters["condition"].toLowerCase()) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _query().snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text("Error: ${snap.error}"));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snap.data!.docs;

        final filtered = docs.where((e) {
          final data = e.data() as Map<String, dynamic>;
          return _matchesFilters(data) && _matchesSearch(data);
        }).toList();

        if (filtered.isEmpty) return const Center(child: Text("No assets found"));

        return GridView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: filtered.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, // 2 boxes per row
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.70,
          ),
          itemBuilder: (_, i) {
            final doc = filtered[i];
            final data = doc.data() as Map<String, dynamic>;
            return AssetGridCard(id: doc.id, data: data);
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// GRID ASSET CARD (PROFESSIONAL UI)
// ---------------------------------------------------------------------------

class AssetGridCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;

  const AssetGridCard({super.key, required this.id, required this.data});

  @override
  Widget build(BuildContext context) {
    final img = (data["images"] is List && data["images"].isNotEmpty)
        ? _decodeImage(data["images"][0])
        : null;

    return GestureDetector(
      onTap: () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: id))),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              blurRadius: 4,
              color: Colors.black12,
              offset: Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: img != null
                  ? Image.memory(img, height: 130, width: double.infinity, fit: BoxFit.cover)
                  : Container(
                height: 130,
                width: double.infinity,
                color: Colors.grey[200],
                child: const Icon(Icons.image, size: 40),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data["title"] ?? "Untitled",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    data["city"] ?? "",
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "₨ ${data["price"]}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  if (data["verified"] == true)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(Icons.verified, color: Colors.green, size: 18),
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

// ---------------------------------------------------------------------------
// FILTER SHEET (LAND + ELECTRONICS)
// ---------------------------------------------------------------------------

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
  late TextEditingController _city;
  late TextEditingController _brand;
  late TextEditingController _condition;

  double minP = 0;
  double maxP = 100000000;

  @override
  void initState() {
    super.initState();
    _city = TextEditingController(text: widget.existing["city"] ?? "");
    _brand = TextEditingController(text: widget.existing["brand"] ?? "");
    _condition = TextEditingController(text: widget.existing["condition"] ?? "");
    minP = (widget.existing["minPrice"] ?? 0).toDouble();
    maxP = (widget.existing["maxPrice"] ?? 100000000).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final isLand = widget.category == "land";

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        controller: widget.controller,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Text("Filters", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            TextField(controller: _city, decoration: const InputDecoration(labelText: "City")),

            if (!isLand) ...[
              const SizedBox(height: 12),
              TextField(controller: _brand, decoration: const InputDecoration(labelText: "Brand")),
              const SizedBox(height: 12),
              TextField(
                controller: _condition,
                decoration: const InputDecoration(labelText: "Condition (new/used)"),
              ),
            ],

            const SizedBox(height: 20),
            const Text("Price Range"),
            RangeSlider(
              values: RangeValues(minP, maxP),
              min: 0,
              max: 100000000,
              onChanged: (v) => setState(() {
                minP = v.start;
                maxP = v.end;
              }),
            ),

            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(child: const Text("Cancel"), onPressed: () => Navigator.pop(context)),
                const SizedBox(width: 8),
                ElevatedButton(
                  child: const Text("Apply"),
                  onPressed: () {
                    final out = <String, dynamic>{
                      "minPrice": minP,
                      "maxPrice": maxP,
                    };

                    if (_city.text.trim().isNotEmpty) out["city"] = _city.text.trim();
                    if (!isLand && _brand.text.trim().isNotEmpty) out["brand"] = _brand.text.trim();
                    if (!isLand &&
                        _condition.text.trim().isNotEmpty) out["condition"] = _condition.text.trim();

                    Navigator.pop(context, out);
                  },
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}
