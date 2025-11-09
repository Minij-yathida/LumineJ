// lib/services/cart_provider.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/cart_item.dart';

class CartProvider extends ChangeNotifier {
  // --------------------------------------------------------------------------
  // STATE
  // --------------------------------------------------------------------------
  final List<CartItem> _items = [];
  // เก็บ “ตัวที่ผู้ใช้ติ๊กเลือกชำระ” ด้วย key แบบ id|size|color
  final Set<String> _selectedKeys = <String>{};

  double _shippingFee = 0.0;
  double _couponAmount = 0.0; // ส่วนลดแบบ “จำนวนเงิน”
  String? _couponCode;
  double _taxRate = 0.0; // เช่น 0.07 = 7%

  // base keys สำหรับ SharedPreferences (ต่อท้ายด้วย UID ถ้ามี)
  static const _kCartKeyBase = 'cart_items_v1';
  static const _kSelectedKeyBase = 'cart_selected_v1';
  static const _kMetaKeyBase = 'cart_meta_v1';

  CartProvider() {
    _restoreFromStorage();
    // เปลี่ยน user -> โหลด cart ของ user นั้น
    FirebaseAuth.instance.authStateChanges().listen((_) async {
      await _restoreFromStorage();
    });
  }

  // --------------------------------------------------------------------------
  // GETTERS
  // --------------------------------------------------------------------------
  List<CartItem> get items => List.unmodifiable(_items);

  List<CartItem> get selectedItems =>
      _items.where((e) => _selectedKeys.contains(_keyOf(e))).toList();

  int get itemCount => _items.fold(0, (s, it) => s + it.quantity);

  bool get isEmpty => _items.isEmpty;
  bool get hasSelection => _selectedKeys.isNotEmpty;

  double get shippingFee => _shippingFee;
  double get taxRate => _taxRate;
  String? get couponCode => _couponCode;

  // รวมทั้งตะกร้า
  double get subtotalAll =>
      _items.fold(0.0, (s, it) => s + it.product.price * it.quantity);

  double get discountAll => _couponAmount.clamp(0, subtotalAll);

  double get taxAll => _taxBase(_items, discountAll, _shippingFee) * _taxRate;

  double get grandTotalAll {
    final base = _taxBase(_items, discountAll, _shippingFee);
    final t = base + taxAll;
    return t < 0 ? 0.0 : t;
  }

  // เฉพาะรายการที่เลือก
  double get subtotalSelected =>
      selectedItems.fold(0.0, (s, it) => s + it.product.price * it.quantity);

  double get discountSelected =>
      _couponAmount.clamp(0, subtotalSelected); // ถ้าอยากลดเฉพาะที่เลือก

  double get taxSelected =>
      _taxBase(selectedItems, discountSelected, _shippingFee) * _taxRate;

  double get grandTotalSelected {
    final base = _taxBase(selectedItems, discountSelected, _shippingFee);
    final t = base + taxSelected;
    return t < 0 ? 0.0 : t;
  }

  // เดิม: ใช้ totalAmount -> ให้เท่ากับ subtotalAll
  double get totalAmount => subtotalAll;

  double _taxBase(
      List<CartItem> src, double discount, double shippingFee) {
    final sum = src.fold<double>(
      0.0,
      (s, it) => s + it.product.price * it.quantity,
    );
    final base = sum - discount + shippingFee;
    return base < 0 ? 0.0 : base;
  }

  // --------------------------------------------------------------------------
  // MUTATIONS – CART
  // --------------------------------------------------------------------------
  void addItem(CartItem newItem) {
    final idx = _indexOf(newItem);
    final maxStock = _maxStockFor(newItem);

    if (maxStock <= 0) {
      // ไม่มีของในสต็อก ไม่ต้องเพิ่ม
      return;
    }

    if (idx >= 0) {
      // มี item เดิม (id+สี+ไซส์ เดียวกัน)
      final cur = _items[idx];
      final desired = cur.quantity + newItem.quantity;
      final capped = desired.clamp(1, maxStock);
      if (capped != cur.quantity) {
        _items[idx] = cur.copyWith(quantity: capped);
      }
    } else {
      final capped = newItem.quantity.clamp(1, maxStock);
      _items.add(newItem.copyWith(quantity: capped));
    }

    _persist();
    notifyListeners();
  }

