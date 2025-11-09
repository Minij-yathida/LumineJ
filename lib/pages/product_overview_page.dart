// lib/pages/customer/product_overview_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:LumineJewelry/pages/customer/product_detail.dart';
import '../../core/app_colors.dart';
import '../../models/product.dart';

class ProductOverviewPage extends StatefulWidget {
  final String? category;
  const ProductOverviewPage({super.key, this.category});

  @override
  State<ProductOverviewPage> createState() => _ProductOverviewPageState();
}

class _ProductOverviewPageState extends State<ProductOverviewPage> {
  /// slug ของหมวดที่เลือก (null = รวมทั้งหมด)
  String? _selectedCategorySlug;
  String _selectedCategoryLabel = 'รวมทั้งหมด';

  CollectionReference<Map<String, dynamic>> get _productsCol =>
      FirebaseFirestore.instance.collection('products');

  @override
  void initState() {
    super.initState();

    // ถ้ามี category ส่งมาจากหน้าก่อน
    final initial = widget.category;
    if (initial != null &&
        initial.trim().isNotEmpty &&
        initial.toLowerCase() != 'all') {
      _selectedCategorySlug = initial.toLowerCase();
      _selectedCategoryLabel = initial;
    }
  }

  /// stream สินค้าตามหมวด
  Stream<QuerySnapshot<Map<String, dynamic>>> _productStream() {
    Query<Map<String, dynamic>> q =
        _productsCol; // ถ้าใช้ active ให้ใส่ where('active', isEqualTo: true)

    if (_selectedCategorySlug != null) {
      q = q.where('category', isEqualTo: _selectedCategorySlug);
    }

    // ถ้า product มี createdAt ให้เปิดอันนี้
    // q = q.orderBy('createdAt', descending: true);

    return q.snapshots();
  }

