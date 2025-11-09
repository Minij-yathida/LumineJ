import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminNotificationService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Create a new notification for admin when a new order is placed
  static Future<void> notifyNewOrder({
    required String orderId,
    required String customerId,
    required double totalAmount,
  }) async {    try {
      await _firestore.collection('admin_notifications').add({
        'type': 'new_order',
        'orderId': orderId,
        'customerId': customerId,
        'totalAmount': totalAmount,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'status': 'unread'
      });
    } catch (e) {
      print('Error creating admin notification: $e');
    }
  }

  /// Mark a notification as read
  static Future<void> markAsRead(String notificationId) async {
    try {
      await _firestore
          .collection('admin_notifications')
          .doc(notificationId)
          .update({
        'read': true,
        'status': 'read'
      });
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  /// Delete a notification
  static Future<void> deleteNotification(String notificationId) async {
    try {
      await _firestore
          .collection('admin_notifications')
          .doc(notificationId)
          .delete();
    } catch (e) {
      print('Error deleting notification: $e');
    }
  }

  /// Mark all notifications as read
  static Future<void> markAllAsRead() async {
    try {
      final QuerySnapshot notifications = await _firestore
          .collection('admin_notifications')
          .where('read', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (var doc in notifications.docs) {
        batch.update(doc.reference, {
          'read': true,
          'status': 'read'
        });
      }
      await batch.commit();
    } catch (e) {
      print('Error marking all notifications as read: $e');
    }
  }

  /// Delete all notifications
  static Future<void> deleteAllNotifications() async {
    try {
      final QuerySnapshot notifications =
          await _firestore.collection('admin_notifications').get();

      final batch = _firestore.batch();
      for (var doc in notifications.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      print('Error deleting all notifications: $e');
    }
  }

  /// Get stream of admin notifications
  static Stream<QuerySnapshot> getNotificationsStream() {
    return _firestore
        .collection('admin_notifications')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  /// Get unread notifications count
  static Stream<int> getUnreadCount() {
    return _firestore
        .collection('admin_notifications')
        .where('read', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.size);
  }
}
