// lib/pages/admin/add_edit_product_page.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';


class AddEditProductPage extends StatefulWidget {
  final String? docId;
  final Map<String, dynamic>? initial;
  const AddEditProductPage({super.key, this.docId, this.initial});

  @override
  State<AddEditProductPage> createState() => _AddEditProductPageState();
}

class _AddEditProductPageState extends State<AddEditProductPage>
    with TickerProviderStateMixin {
  static const String IMGBB_KEY = '8a39c27c6438758e019195ce315004fa';

  final fs = FirebaseFirestore.instance;
  final _form = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  bool _active = true;

  String? _categorySlug; // doc.id ของหมวด
  String? _categoryName; // ชื่อหมวดไว้แสดงผล

  final List<String> _images = [];

  /// เก็บ raw variant จากฟอร์ม
  /// แต่ละตัวอย่างน้อยต้องมี: { id, size, size_id(optional), stock }
  final List<Map<String, dynamic>> _variants = [];

  bool _uploading = false;
  late final TabController _tab;

      @override
    void initState() {
      super.initState();
      _tab = TabController(length: 3, vsync: this);

      final d = widget.initial;
      if (d != null) {
        // (เหมือนเดิมทุกอย่าง)
        _name.text = (d['name'] ?? '').toString();
        _desc.text = (d['description'] ?? '').toString();

        final p = d['basePrice'] ?? d['price'] ?? 0;
        if (p is num) {
          _price.text = p.toStringAsFixed(p % 1 == 0 ? 0 : 2);
        } else {
          _price.text = p.toString();
        }

        _active = d['active'] == true;
        _categorySlug = d['category']?.toString();
        _categoryName = d['categoryName']?.toString();

        final imgs = d['images'];
        if (imgs is List) {
          _images.addAll(imgs.whereType<String>());
        } else if (imgs is String && imgs.isNotEmpty) {
          _images.add(imgs);
        }

        final vars = d['variants'];
        if (vars is List) {
          for (final v in vars) {
            if (v is Map) {
              final mv = Map<String, dynamic>.from(v);
              final size = (mv['size'] ?? '').toString();
              final stock = (mv['stock'] is num)
                  ? (mv['stock'] as num).toInt()
                  : int.tryParse('${mv['stock'] ?? 0}') ?? 0;
              if (size.isEmpty && stock <= 0) continue;

              _variants.add({
                'id': mv['id'] ?? const Uuid().v4(),
                'size': size,
                'size_id': (mv['size_id'] ?? '').toString(),
                'stock': stock,
              });
            }
          }
        }

        if (_variants.isEmpty) {
          final topStock = (d['stock'] is num) ? (d['stock'] as num).toInt() : 0;
          if (topStock > 0) {
            _variants.add({
              'id': const Uuid().v4(),
              'size': 'Freesize',
              'size_id': 'freesize',
              'stock': topStock,
            });
          }
        }
      }

      // ✅ prefetch thumbnail ให้โหลดไวขึ้นตอนโชว์
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final url in _images.take(6)) {
          precacheImage(
            CachedNetworkImageProvider(url),
            context,
          );
        }
      });
    }


  @override
  void dispose() {
    for (final c in [_name, _desc, _price]) {
      c.dispose();
    }
    _tab.dispose();
    super.dispose();
  }

  // ---------- ImgBB ----------
  Future<String?> _uploadToImgBB(XFile file) async {
    try {
    setState(() => _uploading = true);

    final uri = Uri.parse('https://api.imgbb.com/1/upload?key=$IMGBB_KEY');

    final req = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('image', file.path));

    final res = await req.send();
    final body = await res.stream.bytesToString();
    final json = jsonDecode(body);

    if (res.statusCode != 200 || json['data'] == null) {
      debugPrint('ImgBB upload failed: $body');
      return null;
    }

    final data = json['data'];

    // ✅ เลือก URL ที่เหมาะสำหรับ "โหลดเร็ว"
    final thumb = (data['thumb'] is Map) ? data['thumb']['url'] : null;
    final display = data['display_url'];
    final original = data['url'];

    final url = (thumb ?? display ?? original)?.toString();

    if (url == null || url.isEmpty) {
      debugPrint('ImgBB no usable url: $body');
      return null;
    }

    return url;
  } catch (e) {
    debugPrint('ImgBB error: $e');
    return null;
  } finally {
    if (mounted) setState(() => _uploading = false);
  }
}


  Future<void> _pickImages() async {
  if (_uploading) return;

  final picker = ImagePicker();
  final files = await picker.pickMultiImage(
    imageQuality: 70,   // ลดคุณภาพลงนิดหน่อยให้ไฟล์เล็กลง
    maxWidth: 1080,
    maxHeight: 1080,
  );

  if (files.isEmpty) return;

  final remain = 6 - _images.length;
  if (remain <= 0) return;

  setState(() => _uploading = true);

  try {
    // ✅ อัปโหลดแบบ parallel
    final futures = files.take(remain).map(_uploadToImgBB).toList();
    final urls = await Future.wait(futures);

    setState(() {
      _images.addAll(urls.whereType<String>());
    });
  } finally {
    if (mounted) {
      setState(() => _uploading = false);
    }
  }
}


     // ---------- category bottom sheet ----------
  Future<void> _openCategorySheet() async {
    final ivory = const Color(0xFFFBF8F2);
    final brown = const Color(0xFF7A4E3A);

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ivory,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final search = TextEditingController();

        return SafeArea(
          // ไม่ให้ดันขึ้นไปชนขอบบน ให้สนใจด้านล่างอย่างเดียว
          top: false,
          bottom: true,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                // แท่งด้านบน
                Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const Text(
                  'เลือกหมวดหมู่',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TextField(
                    controller: search,
                    decoration: const InputDecoration(
                      hintText: 'ค้นหาหมวด…',
                      prefixIcon: Icon(Icons.search),
                      filled: true,
                    ),
                    onChanged: (_) => (ctx as Element).markNeedsBuild(),
                  ),
                ),

                // ----------- ลิสต์หมวดหมู่ (จำกัดความสูงไม่ให้เต็มจอ) -----------
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 360, // ปรับได้ตามที่ชอบ
                  ),
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: fs.collection('category').snapshots(),
                    builder: (c, snap) {
                      final docs = snap.data?.docs ?? [];
                      final q = search.text.trim().toLowerCase();

                      final fallback = [
                        {'slug': 'bracelet', 'name': 'bracelet'},
                        {'slug': 'earrings', 'name': 'earrings'},
                        {'slug': 'necklace', 'name': 'necklace'},
                        {'slug': 'ring', 'name': 'ring'},
                      ];

                      final itemsFromFs = docs
                          .map((e) => {
                                'slug': e.id,
                                'name': (e.data()['name'] ?? e.id).toString(),
                              })
                          .where((m) =>
                              q.isEmpty ||
                              m['name']!.toLowerCase().contains(q))
                          .toList();

                      final Map<String, Map<String, String>> merged = {};
                      for (final it in fallback) {
                        merged[it['slug']!] = Map<String, String>.from(it);
                      }
                      for (final it in itemsFromFs) {
                        merged[it['slug']!] = {
                          'slug': it['slug']!,
                          'name': it['name']!,
                        };
                      }

                      final items = merged.values.toList()
                        ..sort((a, b) => a['name']!.compareTo(b['name']!));

                      if (snap.connectionState == ConnectionState.waiting &&
                          items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: LinearProgressIndicator(minHeight: 3),
                        );
                      }

                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, thickness: .5),
                        itemBuilder: (_, i) {
                          final it = items[i];
                          final selected = it['slug'] == _categorySlug;
                          return ListTile(
                            title: Text(it['name']!),
                            trailing: selected
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : null,
                            onTap: () => Navigator.pop<Map<String, String>>(
                              ctx,
                              {'slug': it['slug']!, 'name': it['name']!},
                            ),
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
                    style: FilledButton.styleFrom(backgroundColor: brown),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('ปิด'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result != null) {
      setState(() {
        _categorySlug = result['slug'];
        _categoryName = result['name'];
      });
    }
  }


  // ---------- Save ----------
  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;

    final basePrice =
        double.tryParse(_price.text.trim()) ?? 0.0;

    // สร้าง variants + stock_map + stock รวม
    final List<Map<String, dynamic>> variants = [];
    final Map<String, int> stockMap = {};
    int totalStock = 0;

    String _sizeIdFromLabel(String s) {
      final id = s
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '');
      return id.isEmpty ? 'default' : id;
    }

    for (final raw in _variants) {
      final size =
          (raw['size'] ?? '').toString().trim();
      if (size.isEmpty) continue;

      final rawStock = raw['stock'];
      final stock = (rawStock is num)
          ? rawStock.toInt()
          : int.tryParse('$rawStock') ?? 0;
      if (stock <= 0) continue;

      final sizeIdRaw =
          (raw['size_id'] ?? '').toString().trim();
      final sizeId =
          sizeIdRaw.isNotEmpty
              ? sizeIdRaw
              : _sizeIdFromLabel(size);

      variants.add({
        'size': size,
        'size_id': sizeId,
        'stock': stock,
      });

      stockMap['${sizeId}__default'] = stock;
      totalStock += stock;
    }

    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      'description': _desc.text.trim(),
      'category': _categorySlug,
      'categoryName': _categoryName,
      'images': _images,
      'price': basePrice,
      'basePrice': basePrice,
      'active': _active,
      'variants': variants,
      'stock_map': stockMap,
      'stock': totalStock,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (widget.docId == null) {
        await fs.collection('products').add({
          ...payload,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await fs
            .collection('products')
            .doc(widget.docId)
            .update(payload);
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(
              content:
                  Text('บันทึกสินค้าเรียบร้อย')));
    } catch (e) {
      String msg = 'ผิดพลาด: $e';
      if (e is FirebaseException &&
          e.code == 'permission-denied') {
        msg =
            'สิทธิ์ไม่เพียงพอ: บัญชีนี้ไม่มีสิทธิ์เพิ่ม/แก้ไขสินค้า\n(ต้องใช้บัญชีแอดมินหรือปรับกฎ Firestore)';
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
                SnackBar(content: Text(msg)));
      }
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    const ivory = Color(0xFFFBF8F2);
    const brown = Color(0xFF7A4E3A);

    return Scaffold(
      backgroundColor: ivory,
      appBar: AppBar(
        backgroundColor: ivory,
        elevation: 0,
        title: Text(widget.docId == null
            ? 'เพิ่มสินค้าใหม่'
            : 'แก้ไขสินค้า'),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: brown,
          labelColor: brown,
          unselectedLabelColor:
              Colors.grey,
          tabs: const [
            Tab(
                text: 'ข้อมูลหลัก',
                icon: Icon(Icons.info_outline)),
            Tab(
                text: 'รูปภาพ',
                icon: Icon(Icons.image_outlined)),
            Tab(
                text: 'ตัวเลือกย่อย',
                icon: Icon(
                    Icons.format_list_bulleted)),
          ],
        ),
      ),
      body: Form(
        key: _form,
        child: TabBarView(
          controller: _tab,
          children: [
            _buildMainInfoTab(),
            _buildImagesTab(),
            _buildVariantsTab(),
          ],
        ),
      ),
      bottomNavigationBar:
          Container(
        color: Colors.white,
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16 +
              MediaQuery.of(context)
                  .padding
                  .bottom,
        ),
        child:
            FilledButton.icon(
          onPressed: _save,
          style: FilledButton
              .styleFrom(
            backgroundColor:
                brown,
            padding:
                const EdgeInsets
                    .symmetric(
              vertical: 14,
            ),
          ),
          icon: const Icon(
              Icons.save_outlined),
          label: Text(widget.docId ==
                  null
              ? 'สร้างสินค้า'
              : 'บันทึกการแก้ไข'),
        ),
      ),
    );
  }

  Widget _buildMainInfoTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionTitle('ข้อมูลสินค้า'),
        const SizedBox(height: 10),
        TextFormField(
          controller: _name,
          decoration: _input('ชื่อสินค้า *'),
          validator: (v) =>
              (v == null || v.isEmpty)
                  ? 'กรุณากรอกชื่อสินค้า'
                  : null,
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _desc,
          maxLines: 3,
          decoration: _input('รายละเอียด'),
        ),
        const SizedBox(height: 16),
        const _SectionTitle('หมวดหมู่และราคา'),
        const SizedBox(height: 10),
        FormField<String>(
          validator: (_) =>
              (_categorySlug == null)
                  ? 'กรุณาเลือกหมวดหมู่'
                  : null,
          builder: (state) =>
              Column(
            crossAxisAlignment:
                CrossAxisAlignment
                    .start,
            children: [
              OutlinedButton.icon(
                onPressed:
                    _openCategorySheet,
                icon: const Icon(Icons
                    .category_outlined),
                label: Text(
                  _categoryName ==
                          null
                      ? 'เลือกหมวดหมู่ *'
                      : 'หมวด: ${_categoryName!}',
                ),
                style: OutlinedButton
                    .styleFrom(
                  foregroundColor:
                      Colors
                          .brown[
                              700],
                  side: const BorderSide(
                      color: Color(
                          0xFFBCA89F)),
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal:
                        14,
                    vertical:
                        14,
                  ),
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius
                            .circular(
                                12),
                  ),
                ),
              ),
              if (state.hasError)
                const Padding(
                  padding:
                      EdgeInsets.only(
                          top: 6,
                          left: 8),
                  child: Text(
                    'กรุณาเลือกหมวดหมู่',
                    style: TextStyle(
                        color: Colors
                            .red,
                        fontSize:
                            12.5),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _price,
          decoration:
              _input('ราคา (฿) *'),
          keyboardType:
              TextInputType
                  .number,
          validator: (v) =>
              (double.tryParse(
                          v ?? '') ==
                      null)
                  ? 'กรอกราคาเป็นตัวเลข'
                  : null,
        ),
        const SizedBox(height: 10),
        SwitchListTile(
          value: _active,
          onChanged: (v) =>
              setState(() =>
                  _active = v),
          title: const Text(
              'แสดงสินค้า'),
          activeColor:
              const Color(
                  0xFF7A4E3A),
        ),
      ],
    );
  }

  Widget _buildImagesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionTitle('รูปภาพสินค้า'),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment:
              MainAxisAlignment
                  .spaceBetween,
          children: [
            Text(
              'อัปโหลดได้สูงสุด 6 รูป (${_images.length}/6)',
              style:
                  const TextStyle(
                      color: Colors
                          .black54),
            ),
            TextButton.icon(
              onPressed: _images
                          .length >=
                      6
                  ? null
                  : _pickImages,
              icon: const Icon(Icons
                  .add_photo_alternate_outlined),
              label:
                  const Text(
                      'เพิ่มรูป'),
            ),
          ],
        ),
        if (_uploading)
          const LinearProgressIndicator(
              minHeight: 3),
        const SizedBox(height: 8),
        GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: _images.length,
            itemBuilder: (_, i) => Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CachedNetworkImage(
                      imageUrl: _images[i],
                      fit: BoxFit.cover,
                      memCacheWidth: 600,
                      memCacheHeight: 600,
                      placeholder: (_, __) => Container(
                        color: const Color(0xFFF5ECE8),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: const Color.fromARGB(255, 48, 24, 13),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: InkWell(
                    onTap: () => setState(() => _images.removeAt(i)),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 16,
                        color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVariantsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionTitle(
            'ตัวเลือกย่อย (ไซส์)'),
        const SizedBox(height: 8),
        if (_variants.isEmpty)
          Container(
            padding:
                const EdgeInsets.all(
                    12),
            decoration:
                BoxDecoration(
              color:
                  const Color(
                      0xFFF7EFEA),
              borderRadius:
                  BorderRadius
                      .circular(
                          12),
            ),
            child:
                const Text(
              'ยังไม่มีตัวเลือกไซส์\nเพิ่ม "ขนาด + สต็อก" ตามต้องการ',
              style:
                  TextStyle(
                      fontSize:
                          13),
            ),
          ),
        for (int i = 0;
            i < _variants.length;
            i++)
          _VariantCard(
            key: ValueKey(
                _variants[i]['id'] ??
                    i),
            data:
                Map<String, dynamic>.from(
                    _variants[i]),
            onChanged: (m) =>
                setState(() =>
                    _variants[i] =
                        m),
            onRemove: () =>
                setState(() =>
                    _variants.removeAt(
                        i)),
          ),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: () =>
              setState(() =>
                  _variants.add({
                    'id': const Uuid()
                        .v4(),
                    'size':
                        '',
                    'size_id':
                        '',
                    'stock':
                        0,
                  })),
          icon: const Icon(
              Icons.add),
          label: const Text(
              'เพิ่มตัวเลือกใหม่'),
        ),
      ],
    );
  }

  InputDecoration _input(String label) =>
      InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius:
              BorderRadius
                  .circular(
                      12),
          borderSide:
              const BorderSide(
                  color: Colors
                      .brown),
        ),
      );
}

