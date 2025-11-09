// lib/pages/admin/admin_chat_list_page.dart
// หน้านี้สำหรับ "แอดมิน / ร้าน" ใช้ดูแชทของลูกค้าทั้งหมด

import 'package:LumineJewelry/chat/chat_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../services/chat_service.dart';

class AdminChatListPage extends StatefulWidget {
  const AdminChatListPage({super.key});

  @override
  State<AdminChatListPage> createState() => _AdminChatListPageState();
}

class _AdminChatListPageState extends State<AdminChatListPage> {
  @override
  Widget build(BuildContext context) {
    // ✅ ดึงทุก thread ของร้านนี้ ตาม storeId ที่กำหนดใน ChatService
    final q = FirebaseFirestore.instance
        .collection('threads')
        .where('storeId', isEqualTo: ChatService.storeId)
        .orderBy('lastAt', descending: true);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        centerTitle: true,
        elevation: 2,
        title: const Text(
          'กล่องข้อความ (Admin)',
          style: TextStyle(
            fontFamily: 'PlayfairDisplay',
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF5D4037),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('เกิดข้อผิดพลาด: ${snap.error}'));
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const Center(child: Text('ยังไม่มีลูกค้าทักมา'));
          }

          final rawDocs = snap.data!.docs;

          // 🔹 กรอง thread ที่เป็น welcome/placeholder หรือ lastMessage ว่างออก
          final docs = rawDocs.where((doc) {
            final d = doc.data();
            final lm = (d['lastMessage'] ?? '').toString().trim();
            if (lm.isEmpty) return false;
            final low = lm.toLowerCase();
            if (low.contains('ยินดีต้อนรับ') || low.contains('welcome')) {
              return false;
            }
            return true;
          }).toList();

          if (docs.isEmpty) {
            return const Center(child: Text('ยังไม่มีลูกค้าทักมา'));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (_, i) {
              final doc = docs[i];
              final d = doc.data();
              final threadId = doc.id;

              final displayName =
                  (d['userDisplayName'] ?? '').toString().trim();
              final userEmail =
                  (d['userEmail'] ?? '').toString().trim();
              final lastMessage =
                  (d['lastMessage'] ?? '').toString().trim();
              final unread = (d['unread_store'] as int?) ?? 0;
              final photoUrl =
                  (d['userPhotoUrl'] ?? '').toString().trim();

              final titleText = displayName.isNotEmpty
                  ? displayName
                  : (userEmail.isNotEmpty ? userEmail : 'ลูกค้า');

              return ListTile(
                leading: CircleAvatar(
                  backgroundImage:
                      photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                  child: photoUrl.isEmpty
                      ? const Icon(Icons.person)
                      : null,
                ),
                title: Text(
                  titleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight:
                        unread > 0 ? FontWeight.w700 : FontWeight.w500,
                    color: const Color(0xFF4E342E),
                  ),
                ),
                subtitle: Text(
                  lastMessage.isEmpty ? '...' : lastMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.black.withOpacity(
                      unread > 0 ? 0.8 : 0.6,
                    ),
                  ),
                ),
                trailing: unread > 0
                    ? CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.brown.shade400,
                        foregroundColor: Colors.white,
                        child: Text(
                          '$unread',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatPage(
                        threadId: threadId,
                        asStore: true, // ✅ ฝั่งแอดมิน
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
