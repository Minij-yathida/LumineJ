// lib/pages/admin/admin_notifications_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AdminNotificationsPage extends StatefulWidget {
  const AdminNotificationsPage({super.key});

  @override
  State<AdminNotificationsPage> createState() =>
      _AdminNotificationsPageState();
}

class _AdminNotificationsPageState extends State<AdminNotificationsPage> {
  final _money = NumberFormat('#,##0.##', 'th_TH');

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    final days = diff.inDays;
    if (days < 7) return '$days days ago';
    return DateFormat('d MMM yyyy', 'en_US').format(dt);
  }

  String _statusToEnglish(String s) {
    final x = s.trim().toLowerCase();
    switch (x) {
      case 'read':
        return 'Read';
      case 'unread':
        return 'Unread';
      default:
        return 'Unread';
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFFDF5F2);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        top: false,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('notifications_admin')
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return const Center(child: Text('Error loading data'));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snap.data!.docs;
            if (docs.isEmpty) {
              return const _EmptyState();
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: docs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final d = docs[i];
                final data = d.data();
                final orderId = (data['orderId'] ?? '').toString();
                final title =
                    (data['title'] ?? 'New order').toString();
                final body = (data['body'] ?? '').toString();
                final total =
                    data['total'] ?? data['totalAmount'];
                final amount = total is num
                    ? _money.format(total)
                    : (total?.toString() ?? '');
                final ts = data['createdAt'] ?? data['timestamp'];
                final createdAt =
                    ts is Timestamp ? ts.toDate() : DateTime.now();
                final readableTime = _timeAgo(createdAt);
                final isUnread = data['read'] != true;

                final ink = const Color(0xFF4B3B35);
                final accent = const Color(0xFF8D6E63);
                final chipBg = isUnread
                    ? const Color(0xFFFFEDE6)
                    : Colors.grey.shade200;
                final chipTextColor =
                    isUnread ? accent : Colors.grey.shade700;
                final titleColor =
                    isUnread ? ink : ink.withOpacity(0.55);
                final subColor =
                    isUnread ? ink.withOpacity(0.9) : ink.withOpacity(0.55);

                return InkWell(
                  onTap: () async {
                    if (orderId.isNotEmpty) {
                      await _openOrderDetail(orderId);
                    }
                    if (isUnread) {
                      await d.reference.update({'read': true});
                    }
                  },
                  child: _notificationCard(
                    title: title,
                    message: body,
                    orderId: orderId.isNotEmpty ? orderId : null,
                    amount: amount,
                    status: isUnread ? 'Unread' : 'Read',
                    readableTime: readableTime,
                    isUnread: isUnread,
                    titleColor: titleColor,
                    subColor: subColor,
                    chipBg: chipBg,
                    chipTextColor: chipTextColor,
                    onDelete: () async {
                      final confirm =
                          await _showDeleteConfirmation(context);
                      if (confirm) {
                        await d.reference.delete();
                      }
                    },
                    onInfo: orderId.isNotEmpty
                        ? () async => _openOrderDetail(orderId)
                        : null,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ===== shared card / helpers (ยกมาจากของเดิม) =====

  Widget _notificationCard({
    required String title,
    required String message,
    String? orderId,
    String? amount,
    required String status,
    required String readableTime,
    required bool isUnread,
    required Color titleColor,
    required Color subColor,
    required Color chipBg,
    required Color chipTextColor,
    required VoidCallback onDelete,
    VoidCallback? onInfo,
  }) {
    const ink = Color(0xFF4B3B35);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
          color: Colors.brown.withOpacity(0.05),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isUnread
                        ? Colors.white
                        : const Color(0xFFF6F2F0),
                    border: Border.all(
                      color: Colors.brown.withOpacity(0.06),
                    ),
                  ),
                  child: Icon(
                    isUnread
                        ? Icons.notifications_active
                        : Icons.notifications_none_rounded,
                    color: isUnread
                        ? Colors.deepOrange
                        : const Color(0xFF6F4E44),
                    size: 20,
                  ),
                ),
                if (isUnread)
                  Positioned(
                    right: 2,
                    top: 4,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.deepOrange,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.length > 48
                        ? '${title.substring(0, 45)}...'
                        : title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: titleColor,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (orderId != null && orderId.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Order #$orderId',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: subColor,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (amount != null && amount.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Amount ฿$amount',
                        style: TextStyle(
                          fontSize: 13.5,
                          color: subColor,
                          height: 1.35,
                        ),
                      ),
                    ),
                  if (message.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        message.length > 120
                            ? '${message.substring(0, 117)}...'
                            : message,
                        style: TextStyle(
                          fontSize: 13,
                          color: subColor,
                          height: 1.25,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: chipBg,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: (isUnread
                                    ? chipTextColor
                                    : Colors.grey)
                                .withOpacity(0.12),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              status,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: chipTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(
                        Icons.schedule,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        readableTime,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: ink.withOpacity(0.65),
                        ),
                      ),
                      const Spacer(),
                      if (onInfo != null)
                        IconButton(
                          tooltip: 'View order details',
                          icon: const Icon(
                            Icons.info_outline,
                            color: Colors.grey,
                          ),
                          onPressed: onInfo,
                        ),
                      IconButton(
                        tooltip: 'Delete this notification',
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.grey,
                        ),
                        onPressed: onDelete,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _showDeleteConfirmation(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirm Delete'),
            content:
                const Text('Do you want to delete this notification?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _openOrderDetail(String orderId) async {
    // copy logic จากของเดิม (_openOrderDetail) มาทั้งก้อนได้เลย
    // ใช้ orders / products path เดิม ไม่แตะ route
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 72,
            color: Color(0xFFBCAAA4),
          ),
          SizedBox(height: 12),
          Text(
            'No notifications yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6F4E44),
            ),
          ),
          SizedBox(height: 6),
          Text(
            'We will notify you here when there are updates',
            style: TextStyle(
              fontSize: 13.5,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
