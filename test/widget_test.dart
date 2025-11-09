import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:LumineJewelry/pages/customer/home_page.dart';

void main() {
  testWidgets('HomePage has a title and product list', (WidgetTester tester) async {
    // สร้าง widget สำหรับทดสอบ
    await tester.pumpWidget(MaterialApp(home: HomePage()));

    // ตรวจสอบว่า Text widget ที่แสดงชื่อ 'Jewelry Shop' มีอยู่ในหน้า
    expect(find.text('Jewelry Shop'), findsOneWidget);

    // ตรวจสอบว่า GridView หรือการ์ดสินค้าปรากฏขึ้น
    expect(find.byType(GridView), findsOneWidget);
  });

  testWidgets('Product Card shows name and price', (WidgetTester tester) async {
    // สร้าง widget สำหรับทดสอบ
    await tester.pumpWidget(MaterialApp(home: HomePage()));

    // ตรวจสอบว่า Card ของสินค้าแสดงชื่อสินค้า
    expect(find.text('Product Name'), findsWidgets);

    // ตรวจสอบว่าราคาสินค้าปรากฏอยู่ในหน้าจอ
    expect(find.text('\$999.99'), findsWidgets);
  });
}
