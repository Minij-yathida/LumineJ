import 'package:flutter/material.dart';
import '../../core/order_guard.dart';
import 'admin_dashboard_page.dart';
import 'admin_orders_page.dart';
import 'product_management_page.dart';
import 'add_coupon_page.dart';
  
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  @override
  void initState() {
    super.initState();

    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await ensureAdminPageOrDialog(context);
      if (!ok && mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          centerTitle: true,
          elevation: 1,
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: Material(
              color: cs.surface,
              child: TabBar(
                isScrollable: true,
                labelColor: cs.onSurface,
                unselectedLabelColor: cs.onSurface.withOpacity(.55),
                indicatorColor: cs.primary,
                tabs: const [
                  Tab(text: 'Dashboard'),
                  Tab(text: 'Orders'),
                  Tab(text: 'Products'),
                  Tab(text: 'Coupons'),
                ],
              ),
            ),
          ),
        ),
        body: const TabBarView(
          children: [
            AdminDashboardPage(),
            AdminOrdersPage(),
            ProductManagementPage(),
            AddCouponPage(),
          ],
        ),
      ),
    );
  }
  

}
