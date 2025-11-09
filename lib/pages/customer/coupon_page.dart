import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CouponsPage extends StatelessWidget {
  /// ถ้า popOnClaim = true:
  /// - เมื่อกด "รับคูปอง" แล้วสำเร็จ จะ pop(couponMap) กลับไปหน้าเดิม (ใช้ใน Checkout)
  const CouponsPage({
    super.key,
    this.popOnClaim = false,
    this.subtotalForCalc,
  });

  final bool popOnClaim;
  final double? subtotalForCalc;

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;
    final user = FirebaseAuth.instance.currentUser;
    final money = NumberFormat('#,##0', 'th_TH');
    final expiryFormatter = DateFormat('dd/MM/yyyy', 'th_TH');

    // ดูว่า user เคยรับ code ไหนแล้วบ้าง
    final Stream<List<String>> claimedCodesStream = user == null
        ? Stream.value(<String>[])
        : fs
            .collection('users')
            .doc(user.uid)
            .collection('claimedCoupons')
            .snapshots()
            .map(
              (s) => s.docs
                  .map((d) {
                    final data = d.data();
                    // รองรับทั้งโครงเก่าและใหม่
                    final code = (data['code'] ??
                                (data['coupon']?['code']) ??
                                d.id)
                            .toString()
                            .toUpperCase();
                    return code;
                  })
                  .where((c) => c.isNotEmpty)
                  .toList()
                  .cast<String>(),
            );

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F5),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              color: const Color(0xFFFBEAE0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: const Row(
                children: [
                  Icon(Icons.local_offer, color: Color(0xFF6D4C41)),
                  SizedBox(width: 8),
                  Text(
                    'Coupons & Promotions',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6D4C41),
                    ),
                  ),
                ],
              ),
            ),

            // Info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEFE4DC)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x11000000),
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Text(
                  'เลือกคูปองที่ต้องการเพื่อ "รับ" และเก็บไว้ในกระเป๋าคูปองของคุณ',
                  style: TextStyle(fontSize: 13, color: Color(0xFF6D4C41)),
                ),
              ),
            ),

            // List coupons
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: fs
                    .collection('coupons')
                    .where('active', isEqualTo: true)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Text('เกิดข้อผิดพลาด: ${snap.error}'),
                    );
                  }

                  var docs = snap.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return const Center(child: Text('ยังไม่มีคูปองในขณะนี้'));
                  }

                  // sort ตาม code (ถ้าไม่มี code จะตาม id)
                  docs.sort((a, b) {
                    final ca = (a.data()['code'] ?? a.id).toString();
                    final cb = (b.data()['code'] ?? b.id).toString();
                    return ca.compareTo(cb);
                  });

                  return StreamBuilder<List<String>>(
                    stream: claimedCodesStream,
                    builder: (context, claimedSnap) {
                      final claimed = (claimedSnap.data ?? <String>[])
                          .map((s) => s.toUpperCase())
                          .toSet();

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemCount: docs.length,
                        itemBuilder: (context, i) {
                          final doc = docs[i];
                          final data = doc.data();

                          // ใช้ field code ถ้ามี, ถ้าไม่มี fallback เป็น doc.id
                          final rawCode = (data['code'] ?? doc.id)
                              .toString()
                              .trim()
                              .toUpperCase();
                          if (rawCode.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          final type = (data['type'] ?? '').toString();
                          final value = (data['value'] is num)
                              ? (data['value'] as num).toDouble()
                              : 0.0;
                          final usageLimit =
                              (data['usageLimit'] is num)
                                  ? (data['usageLimit'] as num).toInt()
                                  : 0;
                          final usedCount =
                              (data['usedCount'] is num)
                                  ? (data['usedCount'] as num).toInt()
                                  : 0;
                          final expiresAt = data['expiresAt'] as Timestamp?;
                          final description =
                              (data['description'] ?? '').toString();

                          final now = DateTime.now();

                          // หมดอายุ / เต็มสิทธิ์ → ไม่แสดง
                          final isExpired = expiresAt != null &&
                              expiresAt.toDate().isBefore(now);
                          final isExhausted = usageLimit > 0 &&
                              usedCount >= usageLimit;
                          if (isExpired || isExhausted) {
                            return const SizedBox.shrink();
                          }

                          final alreadyClaimed = claimed.contains(rawCode);

                          // label ส่วนลด
                          String discountText = '';
                          if (type == 'percent') {
                            discountText =
                                '${value.toStringAsFixed(0)}% OFF';
                          } else if (type == 'fixed') {
                            discountText =
                                '฿${money.format(value)} OFF';
                          } else if (type.startsWith('shipping_')) {
                            if (type == 'shipping_full') {
                              discountText = 'ส่งฟรี';
                            } else if (type == 'shipping_fixed') {
                              discountText =
                                  'ลดค่าส่ง ฿${money.format(value)}';
                            } else if (type == 'shipping_percent') {
                              discountText =
                                  'ลดค่าส่ง ${value.toStringAsFixed(0)}%';
                            }
                          }

                          final descText = description.isEmpty
                              ? '(ไม่มีคำอธิบาย)'
                              : description;
                          final expiryText = expiresAt != null
                              ? 'หมดอายุ ${expiryFormatter.format(expiresAt.toDate())}'
                              : 'ไม่มีวันหมดอายุ';

                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x22000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 3),
                                )
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.local_offer_rounded,
                                        color: Color(0xFF6D4C41),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              rawCode,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF3E2723),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              descText,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54,
                                                height: 1.3,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                const Icon(
                                                  Icons.access_time,
                                                  size: 14,
                                                  color: Colors.grey,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  expiryText,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.black54,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (discountText.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFF3E6),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                              color:
                                                  const Color(0xFFFAE7D3),
                                            ),
                                          ),
                                          child: Text(
                                            discountText,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF6D4C41),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),

                                  // ปุ่มรับคูปอง
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: alreadyClaimed
                                          ? null
                                          : () async {
                                              final u = FirebaseAuth
                                                  .instance
                                                  .currentUser;
                                              if (u == null) {
                                                await showDialog<void>(
                                                  context: context,
                                                  builder: (ctx) =>
                                                      AlertDialog(
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              18),
                                                    ),
                                                    title: const Text(
                                                      'ต้องเข้าสู่ระบบ',
                                                      style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold),
                                                    ),
                                                    content: const Text(
                                                      'กรุณาเข้าสู่ระบบก่อนรับคูปองนะคะ',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.of(
                                                                    ctx)
                                                                .pop(),
                                                        child: const Text(
                                                            'ปิด'),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                return;
                                              }

                                              // doc id = CODE (ตรงกับ rules)
                                              final claimRef = fs
                                                  .collection('users')
                                                  .doc(u.uid)
                                                  .collection(
                                                      'claimedCoupons')
                                                  .doc(rawCode);

                                              await claimRef.set({
                                                'code': rawCode,
                                                'coupon': {
                                                  ...data,
                                                  'code': rawCode,
                                                },
                                                'claimedAt':
                                                    FieldValue.serverTimestamp(),
                                                'redeemedAt': null,
                                              }, SetOptions(merge: true));

                                              final selected =
                                                  <String, dynamic>{
                                                ...data,
                                                'code': rawCode,
                                              };

                                              // ถ้าเปิดจาก Checkout ให้ส่งคูปองกลับเลย
                                              if (popOnClaim &&
                                                  Navigator.of(context)
                                                      .canPop()) {
                                                Navigator.of(context)
                                                    .pop(selected);
                                                return;
                                              }

                                              // ป๊อปอัปสวย ๆ
                                              await showDialog<void>(
                                                context: context,
                                                barrierDismissible: true,
                                                builder: (ctx) {
                                                  return Dialog(
                                                    shape:
                                                        RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              20),
                                                    ),
                                                    backgroundColor:
                                                        Colors.white,
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              20),
                                                      child: Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Container(
                                                            width: 56,
                                                            height: 56,
                                                            decoration:
                                                                const BoxDecoration(
                                                              shape: BoxShape
                                                                  .circle,
                                                              color: Color(
                                                                  0xFFFFF3E6),
                                                            ),
                                                            child: const Icon(
                                                              Icons
                                                                  .card_giftcard,
                                                              color: Color(
                                                                  0xFF6D4C41),
                                                              size: 30,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              height: 14),
                                                          const Text(
                                                            'เก็บคูปองเรียบร้อยแล้ว',
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              color: Color(
                                                                  0xFF3E2723),
                                                            ),
                                                            textAlign: TextAlign
                                                                .center,
                                                          ),
                                                          const SizedBox(
                                                              height: 6),
                                                          Text(
                                                            rawCode,
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  FontWeight.w700,
                                                              color: Color(
                                                                  0xFF6D4C41),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              height: 12),
                                                          const Text(
                                                            'คุณสามารถใช้คูปองนี้ได้แล้ว ช๊อปเลย!',
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              color: Colors
                                                                  .black54,
                                                            ),
                                                            textAlign: TextAlign
                                                                .center,
                                                          ),
                                                          const SizedBox(
                                                              height: 18),
                                                          SizedBox(
                                                            width:
                                                                double.infinity,
                                                            child:
                                                                ElevatedButton(
                                                              onPressed: () {
                                                                Navigator.of(
                                                                        ctx)
                                                                    .pop();
                                                              },
                                                              style:
                                                                  ElevatedButton
                                                                      .styleFrom(
                                                                backgroundColor:
                                                                    const Color(
                                                                        0xFF6D4C41),
                                                                foregroundColor:
                                                                    Colors
                                                                        .white,
                                                                shape:
                                                                    RoundedRectangleBorder(
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              12),
                                                                ),
                                                                padding:
                                                                    const EdgeInsets
                                                                            .symmetric(
                                                                        vertical:
                                                                            12),
                                                              ),
                                                              child:
                                                                  const Text(
                                                                'ปิด',
                                                                style:
                                                                    TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  );
                                                },
                                              );
                                            },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: alreadyClaimed
                                            ? Colors.grey[300]
                                            : const Color(0xFF6D4C41),
                                        foregroundColor: alreadyClaimed
                                            ? Colors.grey[600]
                                            : Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
                                      icon: Icon(
                                        alreadyClaimed
                                            ? Icons
                                                .check_circle_outline
                                            : Icons.card_giftcard,
                                        size: 18,
                                      ),
                                      label: Text(
                                        alreadyClaimed
                                            ? 'เก็บคูปองแล้ว'
                                            : 'รับคูปอง',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
