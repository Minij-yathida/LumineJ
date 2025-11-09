// lib/pages/admin/admin_order_detail_page.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

class AdminOrderDetailPage extends StatefulWidget {
  final String orderId;
  const AdminOrderDetailPage({super.key, required this.orderId});

  @override
  State<AdminOrderDetailPage> createState() => _AdminOrderDetailPageState();
}

class _AdminOrderDetailPageState extends State<AdminOrderDetailPage> {
  bool _busy = false;

  // ---------- Helpers ----------
  num _num(dynamic v) => (v is num) ? v : num.tryParse('$v') ?? 0;
  double _dbl(dynamic v) => _num(v).toDouble();

  DateTime? _toDT(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  String _fmtDT(DateTime? d) =>
      d == null ? '-' : DateFormat('d MMM y HH:mm', 'th_TH').format(d);

  String _paymentChannelHuman(Map<String, dynamic> payment) {
    final method = (payment['method'] ?? payment['channel'] ?? '').toString();
    switch (method) {
      case 'transfer_qr':
      case 'promptpay':
      case 'qr':
        return 'โอน/พร้อมเพย์';
      case 'transfer_account':
      case 'bank_transfer':
        return 'โอนบัญชี';
      case 'cod':
      case 'cash_on_delivery':
        return 'เก็บปลายทาง';
      case 'card':
      case 'credit_card':
        return 'บัตรเครดิต/เดบิต';
      default:
        return 'ไม่ระบุ';
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'pending':
      case 'waiting_admin':
      case 'pending_cod':
        return Colors.orange;
      case 'paid':
        return Colors.green;
      case 'shipped':
        return Colors.blue;
      case 'completed':
        return Colors.teal;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // --- ดูสลิปแบบ Zoom + Cache (ตอบสนองไวขึ้น) ---
  void _openSlipViewer(String slipUrl) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: slipUrl.startsWith('http')
              ? CachedNetworkImage(
                  imageUrl: slipUrl,
                  fit: BoxFit.contain,
                  memCacheWidth: 1400,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  progressIndicatorBuilder: (context, url, progress) =>
                      const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  errorWidget: (context, url, error) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('โหลดรูปสลิปไม่ได้'),
                  ),
                )
              : Image.file(File(slipUrl), fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _priceLine(String label, double value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text('฿${value.toStringAsFixed(2)}'),
          ],
        ),
      );

  Widget _timelineRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.brown),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(
            value,
            style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // --- Helper: ยกเลิกออเดอร์ + ขอเหตุผล ---
  Future<void> _cancelOrderWithReason(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> o, {
    required bool isCod,
    required double total,
  }) async {
    final controller = TextEditingController();

    final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('ยกเลิกออเดอร์'),
            content: TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'เหตุผลในการยกเลิก',
                hintText: 'เช่น ลูกค้าขอยกเลิก / ไม่ชำระเงิน / สต๊อกไม่พอ ฯลฯ',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('กลับ'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('ยืนยันยกเลิก'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) {
      controller.dispose();
      return;
    }

    final reasonText =
        controller.text.trim().isEmpty ? 'ไม่ระบุ' : controller.text.trim();
    controller.dispose();

    setState(() => _busy = true);
    try {
      await ref.update({
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelReason': reasonText,
      });

      final customerUid =
          (o['userId'] ?? o['user_id'] ?? o['customer']?['uid'])?.toString();

      if (customerUid != null && customerUid.isNotEmpty) {
        final payload = {
          'title': 'ออเดอร์ถูกยกเลิก',
          'body':
              'ออเดอร์ #${widget.orderId} ถูกยกเลิกโดยร้านค้า${isCod ? " (COD)" : ""}\nเหตุผล: $reasonText',
          'orderId': widget.orderId,
          'amount': total,
          'type': 'order_updated',
          'status': 'cancelled',
          'cancelReason': reasonText,
          'createdAt': FieldValue.serverTimestamp(),
        };

        final alertRef = await FirebaseFirestore.instance
            .collection('users')
            .doc(customerUid)
            .collection('alerts')
            .add(payload);

        try {
          await FirebaseFirestore.instance
              .collection('backend_ingest')
              .doc(alertRef.id)
              .set({
            'type': 'admin_alert',
            'orderId': widget.orderId,
            'userId': customerUid,
            'alertId': alertRef.id,
            'payload': payload,
            'createdAt': FieldValue.serverTimestamp(),
            'processed': false,
          });
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🚫 ยกเลิกออเดอร์แล้ว')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref =
        FirebaseFirestore.instance.collection('orders').doc(widget.orderId);

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: Text('ออเดอร์ #${widget.orderId}'),
          ),
          body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: ref.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snap.hasData || !snap.data!.exists) {
                return const Center(child: Text('ไม่พบออเดอร์นี้'));
              }

              final o = snap.data!.data()!;
              final status = (o['status'] ?? 'pending').toString();

              final items =
                  (o['items'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
              final customer =
                  (o['customer'] as Map<String, dynamic>? ?? {});
              final pricing =
                  (o['pricing'] as Map<String, dynamic>? ?? {});
              final payment =
                  (o['payment'] as Map<String, dynamic>? ?? {});
              final createdAtTs = (o['createdAt'] as Timestamp?);

              final subtotal = _dbl(pricing['subtotal']);
              final discount = _dbl(pricing['discount']);
              final shipping =
                  _dbl(pricing['shippingFee'] ?? pricing['shipping']);
              final total =
                  _dbl(pricing['grandTotal'] ?? pricing['total']);

              final slipUrl = (payment['slipUrl'] ?? '') as String;
              final paidAt = _toDT(o['paidAt'] ?? payment['verifiedAt']);
              final shippedAt = _toDT(o['shippedAt']);

              // ✅ รองรับหลาย key สำหรับเวลาสำเร็จสมบูรณ์
              final completedAt = _toDT(
                o['completedAt'] ??
                    o['completed_at'] ??
                    o['receivedAt'] ??
                    o['received_at'],
              );

              final cancelledAt = _toDT(o['cancelledAt']);
              final cancelReason = (o['cancelReason'] ?? '').toString();

              final channel = _paymentChannelHuman(payment);
              final isCod = channel == 'เก็บปลายทาง';

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ---------- Status + created time ----------
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withOpacity(.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: _statusColor(status),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (createdAtTs != null)
                        Text(
                          "สร้าง: ${DateFormat('d MMM y HH:mm', 'th_TH').format(createdAtTs.toDate())}",
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ---------- Timeline ----------
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF4EF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFEEDFD4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ไทม์ไลน์',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        _timelineRow(
                          Icons.receipt_long,
                          'สร้างออเดอร์',
                          _fmtDT(_toDT(o['createdAt'])),
                        ),
                        _timelineRow(
                          Icons.verified,
                          'ยืนยันการชำระ',
                          _fmtDT(paidAt),
                        ),
                        _timelineRow(
                          Icons.local_shipping,
                          'จัดส่งแล้ว',
                          _fmtDT(shippedAt),
                        ),
                        _timelineRow(
                          Icons.check_circle,
                          'สำเร็จสมบูรณ์',
                          _fmtDT(completedAt),
                        ),
                        _timelineRow(
                          Icons.cancel,
                          'ยกเลิก',
                          _fmtDT(cancelledAt),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ---------- Customer ----------
                  const Text(
                    'ข้อมูลลูกค้า',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text('ชื่อ: ${customer['name'] ?? '-'}'),
                  Text('โทร: ${customer['phone'] ?? '-'}'),
                  Text('อีเมล: ${customer['email'] ?? '-'}'),
                  Text('ที่อยู่: ${customer['address'] ?? '-'}'),
                  const Divider(height: 24),

                  // ---------- Items ----------
                  const Text(
                    'รายการสินค้า',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  ...items.map((it) => ProductItemTile(itemData: it)),
                  const Divider(height: 24),

                  // ---------- Pricing ----------
                  _priceLine('ยอดรวม', subtotal),
                  _priceLine('ส่วนลด', -discount),
                  _priceLine('ค่าส่ง', shipping),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text(
                        'รวมทั้งหมด',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '฿${total.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ---------- Payment ----------
                  const Text(
                    'การชำระเงิน',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Text(
                        'ช่องทาง: ',
                        style: TextStyle(color: Colors.black54),
                      ),
                      Text(
                        channel,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // รูปสลิป (Thumbnail)
                  if (slipUrl.isNotEmpty) ...[
                    const Text(
                      'หลักฐานการชำระเงิน',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => _openSlipViewer(slipUrl),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: slipUrl.startsWith('http')
                            ? CachedNetworkImage(
                                imageUrl: slipUrl,
                                height: 260,
                                fit: BoxFit.cover,
                                memCacheWidth: 800,
                                fadeInDuration:
                                    const Duration(milliseconds: 80),
                                fadeOutDuration: Duration.zero,
                                progressIndicatorBuilder:
                                    (context, url, progress) =>
                                        Container(
                                  height: 260,
                                  color: Colors.grey.shade200,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                                errorWidget:
                                    (context, url, error) =>
                                        const Padding(
                                  padding: EdgeInsets.all(24.0),
                                  child:
                                      Text('โหลดหลักฐานการชำระเงินไม่ได้'),
                                ),
                              )
                            : Image.file(
                                File(slipUrl),
                                height: 260,
                                fit: BoxFit.cover,
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // ============================================================
                  // 🌟 Actions (ปุ่มจะเปลี่ยนไปตามสถานะ)
                  // ============================================================

                  // 1️⃣ pending / waiting_admin / pending_cod
                  if (status == 'pending' ||
                      status == 'waiting_admin' ||
                      status == 'pending_cod') ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBF7F4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFEADCD1)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.brown.withOpacity(0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'การดำเนินการ (Admin)',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              // 🔸 ยกเลิกออเดอร์ (มีเหตุผล)
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _cancelOrderWithReason(
                                            ref,
                                            o,
                                            isCod: isCod,
                                            total: total,
                                          ),
                                  icon:
                                      const Icon(Icons.cancel_outlined),
                                  label: const Text('ยกเลิกออเดอร์'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red[600],
                                    side: BorderSide(color: Colors.red[200]!),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // 🔸 ยืนยันชำระ / ยืนยันออเดอร์ COD
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          setState(() => _busy = true);
                                          try {
                                            await ref.update({
                                              'status': 'paid',
                                              'paidAt':
                                                  FieldValue.serverTimestamp(),
                                            });

                                            final customerUid =
                                                (o['userId'] ??
                                                        o['user_id'] ??
                                                        o['customer']?['uid'])
                                                    ?.toString();

                                            if (customerUid != null &&
                                                customerUid.isNotEmpty) {
                                              final payload = {
                                                'title': isCod
                                                    ? 'ยืนยันออเดอร์ (COD)'
                                                    : 'ยืนยันการชำระ',
                                                'body': isCod
                                                    ? 'ออเดอร์ #${widget.orderId} ได้รับการยืนยัน และร้านค้ากำลังเตรียมจัดส่ง'
                                                    : 'ออเดอร์ #${widget.orderId} ได้รับการยืนยันการชำระแล้ว',
                                                'orderId': widget.orderId,
                                                'amount': total,
                                                'type': 'order_updated',
                                                'status': 'paid',
                                                'createdAt':
                                                    FieldValue.serverTimestamp(),
                                              };
                                              final alertRef =
                                                  await FirebaseFirestore
                                                      .instance
                                                      .collection('users')
                                                      .doc(customerUid)
                                                      .collection('alerts')
                                                      .add(payload);
                                              try {
                                                await FirebaseFirestore
                                                    .instance
                                                    .collection(
                                                        'backend_ingest')
                                                    .doc(alertRef.id)
                                                    .set({
                                                  'type': 'admin_alert',
                                                  'orderId':
                                                      widget.orderId,
                                                  'userId': customerUid,
                                                  'alertId': alertRef.id,
                                                  'payload': payload,
                                                  'createdAt':
                                                      FieldValue
                                                          .serverTimestamp(),
                                                  'processed': false,
                                                });
                                              } catch (_) {}
                                            }

                                            if (mounted) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    isCod
                                                        ? '✅ ยืนยันออเดอร์ (COD) แล้ว'
                                                        : '✅ ยืนยันการชำระเรียบร้อย',
                                                  ),
                                                ),
                                              );
                                            }
                                          } finally {
                                            if (mounted) {
                                              setState(() => _busy = false);
                                            }
                                          }
                                        },
                                  icon: const Icon(
                                      Icons.verified_outlined),
                                  label: Text(
                                      isCod ? 'ยืนยันออเดอร์' : 'ยืนยันชำระ'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        const Color(0xFF8D6E63),
                                    foregroundColor: Colors.white,
                                    elevation: 2,
                                    padding:
                                        const EdgeInsets.symmetric(
                                            vertical: 14),
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ]

                  // 2️⃣ paid -> shipped
                  else if (status == 'paid') ...[
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              setState(() => _busy = true);
                              try {
                                await ref.update({
                                  'status': 'shipped',
                                  'shippedAt':
                                      FieldValue.serverTimestamp(),
                                });

                                final customerUid =
                                    (o['userId'] ??
                                            o['user_id'] ??
                                            o['customer']?['uid'])
                                        ?.toString();
                                if (customerUid != null &&
                                    customerUid.isNotEmpty) {
                                  final payload = {
                                    'title': 'จัดส่งแล้ว',
                                    'body':
                                        'ออเดอร์ #${widget.orderId} ถูกอัปเดตเป็น “จัดส่งแล้ว”',
                                    'orderId': widget.orderId,
                                    'amount': total,
                                    'type': 'order_updated',
                                    'status': 'shipped',
                                    'createdAt':
                                        FieldValue.serverTimestamp(),
                                  };
                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(customerUid)
                                      .collection('alerts')
                                      .add(payload);
                                }

                                if (mounted) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          '📦 อัปเดตเป็น “จัดส่งแล้ว”'),
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _busy = false);
                                }
                              }
                            },
                      icon:
                          const Icon(Icons.local_shipping_outlined),
                      label: const Text('อัปเดตเป็น “จัดส่งแล้ว”'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ]

                  // 3️⃣ shipped
                  else if (status == 'shipped') ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFFFFECB3)),
                      ),
                      child: const Center(
                        child: Text(
                          '⏳ รอลูกค้ายืนยันรับสินค้า',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ]

                  // 4️⃣ completed (มีกล่องสวย ๆ + เวลา)
                  else if (status == 'completed') ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFFC8E6C9)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🎉 ออเดอร์สำเร็จสมบูรณ์',
                            style: TextStyle(
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ลูกค้ายืนยันได้รับสินค้าเรียบร้อยแล้ว',
                            style: TextStyle(
                                color: Colors.green[900],
                                fontSize: 13),
                          ),
                          if (completedAt != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'ยืนยันเมื่อ: ${_fmtDT(completedAt)}',
                              style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ]

                  // 5️⃣ cancelled (โชว์เหตุผล)
                  else if (status == 'cancelled') ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFFFFCDD2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🚫 ออเดอร์นี้ถูกยกเลิก',
                            style: TextStyle(
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'เหตุผล: ${cancelReason.isEmpty ? 'ไม่ระบุ' : cancelReason}',
                            style: const TextStyle(
                                color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 40),
                ],
              );
            },
          ),
        ),

        if (_busy)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(.12),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

// --- Widget แสดงสินค้าแต่ละรายการ ---
class ProductItemTile extends StatefulWidget {
  final Map<String, dynamic> itemData;
  const ProductItemTile({super.key, required this.itemData});

  @override
  State<ProductItemTile> createState() => _ProductItemTileState();
}

class _ProductItemTileState extends State<ProductItemTile> {
  num _num(dynamic v) => (v is num) ? v : num.tryParse('$v') ?? 0;
  double _dbl(dynamic v) => _num(v).toDouble();

  Future<DocumentSnapshot<Map<String, dynamic>>>? _productFuture;

  @override
  void initState() {
    super.initState();
    if (widget.itemData['productId'] != null &&
        widget.itemData['productId'].toString().isNotEmpty) {
      _productFuture = FirebaseFirestore.instance
          .collection('products')
          .doc(widget.itemData['productId'].toString())
          .get();
    }
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.itemData;

    final qty = _num(it['qty']).toInt();
    final price = _dbl(it['price']);
    final line = price * qty;
    final color = (it['variant']?['color'] ?? '').toString();
    final size = (it['variant']?['size'] ?? '').toString();
    final variant =
        [size, color].where((e) => e.trim().isNotEmpty).join(' / ');

    String name = (it['name'] ?? '').toString();
    String? imageUrl;
    final iv = it['image'] ?? it['imageUrl'];
    if (iv is String && iv.trim().isNotEmpty) {
      imageUrl = iv.trim();
    }

    if (_productFuture == null) {
      return _buildTile(
        name: name.isEmpty ? '(ไม่มีชื่อสินค้า)' : name,
        imageUrl: imageUrl,
        variant: variant,
        qty: qty,
        price: price,
        line: line,
      );
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _productFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildTile(
            name: 'กำลังโหลด...',
            imageUrl: null,
            variant: variant,
            qty: qty,
            price: price,
            line: line,
            isLoading: true,
          );
        }

        if (snapshot.hasData && snapshot.data!.exists) {
          final productData = snapshot.data!.data()!;
          if (name.isEmpty) {
            name =
                (productData['name'] ?? '(ไม่มีชื่อสินค้า)').toString();
          }
          if (imageUrl == null) {
            final pImgs = productData['images'];
            if (pImgs is List && pImgs.isNotEmpty) {
              imageUrl = pImgs.first.toString();
            } else {
              final pImg =
                  productData['image'] ?? productData['imageUrl'];
              if (pImg is String && pImg.trim().isNotEmpty) {
                imageUrl = pImg.trim();
              }
            }
          }
        } else {
          if (name.isEmpty) {
            name = '(ไม่พบข้อมูลสินค้า)';
          }
        }

        return _buildTile(
          name: name,
          imageUrl: imageUrl,
          variant: variant,
          qty: qty,
          price: price,
          line: line,
        );
      },
    );
  }

  Widget _buildTile({
    required String name,
    required String? imageUrl,
    required String variant,
    required int qty,
    required double price,
    required double line,
    bool isLoading = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEFE4DC)),
      ),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: imageUrl == null
              ? Container(
                  width: 56,
                  height: 56,
                  color: const Color(0xFFF4EDEA),
                  child: isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.image_outlined,
                          color: Colors.brown.withOpacity(.5),
                        ),
                )
              : CachedNetworkImage(
                  imageUrl: imageUrl,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  memCacheWidth: 200,
                  fadeInDuration: const Duration(milliseconds: 80),
                  fadeOutDuration: Duration.zero,
                  placeholder: (context, url) => Container(
                    width: 56,
                    height: 56,
                    color: const Color(0xFFF4EDEA),
                    child: const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 56,
                    height: 56,
                    color: const Color(0xFFF4EDEA),
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.brown.withOpacity(.55),
                    ),
                  ),
                ),
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${variant.isEmpty ? '' : '$variant • '}x$qty   ฿${price.toStringAsFixed(2)}',
        ),
        trailing: Text('฿${line.toStringAsFixed(2)}'),
      ),
    );
  }
}
