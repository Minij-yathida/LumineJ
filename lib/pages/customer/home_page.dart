// lib/pages/customer/home_page.dart
// Home: 4 tabs (Shop, Coupons, Notifications, Profile)
// หน้า Shop มี section + ปุ่มกดไปหน้า ProductsPage (สินค้ารวม + หมวดหมู่)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Firebase
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Watchers
import '../../services/coupon_watcher.dart';

// Services & Models
import '../../services/auth_service.dart';
import '../../services/cart_provider.dart';
import '../../services/notifications_watcher.dart'; // ValueNotifier<int> unreadCount
import '../../services/push_routing.dart';
import '../../services/chat_service.dart';
import '../../models/product.dart';

// Pages
import '../admin/admin_page.dart';
import '../../chat/chat_page.dart';
import '../admin/admin_chat_list_page.dart';
import '../../core/app_colors.dart';
import '../profile/unified_profile_page.dart';
import 'coupon_page.dart';
import 'notifications_page.dart';
import 'search_page.dart';
import 'cart_page.dart';
import 'product_detail.dart';
import 'products_page.dart'; // ✅ หน้า PRODUCTS ใหม่ที่มี filter หมวดหมู่

// Widgets
import '../../widgets/top_bar.dart';
import '../../widgets/bottom_nav.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _current = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = const [
      _ShopSection(),
      CouponsPage(),
      NotificationsPage(),
      UnifiedProfilePage(),
    ];
    
    // Start watching for new coupons
    CouponWatcher.startWatching();

    // ให้ PushRouting เรียกเปลี่ยนแท็บได้ (ใช้จาก notification / deep link)
    PushRouting.setTabSelector((int idx) {
      if (!mounted) return;
      if (idx < 0 || idx >= _pages.length) return;
      setState(() => _current = idx);
    });
  }

  @override
  void dispose() {
    PushRouting.clearTabSelector();
    CouponWatcher.stopWatching();
    super.dispose();
  }

  // =============== Notification Helpers ===============

  Future<void> _markAllRead() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ยังไม่ได้เข้าสู่ระบบ'),
          content: const Text('กรุณาเข้าสู่ระบบเพื่อจัดการการแจ้งเตือนของคุณ'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('ตกลง'),
            ),
          ],
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('ทำเครื่องหมายทั้งหมดว่าอ่านแล้ว?'),
            content: const Text(
                'คุณต้องการทำเครื่องหมายการแจ้งเตือนทั้งหมดว่าอ่านแล้วหรือไม่'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('ยกเลิก'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('ยืนยัน'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    if (mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Dialog(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 24, height: 24, child: CircularProgressIndicator()),
                SizedBox(width: 12),
                Text('กำลังอัปเดต...'),
              ],
            ),
          ),
        ),
      );
    }

    bool isError = false;
    String message = '';

    try {
      final coll = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('alerts');
      final snap = await coll.get();
      final batch = FirebaseFirestore.instance.batch();

      var updated = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final hasStatus = data.containsKey('status');
        final isUnread = hasStatus
            ? (data['status']?.toString() != 'read')
            : ((data['read'] as bool?) != true);

        if (isUnread) {
          final ref = coll.doc(doc.id);
          if (hasStatus) {
            batch.update(ref, {'status': 'read'});
          } else {
            batch.update(ref, {'read': true});
          }
          updated++;
        }
      }

      if (updated > 0) await batch.commit();
      NotificationWatcher.unreadCount.value = 0;
    } catch (e) {
      isError = true;
      message = 'Error: $e';
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // close loading
      }
      if (isError && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('เกิดข้อผิดพลาด'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('ตกลง'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _deleteAllNotifications() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('ลบการแจ้งเตือนทั้งหมด?'),
            content: const Text(
                'ต้องการลบการแจ้งเตือนทั้งหมดหรือไม่ (ไม่สามารถย้อนกลับได้)'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('ยกเลิก'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('ลบทั้งหมด'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    if (mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Dialog(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: 24, height: 24, child: CircularProgressIndicator()),
                SizedBox(width: 12),
                Text('กำลังลบ...'),
              ],
            ),
          ),
        ),
      );
    }

    bool isError = false;
    String message = '';

    try {
      final coll = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('alerts');
      final snap = await coll.get();
      final batch = FirebaseFirestore.instance.batch();

      var removed = 0;
      for (final d in snap.docs) {
        batch.delete(coll.doc(d.id));
        removed++;
      }

      if (removed > 0) await batch.commit();
      NotificationWatcher.unreadCount.value = 0;
    } catch (e) {
      isError = true;
      message = 'Error: $e';
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // close loading
      }
      if (isError && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('เกิดข้อผิดพลาด'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('ตกลง'),
              ),
            ],
          ),
        );
      }
    }
  }

  // =============== BUILD ===============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TopBar(
        currentIndex: _current,
        onSearch: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SearchPage()),
        ),
        onDeleteAll: _deleteAllNotifications,
        onMarkAllRead: _markAllRead,
        actions: const _AdminChatActions(),
      ),
      floatingActionButton: Consumer<CartProvider>(
        builder: (context, cart, _) => FloatingActionButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CartPage()),
          ),
          shape: const CircleBorder(),
          backgroundColor: AppColors.brown,
          foregroundColor: Colors.white,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.shopping_bag_outlined),
              if (cart.itemCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      cart.itemCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      body: IndexedStack(index: _current, children: _pages),
      bottomNavigationBar: BottomNav(
        currentIndex: _current,
        onTap: (i) => setState(() => _current = i),
      ),
    );
  }
}

