import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:LumineJewelry/chat/chat_page.dart'; // ตรวจสอบ path


// =====================================================================
// 🧩 MODEL CLASSES (จาก admin_chat_threads_page.dart)
// =====================================================================

class ChatThread {
  final String id;
  final String userId;
  final String userDisplayName;
  final String userEmail;
  final String userPhotoUrl;
  final String lastMessage;
  final Timestamp? lastAt;
  final int unreadStore;

  ChatThread({
    required this.id,
    required this.userId,
    required this.userDisplayName,
    required this.userEmail,
    required this.userPhotoUrl,
    required this.lastMessage,
    this.lastAt,
    required this.unreadStore,
  });

  factory ChatThread.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final displayName = (data['userDisplayName'] ?? '').toString();
    final email = (data['userEmail'] ?? '').toString();
    final userId = (data['userId'] ?? '').toString();

    return ChatThread(
      id: doc.id,
      userId: userId,
      userDisplayName: displayName.isNotEmpty ? displayName : (email.isNotEmpty ? email : userId),
      userEmail: email,
      userPhotoUrl: (data['userPhotoUrl'] ?? '').toString(),
      lastMessage: (data['lastMessage'] ?? '').toString(),
      lastAt: data['lastAt'] is Timestamp ? data['lastAt'] as Timestamp : null,
      unreadStore: (data['unread_store'] ?? 0) as int,
    );
  }

  String get inits {
    if (userDisplayName.isNotEmpty) return userDisplayName[0].toUpperCase();
    if (userEmail.isNotEmpty) return userEmail[0].toUpperCase();
    if (userId.isNotEmpty) return userId[0].toUpperCase();
    return '?';
  }
}

// =====================================================================
// 📝 ADMIN CHAT LIST PAGE
// =====================================================================

class AdminChatListPage extends StatelessWidget {
  AdminChatListPage({super.key});

  final _fs = FirebaseFirestore.instance;

  // 🔹 ดึง Threads ของร้านที่เป็นของแอดมินที่ล็อกอิน
  Stream<QuerySnapshot<Map<String, dynamic>>> _threadsStream() {
    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    if (adminUid == null) return const Stream.empty();

    // Query Threads ที่มี storeId ตรงกับ Admin UID ที่ล็อกอิน
    return _fs
        .collection('threads')
        .where('storeId', isEqualTo: adminUid)
        .orderBy('lastAt', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFCF7F5),
      appBar: AppBar(
        title: const Text('กล่องข้อความ (Admin)'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF5D4037),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _threadsStream(),
        builder: (context, snap) => _buildBody(context, snap),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap) {
    if (snap.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    if (snap.hasError) {
      debugPrint('⚠️ Chat thread stream error: ${snap.error}');
      return Center(child: Text('เกิดข้อผิดพลาดในการโหลดข้อมูล: ${snap.error}'));
    }

    final docs = snap.data?.docs ?? [];
    
    final threads = docs
        .map((doc) => ChatThread.fromFirestore(doc))
        .where((thread) {
          // กรองข้อความต้อนรับออก
          final lm = thread.lastMessage.toLowerCase();
          if (lm.trim().isEmpty) return false;
          if (lm.contains('ยินดีต้อนรับ') || lm.contains('welcome')) return false;
          return true;
        })
        .toList();

    if (threads.isEmpty) return _buildEmptyState();

    return _buildThreadList(context, threads);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.forum_outlined, size: 56, color: Color(0xFFBCAAA4)),
            SizedBox(height: 12),
            Text('ยังไม่มีห้องแชทจากลูกค้า',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF5D4037))),
            SizedBox(height: 8),
            Text(
              'รอข้อความแรกจากลูกค้า หรือเริ่มต้นแชทใหม่จากหน้าจัดการแชท',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThreadList(BuildContext context, List<ChatThread> threads) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      itemCount: threads.length,
      separatorBuilder: (_, __) => const Divider(indent: 16, endIndent: 16, height: 1),
      itemBuilder: (_, i) => _buildThreadItem(context, threads[i]),
    );
  }

  Widget _buildThreadItem(BuildContext context, ChatThread thread) {
    final time = _readableTime(thread.lastAt);
    final isUnread = thread.unreadStore > 0;

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      shadowColor: const Color(0xFFE9DDD6),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: thread.userPhotoUrl.isNotEmpty
            ? CircleAvatar(radius: 24, backgroundImage: NetworkImage(thread.userPhotoUrl))
            : CircleAvatar(radius: 24, child: Text(thread.inits)),
        title: Text(
          thread.userDisplayName,
          style: TextStyle(
            fontSize: 16,
            fontWeight: isUnread ? FontWeight.w900 : FontWeight.w700,
            color: isUnread ? Colors.black : Colors.black87,
          ),
        ),
        subtitle: Text(
          thread.lastMessage.isNotEmpty ? thread.lastMessage : '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isUnread ? Colors.black.withOpacity(.7) : Colors.black.withOpacity(.5),
            fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        trailing: _buildTrailing(time, thread.unreadStore),
        onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ChatPage(threadId: thread.id, asStore: true)),
            ),
      ),
    );
  }

  Widget _buildTrailing(String time, int unreadCount) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(time, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 8),
        if (unreadCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF7A4E3A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('$unreadCount', style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
      ],
    );
  }

  String _readableTime(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
