import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/product.dart';
import 'product_detail.dart';
import '../../core/app_colors.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _search = TextEditingController();

  List<Product> _allProducts = [];
  List<Product> _filtered = [];
  List<String> _categories = ['all'];
  String _selectedCategory = 'all';

  bool _loading = true;
  Timer? _debounce;

  // Brown/Cream Color Palette
  final Color primaryBrown = const Color(0xFF5D4037);
  final Color accentBrown = const Color(0xFF8D6E63);
  final Color textColor = const Color(0xFF424242);
  final Color lightBackground = const Color(0xFFF9F5F0);

  // ✅ Map คำค้นภาษาไทย -> keyword ที่จะใช้เช็คใน name/category
  // ใช้ normalizeText ตอนเช็คอีกรอบ ให้รองรับทั้งไทย+อังกฤษ
  final Map<String, List<String>> thaiKeywordMap = {
    'แหวน': ['แหวน', 'ring', 'rings'],
    'สร้อยคอ': ['สร้อยคอ', 'necklace', 'necklaces'],
    'กำไล': ['กำไล', 'bracelet', 'bracelets', 'bangle', 'bangles'],
    'ต่างหู': ['ต่างหู', 'earring', 'earrings'],
  };

  // Animation controllers
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _loadData();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  void dispose() {
    _search.removeListener(_onSearchChanged);
    _debounce?.cancel();
    _search.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final prodSnap =
          await FirebaseFirestore.instance.collection('products').get();

      final products =
          prodSnap.docs.map((doc) => Product.fromFirestore(doc)).toList();

      // ✅ Normalize category slug ที่ใช้เป็น filter
      final cats = products
          .map((p) => normalizeText(p.category))
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      setState(() {
        _categories = ['all', ...cats];
        _allProducts = products;
        _filtered = products;
        _loading = false;
      });

      _animationController.forward();
    } catch (e) {
      debugPrint('Load data error: $e');
      setState(() => _loading = false);
    }
  }

  /// 🌐 Normalize Text (รองรับ null ได้)
  String normalizeText(String? text) {
    if (text == null) return '';
    final map = {
      '่': '',
      '้': '',
      '๊': '',
      '๋': '',
      '์': '',
      'ๆ': '',
      '็': '',
      'ํ': '',
    };

    return text
        .trim()
        .toLowerCase()
        .split('')
        .map((c) => map[c] ?? c)
        .join();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _applyFilter);
  }

  // ✅ เช็คว่าคำค้น (หลัง normalize) มีคำไทย แล้ว match กับ category/name ของสินค้าไหม
  bool matchesThaiKeywords(Product p, String normalizedQuery) {
    if (normalizedQuery.isEmpty) return false;

    final name = normalizeText(p.name);
    final cat = normalizeText(p.category);

    for (final entry in thaiKeywordMap.entries) {
      final key = normalizeText(entry.key);
      if (normalizedQuery.contains(key)) {
        // ถ้าคำค้นมี "แหวน" / "สร้อยคอ" / ... ให้ลองเช็ค keyword list
        for (final rawKw in entry.value) {
          final kw = normalizeText(rawKw);
          if (kw.isEmpty) continue;
          if (name.contains(kw) || cat.contains(kw)) {
            return true;
          }
        }
      }
    }

    return false;
  }

  void _applyFilter() {
    final query = normalizeText(_search.text);
    List<Product> base = _allProducts;

    // Filter ตามหมวดหมู่ที่เลือก (ใช้ slug normalized)
    if (_selectedCategory != 'all') {
      base = base
          .where((p) => normalizeText(p.category) == _selectedCategory)
          .toList();
    }

    if (query.isEmpty) {
      setState(() => _filtered = base);
    } else {
      final filtered = base.where((p) {
        final name = normalizeText(p.name);
        final brand = normalizeText(p.brand);
        final cat = normalizeText(p.category);

        // ปกติ: ค้นจากชื่อ / แบรนด์ / หมวด
        final basicMatch =
            name.contains(query) || brand.contains(query) || cat.contains(query);

        // เพิ่ม: คำไทย แหวน/สร้อยคอ/กำไล/ต่างหู map ไป category อังกฤษ
        final thaiMatch = matchesThaiKeywords(p, query);

        return basicMatch || thaiMatch;
      }).toList();

      setState(() => _filtered = filtered);
    }

    _animationController.forward(from: 0.0);
  }

  void _onCategorySelected(String category) {
    setState(() {
      _selectedCategory = category; // category เป็น slug normalized แล้ว
      _search.clear();
    });
    _applyFilter();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBackground,
      appBar: AppBar(
        title: Text(
          'ค้นหาสินค้าคุณภาพ',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: primaryBrown,
          ),
        ),
        centerTitle: false,
        backgroundColor: lightBackground,
        elevation: 0,
        iconTheme: IconThemeData(color: primaryBrown),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: accentBrown.withOpacity(0.1),
            height: 1.0,
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: primaryBrown))
          : FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  _buildSearchAndFilterSection(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _filtered.isEmpty
                            ? 'ไม่พบสินค้าที่ตรงกับคำค้นหา'
                            : 'พบสินค้าทั้งหมด ${_filtered.length} รายการ',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: _buildProductList()),
                ],
              ),
            ),
    );
  }

  // -------------------------------
  // Search Bar & Category Chips
  // -------------------------------
  Widget _buildSearchAndFilterSection() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search, color: primaryBrown),
              hintText: 'ค้นหาชื่อสินค้า หรือหมวดหมู่ เช่น แหวน, สร้อยคอ...',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide(
                  color: accentBrown.withOpacity(0.4),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide(color: primaryBrown, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 20,
              ),
              suffixIcon: _search.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: primaryBrown),
                      onPressed: () {
                        _search.clear();
                        _applyFilter();
                      },
                    )
                  : null,
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _categories.length,
            itemBuilder: (_, i) {
              final c = _categories[i];

              final selected = c == _selectedCategory;

              // แสดงชื่อหมวด (slug -> ตัวแรกใหญ่) ยกเว้น all -> "ทั้งหมด"
              final display = c == 'all'
                  ? 'ทั้งหมด'
                  : (c.isNotEmpty
                      ? '${c[0].toUpperCase()}${c.substring(1)}'
                      : '');

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(
                    display,
                    style: TextStyle(
                      color: selected ? Colors.white : primaryBrown,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  selected: selected,
                  onSelected: (_) => _onCategorySelected(c),
                  selectedColor: primaryBrown,
                  backgroundColor: lightBackground,
                  side: BorderSide(
                    color: selected
                        ? primaryBrown
                        : accentBrown.withOpacity(0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 4,
                  ),
                  elevation: 2,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  // -------------------------------
  // Product List
  // -------------------------------
  Widget _buildProductList() {
    if (_filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.category_outlined,
                size: 50,
                color: accentBrown.withOpacity(0.5),
              ),
              const SizedBox(height: 10),
              Text(
                'ไม่พบสินค้า',
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'ลองค้นหาด้วยคำอื่น หรือเลือกหมวดหมู่ที่ต่างออกไป',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor.withOpacity(0.7),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
      itemCount: _filtered.length,
      itemBuilder: (_, i) => _ProductListItem(
        product: _filtered[i],
        primaryColor: primaryBrown,
        accentColor: accentBrown,
        textColor: textColor,
      ),
    );
  }
}

// -------------------------------
// Product List Item
// -------------------------------
class _ProductListItem extends StatelessWidget {
  final Product product;
  final Color primaryColor;
  final Color accentColor;
  final Color textColor;

  const _ProductListItem({
    required this.product,
    required this.primaryColor,
    required this.accentColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductDetailPage(product: product),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: accentColor.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 70,
                    height: 70,
                    color: Colors.grey.shade200,
                    child: product.images.isNotEmpty
                        ? Image.network(
                            product.images.first,
                            fit: BoxFit.cover,
                            loadingBuilder:
                                (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: CircularProgressIndicator(
                                  color:
                                      accentColor.withOpacity(0.6),
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.image_not_supported,
                              color: Colors.grey.shade400,
                              size: 30,
                            ),
                          )
                        : Icon(
                            Icons.image_not_supported,
                            color: Colors.grey.shade400,
                            size: 30,
                          ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow:
                            TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'หมวดหมู่: ${product.category}',
                        style: TextStyle(
                          fontSize: 12,
                          color: accentColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '฿ ${product.price.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
