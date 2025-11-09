// lib/pages/customer/order_tracking_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class OrderTrackingPage extends StatelessWidget {
  const OrderTrackingPage({super.key});

  // Theme
  Color get _primary => const Color(0xFF6D4C41); // น้ำตาลโกโก้
  Color get _accent => const Color(0xFFE0BFA5); // โรสโกลด์
  Color get _bgSoft => const Color(0xFFF9F4F1);

  // ==========================
  // แถวรายละเอียดใน Modal
  // ==========================
  Widget _buildDetailRow(
    String label,
    String value, {
    bool isTotal = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 13.5,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
                fontSize: isTotal ? 16 : 13.5,
                color: valueColor ??
                    (isTotal ? const Color(0xFFBF360C) : Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================
  // Icon / รูปสินค้า
  // ==========================
  Widget _buildProductIcon(String? imageUrl) {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.network(
          imageUrl,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackIcon(),
        ),
      );
    }
    return _fallbackIcon();
  }

  Widget _fallbackIcon() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          colors: [Colors.brown.shade200, Colors.brown.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(
        Icons.shopping_bag_outlined,
        color: Colors.brown.shade700,
        size: 26,
      ),
    );
  }

  // ==========================
  // รายการสินค้าใน Modal
  // ==========================
  Widget _buildModalProductItem({
    required Map<String, dynamic> item,
    required NumberFormat moneyFormatter,
  }) {
    final qty = (item['qty'] ?? item['quantity'] ?? 1) as num;
    final rawPrice = (item['price'] ?? item['unitPrice'] ?? 0) as num;
    final price = rawPrice.toDouble();
    final size =
        (item['size'] ?? item['variant']?['size'] ?? 'Freesize').toString();
    final imgUrl = (item['image'] ?? item['imageUrl'])?.toString();
    final name =
        (item['name'] ?? item['title'] ?? 'สินค้าไม่ระบุ').toString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProductIcon(imgUrl),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'ขนาด: $size',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${moneyFormatter.format(price)} x $qty',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                        color: Colors.brown,
                      ),
                    ),
                    Text(
                      'รวม ${moneyFormatter.format(price * qty)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================
  // Map status -> UI
  // ==========================
  ({String label, Color color, IconData icon}) _statusMeta(String raw) {
  switch (raw) {
    case 'pending':
    case 'unpaid':
    case 'paid':
      // รอการดำเนินการ / เตรียมส่ง
      return (
        label: 'กำลังดำเนินการ',
        color: Colors.orangeAccent,
        icon: Icons.local_shipping_outlined, // รูปรถ
      );
    case 'shipped':
      // ส่งแล้ว รอลูกค้า
      return (
        label: 'จัดส่งแล้ว',
        color: Colors.blueAccent,
        icon: Icons.inventory_2_rounded, // กล่องพัสดุ
      );
    case 'completed':
    case 'received':
      // ส่งถึงแล้ว
      return (
        label: 'ได้รับสินค้าแล้ว',
        color: Colors.green,
        icon: Icons.verified_rounded, // ติ๊กถูก
      );
    case 'cancelled':
      // ยกเลิก
      return (
        label: 'ยกเลิกแล้ว',
        color: Colors.redAccent,
        icon: Icons.cancel_rounded,
      );
    default:
      return (
        label: 'รอดำเนินการ',
        color: Colors.orangeAccent,
        icon: Icons.more_horiz_rounded,
      );
  }
}

  // ==========================
  // Logic สิทธิ์ปุ่ม (ตาม Rules)
  // ==========================

  bool _canCancelTopStatus(String topStatus) {
    return topStatus == 'pending' ||
        topStatus == 'unpaid' ||
        topStatus == 'paid';
  }

  bool _canMarkReceivedTopStatus(String topStatus) {
    return topStatus == 'shipped';
  }

  // ==========================
  // Popup แจ้งผล
  // ==========================
  Future<void> _showResultDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }

    // ==========================
  // Dialog ยกเลิกคำสั่งซื้อ (อัปเดต orders ตรงๆ)
  // ==========================
  Future<void> _showCancelOrderDialog(
    BuildContext context, {
    required String orderId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showResultDialog(
        context,
        title: 'ไม่ได้เข้าสู่ระบบ',
        message: 'กรุณาเข้าสู่ระบบก่อนทำรายการยกเลิกคำสั่งซื้อ',
      );
      return;
    }

    final TextEditingController reasonCtrl = TextEditingController();
    final fs = FirebaseFirestore.instance;

    await showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'ยกเลิกคำสั่งซื้อ',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'โปรดระบุเหตุผลในการยกเลิก\nเพื่อให้ร้านตรวจสอบและบันทึกข้อมูล',
                style: TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'เช่น เปลี่ยนใจ / สั่งผิด / ใส่ที่อยู่ผิด ฯลฯ',
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.brown.shade200,
                      width: 0.7,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'ปิด',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () async {
                final reason = reasonCtrl.text.trim();
                if (reason.isEmpty) {
                  _showResultDialog(
                    context,
                    title: 'กรุณากรอกเหตุผล',
                    message: 'โปรดระบุเหตุผลในการยกเลิกคำสั่งซื้อก่อนดำเนินการ',
                  );
                  return;
                }

                try {
                  await fs.collection('orders').doc(orderId).update({
                    'status': 'cancelled',
                    'cancelReason': reason,
                    'cancelledAt': FieldValue.serverTimestamp(),
                  });

                  Navigator.pop(ctx);

                  _showResultDialog(
                    context,
                    title: 'ยกเลิกสำเร็จ',
                    message: 'อัปเดตสถานะคำสั่งซื้อเป็น “ยกเลิกแล้ว” เรียบร้อย',
                  );
                } catch (e) {
                  Navigator.pop(ctx);
                  _showResultDialog(
                    context,
                    title: 'ไม่สำเร็จ',
                    message: 'ไม่สามารถยกเลิกคำสั่งซื้อได้\n$e',
                  );
                }
              },
              child: const Text(
                'ยืนยันยกเลิก',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }


  // ==========================
  // Modal รายละเอียดคำสั่งซื้อ
  // ==========================
  void _showOrderDetailModal(
    BuildContext context, {
    required Map<String, dynamic> orderData,
    required String orderId,
    required double total,
    required String createdText,
    required NumberFormat moneyFormatter,
  
  }) {
    final rawItems = (orderData['items'] as List<dynamic>?) ?? <dynamic>[];
    final items = rawItems
        .map((e) => e is Map<String, dynamic>
            ? Map<String, dynamic>.from(e)
            : <String, dynamic>{})
        .toList();

    final topStatus = (orderData['status'] ?? '').toString();
    final payStatus = (orderData['payment']?['status'] ?? '').toString();

    final displayStatus =
        topStatus.isNotEmpty ? topStatus : (payStatus.isNotEmpty ? payStatus : 'pending');

    final meta = _statusMeta(displayStatus);

    final paymentMethodRaw =
        (orderData['payment']?['method'] ?? 'transfer_qr').toString();

    String paymentMethodDisplay;
    switch (paymentMethodRaw.toLowerCase()) {
      case 'transfer':
      case 'bank_transfer':
      case 'transfer_qr':
        paymentMethodDisplay = 'โอนผ่านธนาคาร / QR';
        break;
      case 'cod':
        paymentMethodDisplay = 'เก็บเงินปลายทาง (COD)';
        break;

      default:
        paymentMethodDisplay = 'ช่องทางอื่น ๆ';
    }

    final createdAtTimestamp = orderData['createdAt'];
    String modalCreatedDate = createdText;
    if (createdAtTimestamp is Timestamp) {
      modalCreatedDate = DateFormat('dd MMM yyyy HH:mm', 'th_TH')
          .format(createdAtTimestamp.toDate());
    }

    final cancelReason = (orderData['cancelReason'] ?? '').toString().trim();
    final cancelAtTs = orderData['cancelledAt'] ?? orderData['cancelAt'];
    String? cancelAtText;
    if (cancelAtTs is Timestamp) {
      cancelAtText = DateFormat('dd MMM yyyy HH:mm', 'th_TH')
          .format(cancelAtTs.toDate());
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(26)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 18,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: DraggableScrollableSheet(
              initialChildSize: 0.8,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (c, sc) {
                return SingleChildScrollView(
                  controller: sc,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'รายละเอียดคำสั่งซื้อ',
                                  style: TextStyle(
                                    fontSize: 18.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '#$orderId',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: meta.color.withOpacity(0.06),
                                borderRadius:
                                    BorderRadius.circular(999),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    meta.icon,
                                    size: 14,
                                    color: meta.color,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    meta.label,
                                    style: TextStyle(
                                      color: meta.color,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        const Text(
                          'สินค้าในคำสั่งซื้อ',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ...items
                            .map((it) => _buildModalProductItem(
                                  item: it,
                                  moneyFormatter: moneyFormatter,
                                ))
                            .toList(),

                        const Divider(height: 22, thickness: 0.7),

                        const Text(
                          'สรุปคำสั่งซื้อ',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildDetailRow('วันที่สั่งซื้อ', modalCreatedDate),
                        _buildDetailRow('วิธีชำระเงิน', paymentMethodDisplay),
                        _buildDetailRow(
                          'ยอดรวมทั้งหมด',
                          '฿${moneyFormatter.format(total)}',
                          isTotal: true,
                        ),
                        _buildDetailRow(
                          'สถานะปัจจุบัน',
                          meta.label,
                          valueColor: meta.color,
                        ),

                        if (displayStatus == 'cancelled' &&
                            (cancelReason.isNotEmpty ||
                                cancelAtText != null)) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius:
                                  BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.red.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'รายละเอียดการยกเลิก',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                                if (cancelAtText != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'เวลา: $cancelAtText',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                                if (cancelReason.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    'เหตุผล: $cancelReason',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        if (_canMarkReceivedTopStatus(topStatus))
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 20,
                              ),
                              label: const Padding(
                                padding:
                                    EdgeInsets.symmetric(vertical: 10),
                                child: Text(
                                  'ฉันได้รับสินค้าแล้ว',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    const Color.fromARGB(255, 255, 255, 255),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () async {
                                Navigator.pop(ctx);
                                try {
                                  await FirebaseFirestore.instance
                                      .collection('orders')
                                      .doc(orderId)
                                      .update({
                                    'status': 'completed',
                                    'receivedAt':
                                        FieldValue.serverTimestamp(),
                                  });
                                  _showResultDialog(
                                    context,
                                    title: 'ขอบคุณค่ะ 🤍',
                                    message:
                                        'ยืนยันการรับสินค้าเรียบร้อยแล้ว',
                                  );
                                } catch (e) {
                                  _showResultDialog(
                                    context,
                                    title: 'ไม่สามารถอัปเดตสถานะได้',
                                    message: '$e',
                                  );
                                }
                              },
                            ),
                          ),

                        if (_canCancelTopStatus(topStatus)) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: Icon(
                                Icons.cancel_outlined,
                                color: Colors.red.shade600,
                                size: 20,
                              ),
                              label: const Padding(
                                padding:
                                    EdgeInsets.symmetric(vertical: 9),
                                child: Text(
                                  'ส่งคำขอยกเลิกคำสั่งซื้อ',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: Colors.red.shade300,
                                  width: 1,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showCancelOrderDialog(
                                  context,
                                  orderId: orderId,
                                );
                              },
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  // ==========================
  // หน้าหลัก
  // ==========================
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final fs = FirebaseFirestore.instance;
    final money = NumberFormat('#,##0.00', 'th_TH');

    if (uid == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('ประวัติคำสั่งซื้อ'),
          backgroundColor: _primary,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text('กรุณาเข้าสู่ระบบเพื่อดูคำสั่งซื้อของคุณ'),
        ),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'ประวัติคำสั่งซื้อ',
          style: TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.brown.shade900,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_bgSoft, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: fs
              .collection('orders')
              .where('userId', isEqualTo: uid)
              .orderBy('createdAt', descending: true)
              .limit(50)
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

            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shopping_bag_outlined,
                        size: 64,
                        color: Colors.brown.shade200,
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'ยังไม่มีคำสั่งซื้อ',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'เมื่อคุณสั่งซื้อ รายการจะปรากฏที่นี่\nเพื่อให้คุณติดตามสถานะได้ง่ายขึ้น',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 88, 14, 20),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final doc = docs[i];
                final d = doc.data();
                final id = doc.id;

                final total =
                    (d['pricing']?['grandTotal'] as num?)?.toDouble() ??
                        (d['total'] as num?)?.toDouble() ??
                        0.0;

                final topStatus = (d['status'] ?? '').toString();
                final payStatus = (d['payment']?['status'] ?? '').toString();

                final displayStatus = topStatus.isNotEmpty
                    ? topStatus
                    : (payStatus.isNotEmpty ? payStatus : 'pending');

                final meta = _statusMeta(displayStatus);

                final created = d['createdAt'];
                String createdText = '-';
                if (created is Timestamp) {
                  createdText = DateFormat(
                    'dd MMM yyyy, HH:mm',
                    'th_TH',
                  ).format(created.toDate());
                }

                final rawItems =
                    (d['items'] as List<dynamic>?) ?? <dynamic>[];
                final firstItem =
                    rawItems.isNotEmpty ? rawItems.first : null;
                final firstItemName =
                    (firstItem?['name'] ??
                            firstItem?['title'] ??
                            'สินค้าไม่ระบุ')
                        .toString();
                final firstItemImgUrl =
                    (firstItem?['image'] ?? firstItem?['imageUrl'])
                        ?.toString();

                final canCancel = _canCancelTopStatus(topStatus);
                final canMarkReceived =
                    _canMarkReceivedTopStatus(topStatus);

                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      colors: [Colors.white, _bgSoft],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            Colors.brown.withOpacity(0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                    border: Border.all(
                      color: _accent.withOpacity(0.6),
                      width: 0.5,
                    ),
                  ),
                    child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                        _buildProductIcon(firstItemImgUrl),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                            firstItemName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                            '#$id',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Colors.black45,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                            createdText,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Colors.grey,
                            ),
                            ),
                          ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                            ),
                            decoration: BoxDecoration(
                            color: meta.color.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                              meta.icon,
                              size: 13,
                              color: meta.color,
                              ),
                              const SizedBox(width: 3),
                              Text(
                              meta.label,
                              style: TextStyle(
                                fontSize: 9.8,
                                fontWeight: FontWeight.w700,
                                color: meta.color,
                              ),
                              ),
                            ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '฿${money.format(total)}',
                            style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: Color(0xFFBF360C),
                            ),
                          ),
                          ],
                        ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          // ปุ่มดูรายละเอียด (เหมือนเดิม)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                _showOrderDetailModal(
                                  context,
                                  orderData: d,
                                  orderId: id,
                                  total: total,
                                  createdText: createdText,
                                  moneyFormatter: money,
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 7),
                                side: BorderSide(color: _primary.withOpacity(0.3)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'ดูรายละเอียด',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: _primary,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 8),

                          // 🟡 ไอคอนสถานะ: แสดงตาม meta ไม่สามารถกดได้
                          SizedBox(
                            width: 40,
                            height: 40,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: meta.color,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                meta.icon,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
