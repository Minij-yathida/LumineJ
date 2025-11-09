// lib/widgets/top_bar.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../pages/customer/order_tracking_page.dart';
import '../core/app_colors.dart';

class TopBar extends StatelessWidget implements PreferredSizeWidget {
  const TopBar({
    super.key,
    required this.currentIndex,
    this.onSearch,
    this.onMarkAllRead,
    this.onDeleteAll,
    this.actions,
    this.unreadCountBuilder,
  });

  final int currentIndex;
  final VoidCallback? onSearch;
  final VoidCallback? onMarkAllRead;
  final VoidCallback? onDeleteAll;
  final Widget? actions;
  final ValueListenable<int>? unreadCountBuilder;

  String get _title {
    if (currentIndex == 0) return 'Luminé J.';
    if (currentIndex == 1) return 'Coupons & Promotions';
    if (currentIndex == 2) return 'Notifications';
    return 'My Profile';
  }

  @override
  Widget build(BuildContext context) {
    final bool isProfile = currentIndex == 3;

    // ---------- Profile Tab ----------
    if (isProfile) {
      return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>?>(
        future: () async {
          final u = FirebaseAuth.instance.currentUser;
          if (u == null) return null;
          return FirebaseFirestore.instance
              .collection('users')
              .doc(u.uid)
              .get();
        }(),
        builder: (ctx, snap) {
          String label = 'Luminé Jewelry Member';
          bool isAdmin = false;

          if (snap.hasData && snap.data != null) {
            final data = snap.data!.data() ?? <String, dynamic>{};
            final role = (data['role'] ?? 'customer')
                .toString()
                .trim()
                .toLowerCase();
            isAdmin = role == 'admin';
            if (isAdmin) label = 'Luminé Admin Panel';
          }

          return AppBar(
            title: const Text(
              'My Profile',
              style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5D4037),
              ),
            ),
            centerTitle: true,
            backgroundColor: AppColors.background,
            elevation: 0,
            automaticallyImplyLeading: false,
            actions: [
              if (!isAdmin)
                IconButton(
                  tooltip: 'ติดตามคำสั่งซื้อ',
                  onPressed: () {
                    Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => const OrderTrackingPage(),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.list_alt_outlined,
                    color: Colors.brown,
                  ),
                ),
            ],
            // แถบ Member/Admin ชิดขอบล่าง AppBar
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(40),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                color: const Color(0xFF8D6E63),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontFamily: 'PlayfairDisplay',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    // ---------- Tabs อื่น ----------
    return AppBar(
      title: Text(
        _title,
        style: const TextStyle(
          fontFamily: 'PlayfairDisplay',
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: Color(0xFF5D4037),
        ),
      ),
      centerTitle: true,
      backgroundColor: AppColors.background,
      elevation: currentIndex == 0 ? 0 : 4,
      leading: currentIndex == 0
          ? IconButton(
              icon: Icon(Icons.search, size: 24, color: AppColors.brown),
              onPressed: onSearch,
            )
          : (currentIndex == 2
              ? IconButton(
                  tooltip: 'Delete all',
                  icon: const Icon(Icons.delete_outline, color: Colors.grey),
                  onPressed: onDeleteAll,
                )
              : null),
      actions: currentIndex == 0
          ? [if (actions != null) actions!]
          : (currentIndex == 2
              ? [
                  IconButton(
                    tooltip: 'Mark all read',
                    icon: const Icon(Icons.mark_email_read, color: Colors.grey),
                    onPressed: onMarkAllRead,
                  )
                ]
              : []),
    );
  }

  @override
  Size get preferredSize =>
      currentIndex == 3
          ? const Size.fromHeight(kToolbarHeight + 40)
          : const Size.fromHeight(kToolbarHeight);
}
