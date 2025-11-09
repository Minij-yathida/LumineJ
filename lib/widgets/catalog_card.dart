// lib/widgets/catalog_card.dart

import 'package:flutter/material.dart';

// ✅ แก้ไข Imports Path: ต้องถอย 1 ขั้น (widgets/ -> lib/)
import '../models/product.dart'; 
// ตรวจสอบว่า path นี้ถูกต้อง ถ้าไม่ถูกต้องจะใช้ค่าสีโดยตรง

// กำหนดค่าสีหลักที่ใช้บ่อย (สำหรับกรณีที่ AppColors อาจมีปัญหา)
const Color _brownColor = Color(0xFF8D6E63);
const Color _textColor = Color(0xFF4E342E);
const Color _greyColor = Colors.black38;

class CatalogCard extends StatefulWidget {
  final Product product;
  final VoidCallback onTap;
  const CatalogCard({super.key, required this.product, required this.onTap});

  @override
  State<CatalogCard> createState() => _CatalogCardState();
}

class _CatalogCardState extends State<CatalogCard> {
  bool fav = false;

  @override
  Widget build(BuildContext context) {
    // ⚠️ ดึงรูปแรกจาก List images.
    final String imageUrl = widget.product.images.isNotEmpty
        ? widget.product.images.first
        : 'assets/images/placeholder.png'; // ภาพสำรอง

    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withOpacity(.06),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // รูป
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              // ✅ แก้ไข: ใช้ Image.network สำหรับ URL หรือ Image.asset สำหรับ assets
              // เราจะใช้ Image.network เพราะข้อมูลมาจาก Firebase
              child: Image.network(
                imageUrl, 
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 72, height: 72, 
                  color: Colors.grey.shade100,
                  child: const Icon(Icons.broken_image, color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // รายละเอียด
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ⚠️ แก้ไข: เนื่องจาก Product Model ไม่มี brand จึงใช้ category แทน
                  Text(widget.product.category, 
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _brownColor, // ใช้สีน้ำตาลหลัก
                      )),
                  Text(
                    widget.product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _textColor, fontSize: 13, fontWeight: FontWeight.normal),
                  ),
                  const SizedBox(height: 6),
                  Text('฿${widget.product.price.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _textColor, // สีข้อความเข้ม
                      )),
                ],
              ),
            ),
            // ปุ่ม Favorite
            IconButton(
              onPressed: () => setState(() => fav = !fav),
              icon: Icon(
                fav ? Icons.favorite : Icons.favorite_border,
                color: fav ? _brownColor : _greyColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}