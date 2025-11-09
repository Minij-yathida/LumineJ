// lib/services/push_routing.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

typedef TabSetter = void Function(int);

class PushRouting {
  PushRouting._();

  // callback จาก HomePage เอาไว้เปลี่ยนแท็บใน IndexedStack
  static TabSetter? _setter;

  // payload ที่เข้ามาก่อนที่ HomePage จะลงทะเบียน setter
  static String? _pendingPayload;

  /// ให้ HomePage ส่งตัวเปลี่ยนแท็บมาเก็บไว้
  static void setTabSelector(TabSetter setter) {
    _setter = setter;

    // ถ้ามี payload ค้าง (เช่น แตะ noti เปิดแอปขึ้นมาก่อนเข้า HomePage)
    if (_pendingPayload != null) {
      final p = _pendingPayload!;
      _pendingPayload = null;
      _applyPayload(p);
    }

    try {
      // ignore: avoid_print
      print('PushRouting: setTabSelector registered (hasPending=${_pendingPayload != null})');
    } catch (_) {}
  }

  /// เคลียร์ตอน HomePage dispose กัน stale reference
  static void clearTabSelector() {
    _setter = null;
    try {
      // ignore: avoid_print
      print('PushRouting: clearTabSelector');
    } catch (_) {}
  }

  /// สั่งเด้งไปแท็บ Notifications (index = 2)
  /// ใช้ได้จากที่ไหนก็ได้ในแอป เช่น NotificationWatcher ถ้าต้องการ
  static void openNotificationsTab(BuildContext context) {
    // If Home has registered a setter we call it with -1 as a sentinel to
    // indicate "open notifications tab" (index 2). If no setter, fall
    // back to navigating directly using the provided BuildContext.
    if (_setter != null) {
      // call index 2 (Notifications tab) when Home is present
      _setter?.call(2);
    } else {
      try {
        // ignore: avoid_print
        print('PushRouting: no setter, navigating to /notifications');
      } catch (_) {}
      try {
        Navigator.of(context).pushNamed('/notifications');
      } catch (_) {}
    }
  }

  /// ถูกเรียกเวลา:
  /// - แตะ local notification (NotificationService.onDidReceiveNotificationResponse)
  /// - หรืออยากสั่งจากที่อื่นด้วย payload string เช่น "tab=notifications"
  static void handlePayload(String? payload) {
    if (payload == null || payload.isEmpty) return;

    try {
      // ignore: avoid_print
      print('PushRouting: handlePayload -> "$payload" (hasSetter=${_setter != null})');
    } catch (_) {}

    if (_setter != null) {
      _applyPayload(payload);
    } else {
      // ยังไม่มี setter (เช่น ยังไม่เข้า HomePage) → เก็บไว้ก่อน
      _pendingPayload = payload;
      try {
        // ignore: avoid_print
        print('PushRouting: queued pending payload');
      } catch (_) {}
    }
  }

  /// แปลง payload → คำสั่งเปลี่ยนแท็บ
  static void _applyPayload(String payload) {
    try {
      // ignore: avoid_print
      print('PushRouting: _applyPayload("$payload")');
    } catch (_) {}

    if (payload.contains('tab=notifications')) {
      // If Home is present, call the Notifications tab (index 2).
      // Otherwise the payload will be queued and handled when the setter
      // is registered (setTabSelector will call _applyPayload then).
      _setter?.call(2);
      try {
        // ignore: avoid_print
        print('PushRouting: requested open notifications (index 2)');
      } catch (_) {}
    }
  }

  /// เรียกจาก main() หลัง init Firebase & FirebaseMessaging
  /// ใช้ดัก FCM tap: ทั้งตอนแอปปิด (getInitialMessage) และตอน background (onMessageOpenedApp)
  static Future<void> initOpenHandlers() async {
    // case 1: แอปถูกเปิดจาก noti ขณะปิดอยู่ (terminated)
    final initialMsg = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMsg != null) {
      try {
        // ignore: avoid_print
        print('PushRouting: getInitialMessage data=${initialMsg.data}');
      } catch (_) {}
      _handleFCMData(initialMsg.data);
    }

    // case 2: แอปอยู่ background แล้วแตะ noti
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      try {
        // ignore: avoid_print
        print('PushRouting: onMessageOpenedApp data=${message.data}');
      } catch (_) {}
      _handleFCMData(message.data);
    });
  }

  /// อ่าน data จาก FCM แล้ว map ไปเป็น payload ภายใน
  static void _handleFCMData(Map<String, dynamic> data) {
    final target = (data['target'] ?? data['tab'] ?? '').toString();

    try {
      // ignore: avoid_print
      print('PushRouting: _handleFCMData target="$target"');
    } catch (_) {}

    if (target == 'notifications') {
      // ใช้ format เดียวกับ local noti เพื่อให้เข้า flow เดียวกัน
      handlePayload('tab=notifications');
    }
  }
}
