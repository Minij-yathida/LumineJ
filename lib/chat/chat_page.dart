// lib/pages/chat/chat_page.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:LumineJewelry/services/chat_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/app_colors.dart';

class ChatPage extends StatefulWidget {
  final String? threadId;
  /// true = เปิดในโหมดร้าน/แอดมิน, false = ลูกค้า
  final bool asStore;

  const ChatPage({
    Key? key,
    this.threadId,
    this.asStore = false,
  }) : super(key: key);

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _auth = FirebaseAuth.instance;
  final _chatService = ChatService();
  final _ctrl = TextEditingController();

  String? _threadId;
  bool _isCustomer = true;
  bool _isLoading = true;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _threadSub;
  Timestamp? _lastSeenUserTs;
  Timestamp? _lastSeenStoreTs;
  int _unreadUser = 0;
  int _unreadStore = 0;
  String? _lastClearedMsgId;

  // เก็บ bubble รูป local ชั่วคราว
  final List<_LocalImageBubble> _localImages = [];

  bool get _isStore => widget.asStore;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _threadSub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  // ---------- INIT / THREAD SETUP ----------

  Future<void> _bootstrap() async {
    try {
      final me = _auth.currentUser;
      if (me == null) throw Exception('กรุณาเข้าสู่ระบบก่อน');

      DocumentReference<Map<String, dynamic>> ref;

      if (_isStore) {
        // 🛍 โหมดร้าน/แอดมิน: ต้องมี threadId มาจากหน้า list
        if (widget.threadId == null || widget.threadId!.isEmpty) {
          throw Exception('ไม่พบรหัสห้องแชท');
        }
        ref = FirebaseFirestore.instance
            .collection('threads')
            .doc(widget.threadId);
      } else {
        // 👤 โหมดลูกค้า: เปิด/สร้างห้องของตัวเอง (uid__STORE_Chat)
        ref = await _chatService.openOrCreateThread(widget.threadId);
      }

      final snap = await ref.get();
      if (!snap.exists) throw Exception('ไม่พบห้องแชท');

      final data = snap.data() ?? {};
      final userId = (data['userId'] as String?) ?? me.uid;

      _threadId = ref.id;

      // ลูกค้าคือ uid ตรงกับ userId และไม่ได้บังคับ asStore
      _isCustomer = !_isStore && me.uid == userId;

      _isLoading = false;
      if (mounted) setState(() {});

      
      if (_isCustomer) {
        await _chatService.sendWelcomeIfEmpty(_threadId!);
      }

      // ✅ เข้าแล้วถือว่าอ่านข้อความ → เคลียร์ unread / อัปเดต lastSeen
      await _chatService.markChatReadOnOpen(
        _threadId!,
        asStore: _isStore,
      );

      // ✅ ฟัง thread เพื่ออัปเดต lastSeen / unread ใช้สำหรับ read tick
      _threadSub = _chatService.threadStream(_threadId!).listen((doc) {
        final d = doc.data() ?? {};
        _lastSeenUserTs = d['lastSeen_user'] as Timestamp?;
        _lastSeenStoreTs = d['lastSeen_store'] as Timestamp?;
        _unreadUser = d['unread_user'] is int ? d['unread_user'] as int : 0;
        _unreadStore =
            d['unread_store'] is int ? d['unread_store'] as int : 0;
        if (mounted) setState(() {});
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เข้าแชทไม่สำเร็จ: $e')),
      );
      if (Navigator.canPop(context)) Navigator.pop(context);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream() {
    if (_threadId == null) return const Stream.empty();
    return _chatService.messagesStream(_threadId!);
  }

  /// ถ้ามีข้อความใหม่จากอีกฝั่ง และยังมี unread → mark read ให้
  Future<void> _maybeClearOnNewOtherMessage(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    if (_threadId == null) return;
    if (snap.docs.isEmpty) return;

    final me = _auth.currentUser;
    if (me == null) return;

    final newestDoc = snap.docs.first;
    final newest = newestDoc.data();
    final newestSender = (newest['senderId'] ?? '').toString();

    final hasUnread = _isStore ? (_unreadStore > 0) : (_unreadUser > 0);
    if (!hasUnread) return;
    if (newestSender == me.uid) return;
    if (_lastClearedMsgId == newestDoc.id) return;

    try {
      await _chatService.markChatReadOnOpen(
        _threadId!,
        asStore: _isStore,
      );
      _lastClearedMsgId = newestDoc.id;
    } catch (_) {
      // เงียบไป ไม่ให้ล้ม UI
    }
  }

  // ---------- SEND ----------

  Future<void> _sendText() async {
    if (_threadId == null) return;
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    _ctrl.clear();
    try {
      await _chatService.sendText(_threadId!, text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ส่งข้อความไม่สำเร็จ: $e')),
      );
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_threadId == null) return;
    final file = await _chatService.pickImage();
    if (file == null) return;
    final bytes = await file.readAsBytes();

    final ok = await _confirmImage(bytes);
    if (ok != true) return;

    // แสดง bubble local ทันที (optimistic)
    final tempId = UniqueKey().toString();
    setState(() {
      _localImages.insert(0, _LocalImageBubble(id: tempId, bytes: bytes));
    });

    try {
      await _chatService.sendImageFromBytes(_threadId!, bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _localImages.removeWhere((x) => x.id == tempId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ส่งรูปไม่สำเร็จ: $e')),
      );
      return;
    }

    if (mounted) {
      setState(() {
        _localImages.removeWhere((x) => x.id == tempId);
      });
    }
  }

  Future<bool?> _confirmImage(Uint8List bytes) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('ส่งรูปภาพนี้หรือไม่?'),
        content: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(bytes, fit: BoxFit.cover),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ส่งรูป'),
          ),
        ],
      ),
    );
  }

  // ---------- BUILD UI ----------

  @override
  Widget build(BuildContext context) {
    final me = _auth.currentUser;
    if (me == null) {
      return const Scaffold(
        body: Center(child: Text('กรุณาเข้าสู่ระบบ')),
      );
    }

    if (_isLoading || _threadId == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.background,
          centerTitle: true,
          elevation: 2,
          title: const Text(
            'แชทกับร้าน',
            style: TextStyle(
              fontFamily: 'PlayfairDisplay',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF5D4037),
            ),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        centerTitle: true,
        elevation: 2,
        title: _ThreadTitle(
          isCustomer: _isCustomer,
          threadId: _threadId!,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _messagesStream(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _errorBox('ไม่สามารถโหลดข้อความ: ${snap.error}');
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data?.docs ?? [];

                if (docs.isEmpty && _localImages.isEmpty) {
                  // ถ้ายังไม่มี msg จริงเลย (ระบบยังไม่ยิง welcome)
                  return const Center(child: Text('สวัสดีค่ะ ขอบคุณที่ติดต่อร้าน 🌸 My LumineJewelry ❤️ \nพิมพ์สอบถามได้เลย จะรีบตอบกลับลูกค้าให้อย่างเร่งด่วนที่สุด'));
                }

                if (snap.data != null) {
                  _maybeClearOnNewOtherMessage(snap.data!);
                }

                final totalCount = _localImages.length + docs.length;

                return ListView.builder(
                  reverse: true,
                  cacheExtent: 800,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  itemCount: totalCount,
                  itemBuilder: (_, i) {
                    // อันบนสุด: local images
                    if (i < _localImages.length) {
                      final local = _localImages[i];
                      return _buildImageBubbleLocal(local.bytes);
                    }

                    final docIndex = i - _localImages.length;
                    final doc = docs[docIndex];
                    final m = doc.data();
                    final isMe = m['senderId'] == me.uid;
                    final isSystem = (m['system'] == true);
                    final type = m['type'] as String?;
                    final createdAt = m['createdAt'] as Timestamp?;

                    // bubble system (welcome)
                    if (isSystem) {
                      return Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 6),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0E8E4),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              m['text'] ?? '',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.brown),
                            ),
                          ),
                        ),
                      );
                    }

                    // คำนวณอ่านแล้ว
                    bool isRead = false;
                    if (isMe && createdAt != null) {
                      final otherSeen =
                          _isStore ? _lastSeenUserTs : _lastSeenStoreTs;
                      if (otherSeen != null &&
                          otherSeen.millisecondsSinceEpoch >=
                              createdAt.millisecondsSinceEpoch) {
                        isRead = true;
                      }
                    }

                    final bubbleColor = isMe
                        ? const Color(0xFFE3F2FD)
                        : const Color(0xFFF5F5F5);

                    Widget content;
                    if (type == 'image') {
                      final imageUrl =
                          (m['imageUrl'] ?? '').toString();
                      content = _buildImageBubbleNetwork(
                        context: context,
                        docId: doc.id,
                        imageUrl: imageUrl,
                      );
                    } else {
                      content = Text(
                        (m['text'] ?? '').toString(),
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                      );
                    }

                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: isMe
                            ? CrossAxisAlignment.end
                            : CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: isMe
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            children: [
                              Container(
                                constraints:
                                    const BoxConstraints(maxWidth: 280),
                                padding:
                                    const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: bubbleColor,
                                  borderRadius:
                                      BorderRadius.circular(14),
                                ),
                                child: content,
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 4, right: 4, left: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (createdAt != null)
                                  Text(
                                    DateFormat('d MMM HH:mm', 'th_TH')
                                        .format(createdAt.toDate()),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.black45,
                                    ),
                                  ),
                                if (isMe) const SizedBox(width: 6),
                                if (isMe)
                                  Icon(
                                    isRead
                                        ? Icons.done_all
                                        : Icons.check,
                                    size: 16,
                                    color: isRead
                                        ? Colors.blue
                                        : Colors.grey,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _inputBar(),
        ],
      ),
    );
  }

  // ---------- Widgets ย่อย ----------

  Widget _buildImageBubbleLocal(Uint8List bytes) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 280),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(
                    bytes,
                    width: 180,
                    height: 180,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4, right: 4),
            child: Text(
              'กำลังอัปโหลด...',
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageBubbleNetwork({
    required BuildContext context,
    required String docId,
    required String imageUrl,
  }) {
    if (imageUrl.isEmpty) {
      return Container(
        width: 180,
        height: 180,
        color: Colors.grey.shade100,
        child: const Icon(
          Icons.broken_image_outlined,
          size: 40,
          color: Colors.grey,
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _ImageViewerPage(
              imageUrl: imageUrl,
              heroTag: '${docId}_img',
            ),
          ),
        );
      },
      child: Hero(
        tag: '${docId}_img',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            memCacheWidth: 400,
            memCacheHeight: 400,
            maxWidthDiskCache: 400,
            maxHeightDiskCache: 400,
            placeholder: (context, url) => Container(
              width: 180,
              height: 180,
              color: Colors.grey.shade200,
            ),
            errorWidget: (context, url, error) => Container(
              width: 180,
              height: 180,
              color: Colors.grey.shade100,
              child: const Icon(
                Icons.broken_image_outlined,
                size: 40,
                color: Colors.grey,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputBar() {
    final bg = const Color(0xFFF6E9E4);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Row(
          children: [
            InkWell(
              onTap: _pickAndSendImage,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.image_outlined,
                  color: Colors.brown,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: 'พิมพ์ข้อความ...',
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _sendText(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: _sendText,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.brown.shade400,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.10),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.send,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBox(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _bootstrap,
              child: const Text('ลองใหม่'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- TITLE WIDGET ----------

class _ThreadTitle extends StatelessWidget {
  final bool isCustomer;
  final String threadId;

  const _ThreadTitle({
    required this.isCustomer,
    required this.threadId,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('threads')
          .doc(threadId)
          .snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const Text(
            'แชทกับร้าน',
            style: TextStyle(
              fontFamily: 'PlayfairDisplay',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF5D4037),
            ),
          );
        }
        final data = snap.data!.data() ?? {};
        final storeId = (data['storeId'] ?? '').toString();

        if (isCustomer) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text(
                'แชทกับร้าน',
                style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF5D4037),
                ),
              ),
              if (storeId.isNotEmpty)
                Text(
                  storeId,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
            ],
          );
        }

        final name = (data['userDisplayName'] ??
                data['userEmail'] ??
                'ลูกค้า')
            .toString();
        final email = (data['userEmail'] ?? '').toString();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5D4037),
              ),
            ),
            if (email.isNotEmpty)
              Text(
                email,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------- HELPERS ----------

class _LocalImageBubble {
  final String id;
  final Uint8List bytes;
  _LocalImageBubble({required this.id, required this.bytes});
}

class _ImageViewerPage extends StatelessWidget {
  final String imageUrl;
  final String heroTag;

  const _ImageViewerPage({
    required this.imageUrl,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Center(
        child: Hero(
          tag: heroTag,
          child: InteractiveViewer(
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.contain,
              placeholder: (context, url) =>
                  Container(color: Colors.black),
              errorWidget: (context, url, error) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white70,
                size: 60,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
