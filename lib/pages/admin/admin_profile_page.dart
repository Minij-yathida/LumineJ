// lib/pages/admin/admin_profile_page.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/order_guard.dart'; // ensureAdminPageOrDialog()

class AdminProfilePage extends StatefulWidget {
  const AdminProfilePage({super.key});

  @override
  State<AdminProfilePage> createState() => _AdminProfilePageState();
}

class _AdminProfilePageState extends State<AdminProfilePage> {
  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;
  final _st = FirebaseStorage.instance;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Guard: admin only
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ok = await ensureAdminPageOrDialog(context);
      if (!ok && mounted) Navigator.pop(context);
    });
  }

  DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _fs.collection('users').doc(uid);

  Future<void> _changeProfileIcon(String uid) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (picked == null) return;

      setState(() => _busy = true);

      final file = File(picked.path);
      final ref = _st.ref().child('users/$uid/profile_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      await _userRef(uid).update({'profileIcon': url, 'updatedAt': FieldValue.serverTimestamp()});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('อัปเดตรูปโปรไฟล์แล้ว')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('อัปโหลดไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editField({
    required String uid,
    required String title,
    required String field,
    required String initial,
    int maxLines = 1,
  }) async {
    final c = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          maxLines: maxLines,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('บันทึก')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      setState(() => _busy = true);
      await _userRef(uid).update({field: c.text.trim(), 'updatedAt': FieldValue.serverTimestamp()});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกสำเร็จ')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('กรุณาเข้าสู่ระบบ'));
    }

    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _userRef(uid).snapshots(),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snap.hasData || !snap.data!.exists) {
              return const Center(child: Text('ไม่พบข้อมูลผู้ใช้'));
            }

            final data = snap.data!.data()!;
            final email = (data['email'] ?? _auth.currentUser?.email ?? '') as String;
            final name = (data['displayName'] ?? '') as String;
            final phone = (data['phoneNumber'] ?? data['phone'] ?? '') as String? ?? '';
            final address = (data['address'] ?? '') as String? ?? '';
            final icon = (data['profileIcon'] ?? '') as String? ?? '';

            return ListView(
              padding: EdgeInsets.zero,
              children: [
                // Header (ไม่มี AppBar — ทำ Header เองให้ใกล้เคียงลูกค้า)
                Container(
                  padding: const EdgeInsets.only(top: 36, bottom: 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        cs.primary.withOpacity(.20),
                        cs.primaryContainer.withOpacity(.30),
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Text('My Profile', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text('Luminé Jewelry Member', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 18),
                      CircleAvatar(
                        radius: 48,
                        backgroundColor: cs.surfaceVariant,
                        backgroundImage: icon.isNotEmpty ? NetworkImage(icon) : null,
                        child: icon.isEmpty ? Icon(Icons.person, size: 48, color: cs.onSurface.withOpacity(.55)) : null,
                      ),
                      const SizedBox(height: 12),
                      Text(email, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.image_outlined),
                            label: const Text('Change Profile Icon'),
                            onPressed: () => _changeProfileIcon(uid),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                _inputTile(
                  icon: Icons.badge_outlined,
                  label: 'Full Name',
                  value: name.isEmpty ? '—' : name,
                  trailing: TextButton.icon(
                    onPressed: () => _editField(uid: uid, title: 'แก้ไขชื่อ', field: 'displayName', initial: name),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit'),
                  ),
                ),
                _inputTile(
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: email,
                  trailing: const Text('Not editable', style: TextStyle(color: Colors.black45)),
                ),
                _inputTile(
                  icon: Icons.phone_outlined,
                  label: 'Phone',
                  value: phone.isEmpty ? '—' : phone,
                  trailing: const Text('Not editable', style: TextStyle(color: Colors.black45)),
                ),
                _inputTile(
                  icon: Icons.location_on_outlined,
                  label: 'Address',
                  value: (address.isEmpty ? '—' : address),
                  trailing: TextButton.icon(
                    onPressed: () => _editField(uid: uid, title: 'แก้ไขที่อยู่', field: 'address', initial: address, maxLines: 4),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            );
          },
        ),

        if (_busy)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(.08),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  Widget _inputTile({
    required IconData icon,
    required String label,
    required String value,
    Widget? trailing,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: .5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color)),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }
}
