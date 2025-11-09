import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_colors.dart';
import 'add_edit_product_page.dart';

class ProductManagementPage extends StatefulWidget {
  const ProductManagementPage({super.key});

  @override
  State<ProductManagementPage> createState() => _ProductManagementPageState();
}

class _ProductManagementPageState extends State<ProductManagementPage> {
  final fs = FirebaseFirestore.instance;

  final TextEditingController _search = TextEditingController();
  String _query = '';
  String _selectedCat = 'ทั้งหมด';

  // เรียงหมวดหลักตามที่ต้องการ
  static const List<String> _preferredOrder = [
    'ring',
    'necklace',
    'earrings',
    'bracelet',
  ];

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      setState(() {
        _query = _search.text.trim();
      });
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ---------- helpers ----------

  // หาหมวดหลักจากข้อมูล (รองรับได้หลายรูปแบบ)
  String _primaryCategory(Map<String, dynamic> data) {
    final c = data['category'];
    if (c is String && c.trim().isNotEmpty) return c.trim();
    if (c is List && c.isNotEmpty && c.first is String) {
      return (c.first as String).trim();
    }
    final alt = data['categoryName'];
    if (alt is String && alt.trim().isNotEmpty) return alt.trim();
    return 'อื่น ๆ';
  }

  // เช็คว่าสินค้าอยู่ในหมวดที่เลือกหรือไม่
  bool _inSelectedCategory(Map<String, dynamic> data) {
    // ✅ โหมด "สินค้ารวม" และ "ทั้งหมด" ให้ผ่านทุกตัว
    if (_selectedCat == 'สินค้ารวม' || _selectedCat == 'ทั้งหมด') return true;

    final c = data['category'] ?? data['categoryName'];

    if (c is String) {
      return c.toLowerCase().trim() == _selectedCat.toLowerCase().trim();
    }
    if (c is List) {
      return c.any((e) =>
          e is String &&
          e.toLowerCase().trim() == _selectedCat.toLowerCase().trim());
    }
    return false;
  }

  // จัดลำดับชื่อหมวดให้หมวดหลักขึ้นก่อน
  int _categoryCompare(String a, String b) {
    final al = a.toLowerCase();
    final bl = b.toLowerCase();

    final ai =
        _preferredOrder.indexWhere((x) => x.toLowerCase() == al);
    final bi =
        _preferredOrder.indexWhere((x) => x.toLowerCase() == bl);

    if (ai != -1 && bi != -1) return ai.compareTo(bi);
    if (ai != -1) return -1;
    if (bi != -1) return 1;
    return al.compareTo(bl);
  }

  @override
  Widget build(BuildContext context) {
    final money0 = NumberFormat.currency(
      locale: 'th_TH',
      symbol: '฿',
      decimalDigits: 0,
    );

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: fs.collection('products').snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allDocs = snap.data?.docs ?? [];

        // -----------------------------
        // เตรียมรายการหมวดสำหรับ ChoiceChip
        // -----------------------------
        final cats = <String>{
          'สินค้ารวม', // ✅ โหมดลิสต์รวมทุกสินค้า
          'ทั้งหมด',   // ✅ โหมดแยกตามหมวด แต่แสดงทุกหมวด
          ...allDocs.map((e) => _primaryCategory(e.data())),
        }.toList()
          ..sort((a, b) {
            // ให้ "สินค้ารวม" ขึ้นก่อนสุด, "ทั้งหมด" ถัดมา
            if (a == 'สินค้ารวม') return -1;
            if (b == 'สินค้ารวม') return 1;
            if (a == 'ทั้งหมด') return -1;
            if (b == 'ทั้งหมด') return 1;
            return _categoryCompare(a, b);
          });

        // -----------------------------
        // Filter ตามค้นหา + หมวด
        // -----------------------------
        final filtered = allDocs.where((d) {
          final data = d.data();
          final name = (data['name'] ?? '').toString();
          final okCat = _inSelectedCategory(data);
          final okSearch = _query.isEmpty
              ? true
              : name.toLowerCase().contains(_query.toLowerCase());
          return okCat && okSearch;
        }).toList();

        // -----------------------------
        // แบ่งกรณีแสดงผล:
        // - "สินค้ารวม": ลิสต์ยาวทุกชิ้น (ไม่แบ่งหมวด)
        // - อื่น ๆ: แบ่ง Section ตามหมวด
        // -----------------------------
        // เตรียมข้อมูล grouped สำหรับโหมดหมวดหมู่
        final Map<String,
                List<QueryDocumentSnapshot<Map<String, dynamic>>>>
            grouped = {};

        if (_selectedCat != 'สินค้ารวม') {
          for (final d in filtered) {
            final cat = _primaryCategory(d.data());
            (grouped[cat] ??= []).add(d);
          }
        }

        final sectionCats = grouped.keys.toList()
          ..sort(_categoryCompare);

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // -----------------------------
              // Header: Search + Add
              // -----------------------------
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        prefixIcon: Icon(
                          Icons.search,
                          color: AppColors.brown,
                        ),
                        hintText: 'ค้นหาสินค้า...',
                        hintStyle: TextStyle(color: AppColors.grey),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AddEditProductPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('เพิ่มสินค้า'),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // -----------------------------
              // Category chips
              // -----------------------------
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: cats.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final c = cats[i];
                    final selected =
                        _selectedCat.toLowerCase() ==
                            c.toLowerCase();
                    return ChoiceChip(
                      label: Text(c),
                      selected: selected,
                      onSelected: (_) {
                        setState(() {
                          _selectedCat = c;
                        });
                      },
                      selectedColor:
                          AppColors.brown.withOpacity(.1),
                      labelStyle: TextStyle(
                        color: selected
                            ? AppColors.brown
                            : Colors.black87,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: selected
                              ? AppColors.brown
                              : const Color(0xFFE5E5E5),
                        ),
                      ),
                      backgroundColor: Colors.white,
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),

