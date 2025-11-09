// lib/pages/admin/admin_dashboard_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';


// ตั้งค่า storeId ถ้าระบบมีหลายร้าน (null = ไม่กรอง)
const String? kStoreId = null;
// ตัวอย่าง: const String? kStoreId = 'STORE_Lumine';

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;
    final money = NumberFormat('#,##0.##', 'th_TH');
    final cs = Theme.of(context).colorScheme;

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final startOfMonth = DateTime(now.year, now.month, 1);
    final startOfWeek =
        DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));

    return Container(
      color: cs.surface,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Top icon row removed as requested

          // ===== KPIs วันนี้ =====
          _sectionTitle(context, 'ภาพรวมวันนี้'),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _ordersSince(fs, startOfDay).snapshots(),
            builder: (_, s) {
              final docs = s.data?.docs ?? [];
              double revenue = 0;
              int pending = 0;
              for (final d in docs) {
                final m = d.data();
                final st = (m['status'] ?? '').toString();
                final gt = (m['pricing']?['grandTotal'] ?? m['total'] ?? 0);
                final total = (gt is num) ? gt.toDouble() : double.tryParse('$gt') ?? 0;
                if (st != 'cancelled') revenue += total;
                if (st == 'pending') pending++;
              }
              return _grid(
                context,
                [
                  _kpi(context, Icons.receipt_long, 'ออเดอร์วันนี้', '${docs.length}'),
                  _kpi(context, Icons.account_balance_wallet_outlined, 'รายได้วันนี้',
                      '${money.format(revenue)} ฿'),
                  _kpi(context, Icons.hourglass_bottom, 'รอดำเนินการ', '$pending'),
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          // ===== กราฟรายได้สัปดาห์นี้ =====
          _sectionTitle(context, 'รายได้รายวัน (สัปดาห์นี้)'),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _ordersSince(fs, DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day))
                .snapshots(),
            builder: (_, s) {
              final docs = s.data?.docs ?? [];
              final totals = List<double>.filled(7, 0); // จ-อา
              for (final d in docs) {
                final m = d.data();
                final ts = (m['createdAt'] as Timestamp?)?.toDate();
                if (ts == null) continue;
                final idx = ts.weekday - 1;
                if ((m['status'] ?? '') == 'cancelled') continue;
                final gt = (m['pricing']?['grandTotal'] ?? m['total'] ?? 0);
                final total = (gt is num) ? gt.toDouble() : double.tryParse('$gt') ?? 0;
                totals[idx] += total;
              }
              return _weeklyBar(context, totals);
            },
          ),

          const SizedBox(height: 16),

          // ===== KPIs เดือนนี้ =====
          _sectionTitle(context, 'เดือนนี้'),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _ordersSince(fs, startOfMonth).snapshots(),
            builder: (_, s) {
              final docs = s.data?.docs ?? [];
              double revenue = 0;
              for (final d in docs) {
                final m = d.data();
                final st = (m['status'] ?? '').toString();
                final gt = (m['pricing']?['grandTotal'] ?? m['total'] ?? 0);
                final total = (gt is num) ? gt.toDouble() : double.tryParse('$gt') ?? 0;
                if (st != 'cancelled') revenue += total;
              }
              return _grid(
                context,
                [
                  _kpi(context, Icons.calendar_month, 'ออเดอร์รวม', '${docs.length}'),
                  _kpi(context, Icons.trending_up, 'รายได้รวม', '${money.format(revenue)} ฿'),
                ],
              );
            },
          ),

          const SizedBox(height: 16),

          // ===== สถานะคำสั่งซื้อเดือนนี้ =====
          _sectionTitle(context, 'สถานะคำสั่งซื้อ (เดือนนี้)'),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _ordersSince(fs, startOfMonth).snapshots(),
            builder: (_, s) {
              final docs = s.data?.docs ?? [];
              final map = <String, int>{
                'pending': 0,
                'paid': 0,
                'shipped': 0,
                'completed': 0,
                'cancelled': 0,
              };
              for (final d in docs) {
                final st = (d.data()['status'] ?? 'pending').toString();
                if (map.containsKey(st)) map[st] = (map[st] ?? 0) + 1;
              }
              return _statusChips(context, map);
            },
          ),

          const SizedBox(height: 16),

          // ===== สรุปสินค้าโดยหมวดหมู่ + สต็อกต่ำ =====
          _sectionTitle(context, 'หมวดหมู่สินค้า'),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _productsQuery(fs).snapshots(),
            builder: (_, s) {
              final docs = s.data?.docs ?? [];
              final byCat = <String, int>{};

              for (final d in docs) {
                final m = d.data();
                final cat = (m['category'] ?? '-').toString();
                byCat[cat] = (byCat[cat] ?? 0) + 1;
              }

              if (docs.isEmpty) {
                return _card(child: const ListTile(title: Text('ยังไม่มีสินค้า')));
              }

              return _card(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: byCat.entries.map((e) {
                        return Chip(
                          label: Text('${e.key} · ${e.value}'),
                          avatar: const Icon(Icons.category, size: 18),
                        );
                      }).toList(),
                    )
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ---------- Firestore helpers ----------
  Query<Map<String, dynamic>> _ordersSince(FirebaseFirestore fs, DateTime since) {
    Query<Map<String, dynamic>> q = fs
        .collection('orders')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since));
    if (kStoreId != null) q = q.where('storeId', isEqualTo: kStoreId);
    return q;
  }

  Query<Map<String, dynamic>> _productsQuery(FirebaseFirestore fs) {
    Query<Map<String, dynamic>> q = fs.collection('products');
    if (kStoreId != null) q = q.where('storeId', isEqualTo: kStoreId);
    return q;
  }

  // ---------- UI helpers ----------
  Widget _quickActions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (_, c) {
      final wide = c.maxWidth >= 720;
      final w = wide ? (c.maxWidth - 12) / 2 : c.maxWidth;

      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _card(
            child: _actionTile(
              context,
              icon: Icons.receipt_long,
              title: 'คำสั่งซื้อทั้งหมด',
              desc: 'อัปเดตสถานะ • ตรวจสลิป',
              color: cs.primary,
              onTapRoute: '/admin/orders',
            ),
          ),
          _card(
            child: _actionTile(
              context,
              icon: Icons.inventory_2_outlined,
              title: 'จัดการสินค้า',
              desc: 'เพิ่ม/แก้ไข/สต็อก/ตัวเลือกย่อย',
              color: cs.primary,
              onTapRoute: '/admin/products',
            ),
          ),
          _card(
            child: _actionTile(
              context,
              icon: Icons.local_offer_outlined,
              title: 'คูปอง',
              desc: 'สร้าง/ปิดใช้งานคูปอง',
              color: cs.primary,
              onTapRoute: '/admin/coupons',
            ),
          ),
        ].map((e) => SizedBox(width: w, child: e)).toList(),
      );
    });
  }

  // Top small icon grid: three circular tappable icons
  Widget _iconGrid(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _circleAction(context, Icons.receipt_long, 'Orders', '/admin/orders', cs.primary),
            _circleAction(context, Icons.inventory_2_outlined, 'Products', '/admin/products', cs.primary),
            _circleAction(context, Icons.local_offer_outlined, 'Coupons', '/admin/coupons', cs.primary),
            // Chat shortcut removed from admin dashboard (chat icon shown only on Home page)
          ],
        ),
      ),
    );
  }

  Widget _circleAction(BuildContext context, IconData icon, String label, String route, Color color) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.pushNamed(context, route),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withOpacity(.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _circleActionPush(BuildContext context, IconData icon, String label, VoidCallback onTap, Color color) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withOpacity(.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _actionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String desc,
    required Color color,
    required String onTapRoute,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.pushNamed(context, onTapRoute),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(desc,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(.65))),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget _statusChips(BuildContext context, Map<String, int> m) {
    Color c(String k) {
      switch (k) {
        case 'pending':
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

    final labels = ['pending', 'paid', 'shipped', 'completed', 'cancelled'];
    return _card(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: labels.map((k) {
          return Chip(
            avatar: CircleAvatar(backgroundColor: c(k), radius: 6),
            label: Text('$k · ${m[k] ?? 0}'),
          );
        }).toList(),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          t,
          style:
              Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      );

  Widget _grid(BuildContext context, List<Widget> tiles) {
    return LayoutBuilder(builder: (_, c) {
      final wide = c.maxWidth >= 720;
      final w = wide ? (c.maxWidth - 12) / 2 : c.maxWidth;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: tiles.map((e) => SizedBox(width: w, child: e)).toList(),
      );
    });
  }

  Widget _kpi(BuildContext context, IconData icon, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return _card(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: cs.onSurface.withOpacity(.65))),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _weeklyBar(BuildContext context, List<double> totals) {
    final cs = Theme.of(context).colorScheme;
    final maxV = totals.fold<double>(0, (p, v) => v > p ? v : p);
    final labels = const ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];

    return _card(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: SizedBox(
        height: 180,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(7, (i) {
            final h = maxV == 0 ? 0.0 : (totals[i] / maxV) * 120.0;
            return Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: h,
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(.85),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(labels[i], style: const TextStyle(fontSize: 12)),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) {
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(padding: padding, child: child),
    );
  }
}
