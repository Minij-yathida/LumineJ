// lib/core/order_guard.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// ดึงบทบาทของผู้ใช้ปัจจุบันจาก Firestore ('customer' | 'admin')
Future<String> getCurrentRole() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return 'guest';
  final snap =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
  return (snap.data()?['role'] as String?)?.trim().toLowerCase() ?? 'customer';
}

/// ใช้ก่อน "กดสั่งซื้อ/ไปชำระเงิน"
/// - อนุญาตเฉพาะ role = 'customer'
/// - ถ้าเป็น 'admin' หรือยังไม่ล็อกอิน จะแสดง dialog และ throw เพื่อยกเลิก flow
Future<void> ensureCustomerOrDialog(BuildContext context) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    await showDialog(
      context: context,
      builder: (_) => const AlertDialog(
        title: Text('ต้องเข้าสู่ระบบ'),
        content: Text('กรุณาเข้าสู่ระบบก่อนทำรายการ'),
      ),
    );
    throw Exception('not_signed_in');
  }

  final role = await getCurrentRole();
  if (role != 'customer') {
    await showDialog(
      context: context,
      builder: (_) => const AlertDialog(
        title: Text('บัญชีผู้ดูแลสั่งซื้อไม่ได้'),
        content: Text('บัญชีแอดมินมีสิทธิ์จัดการระบบเท่านั้น ไม่สามารถทำคำสั่งซื้อได้'),
      ),
    );
    throw Exception('role_not_allowed_to_order');
  }
}

/// ใช้ตอน "เข้า/แสดงหน้าแอดมิน"
/// - อนุญาตเฉพาะ role = 'admin'
/// - ถ้าไม่ใช่ admin จะแจ้งเตือนและคืนค่า false (ให้ผู้เรียกตัดสินใจ pop/redirect เอง)
Future<bool> ensureAdminPageOrDialog(BuildContext context) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    await showDialog(
      context: context,
      builder: (_) => const AlertDialog(
        title: Text('สิทธิ์ไม่พอ'),
        content: Text('หน้านี้สำหรับผู้ดูแลระบบเท่านั้น'),
      ),
    );
    return false;
  }

  final role = await getCurrentRole();
  final ok = role == 'admin';
  if (!ok) {
    await showDialog(
      context: context,
      builder: (_) => const AlertDialog(
        title: Text('สิทธิ์ไม่พอ'),
        content: Text('หน้านี้สำหรับผู้ดูแลระบบเท่านั้น'),
      ),
    );
  }
  return ok;
}
