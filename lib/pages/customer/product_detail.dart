// lib/pages/customer/product_detail.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/cart_provider.dart';
import '../../models/cart_item.dart';
import '../../models/product.dart';
import 'cart_page.dart';

final GlobalKey<_ProductDetailBodyState> _productDetailBodyKey =
    GlobalKey<_ProductDetailBodyState>();

class ProductDetailPage extends StatefulWidget {
  final Product product;

  const ProductDetailPage({
    super.key,
    required this.product,
  });

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  final Color brownColor = const Color(0xFF8D6E63);
  final ValueNotifier<bool> _added = ValueNotifier<bool>(false);
  final Duration resetAfter = const Duration(seconds: 2);

  void _onAdded() {
    _added.value = true;
    Future.delayed(resetAfter, () {
      if (mounted) _added.value = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          product.name,
          style: const TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF8D6E63),
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: brownColor,
        elevation: 0.5,
        actions: [
          Consumer<CartProvider>(
            builder: (context, cart, child) {
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.shopping_cart),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CartPage(),
                        ),
                      );
                    },
                  ),
                  if (cart.itemCount > 0)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          '${cart.itemCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: _ProductDetailBody(
        key: _productDetailBodyKey,
        product: product,
        availableSizes: product.availableSizes,
        onAdded: _onAdded,
      ),
      bottomNavigationBar:
          _buildBottomCartBar(context, brownColor, product.price),
    );
  }

  Widget _buildBottomCartBar(
    BuildContext context,
    Color brownColor,
    double price,
  ) {
    final product = widget.product;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<bool>(
                valueListenable: _added,
                builder: (context, added, _) {
                  final bool outOfStock = product.isOutOfStock;
                  final bg = outOfStock
                      ? Colors.grey.shade400
                      : (added ? Colors.grey.shade400 : brownColor);
                  final label = outOfStock
                      ? 'สินค้าหมด'
                      : (added
                          ? 'เพิ่มแล้ว ✓'
                          : 'เพิ่มลงในตะกร้า | ฿ ${price.toStringAsFixed(0)}');

                  return ElevatedButton(
                    onPressed: outOfStock || added
                        ? null
                        : () {
                            _productDetailBodyKey.currentState?._addToCart();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: bg,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    child: Text(label),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===================================================================
// BODY
// ===================================================================

class _ProductDetailBody extends StatefulWidget {
  final Product product;
  final List<String> availableSizes;
  final VoidCallback? onAdded;

  const _ProductDetailBody({
    super.key,
    required this.product,
    required this.availableSizes,
    this.onAdded,
  });

  @override
  State<_ProductDetailBody> createState() => _ProductDetailBodyState();
}

class _ProductDetailBodyState extends State<_ProductDetailBody> {
  String? _selectedSize;
  int _quantity = 1;
  int _currentImage = 0;

  @override
  void initState() {
    super.initState();
    if (widget.availableSizes.length == 1) {
      _selectedSize = widget.availableSizes.first;
    }
  }

  // ----------------- ADD TO CART -----------------

  void _addToCart() {
    final cartProvider = Provider.of<CartProvider>(context, listen: false);

    if (widget.product.isOutOfStock) {
      _showSnackbar('🚨 สินค้าหมดสต๊อก');
      return;
    }

    if (widget.availableSizes.isNotEmpty &&
        (_selectedSize == null || _selectedSize!.isEmpty)) {
      _showSnackbar('กรุณาเลือกไซส์');
      return;
    }

    if (_quantity <= 0) _quantity = 1;

    final newItem = CartItem(
      product: widget.product,
      quantity: _quantity,
      selectedColor: 'N/A',
      selectedSize: _selectedSize ?? '',
    );

    try {
      cartProvider.addItem(newItem);
      _showSnackbar(
        '✅ เพิ่ม ${widget.product.name} ลงตะกร้าแล้ว',
        isError: false,
      );
      widget.onAdded?.call();
    } catch (e) {
      _showSnackbar('🚨 เกิดข้อผิดพลาดในการเพิ่มสินค้าลงตะกร้า: $e');
    }
  }

  void _showSnackbar(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? Colors.red.shade400 : Colors.green.shade600,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  // ----------------- UI -----------------

  @override
  Widget build(BuildContext context) {
    const brownColor = Color(0xFF8D6E63);
    final priceLabel = '฿ ${widget.product.price.toStringAsFixed(0)}';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // รูปหลายรูปเลื่อนได้
          SizedBox(
            height: 350,
            width: double.infinity,
            child: _buildImageCarousel(),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.product.name,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4E342E),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  priceLabel,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: brownColor,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      size: 20,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.product.isOutOfStock
                          ? 'หมดสต็อก'
                          : 'คงเหลือรวม ${widget.product.stock} ชิ้น',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: widget.product.isOutOfStock
                            ? Colors.red.shade400
                            : Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // SIZE (ไม่มีคงเหลือยิบย่อยต่อไซส์แล้ว)
                if (widget.availableSizes.isNotEmpty) ...[
                  const Text(
                    'Size',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10.0,
                    children: widget.availableSizes.map((size) {
                      final isSelected = size == _selectedSize;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedSize = size),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFFF8F1EC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? brownColor
                                  : const Color(0xFFE0D2C8),
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            size,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? brownColor
                                  : const Color(0xFF5D4037),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 22),
                ],

                const Text(
                  'Quantity',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                _buildQtyBox(brownColor),
                const SizedBox(height: 25),
                const Text(
                  'Description',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.product.description,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------- IMAGE CAROUSEL -----------------

  Widget _buildImageCarousel() {
    final images = widget.product.images;

    if (images.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        child: const Center(child: Text('No Image')),
      );
    }

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        PageView.builder(
          itemCount: images.length,
          physics: const BouncingScrollPhysics(),
          onPageChanged: (index) {
            setState(() => _currentImage = index);
          },
          itemBuilder: (_, index) {
            return Image.network(
              images[index],
              width: double.infinity,
              height: 350,
              fit: BoxFit.cover,
            );
          },
        ),
        if (images.length > 1)
          Positioned(
            bottom: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(images.length, (i) {
                final active = i == _currentImage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 10 : 7,
                  height: active ? 10 : 7,
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFF8D6E63)
                        : Colors.white70,
                    shape: BoxShape.circle,
                    border: const Border.fromBorderSide(
                      BorderSide(color: Color(0xFF8D6E63)),
                    ),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  // ----------------- QUANTITY BOX -----------------

  Widget _buildQtyBox(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove, size: 20),
            color: color,
            onPressed: () {
              if (_quantity > 1) {
                setState(() => _quantity--);
              }
            },
          ),
          Text(
            '$_quantity',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            color: color,
            onPressed: () {
              setState(() => _quantity++);
            },
          ),
        ],
      ),
    );
  }
}
