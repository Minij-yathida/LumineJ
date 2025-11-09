// lib/services/notifications_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationsRepo {
  NotificationsRepo();

  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('notifications');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// 🔴 Stream การแจ้งเตือนของผู้ใช้จาก top-level /notifications
  Stream<QuerySnapshot<Map<String, dynamic>>> streamFor(String uid) {
    return _col
        .where('userId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// 🟡 ตัวนับ unread แบบเรียลไทม์ (เผื่อใช้โชว์ badge)
  Stream<int> unreadCount(String uid) {
    return _col
        .where('userId', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .snapshots()
        .map((s) => s.size);
  }

  /// 🟢 เพิ่มแจ้งเตือนใหม่ให้ผู้ใช้ (อ่านจากแท็บ Notifications ได้ทันที)
  Future<void> addNotification({
    required String uid,
    required String title,
    required String body,
    String type = 'info',
    String? orderId,
    Map<String, dynamic>? extra,
  }) {
    return _col.add({
      'userId': uid,
      'title': title,
      'body': body,
      'type': type,
      'orderId': orderId,
      'extra': extra ?? {},
      'read': false, // ✅ ใช้ boolean แทน 'status'
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// ✨ สั้นๆ เวลาอยากใส่แค่ title/body
  Future<void> addSimple({
    required String uid,
    required String title,
    required String body,
  }) {
    return addNotification(uid: uid, title: title, body: body);
  }

  /// ✅ แตะรายการ → ทำเป็นอ่านแล้ว
  Future<void> markRead(String id) async {
    await _col.doc(id).update({'read': true});
  }

  /// ✅ ทำเป็นอ่านแล้วทั้งหมดของผู้ใช้
  Future<void> markAllRead(String uid) async {
    final q = await _col
        .where('userId', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .get();
    final batch = _db.batch();
    for (final d in q.docs) {
      batch.update(d.reference, {'read': true});
    }
    await batch.commit();
  }
}
