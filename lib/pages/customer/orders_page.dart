// lib/pages/customer/orders_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});
  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final _auth = FirebaseAuth.instance;

  Stream<QuerySnapshot<Map<String, dynamic>>> _ordersStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('order_requests')
      .orderBy('createdAt', descending: true)
      .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('คำสั่งซื้อของฉัน')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _ordersStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('ยังไม่มีคำสั่งซื้อ'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i].data();
              final id = docs[i].id;
              final status = d['status'] ?? 'pending';
              final total = d['pricing']?['grandTotal'] ?? 0.0;

              // 🔔 เปลี่ยนสีและข้อความตามสถานะ
              Color c = Colors.grey;
              String label = 'รอดำเนินการ';
              switch (status) {
                case 'pending':
                  c = Colors.amber; label = 'รอการอนุมัติและยืนยันคำสั่งซื้อ';
                  break;
                case 'paid':
                  c = Colors.green; label = 'ชำระเงินแล้ว';
                  break;
                case 'shipped':
                  c = Colors.blue; label = 'กำลังจัดส่ง';
                  break;
                case 'completed':
                  c = Colors.teal; label = 'จัดส่งสำเร็จแล้ว';
                  break;
                case 'cancelled':
                  c = Colors.red; label = 'ถูกยกเลิก';
                  break;
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text('Order #$id'),
                  subtitle: Text('สถานะ: $label', style: TextStyle(color: c)),
                  trailing: Text('฿${total.toStringAsFixed(2)}'),
                  onTap: () {
                    // แสดงรายละเอียดออเดอร์
                    _showOrderDialog(context, d, id);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showOrderDialog(BuildContext context, Map<String, dynamic> order, String id) {
    final status = order['status'] ?? 'pending';
    String msg = '';
    switch (status) {
      case 'pending': msg = 'สถานะ: รอการอนุมัติและยืนยันคำสั่งซื้อการชำระเงิน'; break;
      case 'paid': msg = 'ชำระเงินเรียบร้อยแล้ว รอจัดส่งสินค้า'; break;
      case 'shipped': msg = 'สินค้ากำลังจัดส่ง'; break;
      case 'completed': msg = 'ได้รับสินค้าแล้ว ขอบคุณที่ใช้บริการ!'; break;
      case 'cancelled': msg = 'คำสั่งซื้อนี้ถูกยกเลิก'; break;
    }

    // determine label and color locally for the dialog (was previously only in build)
    Color c = Colors.grey;
    String label = 'รอดำเนินการ';
    switch (status) {
      case 'pending':
        c = Colors.amber;
        label = 'รอการอนุมัติและยืนยันคำสั่งซื้อ';
        break;
      case 'paid':
        c = Colors.green;
        label = 'ชำระเงินแล้ว';
        break;
      case 'shipped':
        c = Colors.blue;
        label = 'กำลังจัดส่ง';
        break;
      case 'completed':
        c = Colors.teal;
        label = 'จัดส่งสำเร็จแล้ว';
        break;
      case 'cancelled':
        c = Colors.red;
        label = 'ถูกยกเลิก';
        break;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.receipt_long, size: 20),
            SizedBox(width: 8),
            Expanded(child: Text('รายละเอียดคำสั่งซื้อ')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Order ID: $id', style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('สถานะ: $label', style: TextStyle(color: c)),
              const SizedBox(height: 8),
              if (order['pricing'] != null) ...[
                Text('ยอดรวม: ฿${(order['pricing']['grandTotal'] ?? 0).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
              ],
              if (order['items'] is List) ...[
                const Text('รายการสินค้า:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ...((order['items'] as List).take(8).map((it) {
                  final name = it['name'] ?? '';
                  final qty = it['qty'] ?? 0;
                  final price = (it['price'] ?? 0).toString();
                      return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text('- $name x$qty • ฿$price'),
                  );
                })),
                const SizedBox(height: 6),
              ],
              const Divider(),
              Text(msg),
            ],
          ),
        ),
        actions: [
          if (status == 'shipped')
            // ไม่อนุญาตให้ลูกค้าอัพเดทสถานะโดยตรงที่ order_requests
          // สถานะจะถูกอัพเดทโดย admin/backend
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ปิด'))
        ],
      ),
    );
  }
}
