// lib/services/auth_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --------------------------- USER MANAGEMENT ---------------------------

  // 1. สร้างเอกสารผู้ใช้ใหม่หลังสมัคร
  Future<void> createUserDocument(
    User user, {
    String role = 'customer',
    required String displayName,
    required String phoneNumber,
    required String address,
  }) async {
    final userDoc = _firestore.collection('users').doc(user.uid);
    final data = {
      'uid': user.uid,
      'email': user.email,
      'role': role,
      'displayName': displayName,
      'phoneNumber': phoneNumber,
      'address': address,
      'createdAt': FieldValue.serverTimestamp(),
    };
    try {
      await userDoc.set(data, SetOptions(merge: true));
      // ลงทะเบียน FCM token (ถ้ามี)
      await initPushNotificationsForCurrentUser();
    } catch (e) {
      print('Error creating user document: $e');
    }
  }

  // 2. ดึงข้อมูลโปรไฟล์จาก Firestore (พร้อม fallback จาก FirebaseAuth)
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      final user = _auth.currentUser;
      if (!doc.exists) {
        // ไม่มี doc → ใช้ข้อมูลจาก FirebaseAuth
        return {
          'displayName': user?.displayName,
          'email': user?.email,
          'phoneNumber': user?.phoneNumber,
          'address': '',
          'profileIcon': null,
        };
      }

      final data = doc.data()!;
      return {
        'displayName': data['displayName'] ?? user?.displayName,
        'email': data['email'] ?? user?.email,
        'phoneNumber': data['phoneNumber'] ?? user?.phoneNumber,
        'address': data['address'] ?? '',
        'profileIcon': data['profileIcon'],
        'role': data['role'] ?? 'customer',
      };
    } catch (e) {
      print('Error fetching user profile: $e');
      return null;
    }
  }

  // 3. ดึง role ของ user
  Future<String> getUserRole(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        return (doc.data()!['role'] as String?) ?? 'customer';
      }
      return 'customer';
    } catch (e) {
      print('Error fetching user role: $e');
      return 'customer';
    }
  }

  // 4. ออกจากระบบ
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // 5. อัปเดตโปรไฟล์
  Future<void> updateUserProfile(String uid, Map<String, dynamic> dataToUpdate) async {
    try {
      await _firestore.collection('users').doc(uid).set(
        {
          ...dataToUpdate,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      print('Error updating user profile: $e');
      rethrow;
    }
  }

  // --------------------------- PRODUCTS ---------------------------
  Stream<QuerySnapshot> getProductsStream() {
    return _firestore.collection('products').orderBy('name').snapshots();
  }

  Future<void> addProduct(Map<String, dynamic> productData) async {
    await _firestore.collection('products').add(productData);
  }

  Future<void> updateProduct(String productId, Map<String, dynamic> productData) async {
    await _firestore.collection('products').doc(productId).update(productData);
  }

  Future<void> deleteProduct(String productId) async {
    await _firestore.collection('products').doc(productId).delete();
  }

  // --------------------------- PUSH TOKEN (ฟรี, ถ้ามี FCM) ---------------------------
  Future<void> initPushNotificationsForCurrentUser() async {
    try {
      final u = _auth.currentUser;
      if (u == null) return;

      final fcm = FirebaseMessaging.instance;

      // ขออนุญาต (Android 13+/iOS)
      await fcm.requestPermission(alert: true, badge: true, sound: true);

      final token = await fcm.getToken();
      if (token != null) {
        await _firestore
            .collection('users')
            .doc(u.uid)
            .collection('fcmTokens')
            .doc(token)
            .set({
          'token': token,
          'createdAt': FieldValue.serverTimestamp(),
          'platform': 'flutter',
        }, SetOptions(merge: true));
      }

      // อัปเดต token เมื่อ refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
        await _firestore
            .collection('users')
            .doc(u.uid)
            .collection('fcmTokens')
            .doc(t)
            .set({
          'token': t,
          'refreshedAt': FieldValue.serverTimestamp(),
          'platform': 'flutter',
        }, SetOptions(merge: true));
      });
    } catch (e) {
      // ถ้าไม่ได้เปิดใช้ FCM ก็เงียบไว้ (ไม่บังคับใช้)
      print('initPushNotificationsForCurrentUser skipped: $e');
    }
  }
}

// Instance ใช้งานทั่วแอป
final AuthService authService = AuthService();

Future<String> getUserRole() async {
  final user = authService._auth.currentUser;
  if (user == null) return 'guest';
  return authService.getUserRole(user.uid);
}
