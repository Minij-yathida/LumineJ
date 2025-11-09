// lib/pages/customer/notifications_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/notifications_watcher.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage>
    with SingleTickerProviderStateMixin {
  final _money = NumberFormat('#,##0.##', 'th_TH');
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;
  VoidCallback? _unreadListener;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );

    // ใช้ NotificationWatcher สำหรับฝั่งลูกค้า
    _unreadListener = () {
      final cnt = NotificationWatcher.unreadCount.value;
      if (cnt > 0) {
        if (!_pulseController.isAnimating) {
          _pulseController.repeat(reverse: true);
        }
      } else {
        if (_pulseController.isAnimating) {
          _pulseController.stop();
        }
        _pulseController.reset();
      }
    };

    NotificationWatcher.unreadCount.addListener(_unreadListener!);

    if (NotificationWatcher.unreadCount.value > 0) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    if (_unreadListener != null) {
      NotificationWatcher.unreadCount.removeListener(_unreadListener!);
    }
    _pulseController.dispose();
    super.dispose();
  }

  // ================= Utils =================

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
      case 'pending':
      case 'รอดำเนินการ':
      case 'รอชำระเงิน':
        return 'Pending';
      case 'paid':
      case 'ชำระเงินแล้ว':
        return 'Paid';
      case 'shipped':
      case 'กำลังจัดส่ง':
        return 'Shipped';
      case 'completed':
      case 'จัดส่งสำเร็จแล้ว':
        return 'Completed';
      case 'cancelled':
      case 'ถูกยกเลิก':
        return 'Cancelled';
      case 'read':
        return 'Read';
      case 'unread':
        return 'Unread';
      default:
        return 'Processing';
    }
  }

  // ================= Build =================

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFFDF5F2);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        backgroundColor: bg,
        body: Center(child: Text('Please sign in')),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      // ไม่มี AppBar ในหน้านี้ ให้หน้าหลักเป็นคนวาง
      body: SafeArea(
        top: false,
        child: _buildUserNotifications(uid),
      ),
    );
  }

  // ================= USER (ลูกค้า) =================

  Widget _buildUserNotifications(String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('alerts')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Text('Error loading data'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allDocs = snap.data!.docs;

        // 1) กรองไม่เอาแชท
        final filtered = allDocs.where((d) {
          final raw = d.data();
          final type = raw['type']?.toString().toLowerCase();
          final hasThread =
              raw.containsKey('threadId') || raw.containsKey('chatId');
          final title = (raw['title']?.toString().toLowerCase()) ?? '';

          if (type == 'chat' ||
              hasThread ||
              title.contains('chat') ||
              title.contains('แชท')) {
            return false;
          }
          return true;
        }).toList();

        // 2) รวมตาม order / title
        final Map<String, Map<String, dynamic>> agg = {};

        String resolveOrderId(Map<String, dynamic> m) {
          final keys = [
            'orderId',
            'order_id',
            'order',
            'orderRef',
            'orderRefId',
            'reference',
            'referenceId',
            'orderNumber',
            'orderNo',
            'ref',
          ];
          for (final k in keys) {
            final v = m[k];
            if (v != null) {
              final s = v.toString().trim();
              if (s.isNotEmpty) return s;
            }
          }
          final combined = '${m['message'] ?? ''} ${m['title'] ?? ''}';
          final reg = RegExp(
            r'order\s*#?\s*([A-Za-z0-9\-_]{6,})',
            caseSensitive: false,
          );
          final match = reg.firstMatch(combined);
          if (match != null && match.groupCount >= 1) {
            return match.group(1)!.trim();
          }
          return '';
        }

        for (final d in filtered) {
          final map = Map<String, dynamic>.from(d.data());
          final resolvedOrderId = resolveOrderId(map);
          final normalizedTitle =
              (map['title'] ?? '').toString().trim().toLowerCase();

          final key = resolvedOrderId.isNotEmpty
              ? 'ORDER|$resolvedOrderId'
              : (normalizedTitle.isNotEmpty
                  ? 'TITLE|$normalizedTitle'
                  : 'MISC|${d.id}');

          if (!agg.containsKey(key)) {
            agg[key] = {
              'sources': <QueryDocumentSnapshot<Map<String, dynamic>>>[d],
              'data': map,
            };
          } else {
            (agg[key]!['sources']
                    as List<QueryDocumentSnapshot<Map<String, dynamic>>>)
                .add(d);

            final existing = agg[key]!['data'] as Map<String, dynamic>;
            final oldMsg = (existing['message'] ?? '').toString();
            final newMsg = (map['message'] ?? '').toString();

            if (newMsg.isNotEmpty && !oldMsg.contains(newMsg)) {
              existing['message'] =
                  oldMsg.isEmpty ? newMsg : '$oldMsg\n$newMsg';
            }
            if (existing['amount'] == null && map['amount'] != null) {
              existing['amount'] = map['amount'];
            }
          }
        }

        final entries = agg.values.toList();
        if (entries.isEmpty) return const _EmptyState();

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final entry = entries[i];
            final sources =
              List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
              entry['sources']
                as List<QueryDocumentSnapshot<Map<String, dynamic>>>,
            );
            final data = Map<String, dynamic>.from(entry['data']);

            final orderId = (data['orderId'] ?? '').toString();

            String title;
            String message = (data['message'] ?? '').toString().trim();

            if (orderId.isNotEmpty) {
              if (sources.length >= 2) {
              title = 'Order placed';
              message =
                'Thanks for your purchase! Please wait for payment verification.';
              } else {
              final t = (data['title'] ?? '').toString().trim();
                if (t.isEmpty || t.contains('สั่งซื้อ')) {
                  title = 'Order placed';
                } else {
                  title = t;
                }

                if (message.contains('โปรดรอยืนยัน') ||
                    message.contains('กำลังดำเนินการ')) {
                  message = 'Please wait for payment verification.';
                }
                if (message.isEmpty) {
                  message =
                      'Thanks for your purchase! We\'re processing your order.';
                }
              }
            } else {
              final t = (data['title'] ?? '').toString().trim();
              title = t.isNotEmpty ? t : 'กล่องข้อความ';
            }

            final rawAmount = data['amount'];
            final amount = rawAmount is num
                ? _money.format(rawAmount)
                : (rawAmount?.toString() ?? '');
            final status =
                _statusToEnglish((data['status'] ?? '').toString());
            final ts = data['createdAt'];
            final createdAt =
                ts is Timestamp ? ts.toDate() : DateTime.now();
            final readableTime = _timeAgo(createdAt);

            final isUnread = status.toLowerCase() != 'read';
            final ink = const Color(0xFF4B3B35);
            final accent = const Color(0xFF8D6E63);
            final chipBg = isUnread
                ? const Color(0xFFFFEDE6)
                : Colors.grey.shade200;
            final chipTextColor =
                isUnread ? accent : Colors.grey.shade700;
            final titleColor = isUnread ? ink : ink.withOpacity(0.55);
            final subColor =
                isUnread ? ink.withOpacity(0.9) : ink.withOpacity(0.55);

            return InkWell(
              onTap: () async {
                if (orderId.isNotEmpty) {
                  await _openOrderDetail(orderId);
                  await _markAggregatedAsRead(uid, sources);
                } else {
                  await _markAggregatedAsRead(uid, sources);
                }
              },
              child: _notificationCard(
                title: title,
                message: message,
                orderId: orderId,
                amount: amount,
                status: status,
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
                    await _deleteAggregated(uid, sources);
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
    );
  }

  // ================= Shared Card UI / Helpers (เหมือนเดิม) =================

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

  // ================= Helper Actions (USER only) =================

  Future<bool> _showDeleteConfirmation(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirm Delete'),
            content: const Text(
                'Do you want to delete this notification?'),
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
    // ... (เหมือนของเดิมทั้งหมด) ...
    // ไม่แก้ path / logic เพื่อนไม่ให้ route พัง
  }

  Future<void> _markAggregatedAsRead(
    String uid,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sources,
  ) async {
    // ... (เหมือนเดิม) ...
  }

  Future<void> _deleteAggregated(
    String uid,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sources,
  ) async {
    // ... (เหมือนเดิม) ...
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
