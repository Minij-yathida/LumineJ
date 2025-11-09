// lib/services/payment_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;


class PaymentService {
  PaymentService._();
  static final instance = PaymentService._();

  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// alias เดิมให้ checkout_page ใช้
  Future<String> createOrderViaFunctions({
    required List<Map<String, dynamic>> items,
    String? couponCode,
    required Map<String, dynamic> customer,
    required Map<String, dynamic> pricing, // {subtotal, shippingFee, grandTotal}
    required Map<String, dynamic> payment, // {method, slipUrl}
  }) async {
    final shippingFee = _safeDouble(pricing['shippingFee']);
    return createOrder(
      items: items,
      couponCode: couponCode,
      customer: customer,
      shippingFee: shippingFee,
      payment: payment,
    );
  }

  /// ✅ สร้างคำสั่งซื้อ + ตัดสต๊อก + ใช้คูปอง + ยิงแจ้งเตือนลูกค้า/แอดมิน
  Future<String> createOrder({
    required List<Map<String, dynamic>> items,
    String? couponCode,
    required Map<String, dynamic> customer,
    required double shippingFee,
    required Map<String, dynamic> payment,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('กรุณาเข้าสู่ระบบก่อนทำรายการ');
    if (items.isEmpty) throw Exception('ไม่มีสินค้าในคำสั่งซื้อ');

    if (kDebugMode) {
      print('=== createOrder debug ===');
      print('currentUser.uid: ${user.uid}');
      print('items.length: ${items.length}');
      if (items.isNotEmpty) print('items[0]: ${items[0]}');
      print('shippingFee: $shippingFee');
      print('payment: $payment');
      print('payment.slipUrl(raw): ${payment['slipUrl'] ?? ''}');
      print('customer: $customer');
    }

    final rawCode = (couponCode ?? '').trim().toUpperCase();
    final hasCoupon = rawCode.isNotEmpty;

    // หา couponRef (นอก transaction)
    DocumentReference<Map<String, dynamic>>? couponDocRef;
    if (hasCoupon) {
      final directRef = _fs.collection('coupons').doc(rawCode);
      final directSnap = await directRef.get();
      if (directSnap.exists) {
        couponDocRef = directRef;
      } else {
        final q = await _fs
            .collection('coupons')
            .where('code', isEqualTo: rawCode)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          couponDocRef = q.docs.first.reference;
        } else {
          throw Exception('ไม่พบคูปองนี้ในระบบ');
        }
      }
    }

    final orderRef = _fs.collection('orders').doc();

    try {
      // ======================== TRANSACTION ========================
      final txResult =
          await _fs.runTransaction<Map<String, dynamic>>((tx) async {
        double subtotal = 0;
        final List<Map<String, dynamic>> finalizedItems = [];

        final Map<
            DocumentReference<Map<String, dynamic>>,
            Map<String, dynamic>> productUpdates = {};

        DocumentReference<Map<String, dynamic>>? claimRef;
        Map<String, dynamic>? claimUpdate;
        Map<String, dynamic>? couponUpdate;

        // ---------- 1) โหลด + เช็คสต๊อกสินค้า ----------
        for (final it in items) {
          final String pid = (it['productId'] ?? '').toString();
          final int qty =
              (it['qty'] is num) ? (it['qty'] as num).toInt() : 0;

          if (pid.isEmpty || qty <= 0) {
            throw Exception('ข้อมูลสินค้าไม่ถูกต้อง');
          }

          final pRef = _fs.collection('products').doc(pid);
          final pSnap = await tx.get(pRef);
          if (!pSnap.exists) {
            throw Exception('มีสินค้าบางรายการไม่พบในระบบ');
          }

          final p = (pSnap.data() ?? {}) as Map<String, dynamic>;
          final double price =
              _safeDouble(p['price'] ?? p['basePrice'] ?? 0);

          subtotal += price * qty;

          final variant = (it['variant'] as Map?) ?? {};
          final size = (variant['size'] ?? '').toString();

          final updates = <String, dynamic>{};

          // ใช้ key size (stock_map) ถ้ามี
          if (size.isNotEmpty &&
              p['stock_map'] is Map &&
              (p['stock_map'] as Map).containsKey(size)) {
            final stockMap =
                Map<String, dynamic>.from(p['stock_map'] as Map);
            final rawStock = stockMap[size];
            int current = rawStock is num
                ? rawStock.toInt()
                : int.tryParse('$rawStock') ?? 0;

            if (current < qty) {
              throw Exception('สินค้าบางรายการสต๊อกไม่พอ');
            }

            stockMap[size] = current - qty;
            updates['stock_map'] = stockMap;
          } else {
            final rawStock = p['stock'];
            int current = rawStock is num
                ? rawStock.toInt()
                : int.tryParse('$rawStock') ?? 0;

            if (current < qty) {
              throw Exception('สินค้าบางรายการสต๊อกไม่พอ');
            }

            updates['stock'] = current - qty;
          }

          if (updates.isNotEmpty) {
            final merged = productUpdates[pRef] ?? <String, dynamic>{};
            merged.addAll(updates);
            productUpdates[pRef] = merged;
          }

          finalizedItems.add({
            'productId': pid,
            'name': p['name'] ?? '',
            'price': price,
            'qty': qty,
            'variant': {'size': size},
            'image': (p['images'] is List &&
                    (p['images'] as List).isNotEmpty)
                ? (p['images'] as List).first
                : null,
          });
        }

        // ---------- 2) ตรวจและใช้คูปอง ----------
        double productDiscount = 0;
        String? appliedCode;

        if (hasCoupon) {
          final code = rawCode;

          claimRef = _fs
              .collection('users')
              .doc(user.uid)
              .collection('claimedCoupons')
              .doc(code);

          final claimSnap = await tx.get(claimRef!);
          if (!claimSnap.exists) {
            throw Exception('กรุณากดรับคูปองก่อนใช้งานโค้ดนี้');
          }
          final claim =
              (claimSnap.data() ?? {}) as Map<String, dynamic>;
          if (claim['redeemedAt'] != null) {
            throw Exception('คุณใช้คูปองนี้ไปแล้ว');
          }

          if (couponDocRef == null) {
            throw Exception('ไม่พบคูปองนี้ในระบบ');
          }
          final couponSnap = await tx.get(couponDocRef!);
          if (!couponSnap.exists) {
            throw Exception('ไม่พบคูปองนี้ในระบบ');
          }
          final c =
              (couponSnap.data() ?? {}) as Map<String, dynamic>;

          if (c['active'] != true) {
            throw Exception('คูปองนี้ไม่สามารถใช้งานได้แล้ว');
          }

          // หมดอายุ
          final expires = c['expiresAt'];
          if (expires != null) {
            DateTime? exp;
            if (expires is Timestamp) {
              exp = expires.toDate();
            } else if (expires is String) {
              try {
                exp = DateTime.parse(expires);
              } catch (_) {}
            }
            if (exp != null && exp.isBefore(DateTime.now())) {
              throw Exception('คูปองนี้หมดอายุแล้ว');
            }
          }

          final minSpend = _safeDouble(c['minSpend']);
          if (minSpend > 0 && subtotal < minSpend) {
            throw Exception('ยอดสั่งซื้อยังไม่ถึงขั้นต่ำของคูปองนี้');
          }

          final int usageLimit = (c['usageLimit'] is num)
              ? (c['usageLimit'] as num).toInt()
              : 0;
          final int usedCountOld = (c['usedCount'] is num)
              ? (c['usedCount'] as num).toInt()
              : 0;
          if (usageLimit > 0 && usedCountOld >= usageLimit) {
            throw Exception('คูปองนี้ถูกใช้ครบจำนวนสิทธิ์แล้ว');
          }

          final type = (c['type'] ?? '').toString();
          final double val = _safeDouble(c['value']);
          double discount = 0;

          if (type == 'percent') {
            discount = subtotal * (val / 100.0);
            final maxDiscount = _safeDouble(c['maxDiscount']);
            if (maxDiscount > 0 && discount > maxDiscount) {
              discount = maxDiscount;
            }
          } else if (type == 'fixed') {
            discount = val;
          }

          if (discount <= 0) throw Exception('คูปองนี้ไม่สามารถใช้ได้');
          if (discount > subtotal) discount = subtotal;

          productDiscount = _round2(discount);
          appliedCode = code;

          claimUpdate = {
            'redeemedAt': FieldValue.serverTimestamp(),
            'usedInOrderId': orderRef.id,
          };
          couponUpdate = {'usedCount': usedCountOld + 1};
        }

        // ---------- 3) ยอดรวม ----------
        final grandTotal =
            _round2((subtotal - productDiscount) + shippingFee);

        // ---------- 4) payment ----------

            // ⬇️ เพิ่มตรงนี้ครับ (ก่อน final method) ⬇️
            if (payment['method'] == 'transfer_qr' &&
                payment['slipUrl'] != null &&
                payment['slipUrl'].toString().isNotEmpty &&
                !payment['slipUrl'].toString().startsWith('http')) {
              try {
                final uri = Uri.parse(
                    'https://api.imgbb.com/1/upload?key=8a39c27c6438758e019195ce315004fa');
                final req = http.MultipartRequest('POST', uri)
                  ..files.add(await http.MultipartFile.fromPath(
                      'image', payment['slipUrl'].toString()));
                final res = await req.send();
                final body = await res.stream.bytesToString();
                final data = jsonDecode(body);

                if (data['data'] != null && data['data']['display_url'] != null) {
                  payment['slipUrl'] = data['data']['display_url'];
                  if (kDebugMode) {
                    print('✅ อัปโหลด slip ขึ้น ImgBB สำเร็จ: ${payment['slipUrl']}');
                  }
                } else {
                  if (kDebugMode) print('⚠️ upload slip ไม่สำเร็จ');
                }
              } catch (e) {
                if (kDebugMode) print('❌ upload slip error: $e');
              }
            }
        final method =
            (payment['method'] == 'cod') ? 'cod' : 'transfer_qr';
        String slipUrl = '';
        if (method == 'transfer_qr') {
          final rawSlip = (payment['slipUrl'] ?? '').toString();
          if (rawSlip.startsWith('http') &&
              (rawSlip.contains('ibb.co') ||
                  rawSlip.contains('imgbb.com'))) {
            slipUrl = rawSlip;
          }
        }

        // ---------- 5) สร้างคำสั่งซื้อ ----------
        final orderData = <String, dynamic>{
          'userId': user.uid,
          'items': finalizedItems,
          'couponCode': appliedCode,
          'customer': customer,
          'shippingFee': _round2(shippingFee),
          'payment': {
            'method': method,
            'slipUrl': slipUrl,
            'status': method == 'cod'
                ? 'cod_pending'
                : 'proof_submitted',
          },
          'status':
              method == 'cod' ? 'pending_cod' : 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'source': 'client',
          'pricing': {
            'subtotal': _round2(subtotal),
            'discount': _round2(productDiscount),
            'grandTotal': grandTotal,
          },
          'shipping': {
            'optionId':
                method == 'cod' ? 'cod' : 'standard',
            'optionName': method == 'cod'
                ? 'Cash on Delivery (เก็บปลายทาง)'
                : 'Standard Delivery',
          },
          'stockDeducted': true,
        };

        // commit updates
        productUpdates.forEach((ref, data) => tx.update(ref, data));
        if (hasCoupon) {
          if (claimRef != null && claimUpdate != null) {
            tx.update(claimRef!, claimUpdate!);
          }
          if (couponDocRef != null && couponUpdate != null) {
            tx.update(couponDocRef!, couponUpdate!);
          }
        }
        tx.set(orderRef, orderData);

        // ส่งข้อมูลจำเป็นไว้ใช้ยิง notification ข้างนอก
        return {
          'orderId': orderRef.id,
          'grandTotal': grandTotal,
          'customerName':
              (customer['name'] ?? '').toString(),
        };
      });

      final orderId =
          (txResult['orderId'] as String?) ?? '';
      final grandTotal =
          _safeDouble(txResult['grandTotal']);
      final customerName =
          (txResult['customerName'] as String?) ?? '';

      if (orderId.isEmpty) {
        throw Exception('ไม่สามารถสร้างคำสั่งซื้อได้');
      }

      // ---------- แจ้งเตือนลูกค้า ----------
      try {
        final uid = _auth.currentUser?.uid;
        if (uid != null) {
          await _fs
              .collection('users')
              .doc(uid)
              .collection('alerts')
              .add({
            'title': 'ขอบคุณสำหรับการสั่งซื้อ 💕',
            'body':
                'เราได้รับคำสั่งซื้อของคุณเรียบร้อยแล้ว\nหมายเลขคำสั่งซื้อ: $orderId\nทีมงานกำลังตรวจสอบและจัดส่งให้โดยเร็วค่ะ',
            'orderId': orderId,
            'type': 'order',
            'status': 'unread',
            'read': false,
            'source': 'client', 
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (e) {
        if (kDebugMode) print('alert error: $e');
      }

      // ---------- แจ้งเตือนแอดมิน (ใช้กับ NotificationsPage isAdmin) ----------
      try {
        await _fs.collection('notifications_admin').add({
          'orderId': orderId,
          'userId': user.uid,
          'customerName': customerName,
          'total': grandTotal,
          'title': '🛍️ มีคำสั่งซื้อใหม่เข้ามาแล้ว',
          'body': customerName.isNotEmpty
              ? 'ลูกค้า $customerName ได้ทำการสั่งซื้อใหม่ หมายเลขคำสั่งซื้อ: $orderId'
              : 'มีคำสั่งซื้อใหม่ หมายเลขคำสั่งซื้อ: $orderId',
          'type': 'new_order',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        if (kDebugMode) print('admin notification error: $e');
      }

      return orderId;
    } catch (e) {
      if (kDebugMode) print('createOrder error: $e');
      throw Exception(
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  // ---------- คืนสต๊อก (ใช้ตอนยกเลิกคำสั่งซื้อได้) ----------
  Future<void> _restockItemsInTx(
      Transaction tx, Map<String, dynamic> orderData) async {
    final items = (orderData['items'] as List?) ?? const [];
    for (final raw in items) {
      if (raw is! Map) continue;
      final it = Map<String, dynamic>.from(raw);
      final String pid = (it['productId'] ?? '').toString();
      final int qty =
          (it['qty'] is num) ? (it['qty'] as num).toInt() : 0;
      if (pid.isEmpty || qty <= 0) continue;

      final variant = (it['variant'] as Map?) ?? {};
      final size = (variant['size'] ?? '').toString();

      final pRef = _fs.collection('products').doc(pid);
      final pSnap = await tx.get(pRef);
      if (!pSnap.exists) continue;

      final p = (pSnap.data() ?? {}) as Map<String, dynamic>;
      final updates = <String, dynamic>{};

      if (size.isNotEmpty &&
          p['stock_map'] is Map &&
          (p['stock_map'] as Map).containsKey(size)) {
        final stockMap =
            Map<String, dynamic>.from(p['stock_map'] as Map);
        final rawStock = stockMap[size];
        int current = rawStock is num
            ? rawStock.toInt()
            : int.tryParse('$rawStock') ?? 0;
        stockMap[size] = current + qty;
        updates['stock_map'] = stockMap;
      } else {
        final rawStock = p['stock'];
        int current = rawStock is num
            ? rawStock.toInt()
            : int.tryParse('$rawStock') ?? 0;
        updates['stock'] = current + qty;
      }

      tx.update(pRef, updates);
    }
  }

  // ---------- Utils ----------
  double _safeDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0.0;
  }

  double _round2(num v) => (v * 100).roundToDouble() / 100.0;
}