import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Manages watching for new active coupons
class CouponWatcher {
  CouponWatcher._();

  /// The number of new available coupons that haven't been used
  static final ValueNotifier<int> newCouponCount = ValueNotifier(0);

  /// Stream subscription for coupon changes
  static StreamSubscription<QuerySnapshot>? _subscription;

  /// Start watching for new coupons
  static void startWatching() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      newCouponCount.value = 0;
      return;
    }

    _subscription?.cancel();
    _subscription = FirebaseFirestore.instance
        .collection('coupons')
        .where('active', isEqualTo: true)
        .where('expiryDate', isGreaterThan: Timestamp.now())
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isEmpty) {
        newCouponCount.value = 0;
        return;
      }

      // Count coupons that haven't been used by this user
      var count = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final usedBy = (data['usedBy'] as List<dynamic>?)?.cast<String>() ?? [];
        if (!usedBy.contains(user.uid)) {
          count++;
        }
      }
      newCouponCount.value = count;
    });
  }

  /// Stop watching for new coupons
  static void stopWatching() {
    _subscription?.cancel();
    _subscription = null;
    newCouponCount.value = 0;
  }
}