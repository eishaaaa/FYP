// lib/screens/user_screens.dart
// Clean, optimized & index-safe user-side asset browsing + filtering + searching
// Images/doc stored as Base64 (Firestore only). Uses shared_screens.dart for shared screens.

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'shared_screens.dart'; // exports: db, auth, AssetDetailScreen, QRScannerScreen, MyAssetsScreen, ProfileScreen, TransactionsScreen

Uint8List? _decode(String? b64) {
  if (b64 == null || b64.isEmpty) return null;
  try {
    return base64Decode(b64);
  } catch (e) {
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
  String _category = 'land';
  String _search = '';
  Map<String, dynamic> _filters = {};

  void _openFilters() async {
    final out = await showModalBottomSheet<Map<String, dynamic>>(
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
    if (out != null) setState(() => _filters = out);
  }

  void _nav(int i) {
    if (i == 1) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const QRScannerScreen()));
      return;
    }
    setState(() => _index = i);
  }

  Widget _body() {
    switch (_index) {
      case 2:
        return const MyAssetsScreen();
      case 3:
        return const ProfileScreen();
    }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Digital Goods Marketplace")),
      body: _body(),
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
    );
  }
}

// ---------------------------------------------------------------------------
// ASSETS LIST
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

  Query _q() {
    Query q = db.collection("assets")
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

  bool _match(Map<String, dynamic> d) {
    final s = search.trim();
    if (s.isEmpty) return true;

    final title = (d['title'] ?? "").toString().toLowerCase();
    final city = (d['city'] ?? "").toString().toLowerCase();
    final price = (d['price'] ?? "").toString();
    final keywords = (d['searchKeywords'] as List?)?.join(" ").toLowerCase() ?? "";

    return title.contains(s) ||
        city.contains(s) ||
        price.contains(s) ||
        keywords.contains(s);
  }

  bool _filter(Map<String, dynamic> d) {
    if (filters["city"] != null &&
        !d["city"].toString().toLowerCase().contains(filters["city"].toString().toLowerCase())) {
      return false;
    }
    if (filters["brand"] != null &&
        (d["brand"] ?? "").toString().toLowerCase() != filters["brand"].toString().toLowerCase()) {
      return false;
    }
    if (filters["condition"] != null &&
        (d["condition"] ?? "").toString().toLowerCase() != filters["condition"].toString().toLowerCase()) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _q().snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text("Error: ${snap.error}"));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());

        final docs = snap.data!.docs;

        final filtered = docs.where((e) {
          final d = e.data() as Map<String, dynamic>;
          return _match(d) && _filter(d);
        }).toList();

        if (filtered.isEmpty) {
          return const Center(child: Text("No assets found"));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: filtered.length,
          itemBuilder: (_, i) {
            final doc = filtered[i];
            final data = doc.data() as Map<String, dynamic>;
            return AssetCard(id: doc.id, data: data);
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// ASSET CARD
// ---------------------------------------------------------------------------

class AssetCard extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;

  const AssetCard({super.key, required this.id, required this.data});

  @override
  Widget build(BuildContext context) {
    final img = (data["images"] is List && data["images"].isNotEmpty)
        ? _decode(data["images"][0])
        : null;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AssetDetailScreen(assetId: id)),
        ),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: img != null
              ? Image.memory(img, width: 70, height: 70, fit: BoxFit.cover)
              : Container(
            width: 70,
            height: 70,
            color: Colors.grey[200],
            child: const Icon(Icons.image, size: 32),
          ),
        ),
        title: Text(data["title"] ?? "Untitled"),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data["city"] ?? ""),
            const SizedBox(height: 4),
            Text(
              "₨ ${data["price"]}",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ],
        ),
        trailing: data["verified"] == true
            ? const Icon(Icons.verified, color: Colors.green)
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// FILTER SHEET
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
    _city = TextEditingController(text: widget.existing["city"]?.toString() ?? "");
    _brand = TextEditingController(text: widget.existing["brand"]?.toString() ?? "");
    _condition = TextEditingController(text: widget.existing["condition"]?.toString() ?? "");
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
            TextField(
              controller: _city,
              decoration: const InputDecoration(labelText: "City"),
            ),

            if (!isLand) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _brand,
                decoration: const InputDecoration(labelText: "Brand"),
              ),
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
                TextButton(
                  child: const Text("Cancel"),
                  onPressed: () => Navigator.pop(context),
                ),
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
                    if (!isLand && _condition.text.trim().isNotEmpty) out["condition"] = _condition.text.trim();

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
