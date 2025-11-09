// lib/services/notification_service.dart
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
    // ตั้งค่าเฉพาะ Android
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    // register tap/open handler so payloads can be routed into the app
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse resp) async {
        try {
          final payload = resp.payload;
          // debug
          try {
            // ignore: avoid_print
            print('NotificationService: onDidReceiveNotificationResponse payload="$payload"');
          } catch (_) {}
          if (payload != null) PushRouting.handlePayload(payload);
        } catch (_) {}
      },
    );

    // ---------- สร้าง Notification Channel ----------
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

    // ---------- ขอสิทธิ์การแจ้งเตือน (Android 13+) ----------
    try {
      await (androidPlugin as dynamic).requestPermission();
      // ignore: avoid_print
      print('NotificationService: requested Android notification permission');
    } catch (_) {
      try {
        await (androidPlugin as dynamic).requestNotificationsPermission();
        // ignore: avoid_print
        print('NotificationService: requested Android notification permission (fallback)');
      } catch (_) {}
    }

    // If the app was launched by tapping a notification, capture its payload
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      final payload = details?.notificationResponse?.payload;
      if (payload != null) {
        try {
          // ignore: avoid_print
          print('NotificationService: app launched from notification payload="$payload"');
        } catch (_) {}
        PushRouting.handlePayload(payload);
      }
    } catch (_) {}
  }

  /// แสดงแจ้งเตือนแบบสั้น
  Future<void> showSimple({
    required String title,
    required String body,
    String? payload,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await show(id: id, title: title, body: body, payload: payload);
  }

  /// แจ้งเตือนแบบกำหนด id เอง
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
}
