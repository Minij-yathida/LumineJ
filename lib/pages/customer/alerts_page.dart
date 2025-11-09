import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/notifications_repo.dart';

class AlertsPage extends StatelessWidget {
  const AlertsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('กรุณาเข้าสู่ระบบก่อน')),
      );
    }

    final repo = NotificationsRepo();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(fontFamily: 'PlayfairDisplay', fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFFF8ECE7),
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF8ECE7),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        children: [
          // ====== สรุปคำสั่งซื้อล่าสุด ======
          _LatestOrderSummary(uid: uid),

          const SizedBox(height: 16),
          Text('การแจ้งเตือนล่าสุด', style: TextStyle(
            color: Colors.brown.shade800,
            fontWeight: FontWeight.bold,
          )),
          const SizedBox(height: 8),

          // ====== รายการแจ้งเตือนจาก alerts ======
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: repo.streamFor(uid),
            builder: (context, snap) {
              if (snap.hasError) {
                return _card(const Text('เกิดข้อผิดพลาดในการโหลดแจ้งเตือน'));
              }
              if (snap.connectionState == ConnectionState.waiting) {
                return _card(const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ));
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return _card(const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('ยังไม่มีการแจ้งเตือน')),
                ));
              }

              return _card(ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 0),
                itemBuilder: (context, i) {
                  final d = docs[i].data();
                  final id = docs[i].id;
                  final title = d['title'] ?? 'ไม่มีหัวข้อ';
                  final body = d['body'] ?? '';
                  final unread = (d['status'] ?? 'unread') == 'unread';
                  final ts = (d['createdAt'] as Timestamp?)?.toDate();

                  return ListTile(
                    leading: Icon(
                      unread ? Icons.notifications_active : Icons.notifications_none,
                      color: unread ? Colors.brown.shade700 : Colors.grey,
                    ),
                    title: Text(title, style: TextStyle(
                      fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                      color: Colors.brown.shade900,
                    )),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(body),
                        if (ts != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(_fmt(ts),
                                style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ),
                      ],
                    ),
                    onTap: () => repo.markRead(id),
                  );
                },
              ));
            },
          ),
        ],
      ),
    );
  }

  static Widget _card(Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)],
      ),
      child: child,
    );
  }

  static String _fmt(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final today = DateTime.now();
    final sameDay = today.year == dt.year && today.month == dt.month && today.day == dt.day;
    return sameDay ? '$h:$m น.' : '${dt.day}/${dt.month}/${dt.year}  $h:$m น.';
  }
}

// ===== Card แสดงสรุปคำสั่งซื้อล่าสุด =====
class _LatestOrderSummary extends StatelessWidget {
  final String uid;
  const _LatestOrderSummary({required this.uid});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('orders')
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(1);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return AlertsPage._card(const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ));
        }
        final doc = snap.data?.docs.isNotEmpty == true ? snap.data!.docs.first : null;
        if (doc == null) {
          return AlertsPage._card(const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: Text('ยังไม่มีคำสั่งซื้อ')),
          ));
        }

        final d = doc.data();
        final status = (d['status'] ?? 'pending') as String;
        final grand = (d['pricing']?['grandTotal'] ?? d['total'] ?? 0.0) * 1.0;
        final method = (d['payment']?['method'] ?? 'transfer_qr') as String; // 'transfer_qr'|'cod'
        final ts = (d['createdAt'] as Timestamp?)?.toDate();

        final title = _statusTitle(method, status);
        final desc = 'ออเดอร์ #${doc.id}  ยอด ฿${grand.toStringAsFixed(2)}';
        final color = _statusColor(status);

        return AlertsPage._card(Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.receipt_long, color: color),
                const SizedBox(width: 8),
                Text('สรุปคำสั่งซื้อล่าสุด',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown.shade900)),
                const Spacer(),
                if (ts != null)
                  Text(AlertsPage._fmt(ts), style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
              const SizedBox(height: 4),
              Text(desc),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  Chip(
                    label: Text(_statusLabel(status)),
                    backgroundColor: color.withOpacity(.12),
                    labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                  Chip(
                    label: Text(method == 'cod' ? 'เก็บเงินปลายทาง' : 'โอน/พร้อมเพย์'),
                    backgroundColor: Colors.black12.withOpacity(.06),
                  ),
                ],
              ),
            ],
          ),
        ));
      },
    );
  }

  static String _statusTitle(String method, String status) {
    if (method == 'cod') {
      switch (status) {
        case 'pending_cod':
        case 'waiting_admin':
          return 'เตรียมชำระปลายทาง';
        case 'shipped':
          return 'พัสดุอยู่ระหว่างจัดส่ง (ชำระปลายทาง)';
        case 'completed':
          return 'คำสั่งซื้อเสร็จสิ้น (COD)';
        case 'cancelled':
          return 'คำสั่งซื้อถูกยกเลิก';
      }
      return 'เตรียมชำระปลายทาง';
    } else {
      // transfer_qr
      switch (status) {
        case 'waiting_admin':
          return 'สถานะ: รอการอนุมัติและยืนยันคำสั่งซื้อสลิป';
        case 'paid':
          return 'ชำระเงินแล้ว กำลังเตรียมจัดส่ง';
        case 'shipped':
          return 'พัสดุอยู่ระหว่างจัดส่ง';
        case 'completed':
          return 'คำสั่งซื้อเสร็จสิ้น';
        case 'cancelled':
          return 'คำสั่งซื้อถูกยกเลิก';
      }
  return 'สถานะ: รอการอนุมัติและยืนยันคำสั่งซื้อ';
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'waiting_admin': return 'รอตรวจสอบคำสั่งซื้อ';
      case 'pending_cod':  return 'เตรียมชำระปลายทาง';
      case 'paid':         return 'ชำระเงินแล้ว';
      case 'shipped':      return 'จัดส่งแล้ว';
      case 'completed':    return 'เสร็จสิ้น';
      case 'cancelled':    return 'ยกเลิก';
      default:             return status;
    }
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'waiting_admin': return Colors.amber.shade800;
      case 'pending_cod':   return Colors.orange.shade700;
      case 'paid':          return Colors.green.shade700;
      case 'shipped':       return Colors.blue.shade700;
      case 'completed':     return Colors.teal.shade700;
      case 'cancelled':     return Colors.red.shade700;
      default:              return Colors.brown.shade700;
    }
  }
}
