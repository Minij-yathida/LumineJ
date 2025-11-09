// lib/services/notification_service.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'push_routing.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'default_channel_id';
  static const String _channelName = 'General';
  static const String _channelDescription = 'General notifications';

  /// เรียกครั้งเดียวตอนเปิดแอป (main.dart)
  Future<void> init() async {
    // Android init
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse:
          (NotificationResponse resp) async {
        final payload = resp.payload;
        if (payload != null && payload.isNotEmpty) {
          try {
            // debug
            // ignore: avoid_print
            print(
                'NotificationService: onTap payload="$payload"');
          } catch (_) {}

          await _handlePayloadAndRoute(payload);
        }
      },
    );

    // ---------- Create Notification Channel ----------
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
        playSound: true,
      ),
    );

    // ---------- Android 13+ permission ----------
    try {
      await (androidPlugin as dynamic).requestPermission();
      // ignore: avoid_print
      print('NotificationService: requested Android permission');
    } catch (_) {
      try {
        await (androidPlugin as dynamic).requestNotificationsPermission();
        // ignore: avoid_print
        print(
            'NotificationService: requested Android permission (fallback)');
      } catch (_) {}
    }

    // ---------- If app launched from notification ----------
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      final payload = details?.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        try {
          // ignore: avoid_print
          print(
              'NotificationService: launched from notification payload="$payload"');
        } catch (_) {}
        await _handlePayloadAndRoute(payload);
      }
    } catch (_) {}
  }

  /// ใช้ตอนสร้าง local notification ทั่วไป
  Future<void> showSimple({
    required String title,
    required String body,
    String? payload,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await show(id: id, title: title, body: body, payload: payload);
  }

  /// แสดงแจ้งเตือน + แนบ payload
  ///
  /// ✅ แนะนำให้ payload เป็น JSON string:
  /// {
  ///   "type": "order",
  ///   "orderId": "...",
  ///   "alertPath": "users/UID/alerts/ALERT_ID"
  /// }
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.message,
      styleInformation: BigTextStyleInformation(''),
      playSound: true,
    );

    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(id, title, body, details, payload: payload);
  }

  Future<void> cancelAll() => _plugin.cancelAll();
  Future<void> cancel(int id) => _plugin.cancel(id);

  // ================= INTERNAL =================

  /// handle tap: mark alert as read (ถ้ามีข้อมูล) แล้วค่อย route
  Future<void> _handlePayloadAndRoute(String payload) async {
    try {
      Map<String, dynamic>? data;

      final trimmed = payload.trim();
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        data = json.decode(trimmed) as Map<String, dynamic>;
      }

      String? alertPath = data?['alertPath'] ?? data?['alertDocPath'];
      String? alertId = data?['alertId'];
      String? userId = data?['userId'];

      // ถ้า payload ให้มาแค่ alertId ให้เดาว่าอยู่ใต้ users/{uid}/alerts
      userId ??= FirebaseAuth.instance.currentUser?.uid;

      if (alertPath == null && alertId != null && userId != null) {
        alertPath = 'users/$userId/alerts/$alertId';
      }

      if (alertPath != null) {
        final ref = FirebaseFirestore.instance.doc(alertPath);
        await ref.set(
          {
            'read': true,
            'status': 'read',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    } catch (e) {
      // ignore: avoid_print
      print('NotificationService: _handlePayload error: $e');
    }

    // สุดท้าย route ตาม payload เดิม (ไม่ไปยุ่ง logic เดิมของนาย)
    try {
      PushRouting.handlePayload(payload);
    } catch (_) {}
  }
}