// ---------- Sub Widgets ----------
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style:
          const TextStyle(
        fontWeight:
            FontWeight.w800,
        fontSize: 18,
        color: Color(
            0xFF3E2C24),
      ),
    );
  }
}

/// การ์ดแก้ไข variant (size + stock)
class _VariantCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final void Function(Map<String, dynamic>) onChanged;
  final VoidCallback onRemove;
  const _VariantCard({
    super.key,
    required this.data,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_VariantCard> createState() =>
      _VariantCardState();
}

class _VariantCardState
    extends State<_VariantCard> {
  late final _size =
      TextEditingController(
          text: widget.data['size']
                  ?.toString() ??
              '');
  late final _stock =
      TextEditingController(
          text: widget.data['stock']
                  ?.toString() ??
              '0');

  @override
  void dispose() {
    _size.dispose();
    _stock.dispose();
    super.dispose();
  }

  void _push() {
    widget.onChanged({
      'id': widget.data['id'],
      'size': _size.text.trim(),
      // size_id จะให้ _save สร้างให้จาก label
      'size_id':
          (widget.data['size_id'] ??
                  '')
              .toString(),
      'stock': int.tryParse(
              _stock.text) ??
          0,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:
          const EdgeInsets.only(
              top: 10),
      padding:
          const EdgeInsets.all(
              10),
      decoration:
          BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius
                .circular(
                    12),
        border: Border.all(
          color:
              const Color(
                  0xFFEFE7E2),
        ),
      ),
      child: Column(
        children: [
          TextField(
            controller: _size,
            onChanged: (_) =>
                _push(),
            decoration:
                const InputDecoration(
              labelText:
                  'ขนาด (เช่น US 5, 16 mm, Freesize)',
            ),
          ),
          const SizedBox(
              height: 8),
          Row(
            children: [
              Expanded(
                child:
                    TextField(
                  controller:
                      _stock,
                  keyboardType:
                      TextInputType
                          .number,
                  onChanged:
                      (_) =>
                          _push(),
                  decoration:
                      const InputDecoration(
                    labelText:
                        'สต็อก',
                  ),
                ),
              ),
              IconButton(
                onPressed:
                    widget
                        .onRemove,
                icon: const Icon(
                  Icons
                      .delete_outline,
                  color:
                      Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
