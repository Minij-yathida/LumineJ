import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../services/cart_provider.dart';
import '../../models/cart_item.dart';
import 'checkout_page.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  final _money = NumberFormat('#,##0.00', 'th_TH');

  void _toggleAll(Iterable<CartItem> items, bool checked) {
    final cart = context.read<CartProvider>();
    if (checked) {
      cart.selectAll();
    } else {
      cart.clearSelection();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cart = context.read<CartProvider>();
    final items = cart.items;
    if (!cart.hasSelection && items.isNotEmpty) {
      cart.selectAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ตะกร้าสินค้า'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF8D6E63),
        elevation: 0,
      ),
      body: Consumer<CartProvider>(
        builder: (context, cart, _) {
          final items = cart.items;

          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_bag_outlined,
                      size: 60, color: Colors.grey),
                  SizedBox(height: 10),
                  Text(
                    'ตะกร้าว่างเปล่า',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final allChecked =
              cart.selectedItems.length == items.length && items.isNotEmpty;
          final totalSel = cart.selectedItems.fold<double>(
              0.0, (s, it) => s + (it.product.price * it.quantity));

          return Column(
            children: [
              // แถวเลือกทั้งหมด
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: Colors.white,
                child: Row(
                  children: [
                    Checkbox(
                      value: allChecked,
                      onChanged: (v) => _toggleAll(items, v ?? false),
                    ),
                    const Text('เลือกทั้งหมด'),
                    const Spacer(),
                    Text(
                      'เลือก ${cart.selectedItems.length}/${items.length} ชิ้น',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // รายการสินค้า
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final it = items[i];
                    final checked = cart.isSelected(it);

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Checkbox(
                              value: checked,
                              onChanged: (_) {
                                cart.toggleSelect(it);
                              },
                            ),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                it.product.images.isNotEmpty
                                    ? it.product.images.first
                                    : 'https://placehold.co/600x400/F0E0D6/8D6E63?text=N/A',
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    it.product.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  // โชว์เฉพาะไซส์ (ถ้าไม่ว่าง)
                                  if (it.selectedSize.isNotEmpty)
                                    Text(
                                      'ไซส์: ${it.selectedSize}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '฿ ${_money.format(it.product.price * it.quantity)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF8D6E63),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // ปุ่มจำนวน + ลบ
                            Row(
                              children: [
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    if (it.quantity > 1) {
                                      cart.updateQuantity(
                                          it, it.quantity - 1);
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.remove_circle_outline,
                                    size: 20,
                                  ),
                                ),
                                Text(
                                  '${it.quantity}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    cart.updateQuantity(
                                        it, it.quantity + 1);
                                  },
                                  icon: const Icon(
                                    Icons.add_circle_outline,
                                    size: 20,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    cart.removeItem(it);
                                  },
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 20,
                                    color: Colors.red.shade400,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // สรุปยอด + ปุ่มเช็คเอาต์
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.shade300,
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'ยอดที่เลือกชำระ:',
                          style: TextStyle(fontSize: 16),
                        ),
                        Text(
                          '฿ ${_money.format(totalSel)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: cart.selectedItems.isEmpty
                            ? null
                            : () {
                                final selectedItems =
                                    cart.selectedItems.toList();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ChangeNotifierProvider.value(
                                      value: cart,
                                      child: CheckoutPage(
                                        itemsOverride: selectedItems,
                                      ),
                                    ),
                                  ),
                                );
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8D6E63),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('ดำเนินการชำระเงิน'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
