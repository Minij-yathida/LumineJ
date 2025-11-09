// lib/pages/category/category_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ✅ แก้ไข Imports โดยใช้ Relative Path ที่ถูกต้อง:
// ขึ้น 2 ระดับ (จาก category/ ไป pages/ (1) และจาก pages/ ไป lib/ (2))
import '../../models/product.dart';      
import '../../widgets/product_card.dart';  

class CategoryPage extends StatelessWidget {
  final String categoryName;

  const CategoryPage({
    super.key,
    required this.categoryName,
  });

  @override
  Widget build(BuildContext context) {
    // ----------------------------------------------------
    // 2. โค้ด Body (ใช้ StreamBuilder เพื่อแสดงสินค้า)
    // ----------------------------------------------------
    return Scaffold(
      appBar: AppBar(
        title: Text(categoryName),
        centerTitle: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor, // ใช้สีพื้นหลังตาม UI
        foregroundColor: Colors.brown, // สีไอคอน/ข้อความ
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // 🔎 ค้นหาสินค้าจาก Firestore ที่มี field 'category' ตรงกับ categoryName
        stream: FirebaseFirestore.instance
            .collection('products')
            .where('category', isEqualTo: categoryName)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('ไม่พบสินค้าในหมวดหมู่นี้'));
          }

          // แปลง Firestore Document เป็น Product Model
          final products = snapshot.data!.docs
              .map((doc) => Product.fromFirestore(doc))
              .toList();
          
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.7, 
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return ProductCard(
                productName: product.name,
                price: product.price,
                // ⚠️ ต้องมี URL รูปภาพที่ถูกต้อง
                imageUrl: product.images.isNotEmpty ? product.images.first : 'assets/images/placeholder.png', 
                onTap: () {
                  // นำทางไป Product Detail
                  Navigator.pushNamed(context, '/product_detail', arguments: product);
                },
              );
            },
          );
        },
      ),
    );
  }
}