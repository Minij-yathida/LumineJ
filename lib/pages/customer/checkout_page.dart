// lib/pages/customer/checkout_page.dart
// ✅ รองรับคูปองที่ใช้ document-id สุ่ม โดย lookup จาก field "code"
// ✅ แก้ _couponSection ให้ดึงคูปองด้วย where('code', in: [...]) + แบ่ง chunk ไม่เกิน 10
// ✅ ใช้ร่วมกับ CouponsPage(popOnClaim: true) ที่เก็บ claimedCoupons ด้วย field code ได้

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:LumineJewelry/pages/customer/coupon_page.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:http/http.dart' as http;

import '../../models/cart_item.dart';
import '../../services/cart_provider.dart';
import '../../services/auth_service.dart';
import '../../services/push_routing.dart';
import '../../core/order_guard.dart';
import '../../services/payment_service.dart';

// ===== Theme =====
const Color _bg = Color(0xFFFBF1F1);
const Color _ink = Color(0xFF5D4037);
const Color _muted = Color(0xFF8D6E63);
const Color _cream1 = Color(0xFFFFF3EE);
const Color _cream2 = Color(0xFFFFFAF7);
const Color _creamChip = Color(0xFFFFF7EC);
const Color _creamBorder = Color(0xFFEEDFD6);
const Color _accentPill = Color(0xFFFFE8E0);
const Color _ok = Color(0xFF1B8A3B);

const Color _gold1 = Color(0xFFFFE7C4);
const Color _gold2 = Color(0xFFFFD79A);
const Color _gold3 = Color(0xFFFFC873);
const Color _rose1 = Color(0xFFFFE5F0);
const Color _rose2 = Color(0xFFFFCFE2);

class CheckoutPage extends StatefulWidget {
  final List<CartItem>? itemsOverride;
  const CheckoutPage({super.key, this.itemsOverride});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _formKey = GlobalKey<FormState>();

  // profile
  final _nameCtl = TextEditingController();
  final _addrCtl = TextEditingController();
  final _phoneCtl = TextEditingController();
  final _emailCtl = TextEditingController();

  // shipping options
  final List<Map<String, dynamic>> _shippingOptions = [
    {
      'id': 'standard',
      'name': 'Standard Delivery (ส่งธรรมดา)',
      'desc': '3-5 วันทำการ',
      'base_price': 35.0,
      'extra_per_item': 5.0,
      'icon': Icons.local_shipping_outlined,
    },
    {
      'id': 'express',
      'name': 'Express Delivery (ส่งด่วน)',
      'desc': '1-2 วันทำการ',
      'base_price': 60.0,
      'extra_per_item': 10.0,
      'icon': Icons.flash_on_outlined,
    },
    {
      'id': 'cod',
      'name': 'Cash on Delivery (เก็บปลายทาง)',
      'desc': '1-3 วันทำการ (มีค่าธรรมเนียม)',
      'base_price': 50.0,
      'extra_per_item': 5.0,
      'icon': Icons.money_outlined,
    },
  ];
  String _selectedShippingOptionId = 'standard';

  // coupon state
  Map<String, dynamic>? _selectedCoupon;
  double _productDiscount = 0.0;
  double _shippingDiscount = 0.0;

  // payment
  int _method = 1; // 1 = โอน, 2 = COD
  bool _creating = false;
  bool _done = false;

  // misc
  final _scroll = ScrollController();
  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;
  final _authService = AuthService();
  final _money = NumberFormat('#,##0.00', 'th_TH');

  static const double kSectionGap = 18;
  static const double kCardGap = 16;
  static const double kRadius = 16;
  static const double kBottomBarHeight = 168;

  TextStyle get tTitle =>
      const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink, height: 1.25);
  TextStyle get tBody =>
      const TextStyle(fontSize: 14.5, color: _ink, height: 1.35);
  TextStyle get tMuted =>
      const TextStyle(fontSize: 13.5, color: _muted, height: 1.35, fontWeight: FontWeight.w500);

  // PromptPay config
  static const String kPromptPayTarget = '0927216974';
  static const String kMerchantName = 'ญาธิดา สุกสาย';
  static const String kMerchantCity = 'BANGKOK';
  static const String kBankName = 'กสิกรไทย (KBank)';
  static const String kBankAccount = '060-8-83020-0';

  @override
  void initState() {
    super.initState();
    _loadProfile();
    if (_shippingOptions.isNotEmpty) {
      _selectedShippingOptionId = _shippingOptions.first['id'];
    }
  }

  Future<void> _loadProfile() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final p = await _authService.getUserProfile(uid);
      _nameCtl.text = (p?['displayName'] ?? '').toString();
      _emailCtl.text = (p?['email'] ?? '').toString();
      _phoneCtl.text = (p?['phoneNumber'] ?? '').toString();
      _addrCtl.text = (p?['address'] ?? '').toString();
    } catch (_) {}
  }

  @override
  void dispose() {
    _scroll.dispose();
    _nameCtl.dispose();
    _addrCtl.dispose();
    _phoneCtl.dispose();
    _emailCtl.dispose();
    super.dispose();
  }

  // ----------------- Pricing -----------------
  double _subtotal(List<CartItem> items) =>
      items.fold(0.0, (s, it) => s + it.product.price * it.quantity);

  double _shippingFee(List<CartItem> items, double subtotal) {
    if (subtotal >= 1500) return 0;
    if (items.isEmpty) return 0;

    String optionIdToFind;
    if (_method == 2) {
      optionIdToFind = 'cod';
    } else {
      optionIdToFind = _selectedShippingOptionId;
    }

    final option = _shippingOptions.firstWhere(
      (opt) => opt['id'] == optionIdToFind,
      orElse: () => _shippingOptions.first,
    );

    final double basePrice = (option['base_price'] as num).toDouble();
    final double extraPerItem = (option['extra_per_item'] as num).toDouble();
    final int count = items.fold<int>(0, (s, it) => s + it.quantity);

    return basePrice + (count - 1).clamp(0, double.infinity) * extraPerItem;
  }

  double _grandTotal(List<CartItem> items) {
    final sub = _subtotal(items);
    final ship = _shippingFee(items, sub);
    final double totalProduct =
        (sub - _productDiscount).clamp(0, double.infinity).toDouble();
    final double totalShipping =
        (ship - _shippingDiscount).clamp(0, double.infinity).toDouble();
    return totalProduct + totalShipping;
  }

  // ----------------- Coupon calc helpers -----------------
  double _calcDiscountFor(Map<String, dynamic> c, double subtotal, DateTime now) {
    final type = (c['type'] ?? '').toString();
    if (type.startsWith('shipping_')) return 0.0;

    if (c['active'] != true) return 0;
    final ts = c['expiresAt'];
    DateTime? exp;
    if (ts is Timestamp) {
      exp = ts.toDate();
    } else if (ts is String) {
      try {
        exp = DateTime.parse(ts);
      } catch (_) {}
    }
    if (exp != null && exp.isBefore(now)) return 0;

    final minSpend =
        (c['minSpend'] is num) ? (c['minSpend'] as num).toDouble() : 0.0;
    if (subtotal < minSpend) return 0;

    final value =
        (c['value'] is num) ? (c['value'] as num).toDouble() : 0.0;
    final maxCap =
        (c['maxDiscount'] is num) ? (c['maxDiscount'] as num).toDouble() : double.infinity;

    double d = (type == 'percent') ? subtotal * value / 100.0 : value;
    if (d > maxCap) d = maxCap;
    return d.clamp(0, subtotal);
  }

  double _calcShippingDiscountFor(
    Map<String, dynamic> c,
    double subtotal,
    double currentShippingFee,
    DateTime now,
  ) {
    final type = (c['type'] ?? '').toString();
    if (!type.startsWith('shipping_')) return 0.0;

    if (c['active'] != true) return 0;
    final ts = c['expiresAt'];
    DateTime? exp;
    if (ts is Timestamp) {
      exp = ts.toDate();
    } else if (ts is String) {
      try {
        exp = DateTime.parse(ts);
      } catch (_) {}
    }
    if (exp != null && exp.isBefore(now)) return 0;

    final minSpend =
        (c['minSpend'] is num) ? (c['minSpend'] as num).toDouble() : 0.0;
    if (subtotal < minSpend) return 0;

    final value =
        (c['value'] is num) ? (c['value'] as num).toDouble() : 0.0;
    final maxCap =
        (c['maxDiscount'] is num) ? (c['maxDiscount'] as num).toDouble() : double.infinity;

    double d = 0.0;
    if (type == 'shipping_fixed') {
      d = value;
    } else if (type == 'shipping_percent') {
      d = currentShippingFee * (value / 100.0);
    } else if (type == 'shipping_full') {
      d = currentShippingFee;
    }

    if (d > maxCap) d = maxCap;
    return d.clamp(0, currentShippingFee);
  }

  Map<String, dynamic>? _pickBestCoupon(
    List<Map<String, dynamic>> coupons,
    double subtotal,
    double shippingFee,
    DateTime now,
  ) {
    if (coupons.isEmpty) return null;
    coupons.sort((a, b) {
      final da = _calcDiscountFor(a, subtotal, now) +
          _calcShippingDiscountFor(a, subtotal, shippingFee, now);
      final db = _calcDiscountFor(b, subtotal, now) +
          _calcShippingDiscountFor(b, subtotal, shippingFee, now);

      if (da != db) return db.compareTo(da);
      final pa =
          (a['priority'] is num) ? (a['priority'] as num).toInt() : 0;
      final pb =
          (b['priority'] is num) ? (b['priority'] as num).toInt() : 0;
      return pb.compareTo(pa);
    });
    final best = coupons.first;
    final totalDiscount = _calcDiscountFor(best, subtotal, now) +
        _calcShippingDiscountFor(best, subtotal, shippingFee, now);
    return totalDiscount > 0 ? best : null;
  }

  // ----------------- PromptPay QR -----------------
  String _ppPayload({
    required String target,
    required double amount,
    required String merchantName,
    required String merchantCity,
  }) {
    String tlv(String id, String value) =>
        '$id${value.length.toString().padLeft(2, '0')}$value';
    String fmtTarget(String t) =>
        RegExp(r'^0\d{9}$').hasMatch(t) ? '0066${t.substring(1)}' : t;
    String sanitize(String s, int max) {
      final up = s
          .toUpperCase()
          .replaceAll(RegExp(r'[^A-Z0-9 .\-]'), '');
      return up.substring(0, up.length.clamp(0, max));
    }

    final f00 = tlv('00', '01');
    final f01 = tlv('01', '11');
    final f29 = tlv(
        '29',
        tlv('00', 'A000000677010111') +
            tlv('01', fmtTarget(target)));
    final f52 = tlv('52', '0000');
    final f53 = tlv('53', '764');
    final f54 = tlv('54', amount.toStringAsFixed(2));
    final f58 = tlv('58', 'TH');
    final f59 = tlv('59', sanitize(merchantName, 25));
    final f60 = tlv('60', sanitize(merchantCity, 15));
    final withoutCrc =
        f00 + f01 + f29 + f52 + f53 + f54 + f58 + f59 + f60 + '6304';
    return withoutCrc + _crc16(withoutCrc).toUpperCase();
  }

  String _crc16(String data) {
    int crc = 0xFFFF;
    for (final c in data.codeUnits) {
      crc ^= c << 8;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 0x8000) != 0
            ? ((crc << 1) ^ 0x1021)
            : (crc << 1);
        crc &= 0xFFFF;
      }
    }
    return crc.toRadixString(16).padLeft(4, '0');
  }

  // ----------------- ImgBB upload -----------------
  Future<String?> _uploadSlipToImgBB(String localPath) async {
    const imgbbKey = String.fromEnvironment('IMGBB_KEY',
        defaultValue: '82bd12994bc8362dc693b62326838c40');
    if (imgbbKey == '82bd12994bc8362dc693b62326838c40' || imgbbKey.isEmpty) {
      throw Exception('');
    }
    final bytes = await File(localPath).readAsBytes();
    final b64 = base64Encode(bytes);
    final uri =
        Uri.parse('https://api.imgbb.com/1/upload?key=$imgbbKey');
    final res = await http.post(
      uri,
      headers: {
        'Content-Type':
            'application/x-www-form-urlencoded'
      },
      body: {'image': b64},
    );
    if (res.statusCode == 200) {
      final data =
          jsonDecode(res.body) as Map<String, dynamic>;
      if (data['success'] == true) {
        return data['data']['url'] as String;
      }
      throw Exception(
          'อัปโหลด ImgBB ล้มเหลว: ${data['error'] ?? 'unknown'}');
    } else {
      throw Exception(
          'IMGBB HTTP ${res.statusCode}: ${res.body}');
    }
  }

  // ----------------- Coupon / claimed helpers -----------------

