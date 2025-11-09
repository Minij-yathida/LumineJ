  import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AdminNotificationWatcher {
  static final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  static void start() {
    _sub?.cancel();

    _sub = FirebaseFirestore.instance
        .collection('notifications_admin')
        // ถ้า read == false หรือ field ไม่มี ให้ถือว่า unread
        .where('read', isEqualTo: false)
        .snapshots()
        .listen((snap) {
      unreadCount.value = snap.docs.length;
    }, onError: (e) {
      if (kDebugMode) {
        print('AdminNotificationWatcher error: $e');
      }
    });
  }

  static void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