// ================== SHOP SECTION ==================

class _ShopSection extends StatelessWidget {
  const _ShopSection({super.key});

  void _openDetail(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final product = Product.fromFirestore(doc);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailPage(product: product),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return StreamBuilder<QuerySnapshot>(
      stream: authService.getProductsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final docs = (snapshot.data?.docs ?? [])
            .cast<QueryDocumentSnapshot<Map<String, dynamic>>>();

        // Best sellers จากฟิลด์ sold
        final best = [...docs]
          ..sort((a, b) {
            final sa = (a.data()['sold'] as num?)?.toInt() ?? 0;
            final sb = (b.data()['sold'] as num?)?.toInt() ?? 0;
            return sb.compareTo(sa);
          });
        final bestSellerDocs = best.take(8).toList();

        // 4 ชิ้นจาก collection สำหรับ collection section
        final oldFour = docs.take(4).toList();

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),

              // ----- Ad Boards -----
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: _AdBoard(
                  asset: 'assets/images/ad_board_1.jpg',
                  title: 'End of Season',
                  subtitle: 'Up to 40% OFF',
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: _AdBoard(
                  asset: 'assets/images/ad_board_2.jpg',
                  title: 'Bridal Picks',
                  subtitle: 'Elegant pieces curated for you',
                ),
              ),

              // ----- NEW ARRIVAL (mock static) -----
              const SizedBox(height: 18),
              const _SectionTitle(title: 'NEW ARRIVAL'),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 0.78,
                  children: const [
                    _NewMockCard(
                      image: 'assets/images/new_drop_1.png',
                      name: 'Astra Petite Ring',
                      price: 175,
                    ),
                    _NewMockCard(
                      image: 'assets/images/new_drop_2.png',
                      name: 'Flare Huggie Earrings',
                      price: 199,
                    ),
                    _NewMockCard(
                      image: 'assets/images/new_drop_3.png',
                      name: 'Halo Mini Necklace',
                      price: 225,
                    ),
                    _NewMockCard(
                      image: 'assets/images/new_drop_4.png',
                      name: 'Serene Chain Bracelet',
                      price: 189,
                    ),
                  ],
                ),
              ),

              // ----- BEST SELLERS -----
              if (bestSellerDocs.isNotEmpty) ...[
                const SizedBox(height: 18),
                _SectionTitle(
                  title: 'BEST SELLERS',
                  actionText: 'Shop now',
                  onAction: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProductsPage(), // ✅ ไปหน้ารวมสินค้า
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 190,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: bestSellerDocs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) {
                      final doc = bestSellerDocs[i];
                      final product = Product.fromFirestore(doc);
                      return ProductMiniCard(
                        product: product,
                        onTap: () => _openDetail(context, doc),
                      );
                    },
                  ),
                ),
              ],

              // ----- FROM OUR COLLECTION -----
              if (oldFour.isNotEmpty) ...[
                const SizedBox(height: 18),
                _SectionTitle(
                  title: 'FROM OUR COLLECTION',
                  actionText: 'View all',
                  onAction: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProductsPage(), // ✅ ไปหน้ารวมสินค้า
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GridView.builder(
                    itemCount: oldFour.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.78,
                    ),
                    itemBuilder: (_, index) {
                      final doc = oldFour[index];
                      final product = Product.fromFirestore(doc);
                      return SpecialProductCard(
                        product: product,
                        onTap: () => _openDetail(context, doc),
                      );
                    },
                  ),
                ),
              ],

              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

