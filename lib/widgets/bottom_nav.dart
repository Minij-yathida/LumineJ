// lib/widgets/bottom_nav.dart
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../core/app_colors.dart';
import '../services/notifications_watcher.dart';
import '../services/coupon_watcher.dart';
import '../services/admin_notification_watcher.dart';

class BottomNav extends StatelessWidget implements PreferredSizeWidget {
  const BottomNav({
    Key? key,
    required this.currentIndex,
    required this.onTap,
    this.isAdmin = false,
  }) : super(key: key);

  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool isAdmin;

  static const double _barHeight = 64.0;

  @override
  Size get preferredSize => const Size.fromHeight(_barHeight);

  Color _itemColor(bool selected) =>
      selected ? AppColors.brown : AppColors.grey;

  Widget _buildItem({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    final color = _itemColor(selected);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: _barHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 22, color: color),
                  if (badge > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          badge.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ถ้าเป็น admin นับจาก notifications_admin
    final ValueListenable<int> notifSource =
        isAdmin ? AdminNotificationWatcher.unreadCount
                : NotificationWatcher.unreadCount;

    return ValueListenableBuilder<int>(
      valueListenable: notifSource,
      builder: (context, unread, _) {
        return SafeArea(
          top: false,
          child: Container(
            height: _barHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.06),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Shop
                _buildItem(
                  icon: Icons.storefront_outlined,
                  label: 'Shop',
                  selected: currentIndex == 0,
                  onTap: () => onTap(0),
                ),

                // Coupons
                ValueListenableBuilder<int>(
                  valueListenable: CouponWatcher.newCouponCount,
                  builder: (context, newCoupons, _) => _buildItem(
                    icon: Icons.card_giftcard_outlined,
                    label: 'Coupons',
                    selected: currentIndex == 1,
                    onTap: () => onTap(1),
                    // admin ไม่ต้องมี badge คูปองใหม่
                    badge: isAdmin ? 0 : newCoupons,
                  ),
                ),

                const SizedBox(width: 72), // gap FAB

                // Notifications
                _buildItem(
                  icon: Icons.notifications_none,
                  label: 'Notifications',
                  selected: currentIndex == 2,
                  onTap: () => onTap(2),
                  badge: unread > 0 ? unread : 0,
                ),

                // Profile
                _buildItem(
                  icon: Icons.person_outline,
                  label: 'Profile',
                  selected: currentIndex == 3,
                  onTap: () => onTap(3),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
