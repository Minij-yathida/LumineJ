  import 'package:cloud_firestore/cloud_firestore.dart';
  import 'package:firebase_auth/firebase_auth.dart';

  class CouponsService {
    CouponsService._();
    static final instance = CouponsService._();

    final _fs = FirebaseFirestore.instance;
    final _auth = FirebaseAuth.instance;

    /// ดึงคูปองที่ active ทั้งหมด (หน้าโปรโมชัน)
    Stream<QuerySnapshot<Map<String, dynamic>>> activeCouponsStream() {
      return _fs
          .collection('coupons')
          .where('active', isEqualTo: true)
          .snapshots();
    }

    /// ลูกค้ากด "รับคูปอง" ด้วยโค้ด (เช่น กรอกโค้ดเอง)
    /// users/{uid}/claimedCoupons/{CODE}:
    /// {
    ///   code: "CODE",
    ///   coupon: { ...ข้อมูลจาก coupons doc ที่ code ตรงกัน... },
    ///   claimedAt: serverTimestamp,
    ///   redeemedAt: null
    /// }
    Future<void> claimCoupon(String code) async {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('กรุณาเข้าสู่ระบบก่อนรับคูปอง');
      }

      final trimmed = code.trim().toUpperCase();
      if (trimmed.isEmpty) {
        throw Exception('โค้ดคูปองไม่ถูกต้อง');
      }

      // รองรับทั้ง doc id สุ่ม + field code
      final qSnap = await _fs
          .collection('coupons')
          .where('code', isEqualTo: trimmed)
          .limit(1)
          .get();

      if (qSnap.docs.isEmpty) {
        throw Exception('ไม่พบคูปองนี้');
      }

      final cDoc = qSnap.docs.first;
      final c = cDoc.data();

      if (c['active'] != true) {
        throw Exception('คูปองนี้ไม่สามารถใช้งานได้แล้ว');
      }

      // (ถ้ามี expiresAt / usageLimit / usedCount จะเช็คเพิ่มได้ที่นี่)

      final claimRef = _fs
          .collection('users')
          .doc(user.uid)
          .collection('claimedCoupons')
          .doc(trimmed); // doc id = CODE (ตรงกับ rules)

      await claimRef.set({
        'code': trimmed,
        'coupon': {
          ...c,
          'code': trimmed,
        },
        'claimedAt': FieldValue.serverTimestamp(),
        'redeemedAt': null,
      }, SetOptions(merge: true));
    }

    /// Preview ส่วนลดจากคูปอง (ไม่แตะเงิน/สต๊อก แค่คำนวณ)
    Future<Map<String, dynamic>> previewCouponDiscount({
      required String code,
      required double subtotal,
    }) async {
      final user = _auth.currentUser;
      if (user == null) {
        return {'ok': false, 'reason': 'NOT_SIGNED_IN'};
      }

      final trimmed = code.trim().toUpperCase();
      if (trimmed.isEmpty) {
        return {'ok': false, 'reason': 'INVALID_CODE'};
      }

      // ต้องเคย "รับคูปอง" แล้วก่อน
      final claimRef = _fs
          .collection('users')
          .doc(user.uid)
          .collection('claimedCoupons')
          .doc(trimmed);
      final claimSnap = await claimRef.get();
      if (!claimSnap.exists) {
        return {'ok': false, 'reason': 'NOT_CLAIMED'};
      }
      final claim = claimSnap.data()!;
      if (claim['redeemedAt'] is Timestamp) {
        return {'ok': false, 'reason': 'ALREADY_USED'};
      }

      // โหลดคูปองหลัก (รองรับ doc id สุ่มด้วย field code)
      QuerySnapshot<Map<String, dynamic>> qSnap = await _fs
          .collection('coupons')
          .where('code', isEqualTo: trimmed)
          .limit(1)
          .get();

      Map<String, dynamic>? c;

      if (qSnap.docs.isNotEmpty) {
        c = qSnap.docs.first.data();
      } else {
        // fallback: เผื่อมีเคส doc id = code
        final direct = await _fs.collection('coupons').doc(trimmed).get();
        if (direct.exists) {
          c = direct.data();
        }
      }

      if (c == null) {
        return {'ok': false, 'reason': 'NOT_FOUND'};
      }

      if (c['active'] != true) {
        return {'ok': false, 'reason': 'INACTIVE'};
      }

      // หมดอายุ
      final expires = c['expiresAt'];
      if (expires != null && expires is Timestamp) {
        if (DateTime.now().isAfter(expires.toDate())) {
          return {'ok': false, 'reason': 'EXPIRED'};
        }
      }

      // ขั้นต่ำ
      final minSpend =
          (c['minSpend'] is num) ? (c['minSpend'] as num).toDouble() : 0.0;
      if (minSpend > 0 && subtotal < minSpend) {
        return {'ok': false, 'reason': 'MIN_SPEND'};
      }

      // จำนวนสิทธิ์ทั้งหมด
      final int usageLimit =
          (c['usageLimit'] is num) ? (c['usageLimit'] as num).toInt() : 0;
      final int usedCount =
          (c['usedCount'] is num) ? (c['usedCount'] as num).toInt() : 0;
      if (usageLimit != 0 && usedCount >= usageLimit) {
        return {'ok': false, 'reason': 'LIMIT_REACHED'};
      }

      // คำนวณส่วนลด (เฉพาะ type ที่ไม่ยุ่งค่าส่ง ตามเงื่อนไขตอนนี้)
      final type = (c['type'] ?? '').toString();
      final double value =
          (c['value'] is num) ? (c['value'] as num).toDouble() : 0.0;

      double discount = 0.0;

      if (type == 'percent') {
        discount = subtotal * (value / 100.0);
        if (c['maxDiscount'] is num) {
          final cap = (c['maxDiscount'] as num).toDouble();
          if (discount > cap) discount = cap;
        }
      } else if (type == 'fixed') {
        discount = value;
      } else {
        // type อื่น (เช่น shipping_*) ให้ backend/checkout handle
        return {'ok': false, 'reason': 'UNSUPPORTED_TYPE'};
      }

      if (discount <= 0) {
        return {'ok': false, 'reason': 'NO_DISCOUNT'};
      }
      if (discount > subtotal) {
        discount = subtotal;
      }

      return {
        'ok': true,
        'discount': double.parse(discount.toStringAsFixed(2)),
      };
    }
  }