Future<void> _markCouponAsUsed(
  String uid,
  String code,
  String orderId,
) async {
  try {
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.isEmpty) return;

    final colRef = _fs
        .collection('users')
        .doc(uid)
        .collection('claimedCoupons');

    // เคสปกติ: doc id = CODE
    final directRef = colRef.doc(normalizedCode);
    final directSnap = await directRef.get();

    if (directSnap.exists) {
      // ถ้าอยากเก็บประวัติใน order แล้วค่อยใช้คูปองใน order แทน claimedCoupons
      // ก็ไม่ต้องเซ็ต redeemedAt ที่นี่แล้ว ลบได้เลย
      await directRef.delete();
      debugPrint('[coupon] deleted $normalizedCode for user $uid (order $orderId)');
      return;
    }

    // fallback: เผื่อมีเคสเก่าวาง docId สุ่มแต่มี field code
    final q = await colRef
        .where('code', isEqualTo: normalizedCode)
        .limit(1)
        .get();

    if (q.docs.isNotEmpty) {
      await q.docs.first.reference.delete();
      debugPrint('[coupon] deleted (fallback) $normalizedCode for user $uid (order $orderId)');
    }
  } catch (e) {
    debugPrint('Error marking coupon as used (delete mode): $e');
  }
}

  // โหลดเอกสารคูปองจาก collection `coupons` ด้วย list ของ code
  // ✅ รองรับ document-id สุ่ม เพราะ lookup ที่ field "code"
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _getCouponsByCodes(List<String> codes) async {
    if (codes.isEmpty) return [];
    final List<
        QueryDocumentSnapshot<Map<String, dynamic>>> docs = [];
    final uniqueCodes =
        codes.toSet().toList(); // กันซ้ำ

    // Firestore whereIn จำกัด 10 ค่า → แบ่งเป็น chunk
    for (var i = 0; i < uniqueCodes.length; i += 10) {
      final batch = uniqueCodes.sublist(
          i,
          (i + 10 > uniqueCodes.length)
              ? uniqueCodes.length
              : i + 10);
      final snap = await _fs
          .collection('coupons')
          .where('code', whereIn: batch)
          .get();
      docs.addAll(snap.docs);
    }
    return docs;
  }

  // ----------------- Transfer sheet -----------------
  Future<String?> _openTransferSheet(double amount) async {
    final payload = _ppPayload(
      target: kPromptPayTarget,
      amount: amount,
      merchantName: kMerchantName,
      merchantCity: kMerchantCity,
    );
    final picker = ImagePicker();
    XFile? picked;
    int sec = 300;
    Timer? timer;
    bool sheetClosed = false;

    final result =
        await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
            builder: (ctx2, setSt) {
          timer ??= Timer.periodic(
              const Duration(seconds: 1), (t) {
            if (sheetClosed) return t.cancel();
            if (!ctx2
                .findAncestorStateOfType<
                    State>()!
                .mounted) return t.cancel();
            if (sec <= 0) {
              t.cancel();
              if (Navigator.of(ctx2)
                  .canPop()) {
                Navigator.pop(ctx2, null);
              }
            } else {
              setSt(() => sec--);
            }
          });
          return _CreamCard(
            radius: kRadius + 4,
            padding:
                const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Text(
                              'ชำระผ่าน โอน/พร้อมเพย์',
                              style:
                                  tTitle)),
                      const LuxBadge(
                          text: 'หมดเวลา'),
                      const SizedBox(
                          width: 8),
                      Text(
                          '${_mm(sec)}:${_ss(sec)}',
                          style: tMuted),
                    ],
                  ),
                  const SizedBox(
                      height: 12),
                  Container(
                    padding:
                        const EdgeInsets
                            .all(12),
                    decoration:
                        BoxDecoration(
                      gradient:
                          const LinearGradient(
                        colors: [
                          _cream1,
                          _cream2
                        ],
                        begin: Alignment
                            .topLeft,
                        end:
                            Alignment.bottomRight,
                      ),
                      borderRadius:
                          BorderRadius
                              .circular(
                                  kRadius),
                      border:
                          Border.all(
                              color:
                                  _creamBorder),
                      boxShadow: const [
                        BoxShadow(
                            blurRadius:
                                14,
                            color: Color(
                                0x14000000))
                      ],
                    ),
                    child: Column(
                      children: [
                        Stack(
                          alignment:
                              Alignment
                                  .center,
                          children: [
                            const LuxRing(
                                size:
                                    260),
                            QrImageView(
                              data:
                                  payload,
                              size:
                                  230,
                              version:
                                  QrVersions
                                      .auto,
                            ),
                          ],
                        ),
                        const SizedBox(
                            height:
                                8),
                        _kv('ชื่อบัญชี',
                            kMerchantName,
                            bold:
                                true),
                        _kv(
                            'ยอดเงิน',
                            '฿${_money.format(amount)}',
                            bold:
                                true),
                        const SizedBox(
                            height:
                                4),
                        _kv(
                            'PromptPay',
                            kPromptPayTarget),
                        _kv(
                            kBankName,
                            'เลขบัญชี $kBankAccount'),
                        const SizedBox(
                            height:
                                4),
                        Text(
                          'โปรดชำระภายในเวลาและแนบหลักฐานการชำระเงิน',
                          style:
                              tMuted,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(
                      height: 10),
                  OutlinedButton.icon(
                    onPressed:
                        () async {
                      final x = await picker
                          .pickImage(
                        source: ImageSource
                            .gallery,
                        imageQuality:
                            85,
                      );
                      if (x != null) {
                        setSt(() =>
                            picked =
                                x);
                      }
                    },
                    icon: const Icon(Icons
                        .image_outlined),
                    label: Text(
                      picked == null
                          ? 'แนบสลิปการชำระเงิน'
                          : 'อัปเดตสลิปการชำระเงิน',
                      style:
                          const TextStyle(
                        color: _ink,
                      ),
                    ),
                  ),
                  if (picked != null)
                    ...[
                      const SizedBox(
                          height:
                              8),
                      ClipRRect(
                        borderRadius:
                            BorderRadius
                                .circular(
                                    10),
                        child: Image
                            .file(
                          File(picked!
                              .path),
                          height:
                              150,
                          fit: BoxFit
                              .cover,
                        ),
                      ),
                    ],
                  const SizedBox(
                      height:
                          12),
                  Row(
                    children: [
                      Expanded(
                        child:
                            OutlinedButton(
                          onPressed: () =>
                              Navigator.pop(
                                  ctx2,
                                  null),
                          child:
                              const Text(
                            'ปิด',
                            style: TextStyle(
                                color:
                                    _ink),
                          ),
                        ),
                      ),
                      const SizedBox(
                          width:
                              10),
                      Expanded(
                        child:
                            ElevatedButton
                                .icon(
                          onPressed:
                              picked ==
                                      null
                                  ? null
                                  : () =>
                                      Navigator.pop(
                                          ctx2,
                                          picked!.path),
                          icon: const Icon(
                              Icons
                                  .verified_outlined),
                          label:
                              const Text(
                                  'ยืนยันโอนแล้ว'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );

    sheetClosed = true;
    timer?.cancel();
    return result;
  }

  String _mm(int s) =>
      (s ~/ 60).toString().padLeft(2, '0');
  String _ss(int s) =>
      (s % 60).toString().padLeft(2, '0');

  // ----------------- Coupon chooser from sheet -----------------
  Future<void> _openClaimedVsAllCouponsSheet(
      List<Map<String, dynamic>> claimedCoupons,
      double subtotal) async {
    final selected =
        await showModalBottomSheet<
            Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFFFFBF9),
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(
              16, 16, 16, 10),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                Row(children: [
                  Text('จัดการคูปอง',
                      style: tTitle.copyWith(
                          fontSize: 20)),
                  const SizedBox(
                      width: 8),
                  const LuxSparkle(
                      size: 18),
                ]),
                const SizedBox(
                    height: 12),
                Text('คูปองที่รับไว้',
                    style: tBody.copyWith(
                        fontWeight:
                            FontWeight
                                .w800)),
                const SizedBox(
                    height: 8),
                if (claimedCoupons
                    .isEmpty) ...[
                  Text(
                      'ยังไม่มีคูปองที่รับไว้',
                      style: tMuted),
                  const SizedBox(
                      height: 12),
                ] else ...[
                  SizedBox(
                    height: 80,
                    child:
                        ListView.separated(
                      scrollDirection:
                          Axis.horizontal,
                      itemCount:
                          claimedCoupons
                              .length,
                      separatorBuilder:
                          (_, __) =>
                              const SizedBox(
                                  width:
                                      8),
                      itemBuilder:
                          (_, i) {
                        final c =
                            claimedCoupons[
                                i];
                        return LuxChip(
                          icon: Icons
                              .local_offer_outlined,
                          label:
                              '${c['code'] ?? 'COUPON'}',
                          isSelected:
                              _selectedCoupon?[
                                      'code'] ==
                                  c['code'],
                          onTap: () {
                            Navigator.pop(
                                ctx,
                                c);
                            setState(() =>
                                _selectedCoupon =
                                    c);
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(
                      height: 12),
                ],
                Row(
                  mainAxisAlignment:
                      MainAxisAlignment
                          .spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Text(
                            'คูปองที่ยังไม่ได้รับ',
                            style: tBody.copyWith(
                                fontWeight:
                                    FontWeight
                                        .w800)),
                        const SizedBox(
                            height:
                                6),
                        Text(
                            'ดูคูปองทั้งหมดและเลือกรับคูปองที่ต้องการ',
                            style:
                                tMuted),
                      ],
                    ),
                    ElevatedButton.icon(
                      onPressed:
                          () async {
                        Navigator.pop(
                            ctx);
                        final selectedFromAll = await Navigator.of(
                                context)
                            .push<Map<String,
                                dynamic>>(
                          MaterialPageRoute(
                            builder: (_) =>
                                const CouponsPage(
                                    popOnClaim:
                                        true),
                          ),
                        );
                        if (selectedFromAll !=
                                null &&
                            mounted) {
                          setState(() =>
                              _selectedCoupon =
                                  selectedFromAll);
                        }
                      },
                      icon: const Icon(Icons
                          .open_in_new),
                      label: const Text(
                          'ไปที่คูปอง'),
                    ),
                  ],
                ),
                const SizedBox(
                    height: 12),
                Align(
                  alignment:
                      Alignment.center,
                  child: TextButton(
                    onPressed: () =>
                        Navigator.pop(
                            ctx),
                    child: const Text(
                        'ปิด'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null && mounted) {
      setState(() => _selectedCoupon =
          selected);
    }
  }

  // ----------------- Coupon Sheet (Best + list) -----------------
  Future<void> _openCouponSheet(
      List<Map<String, dynamic>> coupons,
      double subtotal) async {
    final now = DateTime.now();
    final items =
        context.read<CartProvider>().selectedItems;
    final ship = _shippingFee(items, subtotal);
    final best = _pickBestCoupon(
        coupons, subtotal, ship, now);

    final selected =
        await showModalBottomSheet<
            Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFFFFBF9),
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(
              16, 16, 16, 10),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                Row(children: [
                  Text('เลือกคูปองส่วนลด',
                      style: tTitle.copyWith(
                          fontSize: 20)),
                  const SizedBox(
                      width: 8),
                  const LuxSparkle(
                      size: 18),
                ]),
                const SizedBox(
                    height: 12),
                if (best != null)
                  _bestRow(
                      best,
                      subtotal,
                      ship,
                      now,
                      onTap: () =>
                          Navigator.pop(
                              context,
                              best)),
                Flexible(
                  child:
                      ListView.separated(
                    shrinkWrap: true,
                    itemCount:
                        coupons.length,
                    separatorBuilder:
                        (_, __) =>
                            const SizedBox(
                                height:
                                    10),
                    itemBuilder:
                        (ctx, i) {
                      final c =
                          coupons[i];
                      final pDisc =
                          _calcDiscountFor(
                              c,
                              subtotal,
                              now);
                      final sDisc =
                          _calcShippingDiscountFor(
                              c,
                              subtotal,
                              ship,
                              now);
                      final disc =
                          pDisc + sDisc;

                      DateTime? exp;
                      final ts =
                          c['expiresAt'];
                      if (ts
                          is Timestamp) {
                        exp = ts
                            .toDate();
                      } else if (ts
                          is String) {
                        try {
                          exp = DateTime
                              .parse(
                                  ts);
                        } catch (_) {}
                      }

                      final type = (c['type'] ??
                              '')
                          .toString();
                      final val = (c['value']
                              is num)
                          ? (c['value']
                                  as num)
                              .toDouble()
                          : 0.0;

                      Widget typePill;
                      if (type
                          .startsWith(
                              'shipping_')) {
                        if (type ==
                                'shipping_full' ||
                            (type ==
                                    'shipping_fixed' &&
                                val >
                                    1000) ||
                            (type ==
                                    'shipping_percent' &&
                                val ==
                                    100)) {
                          typePill =
                              _pillChip(
                                  'ส่งฟรี');
                        } else if (type ==
                            'shipping_fixed') {
                          typePill =
                              _pillChip(
                                  'ลดค่าส่ง ฿${_money.format(val)}');
                        } else {
                          typePill =
                              _pillChip(
                                  'ลดค่าส่ง ${val.toStringAsFixed(0)}%');
                        }
                      } else {
                        typePill =
                            _pillChip(type ==
                                    'percent'
                                ? '${val.toStringAsFixed(0)}% OFF'
                                : '฿${_money.format(val)} OFF');
                      }

                      return Container(
                        decoration:
                            BoxDecoration(
                          gradient:
                              const LinearGradient(
                            colors: [
                              _cream1,
                              _cream2
                            ],
                            begin: Alignment
                                .topLeft,
                            end: Alignment
                                .bottomRight,
                          ),
                          borderRadius:
                              BorderRadius
                                  .circular(
                                      14),
                          border:
                              Border.all(
                                  color:
                                      _creamBorder),
                          boxShadow: const [
                            BoxShadow(
                                blurRadius:
                                    12,
                                color: Color(
                                    0x12000000),
                                offset:
                                    Offset(
                                        0,
                                        6))
                          ],
                        ),
                        padding:
                            const EdgeInsets
                                .all(12),
                        child: Row(
                          children: [
                            const LuxIcon(
                                child: Icon(
                                    Icons
                                        .local_offer,
                                    color:
                                        _ink),
                                size: 44),
                            const SizedBox(
                                width:
                                    12),
                            Expanded(
                              child:
                                  Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment
                                        .start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        c['code'] ??
                                            'COUPON',
                                        style: const TextStyle(
                                            fontSize:
                                                16,
                                            fontWeight:
                                                FontWeight.w800,
                                            color:
                                                _ink),
                                      ),
                                      const SizedBox(
                                          width:
                                              6),
                                      const LuxSparkle(
                                          size:
                                              14),
                                    ],
                                  ),
                                  const SizedBox(
                                      height:
                                          2),
                                  Wrap(
                                    spacing:
                                        6,
                                    runSpacing:
                                        -6,
                                    children: [
                                      typePill,
                                      if (c['minSpend']
                                              is num &&
                                          (c['minSpend']
                                                  as num) >
                                              0)
                                        _pillChip(
                                            'ขั้นต่ำ ฿${_money.format((c['minSpend'] as num).toDouble())}'),
                                      if (c['maxDiscount']
                                              is num &&
                                          (c['maxDiscount']
                                                      as num)
                                                  .toDouble() >
                                              0)
                                        _pillChip(
                                            'ลดสูงสุด ฿${_money.format((c['maxDiscount'] as num).toDouble())}'),
                                    ],
                                  ),
                                  if ((c['description'] ??
                                              '')
                                          .toString()
                                          .isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets
                                          .only(
                                              top:
                                                  4),
                                      child: Text(
                                          c['description'],
                                          style:
                                              tMuted),
                                    ),
                                  if (exp !=
                                      null)
                                    Padding(
                                      padding: const EdgeInsets
                                          .only(
                                              top:
                                                  4),
                                      child: Text(
                                        'หมดอายุ: ${exp.day}/${exp.month}/${exp.year}',
                                        style:
                                            tMuted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(
                                width:
                                    8),
                            Column(
                              mainAxisAlignment:
                                  MainAxisAlignment
                                      .center,
                              children: [
                                Text(
                                  pDisc > 0
                                      ? 'ส่วนลดสินค้า'
                                      : (sDisc > 0
                                          ? 'ส่วนลดค่าส่ง'
                                          : 'ส่วนลด'),
                                  style: TextStyle(
                                      fontSize:
                                          12,
                                      color:
                                          _muted),
                                ),
                                Text(
                                  disc > 0
                                      ? '฿${_money.format(disc)}'
                                      : '—',
                                  style: TextStyle(
                                    fontWeight: FontWeight
                                        .w900,
                                    fontSize:
                                        16,
                                    color: disc >
                                            0
                                        ? _ok
                                        : _muted,
                                  ),
                                ),
                                const SizedBox(
                                    height:
                                        6),
                                LuxGhostButton(
                                  label:
                                      'เลือก',
                                  onTap: disc >
                                          0
                                      ? () => Navigator.pop(
                                          ctx,
                                          c)
                                      : null,
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(
                    height: 10),
                Align(
                  alignment:
                      Alignment.center,
                  child:
                      TextButton.icon(
                    onPressed: () =>
                        Navigator.pop(
                            ctx),
                    icon: const Icon(
                        Icons.close,
                        color: _ink),
                    label: const Text(
                      'ปิด',
                      style: TextStyle(
                          color: _ink,
                          fontWeight:
                              FontWeight
                                  .w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null) {
      setState(() => _selectedCoupon =
          selected);
    }
  }

  Widget _bestRow(
      Map<String, dynamic> best,
      double subtotal,
      double shippingFee,
      DateTime now,
      {VoidCallback? onTap}) {
    final pDisc =
        _calcDiscountFor(best, subtotal, now);
    final sDisc = _calcShippingDiscountFor(
        best, subtotal, shippingFee, now);
    final disc = pDisc + sDisc;

    String savingText =
        'ประหยัดได้ประมาณ ฿${_money.format(disc)}';
    if (pDisc == 0 &&
        sDisc > 0 &&
        sDisc >= shippingFee) {
      savingText = 'ใช้คูปองนี้เพื่อ "ส่งฟรี"';
    } else if (pDisc == 0 &&
        sDisc > 0) {
      savingText =
          'ประหยัดค่าส่ง ฿${_money.format(sDisc)}';
    }

    return InkWell(
      onTap: onTap,
      borderRadius:
          BorderRadius.circular(14),
      child: Container(
        margin:
            const EdgeInsets.only(
                bottom: 10),
        padding:
            const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius:
              BorderRadius.circular(
                  14),
          gradient:
              const LinearGradient(
                  colors: [
                _rose1,
                _gold1
              ]),
          border: Border.all(
              color:
                  _creamBorder),
          boxShadow: const [
            BoxShadow(
                blurRadius: 12,
                color: Color(
                    0x16000000),
                offset:
                    Offset(0, 6))
          ],
        ),
        child: Row(
          children: [
            const LuxIcon(
                child: Icon(
                    Icons
                        .recommend_outlined,
                    color:
                        _ink),
                size: 44),
            const SizedBox(
                width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Text(
                    'คุ้มสุด • ${best['code'] ?? ''}',
                    style: tBody.copyWith(
                        fontWeight:
                            FontWeight
                                .w900),
                  ),
                  const SizedBox(
                      height:
                          2),
                  Text(
                    savingText,
                    style: tMuted,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------- Submit -----------------
  Future<void> _submit() async {
    if (!_formKey.currentState!
        .validate()) return;

    final cart =
        context.read<CartProvider>();
    final items = widget.itemsOverride ??
        cart.selectedItems;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(
              content: Text(
                  'ยังไม่ได้เลือกสินค้าเพื่อชำระ')));
      return;
    }

    try {
      await ensureCustomerOrDialog(
          context);
    } catch (_) {
      return;
    }

    // validate selected coupon vs conditions
    if (_selectedCoupon != null) {
      try {
        final data =
            _selectedCoupon!;
        final subtotal =
            _subtotal(cart.selectedItems);
        final shippingFee =
            _shippingFee(
                cart.selectedItems,
                subtotal);
        final pDisc =
            _calcDiscountFor(
                data,
                subtotal,
                DateTime.now());
        final sDisc =
            _calcShippingDiscountFor(
                data,
                subtotal,
                shippingFee,
                DateTime.now());
        if (pDisc + sDisc ==
            0.0) {
          _selectedCoupon = null;
          cart.clearCoupon();
          if (mounted) {
            ScaffoldMessenger.of(
                    context)
                .showSnackBar(
              const SnackBar(
                content: Text(
                    'คูปองไม่ตรงเงื่อนไขยอดสั่งซื้อ/หมดอายุ ถูกนำออกแล้ว'),
              ),
            );
          }
          if (mounted) {
            setState(() {});
          }
          return;
        }

        final uid =
            _auth.currentUser?.uid;
        if (uid != null) {
          final code = (data['code'] ??
                  _selectedCoupon![
                      'code'] ??
                  '')
              .toString();
          bool claimed = false;
          bool alreadyRedeemed =
              false;
          DocumentSnapshot?
              claimSnap;
          try {
            if (code
                .isNotEmpty) {
              final docRef = _fs
                  .collection(
                      'users')
                  .doc(uid)
                  .collection(
                      'claimedCoupons')
                  .doc(code);
              final docSnap =
                  await docRef
                      .get();
              if (docSnap.exists) {
                claimed = true;
                claimSnap = docSnap;
              }
              if (!claimed) {
                final q = await _fs
                    .collection(
                        'users')
                    .doc(uid)
                    .collection(
                        'claimedCoupons')
                    .where('code',
                        isEqualTo:
                            code)
                    .limit(1)
                    .get();
                if (q.docs
                    .isNotEmpty) {
                  claimed = true;
                  claimSnap =
                      q.docs
                          .first;
                }
              }
            }
            if (claimSnap != null) {
              final claimData =
                  claimSnap.data()
                      as Map<String,
                          dynamic>?;
              if (claimData !=
                      null &&
                  claimData.containsKey(
                          'redeemedAt') &&
                  claimData[
                          'redeemedAt'] !=
                      null) {
                alreadyRedeemed =
                    true;
              }
            }
          } catch (_) {
            claimed = false;
          }
          if (!claimed ||
              alreadyRedeemed) {
            _selectedCoupon =
                null;
            cart.clearCoupon();
            String msg = alreadyRedeemed
                ? 'คูปองนี้ถูกใช้ไปแล้ว'
                : 'คูปองยังไม่ได้รับจากคุณ ไม่สามารถใช้งานได้';
            if (mounted) {
              ScaffoldMessenger.of(
                      context)
                  .showSnackBar(
                SnackBar(
                    content:
                        Text(msg)),
              );
            }
            if (mounted) {
              setState(() {});
            }
            return;
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
                  context)
              .showSnackBar(
            SnackBar(
              content: Text(
                  'ตรวจคูปองล้มเหลว: $e'),
            ),
          );
        }
        return;
      }
    }

    setState(() =>
        _creating = true);

    String? slipPath;
    if (_method == 1) {
      slipPath = await _openTransferSheet(
          _grandTotal(items));
      if (slipPath == null) {
        setState(() =>
            _creating = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content: Text(
                'หมดเวลาชำระแล้ว กรุณาลองใหม่อีกครั้ง'),
          ),
        );
        return;
      }
    }

    try {
      final itemsPayload = items
          .map((it) => {
                'productId':
                    it.product.id,
                'qty': it.quantity,
                'variant': {
                  'size':
                      it.selectedSize,
                  'color':
                      it.selectedColor,
                },
              })
          .toList();

      final sub =
          _subtotal(items);
      final ship = _shippingFee(
          items, sub);
      final grandTotal =
          _grandTotal(items);

      final customerPayload = {
        'name': _nameCtl.text.trim(),
        'address':
            _addrCtl.text.trim(),
        'phone': _phoneCtl.text.trim(),
        'email': _emailCtl.text.trim(),
      };

      final pricingPayload = {
        'subtotal': sub,
        'shippingFee': ship,
        'grandTotal':
            grandTotal,
      };

      final paymentPayload = {
        'method':
            _method == 1
                ? 'transfer_qr'
                : 'cod',
        'slipUrl':
            slipPath ?? '',
      };

      final String orderId =
          await PaymentService.instance.createOrderViaFunctions(
        items:itemsPayload,
        couponCode:_selectedCoupon?['code'],
        customer:customerPayload,
        pricing:pricingPayload,
        payment:paymentPayload,
      );
      // ✅ หลังสร้าง order สำเร็จ - mark coupon as used if applicable
      final uid = _auth.currentUser?.uid;
      if (uid != null && _selectedCoupon != null) {
        final code = (_selectedCoupon!['code'] ?? '').toString().toUpperCase();
        if (code.isNotEmpty && (_productDiscount + _shippingDiscount) > 0) {
          await _markCouponAsUsed(uid, code, orderId);
        }
      }

      cart.removeSelected();
      if (mounted) {
        setState(() =>
            _done = true);
      }
    } catch (e) {
      final err =
          e.toString();
      final isOutOfStock = err.contains(
              'สินค้าบางรายการสต๊อกไม่พอ') ||
          err
              .toUpperCase()
              .contains(
                  'OUT_OF_STOCK');

      if (isOutOfStock) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content: Text(
                'ขออภัย สินค้าบางรายการหมดในสต๊อก ระบบจะอัปเดตตะกร้าของคุณโดยอัตโนมัติ'),
          ),
        );
        try {
          await _syncCartStocks(
              items);
        } catch (syncErr) {
          debugPrint(
              'Failed to sync cart stocks: $syncErr');
        }
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          SnackBar(
            content: Text(
                'บันทึกคำสั่งซื้อไม่สำเร็จ: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() =>
            _creating = false);
      }
    }
  }

  Future<void> _syncCartStocks(
      List<CartItem> items) async {
    try {
      final cart =
          context.read<
              CartProvider>();
      final Map<String,
              DocumentSnapshot>
          cache = {};
      for (final it in items) {
        final pid =
            it.product.id;
        if (!cache
            .containsKey(
                pid)) {
          cache[pid] =
              await _fs
                  .collection(
                      'products')
                  .doc(pid)
                  .get();
        }
        final pSnap =
            cache[pid];
        if (pSnap == null ||
            !pSnap.exists) {
          continue;
        }
        final Map<String,
                dynamic>
            data =
            (pSnap.data()
                    as Map<String,
                        dynamic>?) ??
                {};

        final variantKey =
            it.variantKey;
        final rawStockMap =
            data['stock_map'];
        int available = 0;
        if (rawStockMap
                is Map &&
            rawStockMap
                .containsKey(
                    variantKey)) {
          final raw =
              rawStockMap[
                  variantKey];
          if (raw
              is num) {
            available =
                raw.toInt();
          } else if (raw
              is String) {
            available =
                int.tryParse(
                        raw) ??
                    0;
          }
        } else {
          final top =
              data['stock'];
          if (top
              is num) {
            available =
                top.toInt();
          } else if (top
              is String) {
            available =
                int.tryParse(
                        top) ??
                    0;
          }
        }

        if (available <=
            0) {
          cart.removeItem(
              it);
        } else if (available <
            it.quantity) {
          cart.updateQuantity(
              it,
              available);
        }
      }
    } catch (e) {
      debugPrint(
          'Error while syncing cart stocks: $e');
    }
  }

  // ----------------- UI -----------------
  @override
  Widget build(BuildContext context) {
    final cart =
        context.watch<
            CartProvider>();
    final items = widget.itemsOverride ??
        cart.selectedItems;

    final sub =
        _subtotal(items);
    final ship =
        _shippingFee(items, sub);
    final now = DateTime.now();

    if (_selectedCoupon ==
        null) {
      _productDiscount = 0.0;
      _shippingDiscount = 0.0;
    } else {
      _productDiscount =
          _calcDiscountFor(
              _selectedCoupon!,
              sub,
              now);
      _shippingDiscount =
          _calcShippingDiscountFor(
              _selectedCoupon!,
              sub,
              ship,
              now);
    }

    final grandTotal =
        _grandTotal(items);

    if (_done) {
      WidgetsBinding
          .instance
          .addPostFrameCallback(
              (_) {
        PushRouting
            .openNotificationsTab(
                context);
      });
      return Scaffold(
        appBar: AppBar(
            title: const Text(
                'คำสั่งซื้อสำเร็จ')),
        body: Center(
          child: Padding(
            padding:
                const EdgeInsets
                    .all(24),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment
                      .center,
              children: [
                const Icon(
                  Icons
                      .check_circle,
                  color: Color(
                      0xFF4CAF50),
                  size: 120,
                ),
                const SizedBox(
                    height:
                        16),
                Text(
                  'รับคำสั่งซื้อเรียบร้อยแล้ว!',
                  style: tTitle.copyWith(
                      fontSize:
                          22),
                ),
                const SizedBox(
                    height:
                        8),
                Text(
                  _method == 1
                      ? 'สถานะ: กำลังดำเนินการตรวจสอบชำระเงิน'
                      : 'สถานะ: เก็บเงินปลายทาง (COD)',
                  style:
                      tBody,
                  textAlign:
                      TextAlign
                          .center,
                ),
                const SizedBox(
                    height:
                        28),
                SizedBox(
                  width:
                      double.infinity,
                  child:
                      ElevatedButton
                          .icon(
                    onPressed: () =>
                        Navigator.of(context).pushNamedAndRemoveUntil(
                            '/home',
                            (_) =>
                                false),
                    icon: const Icon(
                        Icons
                            .home_outlined),
                    label:
                        const Text(
                            'กลับหน้าหลัก'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
          title: const Text(
              'ยืนยันคำสั่งซื้อ')),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child:
                ListView(
              controller:
                  _scroll,
              key: const PageStorageKey(
                  'checkout-list'),
              cacheExtent:
                  800,
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                kBottomBarHeight +
                    MediaQuery.of(
                            context)
                        .padding
                        .bottom +
                    16,
              ),
              children: [
                Row(
                  children: [
                    const LuxSparkle(
                        size:
                            16),
                    const SizedBox(
                        width:
                            8),
                    Text(
                      'รายการสินค้า',
                      style:
                          tTitle,
                    ),
                  ],
                ),
                const SizedBox(
                    height:
                        kCardGap),
                _CreamCard(
                  padding:
                      const EdgeInsets
                              .symmetric(
                          vertical:
                              6,
                          horizontal:
                              8),
                  child:
                      Column(
                    children: [
                      for (int i = 0;
                          i <
                              items
                                  .length;
                          i++) ...[
                        _itemRow(
                            items[
                                i]),
                        if (i <
                            items.length -
                                1)
                          const Divider(
                            height:
                                10,
                            color:
                                _creamBorder,
                          ),
                      ]
                    ],
                  ),
                ),
                const SizedBox(
                    height:
                        kSectionGap),
                _couponSection(
                    subtotal:
                        sub,
                    shippingFee:
                        ship),
                const SizedBox(
                    height:
                        kSectionGap),
                Row(
                  children: [
                    const LuxSparkle(
                        size:
                            16),
                    const SizedBox(
                        width:
                            8),
                    Text(
                      'ข้อมูลผู้รับสินค้า',
                      style:
                          tTitle,
                    ),
                  ],
                ),
                const SizedBox(
                    height:
                        kCardGap),
                _CreamCard(
                  padding:
                      EdgeInsets
                          .zero,
                  child:
                      _textBox(
                    _nameCtl,
                    'ชื่อ-นามสกุล',
                    'กรุณากรอกชื่อ',
                  ),
                ),
                const SizedBox(
                    height:
                        kCardGap),
                _CreamCard(
                  padding:
                      EdgeInsets
                          .zero,
                  child:
                      _textBox(
                    _addrCtl,
                    'ที่อยู่จัดส่ง',
                    'กรุณากรอกที่อยู่',
                    maxLines:
                        2,
                  ),
                ),
                const SizedBox(
                    height:
                        kCardGap),
                _CreamCard(
                  padding:
                      EdgeInsets
                          .zero,
                  child:
                      _textBox(
                    _phoneCtl,
                    'เบอร์โทร',
                    'กรุณากรอกเบอร์โทร',
                    type: TextInputType
                        .phone,
                  ),
                ),
                const SizedBox(
                    height:
                        kCardGap),
                _CreamCard(
                  padding:
                      EdgeInsets
                          .zero,
                  child:
                      _textBox(
                    _emailCtl,
                    'อีเมล (สำหรับแจ้งเตือน)',
                    'กรุณากรอกอีเมล',
                    type: TextInputType
                        .emailAddress,
                    enabled:
                        false,
                  ),
                ),
                if (_method ==
                    1) ...[
                  const SizedBox(
                      height:
                          kSectionGap),
                  Row(
                    children: [
                      const LuxSparkle(
                          size:
                              16),
                      const SizedBox(
                          width:
                              8),
                      Text(
                        'ช่องทางการจัดส่ง ',
                        style:
                            tTitle,
                      ),
                    ],
                  ),
                  const SizedBox(
                      height:
                          kCardGap),
                  _buildShippingOptionsSection(),
                ],
                const SizedBox(
                    height:
                        kSectionGap),
                Row(
                  children: [
                    const LuxSparkle(
                        size:
                            16),
                    const SizedBox(
                        width:
                            8),
                    Text(
                      'ช่องทางการชำระเงิน',
                      style:
                          tTitle,
                    ),
                  ],
                ),
                const SizedBox(
                    height:
                        kCardGap),
                _paymentGroup(
                    sub, ship),
                const SizedBox(
                    height:
                        24),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child:
                Container(
              decoration:
                  const BoxDecoration(
                color:
                    _cream2,
                borderRadius:
                    BorderRadius.vertical(
                  top: Radius
                      .circular(
                          kRadius),
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius:
                        16,
                    color: Color(
                        0x26000000),
                  ),
                ],
              ),
              child:
                  SafeArea(
                top: false,
                child:
                    Padding(
                  padding:
                      const EdgeInsets.fromLTRB(
                          16,
                          12,
                          16,
                          12),
                  child:
                      Column(
                    mainAxisSize:
                        MainAxisSize
                            .min,
                    children: [
                      _priceLine(
                          'ยอดสินค้า',
                          '฿${_money.format(sub)}'),
                      _priceLine(
                        'ค่าส่ง',
                        '฿${_money.format(ship)}',
                        subtle:
                            true,
                      ),
                      if (_productDiscount >
                          0)
                        _priceLine(
                          'ส่วนลดสินค้า',
                          '-฿${_money.format(_productDiscount)}',
                          subtle:
                              true,
                          color:
                              _ok,
                        ),
                      if (_shippingDiscount >
                          0)
                        _priceLine(
                          'ส่วนลดค่าส่ง',
                          '-฿${_money.format(_shippingDiscount)}',
                          subtle:
                              true,
                          color:
                              _ok,
                        ),
                      const SizedBox(
                          height:
                              6),
                      Row(
                        children: [
                          Expanded(
                            child:
                                Text(
                              'ยอดชำระทั้งหมด',
                              style:
                                  tTitle.copyWith(
                                fontSize:
                                    16,
                              ),
                            ),
                          ),
                          Text(
                            '฿${_money.format(grandTotal)}',
                            style: const TextStyle(
                              fontSize:
                                  18,
                              fontWeight:
                                  FontWeight.w900,
                              color:
                                  _ok,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(
                          height:
                              10),
                      SizedBox(
                        width: double
                            .infinity,
                        height:
                            48,
                        child:
                            LuxCTA(
                          icon: _method ==
                                  1
                              ? Icons
                                  .qr_code_2
                              : Icons
                                  .local_shipping_outlined,
                          label: _creating
                              ? 'กำลังดำเนินการ...'
                              : (_method ==
                                      1
                                  ? 'ไปชำระเงิน'
                                  : 'ยืนยันคำสั่งซื้อ (COD)'),
                          busy:
                              _creating,
                          onPressed: _creating
                                  ? null
                                  : _submit,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- UI pieces ----------
  Widget _itemRow(CartItem it) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment
              .start,
      children: [
        ClipRRect(
          borderRadius:
              BorderRadius
                  .circular(
                      10),
          child:
              Image.network(
            it.product.images
                    .isNotEmpty
                ? it.product
                    .images
                    .first
                : 'https://placehold.co/600x400/F0E0D6/8D6E63?text=N/A',
            width:
                56,
            height:
                56,
            fit: BoxFit
                .cover,
          ),
        ),
        const SizedBox(
            width:
                12),
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment
                    .start,
            children: [
              Text(
                it.product.name,
                style:
                    const TextStyle(
                  fontWeight:
                      FontWeight
                          .w700,
                  fontSize:
                      15,
                  color:
                      _ink,
                  height:
                      1.25,
                ),
              ),
              const SizedBox(
                  height:
                      2),
              Text(
                '฿${_money.format(it.product.price)} x ${it.quantity}',
                style:
                    tMuted,
              ),
            ],
          ),
        ),
        Text(
          '฿${_money.format(it.product.price * it.quantity)}',
          style:
              const TextStyle(
            fontWeight:
                FontWeight
                    .bold,
            color:
                _ink,
          ),
        ),
      ],
    );
  }

  Widget _buildShippingOptionsSection() {
    final optionsToShow =
        _shippingOptions
            .where((opt) =>
                opt['id'] !=
                'cod')
            .toList();

    return _CreamCard(
      child: Column(
        children:
            optionsToShow
                .asMap()
                .entries
                .map(
                    (entry) {
          final int i =
              entry.key;
          final Map<String,
                  dynamic>
              opt =
              entry.value;
          final bool
              isLast =
              i ==
                  optionsToShow.length -
                      1;

          return Column(
            children: [
              _prettyRadio<
                  String>(
                title: opt[
                    'name'],
                value: opt[
                    'id'],
                groupValue:
                    _selectedShippingOptionId,
                icon: opt[
                    'icon'],
                helper: opt[
                    'desc'],
                onChanged:
                    (String?
                        newId) {
                  if (newId !=
                      null) {
                    final pos = _scroll
                        .position
                        .pixels;
                    setState(() =>
                        _selectedShippingOptionId =
                            newId);
                    WidgetsBinding
                        .instance
                        .addPostFrameCallback(
                            (_) {
                      if (_scroll
                          .hasClients) {
                        _scroll.jumpTo(
                            pos);
                      }
                    });
                  }
                },
              ),
              if (!isLast)
                const Divider(
                  height:
                      20,
                  color:
                      _creamBorder,
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _couponSection(
      {required double subtotal,
      required double shippingFee}) {
    final uid =
        _auth.currentUser?.uid;
    if (uid == null) {
      return _CreamCard(
        padding:
            const EdgeInsets
                .all(14),
        child: Row(
          children: [
            Text(
              'กรุณาเข้าสู่ระบบเพื่อใช้คูปอง',
              style: tBody,
            ),
          ],
        ),
      );
    }

    return 
    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
  stream: _fs
      .collection('users')
      .doc(uid)
      .collection('claimedCoupons')
      .where('redeemedAt', isEqualTo: null) // ✅ เอาเฉพาะที่ยังไม่ใช้
      .snapshots(),
      builder:
          (context, snap) {
        if (snap
                .connectionState ==
            ConnectionState
                .waiting) {
          return _CreamCard(
            padding:
                const EdgeInsets
                    .all(14),
            child: Row(
              children: [
                const SizedBox(
                  width:
                      20,
                  height:
                      20,
                  child:
                      CircularProgressIndicator(
                    strokeWidth:
                        2,
                  ),
                ),
                const SizedBox(
                    width:
                        10),
                Text(
                  'กำลังโหลดคูปองที่รับไว้…',
                  style:
                      tBody,
                ),
              ],
            ),
          );
        }

        if (snap
            .hasError) {
          if (snap.error
                  .toString()
              .contains(
                  'composite index')) {
            return _CreamCard(
              padding:
                  const EdgeInsets
                      .all(14),
              child: Text(
                'เกิดข้อผิดพลาด: คุณต้องสร้าง Index ใน Firestore ก่อน โปรดดู Log ใน Console สำหรับลิงก์',
                style: tBody.copyWith(
                    color: Colors
                        .redAccent),
              ),
            );
          }
          return _CreamCard(
            padding:
                const EdgeInsets
                    .all(14),
            child: Text(
              'เกิดข้อผิดพลาด: ${snap.error}',
              style: tBody.copyWith(
                  color: Colors
                      .redAccent),
            ),
          );
        }

        final claimDocs =
            snap.data
                    ?.docs ??
                [];

        final codes = claimDocs
            .map((doc) => (doc
                        .data()[
                    'code'] ??
                doc.id)
                .toString()
                .toUpperCase())
            .where((c) =>
                c.isNotEmpty)
            .toList();

        final headerRow =
            Row(
          children: [
            const LuxIcon(
                child: Icon(
                    Icons
                        .discount_outlined,
                    color:
                        _ink),
                size: 40),
            const SizedBox(
                width:
                    10),
            Expanded(
              child: Text(
                'คูปองที่คุณรับไว้',
                style:
                    tTitle,
              ),
            ),
            LuxGhostButton(
              icon: Icons
                  .list_alt_outlined,
              label:
                  'ดูทั้งหมด',
              onTap:
                  () {},
            ),
          ],
        );

        if (codes
            .isEmpty) {
          return _CreamCard(
            padding:
                const EdgeInsets
                    .all(14),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                headerRow,
                const SizedBox(
                    height:
                        8),
                Text(
                  'คุณยังไม่ได้รับคูปองใด ๆ (หรือใช้ไปหมดแล้ว)\nกด "ดูทั้งหมด" เพื่อเลือกรับคูปอง',
                  style:
                      tMuted,
                ),
              ],
            ),
          );
        }

        // ✅ โหลดคูปองโดย lookup จาก field "code"
        return FutureBuilder<
            List<
                QueryDocumentSnapshot<
                    Map<String,
                        dynamic>>>>(
          future:
              _getCouponsByCodes(
                  codes),
          builder:
              (context,
                  cSnap) {
            if (cSnap
                    .connectionState ==
                ConnectionState
                    .waiting) {
              return _CreamCard(
                padding:
                    const EdgeInsets
                        .all(14),
                child: Row(
                  children: [
                    const SizedBox(
                      width:
                          20,
                      height:
                          20,
                      child:
                          CircularProgressIndicator(
                        strokeWidth:
                            2,
                      ),
                    ),
                    const SizedBox(
                        width:
                            10),
                    Text(
                      'กำลังซิงค์ข้อมูลคูปอง…',
                      style:
                          tBody,
                    ),
                  ],
                ),
              );
            }

            if (cSnap
                .hasError) {
              return _CreamCard(
                padding:
                    const EdgeInsets
                        .all(14),
                child: Text(
                  'โหลดข้อมูลคูปองไม่สำเร็จ: ${cSnap.error}',
                  style: tBody.copyWith(
                      color: Colors
                          .redAccent),
                ),
              );
            }

            final couponDocs =
                cSnap.data ??
                    [];

            final Map<
                String,
                Map<String,
                    dynamic>> byCode =
                {};
            for (final d
                in couponDocs) {
              final data =
                  d.data();
              final code =
                  (data['code'] ??
                          d.id)
                      .toString()
                      .toUpperCase();
              byCode[code] = {
                ...data,
                'code':
                    code,
              };
            }

            final claimedCouponsData =
                <Map<String,
                    dynamic>>[];
            for (final code
                in codes) {
              final c =
                  byCode[code];
              if (c ==
                  null) {
                continue;
              }
              if (c['active'] !=
                  true) {
                continue;
              }
              claimedCouponsData
                  .add(c);
            }

            if (claimedCouponsData
                .isEmpty) {
              return _CreamCard(
                padding:
                    const EdgeInsets
                        .all(14),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    headerRow,
                    const SizedBox(
                        height:
                            8),
                    Text(
                      'ยังไม่พบคูปองที่ใช้งานได้\nลองไปหน้า "คูปอง" เพื่อเลือกรับคูปองล่าสุด',
                      style:
                          tMuted,
                    ),
                  ],
                ),
              );
            }

            final now =
                DateTime
                    .now();
            final best =
                _pickBestCoupon(
              claimedCouponsData,
              subtotal,
              shippingFee,
              now,
            );

            final realHeaderRow =
                Row(
              children: [
                const LuxIcon(
                    child: Icon(
                        Icons
                            .discount_outlined,
                        color:
                            _ink),
                    size:
                        40),
                const SizedBox(
                    width:
                        10),
                Expanded(
                  child: Text(
                    'คูปองที่คุณรับไว้',
                    style:
                        tTitle,
                  ),
                ),
                LuxGhostButton(
                  icon: Icons
                      .list_alt_outlined,
                  label:
                      'ดูทั้งหมด',
                  onTap:
                      () async {
                    await _openClaimedVsAllCouponsSheet(
                        claimedCouponsData,
                        subtotal);
                  },
                ),
              ],
            );

            final quick =
                SingleChildScrollView(
              scrollDirection:
                  Axis.horizontal,
              child: Row(
                children:
                    claimedCouponsData
                        .map(
                            (c) {
                  final type = (c['type'] ??
                          '')
                      .toString();
                  final val = (c['value']
                          is num)
                      ? (c['value']
                              as num)
                          .toDouble()
                      : 0.0;
                  String chipTxt;
                  if (type.startsWith(
                      'shipping_')) {
                    chipTxt =
                        'ลดค่าส่ง';
                  } else {
                    chipTxt = type ==
                            'percent'
                        ? '${val.toStringAsFixed(0)}% OFF'
                        : '฿${_money.format(val)} OFF';
                  }

                  final bool
                      isSelected =
                      _selectedCoupon?[
                              'code'] ==
                          c['code'];

                  return Padding(
                    padding:
                        const EdgeInsets.only(
                            right:
                                8),
                    child:
                        LuxChip(
                      icon: isSelected
                          ? Icons
                              .check_circle
                          : Icons
                              .local_offer_outlined,
                      label:
                          '${c['code']} • $chipTxt',
                      isSelected:
                          isSelected,
                      onTap: () =>
                          setState(() => _selectedCoupon =
                              c),
                    ),
                  );
                }).toList(),
              ),
            );

            final applied =
                _selectedCoupon ==
                        null
                    ? const SizedBox
                        .shrink()
                    : Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          const SizedBox(
                              height:
                                  10),
                          _couponTicket(
                              _selectedCoupon!,
                              subtotal,
                              shippingFee),
                          Align(
                            alignment:
                                Alignment
                                    .centerRight,
                            child:
                                TextButton
                                    .icon(
                              onPressed:
                                  () {
                                setState(
                                    () =>
                                        _selectedCoupon =
                                            null);
                              },
                              icon: const Icon(
                                  Icons
                                      .close,
                                  color:
                                      _ink),
                              label:
                                  const Text(
                                'เอาคูปองออก',
                                style:
                                    TextStyle(
                                  color:
                                      _ink,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );

            return _CreamCard(
              padding:
                  const EdgeInsets
                      .all(14),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  realHeaderRow,
                  const SizedBox(
                      height:
                          10),
                  if (best !=
                          null &&
                      _selectedCoupon?[
                              'code'] !=
                          best['code'])
                    _bestRow(
                      best,
                      subtotal,
                      shippingFee,
                      now,
                      onTap: () =>
                          setState(() => _selectedCoupon =
                              best),
                    ),
                  quick,
                  applied,
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _couponTicket(
      Map<String, dynamic> c,
      double subtotal,
      double shippingFee) {
    final now =
        DateTime.now();
    final pDisc =
        _calcDiscountFor(
            c, subtotal, now);
    final sDisc =
        _calcShippingDiscountFor(
            c,
            subtotal,
            shippingFee,
            now);
    final disc = pDisc + sDisc;

    final type = (c['type'] ??
            '')
        .toString();
    final val =
        (c['value'] is num)
            ? (c['value']
                    as num)
                .toDouble()
            : 0.0;

    DateTime? exp;
    final ts =
        c['expiresAt'];
    if (ts is Timestamp) {
      exp = ts.toDate();
    } else if (ts
        is String) {
      try {
        exp = DateTime
            .parse(ts);
      } catch (_) {}
    }

    Widget typePill;
    if (type.startsWith(
        'shipping_')) {
      if (type ==
              'shipping_full' ||
          (type ==
                  'shipping_fixed' &&
              val >
                  1000) ||
          (type ==
                  'shipping_percent' &&
              val ==
                  100)) {
        typePill =
            _pillChip(
                'ส่งฟรี');
      } else if (type ==
          'shipping_fixed') {
        typePill =
            _pillChip(
                'ลดค่าส่ง ฿${_money.format(val)}');
      } else {
        typePill =
            _pillChip(
                'ลดค่าส่ง ${val.toStringAsFixed(0)}%');
      }
    } else {
      typePill = _pillChip(
          type == 'percent'
              ? '${val.toStringAsFixed(0)}% OFF'
              : '฿${_money.format(val)} OFF');
    }

    return Container(
      decoration:
          BoxDecoration(
        gradient:
            const LinearGradient(
          colors: [
            _cream1,
            _cream2
          ],
        ),
        borderRadius:
            BorderRadius.circular(
                18),
        border:
            Border.all(
                color:
                    _creamBorder),
        boxShadow: const [
          BoxShadow(
            blurRadius:
                10,
            color: Color(
                0x11000000),
          )
        ],
      ),
      padding:
          const EdgeInsets
              .all(14),
      child: Row(
        children: [
          const LuxIcon(
              child: Icon(
                  Icons
                      .confirmation_number_outlined,
                  color:
                      _ink),
              size: 44),
          const SizedBox(
              width:
                  12),
          Expanded(
            child:
                DefaultTextStyle(
              style:
                  tBody,
              child:
                  Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Row(
                    children: [
                      Text(
                        c['code'] ??
                            'COUPON',
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight
                                  .w800,
                          color:
                              _ink,
                        ),
                      ),
                      const SizedBox(
                          width:
                              6),
                      const LuxSparkle(
                          size:
                              14),
                    ],
                  ),
                  const SizedBox(
                      height:
                          4),
                  Wrap(
                    spacing:
                        6,
                    runSpacing:
                        -6,
                    children: [
                      typePill,
                      if (c['minSpend']
                              is num &&
                          (c['minSpend']
                                      as num)
                                  .toDouble() >
                              0)
                        _pillChip(
                            'ขั้นต่ำ ฿${_money.format((c['minSpend'] as num).toDouble())}'),
                      if (c['maxDiscount']
                              is num &&
                          (c['maxDiscount']
                                      as num)
                                  .toDouble() >
                              0)
                        _pillChip(
                            'ลดสูงสุด ฿${_money.format((c['maxDiscount'] as num).toDouble())}'),
                    ],
                  ),
                  if ((c['description'] ??
                              '')
                          .toString()
                          .isNotEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.only(
                              top:
                                  4),
                      child:
                          Text(
                        c['description'],
                        style:
                            tMuted,
                      ),
                    ),
                  if (exp !=
                      null)
                    Padding(
                      padding:
                          const EdgeInsets.only(
                              top:
                                  4),
                      child:
                          Text(
                        'หมดอายุ: ${exp.day}/${exp.month}/${exp.year}',
                        style:
                            tMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(
              width:
                  8),
          Column(
            mainAxisAlignment:
                MainAxisAlignment
                    .center,
            children: [
              Text(
                pDisc > 0
                    ? 'ส่วนลดสินค้า'
                    : (sDisc > 0
                        ? 'ส่วนลดค่าส่ง'
                        : 'ส่วนลด'),
                style:
                    TextStyle(
                  fontSize:
                      12,
                  color:
                      _muted,
                ),
              ),
              Text(
                '฿${_money.format(disc)}',
                style:
                    const TextStyle(
                  fontWeight:
                      FontWeight
                          .w900,
                  fontSize:
                      16,
                  color:
                      _ok,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _paymentGroup(
      double sub, double ship) {
    final codOption =
        _shippingOptions
            .firstWhere(
      (o) =>
          o['id'] ==
          'cod',
      orElse: () =>
          {'base_price': 50.0},
    );
    final codPrice =
        (codOption['base_price']
                as num)
            .toDouble();

    return _CreamCard(
      child: Column(
        children: [
          _prettyRadio<int>(
            title:
                'บัญชีธนาคาร / พร้อมเพย์',
            value:
                1,
            groupValue:
                _method,
            icon: Icons
                .account_balance_wallet_outlined,
            helper:
                'สแกน QR พร้อมเพย์ แล้วแนบสลิปเพื่อยืนยัน',
            onChanged:
                (int?
                    newValue) {
              final pos = _scroll
                  .position
                  .pixels;
              setState(() =>
                  _method =
                      newValue ??
                          1);
              WidgetsBinding
                  .instance
                  .addPostFrameCallback(
                      (_) {
                if (_scroll
                    .hasClients) {
                  _scroll.jumpTo(
                      pos);
                }
              });
            },
          ),
          const Divider(
            height:
                20,
            color:
                _creamBorder,
          ),
          _prettyRadio<int>(
            title:
                'เก็บเงินปลายทาง (COD)',
            value:
                2,
            groupValue:
                _method,
            icon: Icons
                .local_shipping_outlined,
            helper:
                'ชำระเมื่อสินค้าส่งถึงมือ (ค่าส่ง ฿${_money.format(codPrice)})',
            onChanged:
                (int?
                    newValue) {
              final pos = _scroll
                  .position
                  .pixels;
              setState(() =>
                  _method =
                      newValue ??
                          1);
              WidgetsBinding
                  .instance
                  .addPostFrameCallback(
                      (_) {
                if (_scroll
                    .hasClients) {
                  _scroll.jumpTo(
                      pos);
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _prettyRadio<T>({
    required String title,
    required T value,
    required T groupValue,
    required IconData icon,
    String? helper,
    required ValueChanged<T?>
        onChanged,
  }) {
    final selected =
        value == groupValue;
    return InkWell(
      borderRadius:
          BorderRadius.circular(
              12),
      onTap: () =>
          onChanged(value),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(
                vertical:
                    6,
                horizontal:
                    6),
        child: Column(
          children: [
            Row(
              children: [
                LuxIcon(
                    child: Icon(
                        icon,
                        color:
                            _ink),
                    size:
                        44),
                const SizedBox(
                    width:
                        12),
                Expanded(
                  child: Text(
                    title,
                    style: tBody.copyWith(
                        fontWeight:
                            FontWeight
                                .w700),
                  ),
                ),
                Radio<T>(
                  value:
                      value,
                  groupValue:
                      groupValue,
                  onChanged:
                      onChanged,
                  activeColor:
                      _ink,
                ),
                if (selected)
                  const Icon(
                    Icons
                        .check_circle,
                    color:
                        _ok,
                  ),
              ],
            ),
            if (helper !=
                null) ...[
              const SizedBox(
                  height:
                      6),
              Row(
                children: [
                  const Icon(
                    Icons
                        .info_outline,
                    size:
                        16,
                    color:
                        _muted,
                  ),
                  const SizedBox(
                      width:
                          6),
                  Expanded(
                    child: Text(
                      helper,
                      style:
                          tMuted,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _priceLine(
      String label,
      String value,
      {bool subtle = false,
      Color? color}) {
    final defaultColor =
        subtle
            ? _muted
            : _ink;
    return Padding(
      padding:
          const EdgeInsets.symmetric(
              vertical:
                  2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                height:
                    1.3,
                color:
                    color ??
                        defaultColor,
                fontWeight: subtle
                    ? FontWeight
                        .w500
                    : FontWeight
                        .w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              height:
                  1.3,
              color:
                  color ??
                      defaultColor,
              fontWeight: subtle
                  ? FontWeight
                      .w600
                  : FontWeight
                      .w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v,
          {bool bold = false}) =>
      Row(
        mainAxisAlignment:
            MainAxisAlignment
                .spaceBetween,
        children: [
          Text(
            k,
            style:
                TextStyle(
              color:
                  _muted,
              height:
                  1.3,
              fontWeight: bold
                  ? FontWeight
                      .w700
                  : FontWeight
                      .w500,
            ),
          ),
          Text(
            v,
            style:
                TextStyle(
              height:
                  1.3,
              fontWeight: bold
                  ? FontWeight
                      .w900
                  : FontWeight
                      .w700,
              color:
                  _ink,
            ),
          ),
        ],
      );

  Widget _textBox(
    TextEditingController c,
    String label,
    String errMsg, {
    int maxLines = 1,
    TextInputType? type,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: c,
      keyboardType: type,
      maxLines: maxLines,
      enabled: enabled,
      decoration:
          InputDecoration(
        labelText:
            label,
        labelStyle:
            tMuted,
        border:
            OutlineInputBorder(
          borderRadius:
              BorderRadius
                  .circular(
                      kRadius),
        ),
        enabledBorder:
            OutlineInputBorder(
          borderRadius:
              BorderRadius
                  .circular(
                      kRadius),
          borderSide:
              const BorderSide(
                  color:
                      _creamBorder),
        ),
        focusedBorder:
            OutlineInputBorder(
          borderRadius:
              BorderRadius
                  .circular(
                      kRadius),
          borderSide:
              const BorderSide(
            color:
                _ink,
            width:
                1.2,
          ),
        ),
        filled:
            true,
        fillColor:
            const Color(
                0xFFFFF7F3),
        contentPadding:
            const EdgeInsets
                .symmetric(
          horizontal:
              14,
          vertical:
              14,
        ),
      ),
      style:
          tBody,
      validator:
          (v) =>
              v == null ||
                      v.isEmpty
                  ? errMsg
                  : null,
    );
  }

  Widget _pillChip(String text) {
    return Container(
      padding:
          const EdgeInsets
              .symmetric(
        horizontal:
            8,
        vertical:
            6,
      ),
      decoration:
          BoxDecoration(
        color:
            _creamChip,
        borderRadius:
            BorderRadius
                .circular(
                    12),
        border:
            Border.all(
          color:
              _creamBorder,
        ),
      ),
      child: Text(
        text,
        style:
            const TextStyle(
          fontSize:
              12,
          fontWeight:
              FontWeight
                  .w700,
          color:
              _ink,
        ),
      ),
    );
  }
}

// ======= Generic cream card =======
class _CreamCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  const _CreamCard(
      {required this.child,
      this.padding,
      this.radius = 16});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:
          const EdgeInsets.symmetric(
              vertical: 8),
      decoration:
          BoxDecoration(
        borderRadius:
            BorderRadius.circular(
                radius),
        gradient:
            const LinearGradient(
          colors: [
            _cream1,
            _cream2
          ],
          begin:
              Alignment.topLeft,
          end: Alignment
              .bottomRight,
        ),
        border:
            Border.all(
          color:
              _creamBorder,
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius:
                18,
            offset:
                Offset(0, 10),
            color: Color(
                0x1A5D4037),
          )
        ],
      ),
      child: Padding(
        padding: padding ??
            const EdgeInsets
                .all(12),
        child: child,
      ),
    );
  }
}

// ======= Luxe widgets =======
class LuxIcon extends StatelessWidget {
  final Widget child;
  final double size;
  const LuxIcon(
      {super.key,
      required this.child,
      this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width:
          size,
      height:
          size,
      decoration:
          BoxDecoration(
        borderRadius:
            BorderRadius.circular(
                12),
        gradient:
            const LinearGradient(
          colors: [
            _gold1,
            _rose1
          ],
          begin:
              Alignment.topLeft,
          end: Alignment
              .bottomRight,
        ),
        border:
            Border.all(
          color:
              _creamBorder,
        ),
        boxShadow: const [
          BoxShadow(
            blurRadius:
                12,
            offset:
                Offset(0, 6),
            color: Color(
                0x22000000),
          )
        ],
      ),
      child:
          Stack(
        children: [
          Positioned.fill(
            child:
                Container(
              decoration:
                  BoxDecoration(
                borderRadius:
                    BorderRadius.circular(
                        12),
                color: Colors
                    .white
                    .withOpacity(
                        .32),
              ),
            ),
          ),
          Align(
            child:
                child,
          ),
          Positioned(
            top:
                2,
            left:
                2,
            right:
                2,
            child:
                Container(
              height:
                  size *
                      .22,
              decoration:
                  BoxDecoration(
                borderRadius:
                    const BorderRadius.vertical(
                        top:
                            Radius.circular(12)),
                gradient:
                    LinearGradient(
                  colors: [
                    Colors
                        .white
                        .withOpacity(
                            .75),
                    Colors
                        .white
                        .withOpacity(
                            0),
                  ],
                  begin:
                      Alignment.topCenter,
                  end: Alignment
                      .bottomCenter,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LuxChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isSelected;
  const LuxChip(
      {super.key,
      required this.icon,
      required this.label,
      this.onTap,
      this.isSelected =
          false});

  @override
  Widget build(BuildContext context) {
    final List<Color>
        gradient =
        isSelected
            ? [
                _gold3,
                _gold2
              ]
            : [
                _rose1,
                _gold1
              ];
    final Border
        border =
        isSelected
            ? Border.all(
                color: _ink.withOpacity(
                    0.5),
                width:
                    1.5,
              )
            : Border.all(
                color:
                    _creamBorder,
              );

    final chip =
        Container(
      padding:
          const EdgeInsets
              .symmetric(
        horizontal:
            12,
        vertical:
            10,
      ),
      decoration:
          BoxDecoration(
        borderRadius:
            BorderRadius.circular(
                30),
        gradient:
            LinearGradient(
          colors:
              gradient,
          begin:
              Alignment.topLeft,
          end: Alignment
              .bottomRight,
        ),
        border:
            border,
        boxShadow: const [
          BoxShadow(
            blurRadius:
                10,
            color: Color(
                0x15000000),
            offset:
                Offset(0, 6),
          )
        ],
      ),
      child:
          Row(
        mainAxisSize:
            MainAxisSize
                .min,
        children: [
          Icon(
            icon,
            size:
                18,
            color:
                _ink,
          ),
          const SizedBox(
              width:
                  8),
          Text(
            label,
            style:
                const TextStyle(
              color:
                  _ink,
              fontWeight:
                  FontWeight
                      .w700,
            ),
          ),
          if (!isSelected)
            ...[
              const SizedBox(
                  width:
                      6),
              const LuxSparkle(
                  size:
                      14),
            ],
        ],
      ),
    );

    return Material(
      color: Colors
          .transparent,
      child:
          InkWell(
        onTap:
            onTap,
        borderRadius:
            BorderRadius.circular(
                30),
        child:
            chip,
      ),
    );
  }
}

class LuxGhostButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  const LuxGhostButton(
      {super.key,
      this.icon,
      required this.label,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null
          ? 0.5
          : 1,
      child:
          InkWell(
        onTap:
            onTap,
        borderRadius:
            BorderRadius.circular(
                30),
        child:
            Container(
          padding:
              const EdgeInsets
                  .symmetric(
            horizontal:
                10,
            vertical:
                8,
          ),
          decoration:
              BoxDecoration(
            color: Colors
                .white
                .withOpacity(
                    .55),
            borderRadius:
                BorderRadius.circular(
                    30),
            border:
                Border.all(
              color:
                  _creamBorder,
            ),
          ),
          child:
              Row(
            children: [
              if (icon !=
                  null) ...[
                Icon(
                  icon,
                  size:
                      16,
                  color:
                      _ink,
                ),
                const SizedBox(
                    width:
                        6),
              ],
              Text(
                label,
                style:
                    const TextStyle(
                  color:
                      _ink,
                  fontWeight:
                      FontWeight
                          .w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LuxCTA extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  const LuxCTA(
      {super.key,
      required this.icon,
      required this.label,
      this.busy = false,
      this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap:
          busy ? null : onPressed,
      borderRadius:
          BorderRadius.circular(
              16),
      child:
          Container(
        height:
            48,
        decoration:
            BoxDecoration(
          borderRadius:
              BorderRadius.circular(
                  16),
          gradient:
              const LinearGradient(
            colors: [
              _gold2,
              _gold1
            ],
            begin:
                Alignment.topLeft,
            end: Alignment
                .bottomRight,
          ),
          boxShadow: const [
            BoxShadow(
              blurRadius:
                  18,
              offset:
                  Offset(0, 8),
              color: Color(
                  0x22000000),
            )
          ],
          border:
              Border.all(
            color:
                _creamBorder,
          ),
        ),
        child:
            Center(
          child:
              Row(
            mainAxisSize:
                MainAxisSize
                    .min,
            children: [
              if (busy)
                const SizedBox(
                  width:
                      20,
                  height:
                      20,
                  child:
                      CircularProgressIndicator(
                    strokeWidth:
                        2,
                    color:
                        _ink,
                  ),
                )
              else
                Icon(
                  icon,
                  color:
                      _ink,
                ),
              const SizedBox(
                  width:
                      8),
              Text(
                label,
                style:
                    const TextStyle(
                  color:
                      _ink,
                  fontWeight:
                      FontWeight
                          .w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LuxBadge extends StatelessWidget {
  final String text;
  const LuxBadge(
      {super.key,
      required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets
              .symmetric(
        horizontal:
            10,
        vertical:
            6,
      ),
      decoration:
          BoxDecoration(
        borderRadius:
            BorderRadius.circular(
                12),
        gradient:
            const LinearGradient(
          colors: [
            _gold1,
            _rose1
          ],
        ),
        border:
            Border.all(
          color:
              _creamBorder,
        ),
      ),
      child: Text(
        text,
        style:
            const TextStyle(
          fontWeight:
              FontWeight
                  .w800,
          color:
              _ink,
        ),
      ),
    );
  }
}

class LuxSparkle extends StatelessWidget {
  final double size;
  const LuxSparkle(
      {super.key,
      this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons
          .auto_awesome,
      size:
          size,
      color:
          _gold3,
    );
  }
}

class LuxRing extends StatelessWidget {
  final double size;
  const LuxRing(
      {super.key,
      required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width:
          size,
      height:
          size,
      decoration:
          const BoxDecoration(
        shape:
            BoxShape
                .circle,
        gradient:
            SweepGradient(
          colors: [
            _gold1,
            _gold2,
            _rose2,
            _rose1,
            _gold1
          ],
        ),
      ),
      child:
          Container(
        margin:
            const EdgeInsets
                .all(8),
        decoration:
            BoxDecoration(
          shape:
              BoxShape
                  .circle,
          color: Colors
              .white
              .withOpacity(
                  0.6),
          boxShadow: const [
            BoxShadow(
              blurRadius:
                  30,
              color: Color(
                  0x22FFB300),
            )
          ],
        ),
      ),
    );
  }
}
