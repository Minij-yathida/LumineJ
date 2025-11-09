import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img; // ✅ ใช้ย่อลดขนาดรูป

class ChatService {
  // --- Config ---
  static const String storeId = 'STORE_Chat';
  static const String IMGBB_KEY = 'c58a57ebfa7c164a274dc230c970f5a2';
  // ---------------

  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;
  final _picker = ImagePicker();

  String _threadIdFor(String userId, String storeId) => '${userId}__${storeId}';

  Future<DocumentReference<Map<String, dynamic>>> openOrCreateThread(
    String? currentThreadId, {
    String? targetStoreId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    final uid = user.uid;
    final store = (targetStoreId != null && targetStoreId.isNotEmpty)
        ? targetStoreId
        : storeId;
    final id = (currentThreadId != null && currentThreadId.isNotEmpty)
        ? currentThreadId
        : _threadIdFor(uid, store);

    final ref = _fs.collection('threads').doc(id);
    final snap = await ref.get();

    if (!snap.exists) {
      await ref.set({
        'participants': [uid, store],
        'userId': uid,
        'storeId': store,
        'userDisplayName': user.displayName ?? 'Customer (${uid.substring(0, 4)})',
        'userEmail': user.email ?? '',
        'userPhotoUrl': user.photoURL ?? '',
        'lastMessage': '',
        'lastSender': null,
        'lastAt': FieldValue.serverTimestamp(),
        'unread_user': 0,
        'unread_store': 0,
        'unread': 0,
      }, SetOptions(merge: true));
    }

    return ref;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> threadStream(String threadId) {
    return _fs.collection('threads').doc(threadId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(String threadId) {
    return _fs
        .collection('threads')
        .doc(threadId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  Future<void> sendWelcomeIfEmpty(String threadId) async {
    final msgs = _fs.collection('threads').doc(threadId).collection('messages');
    final q = await msgs.limit(1).get();
    if (q.docs.isNotEmpty) return;

    final uid = _auth.currentUser!.uid;
    final msgRef = msgs.doc();
    final now = FieldValue.serverTimestamp();

    await msgRef.set({
      'id': msgRef.id,
      'threadId': threadId,
      'senderId': uid,
      'type': 'text',
      'text':
          'สวัสดีค่ะ ขอบคุณที่ติดต่อร้าน 🌸\nพิมพ์สอบถามได้เลย จะรีบตอบกลับลูกค้าให้อย่างเร่งด่วนที่สุด',
      'createdAt': now,
      'sentAt': now,
      'status': 'sent',
      'system': true,
    });

    await _fs.collection('threads').doc(threadId).update({
      'lastMessage': 'ยินดีต้อนรับ 👋',
      'lastSender': uid,
      'lastAt': now,
      'unread_user': 0,
      'unread_store': 0,
      'unread': 0,
    });
  }

  Future<void> sendText(String threadId, String text) async {
    final uid = _auth.currentUser!.uid;
    final threadRef = _fs.collection('threads').doc(threadId);
    final msgRef = threadRef.collection('messages').doc();
    final now = FieldValue.serverTimestamp();

    final batch = _fs.batch();

    batch.set(msgRef, {
      'id': msgRef.id,
      'threadId': threadId,
      'senderId': uid,
      'type': 'text',
      'text': text,
      'createdAt': now,
      'sentAt': now,
      'status': 'sent',
      'system': false,
    });

    final threadSnap = await threadRef.get();
    if (!threadSnap.exists) {
      await batch.commit();
      return;
    }

    final data = threadSnap.data()!;
    final userId = (data['userId'] ?? uid) as String;
    final bool isCustomer = (uid == userId);

    batch.update(threadRef, {
      'lastMessage': text,
      'lastSender': uid,
      'lastAt': now,
      if (isCustomer)
        'unread_store': FieldValue.increment(1)
      else
        'unread_user': FieldValue.increment(1),
      'unread': FieldValue.increment(1),
    });

    await batch.commit();
  }

  /// ✅ เลือกรูปด้วยคุณภาพลดลงหน่อย เพื่อลดขนาดไฟล์ (upload + โหลดไวขึ้น)
  Future<XFile?> pickImage() async {
    return _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70, // เดิม 85 → ลดลงให้ไฟล์เล็กลง
    );
  }

  /// ✅ ย่อ/บีบอัดรูปก่อนส่งไป ImgBB → URL โหลดเร็วขึ้น
  Future<void> sendImageFromBytes(String threadId, Uint8List bytes) async {
    final uid = _auth.currentUser!.uid;

    // 1) พยายามย่อรูป (ถ้า decode ได้)
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        const maxSide = 900; // ด้านยาวสุด ~900px พอใช้ในแชท
        final resized = img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? maxSide : null,
          height: decoded.height > decoded.width ? maxSide : null,
        );

        // เข้ารหัส JPG ใหม่ ลดคุณภาพลงเพื่อเล็กลง
        final compressed = img.encodeJpg(resized, quality: 70);
        bytes = Uint8List.fromList(compressed);
      }
    } catch (e) {
      debugPrint('image compress error: $e');
      // ถ้า compress พัง ใช้ bytes เดิมต่อได้ ไม่ต้อง throw
    }

    // 2) อัปโหลดไป ImgBB (base64)
    final base64Image = base64Encode(bytes);

    final response = await http.post(
      Uri.parse('https://api.imgbb.com/1/upload?key=$IMGBB_KEY'),
      body: {'image': base64Image},
    );

    Map<String, dynamic> result;
    try {
      result = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('imgbb: invalid json response: ${response.body}');
      throw Exception('Upload failed: invalid response');
    }

    if (result['status'] != 200 && result['success'] != true) {
      debugPrint('imgbb upload failed: ${response.body}');
      throw (result['error']?['message'] ?? 'Upload failed');
    }

    final dataMap = (result['data'] ?? {}) as Map<String, dynamic>;
    final imageUrl = (dataMap['url'] ??
            dataMap['display_url'] ??
            dataMap['image'] ??
            dataMap['thumb'] ??
            dataMap['viewer'] ??
            '')
        .toString();

    if (imageUrl.isEmpty) {
      debugPrint('imgbb: no usable url in response: ${response.body}');
      throw Exception('Upload failed: no image url returned');
    }

    // 3) เขียน message + อัปเดต thread (เหมือนเดิม)
    final threadRef = _fs.collection('threads').doc(threadId);
    final msgRef = threadRef.collection('messages').doc();
    final now = FieldValue.serverTimestamp();

    final batch = _fs.batch();

    batch.set(msgRef, {
      'id': msgRef.id,
      'threadId': threadId,
      'senderId': uid,
      'type': 'image',
      'imageUrl': imageUrl,
      'createdAt': now,
      'sentAt': now,
      'status': 'sent',
      'system': false,
    });

    final threadSnap = await threadRef.get();
    if (!threadSnap.exists) {
      await batch.commit();
      return;
    }

    final data = threadSnap.data()!;
    final userId = (data['userId'] ?? uid) as String;
    final bool isCustomer = (uid == userId);

    batch.update(threadRef, {
      'lastMessage': '[รูปภาพ]',
      'lastSender': uid,
      'lastAt': now,
      if (isCustomer)
        'unread_store': FieldValue.increment(1)
      else
        'unread_user': FieldValue.increment(1),
      'unread': FieldValue.increment(1),
    });

    await batch.commit();
  }

  Future<void> markChatReadOnOpen(String threadId, {bool asStore = false}) async {
    final ref = _fs.collection('threads').doc(threadId);
    final threadSnap = await ref.get();
    if (!threadSnap.exists) return;
    final data = threadSnap.data()!;
    final userId = data['userId'] as String? ?? '';
    final storeIdLocal = data['storeId'] as String? ?? storeId;

    final currentUserId = _auth.currentUser!.uid;
    final isCustomer = !asStore;

    final otherParticipantId = isCustomer ? storeIdLocal : userId;

    final msgsRef = ref.collection('messages');
    final qs = await msgsRef
        .where('senderId', isEqualTo: otherParticipantId)
        .where('status', whereIn: ['sent', 'delivered'])
        .get();

    if (qs.docs.isNotEmpty) {
      final batch = _fs.batch();
      for (final doc in qs.docs) {
        batch.update(doc.reference, {
          'status': 'read',
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }

    await ref.update({
      if (isCustomer) 'unread_user': 0 else 'unread_store': 0,
      'unread': 0,
      if (isCustomer)
        'lastSeen_user': FieldValue.serverTimestamp()
      else
        'lastSeen_store': FieldValue.serverTimestamp(),
    });
  }

  Stream<int> totalUnreadStoreCountStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return _fs
        .collection('threads')
        .where('storeId', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
      int totalUnread = 0;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        totalUnread += (data['unread_store'] ?? 0) as int;
      }
      return totalUnread;
    });
  }
}