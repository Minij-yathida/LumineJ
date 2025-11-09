// lib/models/product.dart

import 'package:cloud_firestore/cloud_firestore.dart';

/// ---------------------------------------------------------------------------
/// รุ่นย่อย: ตัวเลือก "ไซส์" ของสินค้า 1 ชิ้น
/// ---------------------------------------------------------------------------
class ProductVariant {
  /// label โชว์หน้า UI เช่น "US 5", "16", "Free Size"
  final String size;

  /// key ภายใน เช่น "us5", "16", "freesize"
  final String sizeId;

  /// สต็อกของไซส์นี้
  final int stock;

  ProductVariant({
    required this.size,
    required this.sizeId,
    required this.stock,
  });

  /// ใช้เป็น key คู่กับ stock_map: "<sizeId>__default"
  String get key => '${sizeId}__default';

  factory ProductVariant.fromMap(Map<String, dynamic> map) {
    return ProductVariant(
      size: (map['size'] ?? '').toString(),
      sizeId: (map['size_id'] ?? '').toString(),
      stock: (map['stock'] is num) ? (map['stock'] as num).toInt() : 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'size': size,
      'size_id': sizeId,
      'stock': stock,
    };
  }
}

/// ---------------------------------------------------------------------------
/// Product หลัก
/// ---------------------------------------------------------------------------
class Product {
  final String id;
  final String name;
  final double price;
  final List<String> images;
  final String category;
  final String description;
  final String? brand;

  /// เดิมในโปรเจกต์ – เอาไว้ให้โค้ดเก่าที่อ้าง `availableColors`, `availableSizes` ยังทำงานได้
  /// สำหรับโครงสร้างใหม่เราจะใช้ `variants` (size-only) เป็นหลัก
  final List<String> availableColors;
  final List<String> availableSizes;

  /// สต็อกรวมของสินค้า (ทุกไซส์รวมกัน)
  final int stock;

  /// สำหรับเช็คสต็อกตามตัวเลือก: key = "<sizeId>__default"
  final Map<String, int> stockMap;

  /// รายการไซส์ตามโครง Firestore ใหม่
  final List<ProductVariant> variants;

  /// สินค้าเปิดใช้งานไหม (ใช้ซ่อนของที่ไม่ขายแล้ว)
  final bool active;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.images,
    required this.category,
    required this.description,
    required this.availableColors,
    required this.availableSizes,
    required this.stock,
    required this.stockMap,
    required this.variants,
    required this.active,
    this.brand,
  });

  /// true = ของหมดทุกไซส์ / ไม่มีสต็อกให้ขาย
  bool get isOutOfStock {
    if (variants.isNotEmpty) {
      return variants.every((v) => v.stock <= 0);
    }
    if (stockMap.isNotEmpty) {
      return stockMap.values.every((s) => s <= 0);
    }
    return stock <= 0;
  }

  /// ดึง stock ของ sizeId นั้น ๆ (ถ้าไม่เจอ คืน 0)
  int stockForSizeId(String sizeId) {
    if (sizeId.isEmpty) return stock;
    final key = '${sizeId}__default';
    if (stockMap.containsKey(key)) {
      return stockMap[key] ?? 0;
    }
    // ลองหาใน variants
    final v = variants.where((e) => e.sizeId == sizeId).toList();
    if (v.isNotEmpty) return v.first.stock;
    return 0;
  }

  /// -------------------------------------------------------------------------
  /// fromFirestore: แปลง document -> Product
  /// -------------------------------------------------------------------------
  factory Product.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    // -------------------- Images --------------------
    final rawImages = data['images'];
    List<String> imageList;
    if (rawImages is List) {
      imageList = rawImages.map((e) => e.toString()).toList();
    } else if (rawImages is String && rawImages.trim().isNotEmpty) {
      imageList = [rawImages.trim()];
    } else {
      imageList = <String>[];
    }

    // -------------------- Price --------------------
    // รองรับทั้ง price เดิม และ basePrice ใหม่จากหลังบ้าน
    final rawPrice = data['price'] ?? data['basePrice'] ?? 0;
    double parsedPrice;
    if (rawPrice is int) {
      parsedPrice = rawPrice.toDouble();
    } else if (rawPrice is double) {
      parsedPrice = rawPrice;
    } else if (rawPrice is String) {
      parsedPrice = double.tryParse(rawPrice) ?? 0.0;
    } else {
      parsedPrice = 0.0;
    }

    // helper แปลงเป็น List<String>
    List<String> toStringList(dynamic raw) {
      if (raw is List) {
        return raw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else if (raw is String && raw.trim().isNotEmpty) {
        return [raw.trim()];
      }
      return <String>[];
    }

    // -------------------- stock_map --------------------
    final Map<String, int> stockMap = {};
    final rawStockMap = data['stock_map'];
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

    // -------------------- variants (size-only) --------------------
    final List<ProductVariant> variants = [];
    final rawVariants = data['variants'];
    if (rawVariants is List) {
      for (final v in rawVariants) {
        if (v is Map<String, dynamic>) {
          variants.add(ProductVariant.fromMap(v));
        } else if (v is Map) {
          variants.add(ProductVariant.fromMap(
              Map<String, dynamic>.from(v as Map)));
        }
      }
    }

    // ถ้า stock_map ยังว่างแต่มี variants -> สร้าง stock_map จาก variants ให้
    if (stockMap.isEmpty && variants.isNotEmpty) {
      for (final v in variants) {
        stockMap[v.key] = v.stock;
      }
    }

    // -------------------- stock รวม --------------------
    int parsedStock = 0;

    // 1) ถ้ามี field stock ที่ top-level → ใช้ก่อน
    final topStock = data['stock'];
    if (topStock is num) {
      parsedStock = topStock.toInt();
    }

    // 2) ถ้ายัง 0 และมี variants → sum จาก variants
    if (parsedStock == 0 && variants.isNotEmpty) {
      parsedStock = variants.fold(0, (sum, v) => sum + v.stock);
    }

    // 3) ถ้ายัง 0 และมี stock_map → sum จาก stock_map
    if (parsedStock == 0 && stockMap.isNotEmpty) {
      parsedStock = stockMap.values.fold(0, (sum, s) => sum + s);
    }

    // -------------------- availableSizes / availableColors --------------------
    // โครงสร้างใหม่: เอาไซส์จาก variants เป็นหลัก
    List<String> sizes = [];
    List<String> colors = [];

    if (variants.isNotEmpty) {
      sizes = variants.map((v) => v.size).toList();
    } else {
      // fallback ของเก่า
      sizes = toStringList(data['availableSizes'] ?? data['sizes']);
      colors = toStringList(data['availableColors'] ?? data['colors']);
    }

    // -------------------- active --------------------
    final bool active = data['active'] == true;

    // -------------------- Return Product --------------------
    return Product(
      id: doc.id,
      name: (data['name'] ?? '').toString(),
      price: parsedPrice,
      images: imageList,
      category: (data['category'] ?? '').toString(),
      description:
          (data['description'] ?? 'No description available.').toString(),
      brand: data['brand']?.toString(),
      availableColors: colors,
      availableSizes: sizes,
      stock: parsedStock,
      stockMap: stockMap,
      variants: variants,
      active: active,
    );
  }

  /// (ถ้าอยากใช้ใน local storage หรือ cart) → แปลงเป็น Map แบบเบื้องต้น
  Map<String, dynamic> toBasicMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'images': images,
      'category': category,
      'description': description,
      'brand': brand,
      'availableColors': availableColors,
      'availableSizes': availableSizes,
      'stock': stock,
      'active': active,
    };
  }
}
