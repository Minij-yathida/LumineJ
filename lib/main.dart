// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

// === การแก้ไขที่สำคัญ: ต้อง Import ไฟล์นี้! ===
import 'firebase_options.dart'; 

import 'services/auth_service.dart';
import 'services/cart_provider.dart';
import 'services/notification_service.dart';
import 'services/push_routing.dart';
import 'services/notifications_watcher.dart';

import 'pages/auth/login_page.dart';
import 'pages/auth/register_page.dart';
import 'pages/customer/home_page.dart';
import 'pages/customer/cart_page.dart';
import 'pages/customer/search_page.dart';
import 'pages/customer/checkout_page.dart';
import 'pages/customer/coupon_page.dart';
import 'pages/profile/unified_profile_page.dart';
import 'pages/admin/admin_page.dart';
import 'pages/admin/product_management_page.dart';
import 'pages/product_overview_page.dart';
import 'pages/customer/notifications_page.dart';
import 'chat/chat_page.dart';
import 'pages/customer/order_tracking_page.dart';
import 'pages/admin/add_coupon_page.dart';
import 'pages/customer/orders_page.dart';

final AuthService _authService = AuthService();

/// 🟡 Background handler: ห้ามเรียก UI / plugin ที่ยังไม่รองรับ
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // *** สำคัญ: ต้องใส่ options ใน initializeApp() ในทุก entry point ***
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform); 
}

Future<void> _initFirebaseAndMessaging() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // === แก้ไข: ใส่ options เพื่อเชื่อมต่อกับ Project ID ที่ถูกต้อง ===
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, 
  );

  // 🟢 Local notifications (ใช้ตอน onMessage + จาก NotificationWatcher)
  await NotificationService.instance.init();

  // Debug: print FCM token (helpful to verify device registered)
  try {
    final tok = await FirebaseMessaging.instance.getToken();
    // ignore: avoid_print
    print('FCM token: $tok');
  } catch (e) {
    // ignore: avoid_print
    print('Failed to get FCM token: $e');
  }

  // ล้าง noti ค้าง (ป้องกัน noti เก่า ๆ กอง)
  await NotificationService.instance.cancelAll();

  // ขอสิทธิ์แจ้งเตือน
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // เมื่อมี FCM เข้ามาตอนแอพ foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    final title = message.notification?.title ?? 'แจ้งเตือน';
    final body = message.notification?.body ?? '';

    // Debug
    // ignore: avoid_print
    print('FCM onMessage: $title | $body');

    // NOTE: Centralized notification display — do NOT call the local
    // NotificationService here. Instead we record the alert in Firestore
    // and let NotificationWatcher (single source) show the device
    // notification. This prevents duplicated device notifications.

    // บันทึกเก็บใน alerts ของ user สำหรับหน้า NotificationsPage
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final ref = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('alerts')
          .add({
        'title': title,
        'body': body,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Also write an ingest entry so backend processors definitely see it
      try {
        await FirebaseFirestore.instance.collection('backend_ingest').doc(ref.id).set({
          'alertId': ref.id,
          'userId': uid,
          'type': 'push_fcm_alert',
          'title': title,
          'body': body,
          'createdAt': FieldValue.serverTimestamp(),
          'processed': false,
        });
      } catch (_) {}
    }
  });

  // Background FCM handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // ถ้ามี user อยู่แล้ว → sync FCM token เข้าบัญชี
  final u = FirebaseAuth.instance.currentUser;
  if (u != null) {
    await _authService.initPushNotificationsForCurrentUser();
  }

  // ดักกรณีแตะ FCM เพื่อเปิดแอพ / กลับเข้าแอพ
  await PushRouting.initOpenHandlers();
}

Future<void> main() async {
  await _initFirebaseAndMessaging();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CartProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return NotificationWatcher(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Jewelry Shop',
        locale: const Locale('th', 'TH'),
        supportedLocales: const [
          Locale('th', 'TH'),
          Locale('en', 'US'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF8D6E63),
          scaffoldBackgroundColor: const Color(0xFFFFF8F5),
          fontFamily: 'Roboto',
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFFFF8F5),
            foregroundColor: Color(0xFF4E342E),
            elevation: 0,
          ),
        ),
        initialRoute: '/login',
        routes: {
          '/login': (_) => const LoginPage(),
          '/register': (_) => const RegisterPage(),
          '/home': (_) => const HomePage(),
          '/cart': (_) => const CartPage(),
          '/search': (_) => const SearchPage(),
          '/profile': (_) => const UnifiedProfilePage(),
          '/notifications': (_) => const NotificationsPage(),
          '/chat': (_) => const ChatPage(asStore: true,),
          '/products': (_) => const ProductOverviewPage(),
          '/admin': (_) => const AdminPage(),
          '/admin/product_manage': (_) => const ProductManagementPage(),
          '/admin/coupons': (_) => const AddCouponPage(),
          '/orders': (_) => const OrdersPage(),
          '/checkout': (_) => const CheckoutPage(),
          '/order-tracking': (_) => const OrderTrackingPage(),
          '/coupons': (_) => CouponsPage(),
        },
      ),
    );
  }
}