// lib/pages/customer/products_page.dart
// ProductsPage: All products + search + category filter

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/product.dart';
import 'product_detail.dart';
import '../../core/app_colors.dart';

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  final TextEditingController _search = TextEditingController();

  List<Product> _allProducts = [];
  List<Product> _filtered = [];
  List<String> _categories = ['all'];
  String _selectedCategory = 'all';

  bool _loading = true;
  Timer? _debounce;
  final Color brownColor = const Color(0xFF8D6E63);

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _loadData();
  }

  @override
  void dispose() {
    _search.removeListener(_onSearchChanged);
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  // ---------- LOAD DATA FROM FIRESTORE ----------

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final prodSnap =
          await FirebaseFirestore.instance.collection('products').get();

      final products =
          prodSnap.docs.map((doc) => Product.fromFirestore(doc)).toList();

      // build categories from existing products (lowercase keys)
      final catSet = <String>{};
      for (final p in products) {
        final raw = (p.category ?? '').toString().trim();
        if (raw.isEmpty) continue;
        catSet.add(raw.toLowerCase());
      }

      final cats = catSet.toList()..sort();

      setState(() {
        _allProducts = products;
        _filtered = products;
        _categories = ['all', ...cats];
        _loading = false;
      });
    } catch (e) {
      debugPrint('Load data error: $e');
      setState(() => _loading = false);
    }
  }

  // ---------- SEARCH / FILTER LOGIC ----------

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _applyFilter);
  }

  void _applyFilter() {
    final query = _search.text.trim().toLowerCase();

    // base list by category
    List<Product> base = _allProducts;
    if (_selectedCategory != 'all') {
      base = base.where((p) {
        final cat = (p.category ?? '').toString().toLowerCase();
        return cat == _selectedCategory;
      }).toList();
    }

    if (query.isEmpty) {
      setState(() => _filtered = base);
      return;
    }

    setState(() {
      _filtered = base.where((p) {
        final name = p.name.toLowerCase();
        final brand = (p.brand ?? '').toString().toLowerCase();
        final cat = (p.category ?? '').toString().toLowerCase();
        return name.contains(query) ||
            brand.contains(query) ||
            cat.contains(query);
      }).toList();
    });
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'PRODUCT',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF8D6E63),
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF8D6E63)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Search box
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.search, color: brownColor),
                      hintText: 'Search products...',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide:
                            BorderSide(color: brownColor.withOpacity(0.25)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide:
                            BorderSide(color: brownColor.withOpacity(0.18)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: brownColor),
                      ),
                    ),
                  ),
                ),

                // Category chips
                SizedBox(
                  height: 54,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _categories.length,
                    itemBuilder: (_, i) {
                      final c = _categories[i];
                      final display = c == 'all'
                          ? 'All'
                          : c.isEmpty
                              ? 'Other'
                              : c[0].toUpperCase() + c.substring(1);
                      final selected = c == _selectedCategory;

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: ChoiceChip(
                          label: Text(display),
                          selected: selected,
                          onSelected: (_) {
                            setState(() => _selectedCategory = c);
                            _applyFilter();
                          },
                          selectedColor: brownColor.withOpacity(0.15),
                          backgroundColor: Colors.white,
                          labelStyle: TextStyle(
                            color: selected
                                ? brownColor
                                : Colors.brown.shade300,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                          ),
                          shape: StadiumBorder(
                            side: BorderSide(
                              color: selected
                                  ? brownColor.withOpacity(0.6)
                                  : const Color(0xFFEAD7C8),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Count
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_filtered.length} items found',
                      style: TextStyle(
                        color: brownColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                // Products grid
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Text(
                            'No products found',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      : GridView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(16, 4, 16, 20),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) =>
                              _ProductCard(product: _filtered[i]),
                        ),
                ),
              ],
            ),
    );
  }
}

// ---------- PRODUCT CARD ----------

class _ProductCard extends StatelessWidget {
  final Product product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    const brown = Color(0xFF8D6E63);

    Widget buildImage() {
      if (product.images.isEmpty) {
        return Container(color: Colors.grey.shade200);
      }
      final url = product.images.first;
      if (url.startsWith('http')) {
        return Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.broken_image, color: Colors.grey),
        );
      }
      return Image.asset(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.image_not_supported, color: Colors.grey),
      );
    }

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailPage(product: product),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: brown.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // image
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: AspectRatio(aspectRatio: 1, child: buildImage()),
            ),
            // name + price
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Color(0xFF4E342E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '฿ ${product.price.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: brown,
                      fontWeight: FontWeight.w600,
                    ),
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