  void updateQuantity(CartItem item, int newQuantity) {
    final idx = _indexOf(item);
    if (idx < 0) return;

    if (newQuantity <= 0) {
      removeItem(_items[idx]);
      return;
    }

    final maxStock = _maxStockFor(_items[idx]);
    final q = newQuantity.clamp(1, maxStock);
    _items[idx] = _items[idx].copyWith(quantity: q);

    _persist();
    notifyListeners();
  }

  void removeItem(CartItem itemToRemove) {
    final key = _keyOf(itemToRemove);
    _items.removeWhere((it) => _keyOf(it) == key);
    _selectedKeys.remove(key);
    _persist();
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    _selectedKeys.clear();
    _persist();
    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // SELECTION – เลือกเพื่อ “ไปชำระ”
  // --------------------------------------------------------------------------
  void toggleSelect(CartItem item) {
    final k = _keyOf(item);
    if (_selectedKeys.contains(k)) {
      _selectedKeys.remove(k);
    } else {
      _selectedKeys.add(k);
    }
    _persist();
    notifyListeners();
  }

  bool isSelected(CartItem item) => _selectedKeys.contains(_keyOf(item));

  void selectAll() {
    _selectedKeys
      ..clear()
      ..addAll(_items.map(_keyOf));
    _persist();
    notifyListeners();
  }

  void clearSelection() {
    _selectedKeys.clear();
    _persist();
    notifyListeners();
  }

  /// ลบเฉพาะที่เลือก (หลังชำระเงินสำเร็จ)
  void removeSelected() {
    _items.removeWhere((it) => _selectedKeys.contains(_keyOf(it)));
    _selectedKeys.clear();
    _persist();
    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // META – shipping / tax / coupon
  // --------------------------------------------------------------------------
  void setShippingFee(double v) {
    _shippingFee = v < 0 ? 0.0 : v;
    _persist();
    notifyListeners();
  }

  void setTaxRate(double r) {
    _taxRate = r < 0 ? 0.0 : r;
    _persist();
    notifyListeners();
  }

  void applyCoupon({required String code, required double amount}) {
    _couponCode = code.trim().isEmpty ? null : code.trim();
    _couponAmount = amount < 0 ? 0.0 : amount;
    _persist();
    notifyListeners();
  }

  void clearCoupon() {
    _couponCode = null;
    _couponAmount = 0.0;
    _persist();
    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // ORDER PAYLOAD
  // --------------------------------------------------------------------------
  Map<String, dynamic> _payloadFrom(
    List<CartItem> src, {
    required double subtotal,
    required double discount,
    required double shipping,
    required double tax,
    required double grand,
    String currency = 'THB',
  }) {
    final lines = src
        .map((it) => {
              'productId': it.product.id,
              'name': it.product.name,
              'price':
                  double.parse(it.product.price.toStringAsFixed(2)),
              'qty': it.quantity,
              'image': it.product.images.isNotEmpty
                  ? it.product.images.first
                  : null,
              'variant': {
                'size': it.selectedSize,
                'color': it.selectedColor,
              },
            })
        .toList();

    return {
      'currency': currency,
      'items': lines,
      'pricing': {
        'subtotal': double.parse(subtotal.toStringAsFixed(2)),
        'discount': double.parse(discount.toStringAsFixed(2)),
        'shippingFee': double.parse(shipping.toStringAsFixed(2)),
        'taxRate': _taxRate,
        'tax': double.parse(tax.toStringAsFixed(2)),
        'grandTotal': double.parse(grand.toStringAsFixed(2)),
      },
      'promotion': {'couponCode': _couponCode},
    };
  }

  /// payload ทั้งตะกร้า
  Map<String, dynamic> buildOrderPayloadAll({String currency = 'THB'}) {
    return _payloadFrom(
      _items,
      subtotal: subtotalAll,
      discount: discountAll,
      shipping: _shippingFee,
      tax: taxAll,
      grand: grandTotalAll,
      currency: currency,
    );
  }

  /// ✅ payload เฉพาะรายการที่เลือกไปชำระ
  Map<String, dynamic> buildOrderPayloadSelected(
      {String currency = 'THB'}) {
    return _payloadFrom(
      selectedItems,
      subtotal: subtotalSelected,
      discount: discountSelected,
      shipping: _shippingFee,
      tax: taxSelected,
      grand: grandTotalSelected,
      currency: currency,
    );
  }

  /// alias: เคลียร์เฉพาะที่ชำระแล้ว
  void finalizeCheckoutSelected() => removeSelected();

  // --------------------------------------------------------------------------
  // PERSISTENCE
  // --------------------------------------------------------------------------
  String _keyFor(String base) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? base : '$base|$uid';
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // cart
      final listJson =
          jsonEncode(_items.map((e) => e.toJson()).toList());
      await prefs.setString(_keyFor(_kCartKeyBase), listJson);

      // selected
      await prefs.setStringList(
        _keyFor(_kSelectedKeyBase),
        _selectedKeys.toList(),
      );

      // meta
      await prefs.setString(
        _keyFor(_kMetaKeyBase),
        jsonEncode({
          'shippingFee': _shippingFee,
          'couponAmount': _couponAmount,
          'couponCode': _couponCode,
          'taxRate': _taxRate,
        }),
      );
    } catch (e) {
      if (kDebugMode) {
        print('Persist cart error: $e');
      }
    }
  }

  Future<void> _restoreFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid;

      final cartKey = _keyFor(_kCartKeyBase);
      final selKey = _keyFor(_kSelectedKeyBase);
      final metaKey = _keyFor(_kMetaKeyBase);

      // ----- cart -----
      String? listJson;
      if (uid != null) {
        listJson = prefs.getString(cartKey);
      } else {
        // guest: ใช้ key ปัจจุบัน หรือ legacy เดิม
        listJson =
            prefs.getString(cartKey) ?? prefs.getString(_kCartKeyBase);
      }

      if (listJson != null) {
        final raw = jsonDecode(listJson) as List;
        _items
          ..clear()
          ..addAll(raw.map((e) =>
              CartItem.fromJson(e as Map<String, dynamic>)));
      } else {
        _items.clear();
      }

      // ----- selected -----
      List<String>? sel;
      if (uid != null) {
        sel = prefs.getStringList(selKey);
      } else {
        sel = prefs.getStringList(selKey) ??
            prefs.getStringList(_kSelectedKeyBase);
      }
      _selectedKeys
        ..clear()
        ..addAll(sel ?? const []);

      // ----- meta -----
      String? meta;
      if (uid != null) {
        meta = prefs.getString(metaKey);
      } else {
        meta = prefs.getString(metaKey) ??
            prefs.getString(_kMetaKeyBase);
      }

      // ถ้า login แล้ว เคลียร์ legacy key ทิ้ง
      if (uid != null) {
        try {
          await prefs.remove(_kCartKeyBase);
          await prefs.remove(_kSelectedKeyBase);
          await prefs.remove(_kMetaKeyBase);
        } catch (_) {}
      }

      if (meta != null) {
        final m = jsonDecode(meta) as Map<String, dynamic>;
        _shippingFee = (m['shippingFee'] ?? 0.0) * 1.0;
        _couponAmount = (m['couponAmount'] ?? 0.0) * 1.0;
        _couponCode = m['couponCode'];
        _taxRate = (m['taxRate'] ?? 0.0) * 1.0;
      } else {
        _shippingFee = 0.0;
        _couponAmount = 0.0;
        _couponCode = null;
        _taxRate = 0.0;
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Restore cart error: $e');
      }
    }
  }

  // --------------------------------------------------------------------------
  // HELPERS
  // --------------------------------------------------------------------------
  int _indexOf(CartItem it) =>
      _items.indexWhere((e) => _keyOf(e) == _keyOf(it));

  String _keyOf(CartItem it) => it.key;

  /// หา stock สูงสุดที่อนุญาตสำหรับ item นั้น (ตามไซส์ที่เลือก ถ้ามี)
  int _maxStockFor(CartItem it) {
    final prod = it.product;
    final size = it.selectedSize;

    if (size.isNotEmpty && prod.variants.isNotEmpty) {
      final match = prod.variants
          .where((v) => v.size == size)
          .toList();
      if (match.isNotEmpty) {
        final s = match.first.stock;
        if (s > 0) return s;
      }
    }
    // fallback: ใช้ stock รวมของสินค้า
    return prod.stock > 0 ? prod.stock : 0;
  }
}