  /// bottom sheet เลือกหมวดหมู่
  /// ดึงจาก field category ใน products + fallback (ring/necklace/bracelet/earrings)
  Future<void> _openCategorySheet() async {
    const ivory = Color(0xFFFBF8F2);
    const brown = Color(0xFF7A4E3A);

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const Text(
                'เลือกหมวดหมู่',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),

              Flexible(
                child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  future: _productsCol.get(), // ดึง products มาดูว่ามี category อะไรบ้าง
                  builder: (context, snap) {
                    // fallback พื้นฐาน
                    final fallback = <String, String>{
                      'ring': 'ring',
                      'necklace': 'necklace',
                      'bracelet': 'bracelet',
                      'earrings': 'earrings',
                    };

                    // รวม slug จาก products
                    final Map<String, String> merged = {};
                    merged.addAll(fallback);

                    if (snap.hasData) {
                      for (final doc in snap.data!.docs) {
                        final data = doc.data();
                        final slug =
                            (data['category'] ?? '').toString().trim();
                        if (slug.isEmpty) continue;
                        // ใช้ slug เป็นชื่อ ถ้าไม่มีชื่อสวย ๆ
                        merged[slug] = merged[slug] ?? slug;
                      }
                    }

                    // สร้างลิสต์ + แถวบนสุด = รวมทั้งหมด
                    final items = <Map<String, String>>[
                      {'slug': '', 'name': 'รวมทั้งหมด'},
                      ...merged.entries.map(
                        (e) => {'slug': e.key, 'name': e.value},
                      ),
                    ];

                    if (snap.connectionState ==
                            ConnectionState.waiting &&
                        items.length <= 1) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: LinearProgressIndicator(minHeight: 3),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, thickness: 0.5),
                      itemBuilder: (_, i) {
                        final it = items[i];
                        final isAll = it['slug']!.isEmpty;
                        final selected = isAll
                            ? _selectedCategorySlug == null
                            : _selectedCategorySlug == it['slug'];

                        return ListTile(
                          title: Text(it['name']!),
                          trailing: selected
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                )
                              : null,
                          onTap: () => Navigator.pop<Map<String, String>>(
                              ctx, it),
                        );
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: brown,
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('ปิด'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result != null) {
      setState(() {
        if (result['slug'] == null || result['slug']!.isEmpty) {
          _selectedCategorySlug = null;
          _selectedCategoryLabel = 'รวมทั้งหมด';
        } else {
          _selectedCategorySlug = result['slug']!;
          _selectedCategoryLabel = result['name'] ?? 'หมวดหมู่';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.text),
        title: const Text(
          'PRODUCTS',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Search products',
            icon: Icon(Icons.search, color: AppColors.text),
            onPressed: () async {
              final result = await showSearch<Product?>(
                context: context,
                delegate: _ProductSearchDelegate(
                  categorySlug: _selectedCategorySlug,
                ),
              );
              if (result != null && context.mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProductDetailPage(product: result),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),

          // ปุ่มวงรีเลือกหมวด
          Center(
            child: InkWell(
              onTap: _openCategorySheet,
              borderRadius: BorderRadius.circular(30),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 26, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: AppColors.brown,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check,
                        size: 18, color: AppColors.brown),
                    const SizedBox(width: 8),
                    Text(
                      _selectedCategoryLabel,
                      style: const TextStyle(
                        color: AppColors.brown,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ตารางสินค้า
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _productStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                      child: Text(
                          'เกิดข้อผิดพลาด: ${snapshot.error}'));
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      _selectedCategorySlug == null
                          ? 'ยังไม่มีสินค้า'
                          : 'ยังไม่มีสินค้าในหมวดนี้',
                      style: const TextStyle(fontSize: 14),
                    ),
                  );
                }

                final products = docs
                    .map((d) => Product.fromFirestore(d))
                    .toList();

                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: GridView.builder(
                    itemCount: products.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.75,
                    ),
                    itemBuilder: (context, index) =>
                        _ProductCard(product: products[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// การ์ดสินค้า
class _ProductCard extends StatelessWidget {
  final Product product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailPage(product: product),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
                child: product.images.isNotEmpty
                    ? Image.network(
                        product.images.first,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      )
                    : Container(
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.image,
                          size: 40,
                          color: Colors.grey,
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 10),
              child: Column(
                children: [
                  Text(
                    product.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '฿ ${product.price.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: AppColors.brown,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
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

// delegate ค้นหา
class _ProductSearchDelegate extends SearchDelegate<Product?> {
  final String? categorySlug;
  _ProductSearchDelegate({this.categorySlug});

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('products');

  Future<List<Product>> _fetchOnce() async {
    final snap = (categorySlug == null)
        ? await _col.get()
        : await _col.where('category', isEqualTo: categorySlug).get();
    return snap.docs.map((d) => Product.fromFirestore(d)).toList();
  }

  @override
  String get searchFieldLabel => 'Search products...';

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            onPressed: () => query = '',
            icon: const Icon(Icons.clear),
          ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        onPressed: () => close(context, null),
        icon: const Icon(Icons.arrow_back),
      );

  @override
  Widget buildResults(BuildContext context) {
    return FutureBuilder<List<Product>>(
      future: _fetchOnce(),
      builder: (context, snap) {
        if (snap.connectionState ==
            ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator());
        }
        final list = snap.data ?? [];
        final q = query.toLowerCase();
        final filtered = q.isEmpty
            ? list
            : list
                .where((p) =>
                    p.name.toLowerCase().contains(q) ||
                    p.description
                        .toLowerCase()
                        .contains(q))
                .toList();
        if (filtered.isEmpty) {
          return const Center(child: Text('No products found'));
        }
        return ListView.separated(
          itemCount: filtered.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1),
          itemBuilder: (context, i) {
            final p = filtered[i];
            return ListTile(
              leading: p.images.isNotEmpty
                  ? Image.network(
                      p.images.first,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    )
                  : const Icon(Icons.image),
              title: Text(p.name),
              subtitle: Text(
                  '฿ ${p.price.toStringAsFixed(0)}'),
              onTap: () => close(context, p),
            );
          },
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return FutureBuilder<List<Product>>(
      future: _fetchOnce(),
      builder: (context, snap) {
        if (snap.connectionState ==
            ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator());
        }
        final list = snap.data ?? [];
        final q = query.toLowerCase();
        final filtered = q.isEmpty
            ? list.take(6).toList()
            : list
                .where((p) =>
                    p.name.toLowerCase().contains(q) ||
                    p.description
                        .toLowerCase()
                        .contains(q))
                .toList();
        if (filtered.isEmpty) {
          return const Center(
              child: Text('No suggestions'));
        }
        return ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (context, i) {
            final p = filtered[i];
            return ListTile(
              leading: p.images.isNotEmpty
                  ? Image.network(
                      p.images.first,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                    )
                  : const Icon(Icons.image),
              title: Text(p.name),
              subtitle: Text(
                  '฿ ${p.price.toStringAsFixed(0)}'),
              onTap: () {
                query = p.name;
                showResults(context);
              },
            );
          },
        );
      },
    );
  }
}