// ================== SMALL UI PIECES ==================

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    this.actionText,
    this.onAction,
    super.key,
  });

  final String title;
  final String? actionText;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                  letterSpacing: .3,
                ),
          ),
          const Spacer(),
          if (actionText != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                actionText!,
                style: TextStyle(
                  color: AppColors.brown,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AdBoard extends StatelessWidget {
  const _AdBoard({
    required this.asset,
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String asset;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final ImageProvider imageProvider =
        asset.startsWith('http') ? NetworkImage(asset) : AssetImage(asset);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Image(
              image: imageProvider,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: Colors.grey.shade200,
                alignment: Alignment.center,
                child: const Icon(Icons.image_not_supported,
                    color: Colors.grey),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withOpacity(.05),
                    Colors.black.withOpacity(.35),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NewMockCard extends StatelessWidget {
  const _NewMockCard({
    required this.image,
    required this.name,
    required this.price,
    super.key,
  });

  final String image;
  final String name;
  final double price;

  @override
  Widget build(BuildContext context) {
    final imageWidget = image.startsWith('http')
        ? Image.network(
            image,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.image_not_supported),
          )
        : Image.asset(
            image,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.image_not_supported),
          );

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.05),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(14)),
                  child: AspectRatio(aspectRatio: 1, child: imageWidget),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '฿ ${price.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8D6E63),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: 10,
          top: 10,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF8D6E63),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'NEW',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ProductMiniCard extends StatelessWidget {
  const ProductMiniCard({
    required this.product,
    required this.onTap,
    super.key,
  });

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imagePath = product.images.isNotEmpty ? product.images.first : '';

    Widget buildImage() {
      if (imagePath.isEmpty) {
        return const Icon(Icons.image_not_supported, color: Colors.grey);
      }
      return imagePath.startsWith('http')
          ? Image.network(
              imagePath,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
            )
          : Image.asset(
              imagePath,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.image_not_supported),
            );
    }

    return InkWell(
      onTap: onTap,
      child: Container(
        width: 130,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: buildImage(),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              product.name,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '฿ ${product.price.toStringAsFixed(0)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF8D6E63),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SpecialProductCard extends StatelessWidget {
  const SpecialProductCard({
    required this.product,
    required this.onTap,
    super.key,
  });

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imagePath = product.images.isNotEmpty ? product.images.first : '';

    Widget buildImage() {
      if (imagePath.isEmpty) {
        return const Icon(Icons.image_not_supported, color: Colors.grey);
      }
      return imagePath.startsWith('http')
          ? Image.network(
              imagePath,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
            )
          : Image.asset(
              imagePath,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.image_not_supported),
            );
    }

    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: buildImage(),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            product.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium
                ?.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          Text(
            '฿ ${product.price.toStringAsFixed(0)}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: const Color(0xFF8D6E63),
            ),
          ),
        ],
      ),
    );
  }
}

