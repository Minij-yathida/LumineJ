// lib/models/cart_item.dart
import 'product.dart';

class CartItem {
  final Product product;
  final int quantity;
  final String selectedColor; // ส่วนใหญ่จะเป็น 'N/A'
  final String selectedSize;  // label ไซส์ที่เลือก เช่น "US 5", "16", "Free Size"

  CartItem({
    required this.product,
    required this.quantity,
    required this.selectedColor,
    required this.selectedSize,
  });

  CartItem copyWith({
    Product? product,
    int? quantity,
    String? selectedColor,
    String? selectedSize,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      selectedColor: selectedColor ?? this.selectedColor,
      selectedSize: selectedSize ?? this.selectedSize,
    );
  }

  /// คีย์สำหรับระบุ item ในตะกร้า
  String get key => '${product.id}::$selectedColor::$selectedSize';

  /// ✅ คีย์สำหรับเช็ค stock_map ใน Firestore
  /// พยายาม map จาก selectedSize -> ProductVariant.sizeId -> "<sizeId>__default"
  String get variantKey {
    // 1) ถ้ามี variants ใน product ให้แมปจาก label
    try {
      if (product.variants.isNotEmpty) {
        for (final v in product.variants) {
          if (v.size == selectedSize || v.sizeId == selectedSize) {
            return v.key; // = '${v.sizeId}__default'
          }
        }
      }
    } catch (_) {}

    // 2) เดา sizeId จาก label เช่น "US 5" -> "us5"
    final label = selectedSize.trim();
    if (label.isNotEmpty) {
      final slug = label
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), '');
      return '${slug}__default';
    }

    // 3) fallback สุดท้าย (ให้ _syncCartStocks ไปใช้ top-level stock แทน)
    return 'default__default';
  }

  // ---------------------------------------------------------------------------
  // PERSIST (เก็บลง SharedPreferences)
  // ---------------------------------------------------------------------------
  Map<String, dynamic> toJson() {
    Map<String, dynamic> productJson;

    // ถ้า Product มี toJson()/toBasicMap ลองใช้ก่อน
    try {
      final dyn = product as dynamic;

      if (dyn.toJson is Function) {
        final maybe = dyn.toJson();
        if (maybe is Map<String, dynamic>) {
          productJson = Map<String, dynamic>.from(maybe);
        } else {
          productJson = _fallbackProductJson(product);
        }
      } else if (dyn.toBasicMap is Function) {
        final maybe = dyn.toBasicMap();
        if (maybe is Map<String, dynamic>) {
          productJson = Map<String, dynamic>.from(maybe);
        } else {
          productJson = _fallbackProductJson(product);
        }
      } else {
        productJson = _fallbackProductJson(product);
      }
    } catch (_) {
      productJson = _fallbackProductJson(product);
    }

    return {
      'product': productJson,
      'quantity': quantity,
      'selectedColor': selectedColor,
      'selectedSize': selectedSize,
    };
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final p = (json['product'] as Map?)?.cast<String, dynamic>() ?? const {};
    final prod = _productFromMap(p);

    return CartItem(
      product: prod,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      selectedColor: (json['selectedColor'] ?? 'N/A').toString(),
      selectedSize: (json['selectedSize'] ?? '').toString(),
    );
  }
}

// ============================================================================
// helpers: สร้าง Product กลับจาก map ที่เก็บไว้ใน local
// ============================================================================

Product _productFromMap(Map<String, dynamic> p) {
  // ----- variants -----
  final List<ProductVariant> vs = [];
  final rawVariants = p['variants'];
  if (rawVariants is List) {
    for (final v in rawVariants) {
      if (v is Map<String, dynamic>) {
        try {
          vs.add(ProductVariant.fromMap(v));
        } catch (_) {}
      } else if (v is Map) {
        try {
          vs.add(ProductVariant.fromMap(Map<String, dynamic>.from(v)));
        } catch (_) {}
      }
    }
  }

  // ----- stock_map -----
  final Map<String, int> stockMap = {};
  final rawStockMap = p['stock_map'];
  if (rawStockMap is Map) {
    rawStockMap.forEach((key, value) {
      if (value is num) {
        stockMap[key.toString()] = value.toInt();
      } else if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          stockMap[key.toString()] = parsed;
        }
      }
    });
  }

  // ถ้าไม่มี stock_map แต่มี variants → สร้าง map จาก variants
  if (stockMap.isEmpty && vs.isNotEmpty) {
    for (final v in vs) {
      stockMap[v.key] = v.stock;
    }
  }

  // ----- availableSizes / availableColors -----
  final availableSizes =
      (p['availableSizes'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          vs.map((e) => e.size).toSet().toList();

  final availableColors =
      (p['availableColors'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];

  // ----- stock รวม -----
  int totalStock = 0;
  if (p['stock'] is num) {
    totalStock = (p['stock'] as num).toInt();
  } else if (vs.isNotEmpty) {
    totalStock = vs.fold(0, (s, v) => s + v.stock);
  } else if (stockMap.isNotEmpty) {
    totalStock = stockMap.values.fold(0, (s, v) => s + v);
  }

  // ----- active -----
  final bool active = (p['active'] == false) ? false : true;

  return Product(
    id: (p['id'] ?? '').toString(),
    name: (p['name'] ?? '').toString(),
    price: (p['price'] is num)
        ? (p['price'] as num).toDouble()
        : double.tryParse('${p['price'] ?? 0}') ?? 0.0,
    images: (p['images'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const [],
    category: (p['category'] ?? '').toString(),
    description: (p['description'] ?? '').toString(),
    brand: p['brand']?.toString(),
    availableColors: availableColors,
    availableSizes: availableSizes,
    stock: totalStock,
    stockMap: stockMap,
    variants: vs,
    active: active,
  );
}

/// ใช้ตอน serialize Product ถ้า Product ไม่มี toJson ภายใน
Map<String, dynamic> _fallbackProductJson(Product p) {
  return {
    'id': p.id,
    'name': p.name,
    'price': p.price,
    'images': p.images,
    'category': p.category,
    'description': p.description,
    'brand': p.brand,
    'availableColors': p.availableColors,
    'availableSizes': p.availableSizes,
    'stock': p.stock,
    'stock_map': p.stockMap,
    'variants': p.variants.map((v) => {
          'size': v.size,
          'size_id': v.sizeId,
          'stock': v.stock,
        }).toList(),
    'active': p.active,
  };
}
