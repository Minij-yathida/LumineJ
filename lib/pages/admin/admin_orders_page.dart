// lib/pages/admin/admin_orders_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'admin_order_detail_page.dart';

class AdminOrdersPage extends StatefulWidget {
  const AdminOrdersPage({super.key});
  @override
  State<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

class _AdminOrdersPageState extends State<AdminOrdersPage> {
  final _fs = FirebaseFirestore.instance;
  final _fmt = DateFormat('d MMM yyyy HH:mm', 'th_TH');
  final _q = TextEditingController();
  String _statusFilter = 'all'; // all|pending|paid|shipped|completed|cancelled

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'pending': return Colors.amber;
      case 'paid': return Colors.green;
      case 'shipped': return Colors.blue;
      case 'completed': return Colors.teal;
      case 'cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }

  Widget _statusChip(String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _statusColor(s).withOpacity(.12),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(s, style: TextStyle(color: _statusColor(s), fontWeight: FontWeight.w700)),
      );

  // --- ADDED: ฟังก์ชันสำหรับจัดรูปแบบวันที่ ---
  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final checkDate = DateTime(date.year, date.month, date.day);

    if (checkDate == today) {
      return 'วันนี้';
    } else if (checkDate == yesterday) {
      return 'เมื่อวานนี้';
    } else {
      return DateFormat('d MMMM yyyy', 'th_TH').format(checkDate);
    }
  }

  // --- ADDED: ฟังก์ชันสำหรับจัดกลุ่มออเดอร์ ---
  Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> _groupOrdersByDay(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> grouped = {};

    for (final d in docs) {
      final o = d.data();
      final t = (o['createdAt'] as Timestamp?);
      
      // ถ้าไม่มีเวลาสร้าง (ข้อมูลเก่ามาก) ให้จัดกลุ่มเป็น 'ไม่ระบุวัน'
      String dateKey;
      if (t != null) {
        dateKey = _formatDateHeader(t.toDate());
      } else {
        dateKey = 'ไม่ระบุวัน';
      }

      if (grouped[dateKey] == null) {
        grouped[dateKey] = [];
      }
      grouped[dateKey]!.add(d);
    }
    return grouped;
  }
  // --- END ADDED ---

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _q,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'ค้นหา (ID/ชื่อ/UID)',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        // Status filter row
        SizedBox(
          height: 44,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            children: [
              _statusBtn('ทั้งหมด', 'all'),
              _statusBtn('pending', 'pending'),
              _statusBtn('paid', 'paid'),
              _statusBtn('shipped', 'shipped'),
              _statusBtn('completed', 'completed'),
              _statusBtn('cancelled', 'cancelled'),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // List
        Expanded(
          // --- MODIFIED: แก้ไข StreamBuilder ทั้งหมด ---
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _fs.collection('orders').orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final raw = snap.data?.docs ?? [];
              final kw = _q.text.trim().toLowerCase();

              final docs = raw.where((d) {
                final data = d.data();
                final status = (data['status'] ?? 'pending').toString();
                final customer = (data['customer'] ?? {}) as Map<String, dynamic>;
                final name = (customer['name'] ?? '').toString().toLowerCase();
                final uid = (data['userId'] ?? '').toString().toLowerCase();
                final hitKw = kw.isEmpty || d.id.toLowerCase().contains(kw) || name.contains(kw) || uid.contains(kw);
                final hitFilter = _statusFilter == 'all' || status == _statusFilter;
                return hitKw && hitFilter;
              }).toList();

              if (docs.isEmpty) {
                return const Center(child: Text('ยังไม่มีออเดอร์ตามเงื่อนไข'));
              }

              // --- ส่วนใหม่: จัดกลุ่ม ---
              final groupedOrders = _groupOrdersByDay(docs);
              final dateKeys = groupedOrders.keys.toList();

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: dateKeys.length,
                itemBuilder: (_, index) {
                  final dateKey = dateKeys[index];
                  final ordersInDay = groupedOrders[dateKey]!;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- หัวข้อวันที่ ---
                      Padding(
                        padding: EdgeInsets.only(
                          top: index == 0 ? 0 : 20, // เว้นระยะห่างระหว่างกลุ่ม
                          bottom: 8,
                          left: 4,
                        ),
                        child: Text(
                          dateKey,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),

                      // --- ลิสต์ออเดอร์ในวันนั้น ---
                      ...ordersInDay.map((d) {
                        final o = d.data();
                        final status = (o['status'] ?? 'pending').toString();
                        final t = (o['createdAt'] as Timestamp?);
                        final customer = (o['customer'] ?? {}) as Map<String, dynamic>;
                        final total = _num(o['pricing']?['grandTotal'] ?? o['total']).toDouble();

                        // --- นี่คือ Card เดิมของคุณ ---
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8), // ใช้แทน separator
                          child: Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => AdminOrderDetailPage(orderId: d.id)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text('ออเดอร์ #${d.id}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                        ),
                                        _statusChip(status),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text('ลูกค้า: ${customer['name'] ?? '-'}',
                                        style: const TextStyle(color: Colors.black87)),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${t != null ? _fmt.format(t.toDate()) : '-'}   •   ฿${total.toStringAsFixed(2)}',
                                      style: const TextStyle(color: Colors.black54, fontSize: 12.5),
                                    ),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      height: 40,
                                      child: OutlinedButton.icon(
                                        onPressed: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (_) => AdminOrderDetailPage(orderId: d.id)),
                                        ),
                                        icon: const Icon(Icons.receipt_long_outlined),
                                        label: const Text('เปิดดูรายละเอียด / ยืนยัน'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  );
                },
              );
            },
          ),
          // --- END MODIFIED ---
        ),
      ],
    );
  }

  Widget _statusBtn(String label, String key) {
    final active = _statusFilter == key;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => setState(() => _statusFilter = key),
        selectedColor: const Color(0xFFDCEFE6),
      ),
    );
  }

  static num _num(dynamic v) => (v is num) ? v : num.tryParse('$v') ?? 0;
}