// ================== ADMIN / CHAT ACTIONS ==================

class _AdminChatActions extends StatelessWidget {
  const _AdminChatActions({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    // ยังไม่ล็อกอิน: ให้ปุ่มแชทธรรมดา
    if (user == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.chat_bubble_outline,
                size: 24, color: AppColors.brown),
            onPressed: () async {
              try {
                final ref = await ChatService().openOrCreateThread(null);
                if (!context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatPage(
                      threadId: ref.id,
                      asStore: true,
                    ),
                  ),
                );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('ไม่สามารถเข้าแชทได้: $e')),
                  );
                }
              }
            },
          ),
        ],
      );
    }

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(),
      builder: (ctx, snap) {
        final role = (snap.data?.data()?['role'] ?? 'customer').toString();
        final isAdmin = role == 'admin';

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isAdmin)
              IconButton(
                tooltip: 'Admin',
                icon: Icon(Icons.dashboard_customize_outlined,
                    color: AppColors.brown),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminPage(),
                    ),
                  );
                },
              ),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: isAdmin
                  ? FirebaseFirestore.instance
                      .collection('threads')
                      .where('storeId',
                          isEqualTo: ChatService.storeId)
                      .snapshots()
                  : FirebaseFirestore.instance
                      .collection('threads')
                      .where('userId', isEqualTo: user.uid)
                      .where('storeId',
                          isEqualTo: ChatService.storeId)
                      .snapshots(),
              builder: (c, s) {
                int totalUnread = 0;
                int customerCount = 0; // จำนวนลูกค้า (threads) สำหรับแอดมิน ที่ยังมี unread
                if (s.hasData && s.data != null) {
                  for (final d in s.data!.docs) {
                    final data = d.data();
                    if (isAdmin) {
                      // นับเฉพาะ thread ที่ไม่ใช่ placeholder/welcome และมี unread_store > 0
                      final lm = (data['lastMessage'] ?? '').toString();
                      if (lm.trim().isEmpty) continue;
                      final low = lm.toLowerCase();
                      if (low.contains('ยินดีต้อนรับ') || low.contains('welcome')) continue;
                      final unreadStore = (data['unread_store'] as int?) ?? 0;
                      if (unreadStore > 0) {
                        customerCount++;
                        totalUnread += unreadStore;
                      }
                    } else {
                      totalUnread += (data['unread_user'] as int?) ?? 0;
                    }
                  }
                }

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: Icon(Icons.chat_bubble_outline,
                          size: 24, color: AppColors.brown),
                      onPressed: () {
                        if (isAdmin) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AdminChatListPage(),
                            ),
                          );
                        } else {
                          ChatService()
                              .openOrCreateThread(null)
                              .then((ref) {
                            if (!context.mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatPage(
                                  threadId: ref.id,
                                  asStore: true,
                                ),
                              ),
                            );
                          }).catchError((e) {
                            final msg = e.toString();
                            if (!context.mounted) return;
                            if (msg.contains('permission-denied')) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'ไม่สามารถเข้าแชทได้: ไม่มีสิทธิ์เข้าถึงแชท'),
                                ),
                              );
                            } else if (msg.contains('not-found') ||
                                msg.contains('NOT_FOUND')) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'บริการแชทยังไม่พร้อมใช้งาน (not-found)'),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('ไม่สามารถเข้าแชทได้: $msg'),
                                ),
                              );
                            }
                          });
                        }
                      },
                    ),
                    if (isAdmin ? customerCount > 0 : totalUnread > 0)
                      Positioned(
                        right: 2,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isAdmin ? '$customerCount' : '$totalUnread',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}
