// lib/services/notifications_watcher.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

import 'notification_service.dart';
import 'push_routing.dart';

class NotificationWatcher extends StatefulWidget {
  final Widget child;
  const NotificationWatcher({super.key, required this.child});

  static final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  static Future<void> markAllRead() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final fs = FirebaseFirestore.instance;
    // Fetch recent alerts and update any that are not marked read.
    // We can't reliably use a single where() because some documents use
    // a boolean `read` field while others use `status: 'read'|'unread'`.
    final col = fs.collection('users').doc(uid).collection('alerts');
    final q = await col.limit(500).get();

    final batch = fs.batch();
    for (final d in q.docs) {
      final data = d.data();
      final bool needsUpdate = data.containsKey('status')
          ? (data['status']?.toString() != 'read')
          : ((data['read'] as bool?) != true);
      if (needsUpdate) {
        if (data.containsKey('status')) {
          batch.update(d.reference, {'status': 'read'});
        } else {
          batch.update(d.reference, {'read': true});
        }
      }
    }
    await batch.commit();
    // ensure UI badge updates immediately
    NotificationWatcher.unreadCount.value = 0;
  }

  @override
  State<NotificationWatcher> createState() => _NotificationWatcherState();
}

class _NotificationWatcherState extends State<NotificationWatcher>
    with WidgetsBindingObserver {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  String? _uid;
  bool _skippedFirst = false;
  final Set<String> _seenIds = <String>{};
  // Recent shown messages keyed by title||body -> timestamp. Used to
  // deduplicate notifications that have identical content arriving from
  // multiple sources (FCM + Firestore writes).
  final Map<String, DateTime> _recentShown = <String, DateTime>{};
  bool _isForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Track initial lifecycle state: assume foreground unless told otherwise
    try {
      _isForeground = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    } catch (_) {
      _isForeground = true;
    }
    _attach();
    FirebaseAuth.instance.userChanges().listen((_) => _attach());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // track foreground/background so we only show system/local notifications
    // when the app is backgrounded. When foreground, the app UI should
    // present in-app banners/dialogs instead.
    _isForeground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) _attach();
  }

  void _attach() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _detach();
      NotificationWatcher.unreadCount.value = 0;
      return;
    }
    if (_uid == uid && _sub != null) return;

    _detach();
    _uid = uid;
    _skippedFirst = false;
    _seenIds.clear();

    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('alerts') // ← ถ้าอยากใช้ notifications ก็เปลี่ยนตรงนี้
        .orderBy('createdAt', descending: true)
        .limit(30)
        .snapshots()
        .listen(_onSnapshot, onError: (_) {
      NotificationWatcher.unreadCount.value = 0;
    });
  }

  void _detach() {
    _sub?.cancel();
    _sub = null;
    _uid = null;
  }

  Future<void> _onSnapshot(
      QuerySnapshot<Map<String, dynamic>> snap) async {
    // Debug: log snapshot arrival
    try {
      // ignore: avoid_print
      print('NotificationWatcher: snapshot received, docCount=${snap.docs.length}');
    } catch (_) {}

    // นับยังไม่อ่าน (รองรับทั้ง read/status)
    final unread = snap.docs.where((d) {
      final data = d.data();
      if (data.containsKey('status')) return data['status'] != 'read';
      return data['read'] != true;
    }).length;
    NotificationWatcher.unreadCount.value = unread;
    try {
      // ignore: avoid_print
      print('NotificationWatcher: unreadCount updated -> $unread');
    } catch (_) {}

    // ข้าม batch แรกที่เป็นของเก่า
    if (!_skippedFirst) {
      _skippedFirst = true;
      return;
    }

    for (final change in snap.docChanges) {
      if (change.type != DocumentChangeType.added) continue;

      final doc = change.doc;
      if (_seenIds.contains(doc.id)) continue;
      _seenIds.add(doc.id);

      final data = doc.data() ?? {};
      // ปรับแต่งข้อความแจ้งเตือนให้ละเอียดและจัดรูปแบบ
      final orderId = data['orderId'] ?? data['order_id'] ?? '';
      final amount = data['amount'] ?? data['price'] ?? '';
      final status = data['statusText'] ?? data['status'] ?? '';
      final title = (data['title'] ?? 'แจ้งเตือน').toString();
      final bodyRaw = (data['body'] ?? '').toString();

      // สร้างข้อความแจ้งเตือนแบบละเอียด
      String body = bodyRaw;
      if (orderId != '' && amount != '' && status != '') {
        body = 'ออเดอร์ $orderId\nยอดชำระ $amount บาท\nสถานะ: $status';
      } else if (orderId != '' && amount != '') {
        body = 'ออเดอร์ $orderId\nยอดชำระ $amount บาท';
      } else if (orderId != '') {
        body = 'ออเดอร์ $orderId';
      } else if (bodyRaw.isEmpty) {
        body = 'คุณมีการแจ้งเตือนใหม่';
      }

      // เพิ่ม delay เล็กน้อยเพื่อหลีกเลี่ยงการแสดงทับ FloatingActionButton (เช่น ไอคอนตะกร้า)
      await Future.delayed(const Duration(milliseconds: 600));

      // Deduplicate by exact (title+body) within a short window to avoid
      // showing duplicate device notifications when the server both
      // pushes an FCM notification and writes an alerts document.
      try {
        final key = '$title||$body';
        // purge old entries (window = 5 minutes)
        final now = DateTime.now();
        _recentShown.removeWhere((k, v) => now.difference(v) > const Duration(minutes: 5));
        if (_recentShown.containsKey(key)) {
          // already shown recently -> skip
          // ignore: avoid_print
          print('NotificationWatcher: skipping duplicate notification for doc=${doc.id} (duplicate title/body)');
        } else {
          // Show a system/local notification for new alerts.
          // Debug: log that we will attempt to show local notification
          // ignore: avoid_print
          print('NotificationWatcher: showing local notification for doc=${doc.id} title="$title" body="$body" (isForeground=$_isForeground)');
          await NotificationService.instance.show(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            title: title,
            body: body,
            payload: 'tab=notifications',
          );
          _recentShown[key] = now;
          // ignore: avoid_print
          print('NotificationWatcher: NotificationService.show completed for doc=${doc.id}');
        }
      } catch (e) {
        // ignore: avoid_print
        print('NotificationWatcher: NotificationService.show threw: $e');
      }
      // Decide whether to auto-open notifications tab for important alerts
      try {
        final lowerTitle = title.toLowerCase();
        final lowerBody = body.toLowerCase();
        final lowerType = (data['type'] ?? '').toString().toLowerCase();

        bool shouldOpen = false;

        // 1) Payment confirmation: type contains 'order' and status == 'paid'
        final statusField = (data['status'] ?? '').toString().toLowerCase();
        if (lowerType.contains('order') && statusField == 'paid') shouldOpen = true;

        // 2) Title/body contains keywords about payment confirmation
        if (lowerTitle.contains('ยืนยัน') && lowerBody.contains('ชำระ')) shouldOpen = true;

        // 3) Coupon assignment: title/type/body mentions 'คูปอง' or 'coupon'
        if (lowerTitle.contains('คูปอง') || lowerBody.contains('คูปอง') || lowerType.contains('coupon') || lowerTitle.contains('coupon')) shouldOpen = true;

        if (shouldOpen && _isForeground) {
          // navigate to notifications tab
          PushRouting.openNotificationsTab(context);
        }
      } catch (_) {}
      // Don't auto-mark as read to ensure badge shows up
      // Notifications will be marked as read when user views them or uses markAllRead()
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
