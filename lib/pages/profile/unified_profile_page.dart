// lib/pages/profile/unified_profile_page.dart
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../widgets/profile_info_card.dart';

class UnifiedProfilePage extends StatefulWidget {
  const UnifiedProfilePage({super.key});

  @override
  State<UnifiedProfilePage> createState() => _UnifiedProfilePageState();
}

class _UnifiedProfilePageState extends State<UnifiedProfilePage> {
  final _fs = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _busy = false;
  String? _localPickedPath; // local preview

  // ---------------- Name & Address ----------------

  Future<void> _editName(String oldVal) async {
    final u = _auth.currentUser;
    if (u == null) return;

    final c = TextEditingController(text: oldVal);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('แก้ไขชื่อ–นามสกุล'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(hintText: 'ชื่อ–นามสกุลใหม่'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );

    if (!mounted || ok != true) return;

    setState(() => _busy = true);
    try {
      await _fs.collection('users').doc(u.uid).update({
        'displayName': c.text.trim(),
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editAddress(String oldVal) async {
    final u = _auth.currentUser;
    if (u == null) return;

    final c = TextEditingController(text: oldVal);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('แก้ไขที่อยู่'),
        content: TextField(
          controller: c,
          decoration: const InputDecoration(hintText: 'ที่อยู่อาศัยใหม่'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );

    if (!mounted || ok != true) return;

    setState(() => _busy = true);
    try {
      await _fs.collection('users').doc(u.uid).update({
        'address': c.text.trim(),
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- Avatar (อัปโหลด + ให้โหลดไวขึ้น) ----------------

  Future<void> _changePhotoUrl(String? current) async {
    final u = _auth.currentUser;
    if (u == null) return;

    final picker = ImagePicker();
    XFile? picked;

    try {
      picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 65, // ลดขนาดไฟล์ลง
        maxWidth: 800,
        maxHeight: 800,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ไม่สามารถเข้าถึงรูปได้: $e')),
      );
      return;
    }

    if (picked == null) return;

    setState(() {
      _localPickedPath = picked!.path; // แสดง preview ก่อน
      _busy = true;
    });

    try {
      const imgbbKey = String.fromEnvironment(
        'IMGBB_KEY',
        defaultValue: '82bd12994bc8362dc693b62326838c40',
      );
      if (imgbbKey.isEmpty) {
        throw Exception('IMGBB_KEY ไม่ถูกตั้งค่า');
      }

      final uri = Uri.parse('https://api.imgbb.com/1/upload?key=$imgbbKey');

      final request = http.MultipartRequest('POST', uri)
        ..files.add(
          await http.MultipartFile.fromPath('image', picked.path),
        );

      final streamed = await request.send();
      final res = await http.Response.fromStream(streamed);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          final imageData = data['data'] as Map<String, dynamic>;

          // ถ้ามี thumb ให้ใช้ (ไฟล์เล็ก โหลดไว) ถ้าไม่มีก็ใช้ url ปกติ
          final thumb = (imageData['thumb'] ?? {}) as Map<String, dynamic>;
          final url =
              (thumb['url'] as String?) ?? (imageData['url'] as String);

          await _fs.collection('users').doc(u.uid).update({
            'profilePhotoUrl': url,
          });

          if (!mounted) return;
          setState(() {
            _busy = false;
            _localPickedPath = null; // ให้ใช้รูปจาก network แทน
          });
          return;
        }

        throw Exception(
          'อัปโหลด ImgBB ล้มเหลว: ${data['error'] ?? 'unknown'}',
        );
      } else {
        throw Exception('IMGBB HTTP ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('อัปโหลดรูปไม่สำเร็จ: $e')),
      );
      setState(() {
        _busy = false;
        // ถ้า fail ให้คงรูปเดิมไว้
        _localPickedPath = null;
      });
    }
  }

  // ---------------- Logout ----------------

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการออกจากระบบ'),
        content: const Text('คุณต้องการออกจากระบบจริงหรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ออกจากระบบ'),
          ),
        ],
      ),
    );

    if (!mounted || confirm != true) return;

    setState(() => _busy = true);
    try {
      await _auth.signOut();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/login',
        (r) => false,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------- Utils ----------------

  String _fmtDT(dynamic v) {
    DateTime? dt;
    if (v is Timestamp) dt = v.toDate();
    if (v is DateTime) dt = v;
    return dt == null
        ? '-'
        : DateFormat('d MMM y, HH:mm', 'th_TH').format(dt);
  }

  // ---------------- Build ----------------

  @override
  Widget build(BuildContext context) {
    final u = _auth.currentUser;
    if (u == null) {
      return const Center(child: Text('Not signed in'));
    }

    return Stack(
      children: [
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _fs.collection('users').doc(u.uid).snapshots(),
          builder: (context, s) {
            if (s.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final doc = s.data;
            final data = doc?.data() ?? <String, dynamic>{};

            data['email'] ??= u.email ?? '-';
            data['displayName'] ??= u.displayName ?? '-';
            data['createdAt'] ??= u.metadata.creationTime;
            data['lastLogin'] ??= u.metadata.lastSignInTime;

            final role =
                (data['role'] ?? 'customer').toString().trim().toLowerCase();
            final isAdmin = role == 'admin';

            final email = (data['email'] ?? '-').toString();
            final name = (data['displayName'] ?? '-').toString();
            final phone = (data['phoneNumber'] ?? '-').toString();
            final photoUrl = (data['profilePhotoUrl'] ?? '').toString();
            final createdAt = data['createdAt'] ?? u.metadata.creationTime;
            final lastLogin = data['lastLogin'] ?? u.metadata.lastSignInTime;
            final address = (data['address'] ?? '-').toString();

            return SingleChildScrollView(
              child: Column(
                children: [
                  // ---------- Profile Header ----------
                  Container(
                    height: 210,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.brown.shade200,
                          Colors.brown.shade400,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(30),
                        bottomRight: Radius.circular(30),
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: () => _changePhotoUrl(photoUrl),
                            child: SizedBox(
                              width: 100,
                              height: 100,
                              child: ClipOval(
                                child: Builder(
                                  builder: (ctx) {
                                    // 1) local preview ทันทีหลังเลือก
                                    if (_localPickedPath != null) {
                                      return Image.file(
                                        File(_localPickedPath!),
                                        width: 100,
                                        height: 100,
                                        fit: BoxFit.cover,
                                      );
                                    }

                                    // 2) รูปจากเน็ต: ใช้ CachedNetworkImage + จำกัดขนาด cache ให้เล็กลง
                                    if (photoUrl.isNotEmpty) {
                                      return CachedNetworkImage(
                                        imageUrl: photoUrl,
                                        // จำกัด size ใน cache ให้เหมาะกับ avatar
                                        memCacheWidth: 200,
                                        memCacheHeight: 200,
                                        maxWidthDiskCache: 200,
                                        maxHeightDiskCache: 200,
                                        imageBuilder: (context, imageProvider) {
                                          return Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              image: DecorationImage(
                                                image: imageProvider,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          );
                                        },
                                        placeholder: (_, __) => Container(
                                          color: Colors.white,
                                          child: const Center(
                                            child: SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            ),
                                          ),
                                        ),
                                        errorWidget: (_, __, ___) => Container(
                                          color: Colors.white,
                                          child: Icon(
                                            Icons.account_circle,
                                            size: 80,
                                            color: Colors.brown[400],
                                          ),
                                        ),
                                      );
                                    }

                                    // 3) ไม่มีรูป -> icon
                                    return Container(
                                      color: Colors.white,
                                      child: Icon(
                                        Icons.account_circle,
                                        size: 80,
                                        color: Colors.brown[400],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            email,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ---------- Change Profile Picture ----------
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ElevatedButton.icon(
                      onPressed: () => _changePhotoUrl(photoUrl),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.brown[200],
                        foregroundColor: Colors.brown[900],
                        minimumSize: const Size(double.infinity, 45),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.image),
                      label: const Text('Change Profile Picture'),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ---------- Info Cards ----------
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        ProfileInfoCard(
                          icon: Icons.person,
                          label: 'Full Name',
                          value: name,
                          trailing: isAdmin
                              ? const Text(
                                  'Not editable',
                                  style: TextStyle(
                                      color: Colors.grey, fontSize: 12),
                                )
                              : TextButton.icon(
                                  onPressed: () => _editName(name),
                                  icon: const Icon(Icons.edit, size: 18),
                                  label: const Text('Edit'),
                                ),
                        ),
                        const SizedBox(height: 10),
                        ProfileInfoCard(
                          icon: Icons.email,
                          label: 'Email',
                          value: email,
                          trailing: const Text(
                            'Not editable',
                            style:
                                TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ProfileInfoCard(
                          icon: Icons.phone,
                          label: 'Phone',
                          value: phone,
                          trailing: const Text(
                            'Not editable',
                            style:
                                TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ProfileInfoCard(
                          icon: Icons.badge_outlined,
                          label: 'Position',
                          value: role,
                          trailing: const Text(
                            '—',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (role == 'customer') ...[
                          ProfileInfoCard(
                            icon: Icons.location_on,
                            label: 'Address',
                            value: address,
                            trailing: TextButton.icon(
                              onPressed: () => _editAddress(address),
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('Edit'),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        ProfileInfoCard(
                          icon: Icons.event_available,
                          label: 'Account Created',
                          value: _fmtDT(createdAt),
                          trailing: const Text(
                            '—',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        const SizedBox(height: 10),
                        ProfileInfoCard(
                          icon: Icons.access_time,
                          label: 'Last Login',
                          value: _fmtDT(lastLogin),
                          trailing: const Text(
                            '—',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ---------- Logout ----------
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _logout,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[400],
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.logout),
                          label: const Text('Logout'),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        if (_busy)
          Container(
            color: Colors.black26,
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
      ],
    );
  }
}