              // -----------------------------
              // Content
              // -----------------------------
              if (filtered.isEmpty) ...[
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 64,
                          color: Colors.black26,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'ไม่พบสินค้า',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.black54,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'ลองพิมพ์ค้นหาหรือเปลี่ยนหมวดหมู่',
                          style:
                              TextStyle(color: Colors.black45),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (_selectedCat == 'สินค้ารวม') ...[
                // ✅ โหมด "สินค้ารวม": แสดงลิสต์รวมทุกสินค้า ไม่แยกหมวด
                Expanded(
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 6),
                    itemBuilder: (_, i) {
                      final d = filtered[i];
                      return _ProductTile(
                        doc: d,
                        money0: money0,
                        onEdit: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AddEditProductPage(
                                docId: d.id,
                                initial: d.data(),
                              ),
                            ),
                          );
                        },
                        onDelete: () async {
                          final name =
                              (d.data()['name'] ?? '')
                                  .toString();
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text(
                                  'ลบสินค้านี้หรือไม่?'),
                              content: Text(
                                '“${name.isEmpty ? '(ไม่มีชื่อสินค้า)' : name}”',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(
                                          ctx, false),
                                  child:
                                      const Text('ยกเลิก'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(
                                          ctx, true),
                                  child: const Text('ลบ'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            try {
                              await fs.collection('products').doc(d.id).delete();
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ลบสินค้าสำเร็จ')));
                            } catch (e) {
                              // fallback: create admin notification so backend/admins can process deletion
                              try {
                                await fs.collection('admin_notifications').doc('delete_product_${d.id}').set({
                                  'type': 'delete_request',
                                  'resource': 'product',
                                  'resourceId': d.id,
                                  'title': (d.data()['name'] ?? '').toString(),
                                  'createdAt': FieldValue.serverTimestamp(),
                                  'status': 'pending',
                                }, SetOptions(merge: true));
                              } catch (_) {}
                              final msg = e.toString();
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ไม่สามารถลบสินค้าได้: $msg')));
                            }
                          }
                        },
                      );
                    },
                  ),
                ),
              ] else ...[
                // ✅ โหมดหมวดหมู่ (ทั้งหมด หรือ เลือกหมวดเฉพาะ) : แยก Section ตามหมวด
                Expanded(
                  child: ListView.separated(
                    itemCount: sectionCats.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 12),
                    itemBuilder: (_, sec) {
                      final cat = sectionCats[sec];

                      final items = [...(grouped[cat] ?? [])]
                        ..sort((a, b) {
                          final an =
                              (a.data()['name'] ?? '')
                                  .toString()
                                  .toLowerCase();
                          final bn =
                              (b.data()['name'] ?? '')
                                  .toString()
                                  .toLowerCase();
                          return an.compareTo(bn);
                        });

                      return _Section(
                        title: cat,
                        child: Column(
                          children: [
                            for (int i = 0;
                                i < items.length;
                                i++) ...[
                              _ProductTile(
                                doc: items[i],
                                money0: money0,
                                onEdit: () {
                                  final d = items[i];
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          AddEditProductPage(
                                        docId: d.id,
                                        initial: d.data(),
                                      ),
                                    ),
                                  );
                                },
                                onDelete: () async {
                                  final d = items[i];
                                  final name =
                                      (d.data()['name'] ??
                                              '')
                                          .toString();
                                  final ok =
                                      await showDialog<
                                          bool>(
                                    context: context,
                                    builder: (ctx) =>
                                        AlertDialog(
                                      title: const Text(
                                          'ลบสินค้านี้หรือไม่?'),
                                      content: Text(
                                        '“${name.isEmpty ? '(ไม่มีชื่อสินค้า)' : name}”',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(
                                                  ctx,
                                                  false),
                                          child:
                                              const Text(
                                                  'ยกเลิก'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(
                                                  ctx,
                                                  true),
                                          child:
                                              const Text(
                                                  'ลบ'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok == true) {
                                    await fs
                                        .collection(
                                            'products')
                                        .doc(d.id)
                                        .delete();
                                  }
                                },
                              ),
                              if (i < items.length - 1)
                                const Divider(
                                  height: 8,
                                  color:
                                      Color(0xFFEFEFEF),
                                ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding:
            const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_special_outlined,
                  color: AppColors.brown,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final NumberFormat money0;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductTile({
    required this.doc,
    required this.money0,
    required this.onEdit,
    required this.onDelete,
  });

  // แปลงลิงก์ Google Drive → ลิงก์ดูรูปได้ตรง ๆ
  String _normalizeImageUrl(String url) {
    var u = url.trim();
    if (u.contains('drive.google.com/file/d/')) {
      final re = RegExp(r'd/([^/]+)/');
      final m = re.firstMatch(u);
      if (m != null) {
        final id = m.group(1);
        return 'https://drive.google.com/uc?export=view&id=$id';
      }
    }
    if (u.contains('drive.google.com/uc?')) {
      u = u.replaceFirst(
        'export=download',
        'export=view',
      );
    }
    return u;
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final name = (data['name'] ?? '').toString();
    final category =
        (data['category'] ?? data['categoryName'] ?? '-')
            .toString();

    final priceRaw =
        data['price'] ?? data['basePrice'] ?? 0;
    final price = priceRaw is num
        ? priceRaw.toDouble()
        : double.tryParse('$priceRaw') ?? 0.0;
    final priceText = money0.format(price);

    final stockRaw = data['stock'];
    final stock = stockRaw is num
        ? stockRaw.toInt()
        : int.tryParse('$stockRaw');

    // รูปภาพ: รองรับทั้ง List<String> และ String เดี่ยว
    List<String> images = [];
    final imgs = data['images'];
    if (imgs is List) {
      images = imgs
          .whereType<String>()
          .map(_normalizeImageUrl)
          .where((e) => e.isNotEmpty)
          .toList();
    } else if (imgs is String &&
        imgs.trim().isNotEmpty) {
      images = [_normalizeImageUrl(imgs)];
    }

    // variants
    final v = data['variants'];
    List<String> colors = [];
    List<String> sizes = [];
    if (v is Map<String, dynamic>) {
      final c = v['color'];
      if (c is List) {
        colors = c
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else if (c is String &&
          c.trim().isNotEmpty) {
        colors = [c.trim()];
      }

      final s = v['sizes'];
      if (s is List) {
        sizes = s
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else if (s is String &&
          s.trim().isNotEmpty) {
        sizes = [s.trim()];
      }
    }

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(
              vertical: 6, horizontal: 6),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: images.isEmpty
            ? Container(
                width: 56,
                height: 56,
                color: AppColors.background,
                child: Icon(
                  Icons.diamond_outlined,
                  color: AppColors.brown,
                ),
              )
            : Image.network(
                images.first,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(
                  width: 56,
                  height: 56,
                  color: AppColors.background,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.brown,
                  ),
                ),
              ),
      ),
      title: Text(
        name.isEmpty ? '(ไม่มีชื่อสินค้า)' : name,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text('$priceText • หมวด: $category'),
          if (stock != null)
            Text(
              'สต็อก: $stock ชิ้น',
              style: const TextStyle(
                color: Colors.black54,
              ),
            ),
          if (images.length > 1) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection:
                    Axis.horizontal,
                itemCount: images.length
                    .clamp(0, 8),
                separatorBuilder: (_, __) =>
                    const SizedBox(
                        width: 6),
                itemBuilder: (_, i) =>
                    ClipRRect(
                  borderRadius:
                      BorderRadius
                          .circular(6),
                  child: Image.network(
                    images[i],
                    width: 46,
                    height: 46,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, __, ___) =>
                            Container(
                      width: 46,
                      height: 46,
                      color:
                          const Color(
                              0xFFF2EAE3),
                      child:
                          const Icon(
                        Icons
                            .broken_image_outlined,
                        size: 18,
                        color: Color(
                            0xFF8D6E63),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (colors.isNotEmpty ||
              sizes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: -6,
              children: [
                if (colors.isNotEmpty)
                  _chipMini(
                    'สี: ${colors.join(", ")}',
                  ),
                if (sizes.isNotEmpty)
                  _chipMini(
                    'ไซซ์: ${sizes.join(", ")}',
                  ),
              ],
            ),
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'แก้ไขสินค้า',
            onPressed: onEdit,
            icon: const Icon(Icons.edit),
          ),
          IconButton(
            tooltip: 'ลบสินค้า',
            onPressed: onDelete,
            icon: const Icon(
              Icons.delete_outline,
              color: Colors.red,
            ),
          ),
        ],
      ),
      onTap: onEdit,
    );
  }

  Widget _chipMini(String text) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
              horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F4EF),
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color:
              const Color(0xFFE5DED3),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          color: Color(0xFF5D4037),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
