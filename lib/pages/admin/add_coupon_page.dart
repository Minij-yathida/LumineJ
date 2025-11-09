import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AddCouponPage extends StatefulWidget {
  const AddCouponPage({super.key});
  @override
  State<AddCouponPage> createState() => _AddCouponPageState();
}

class _AddCouponPageState extends State<AddCouponPage> {
  final fs = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    // แนะนำให้ลบคูปองหมดอายุด้วย Cloud Functions / สคริปต์ฝั่งแอดมิน
    // ไม่ทำ auto delete จาก client เพื่อลด PERMISSION_DENIED
    // _cleanupExpiredCoupons();
  }

  /// ถ้าจะใช้ลบคูปองหมดอายุจากฝั่ง client
  /// ให้แน่ใจว่าหน้านี้ใช้เฉพาะ admin และ rules อนุญาต isAdminViaDoc()
  Future<void> _cleanupExpiredCoupons() async {
    final now = Timestamp.now();
    final snap = await fs
        .collection('coupons')
        .where('expiresAt', isLessThan: now)
        .get();
    for (final doc in snap.docs) {
      await doc.reference.delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.##', 'th_TH');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'คูปอง & โปรโมชัน',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _openEditorDialog(),
                icon: const Icon(Icons.add),
                label: const Text('เพิ่มคูปอง'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        /// แสดงรายการคูปองทั้งหมด
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: fs
                .collection('coupons')
                .orderBy('code')
                .snapshots(),
            builder: (_, s) {
              if (s.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = s.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(child: Text('ยังไม่มีคูปอง'));
              }

              return ListView.separated(
                padding: const EdgeInsets.all(12),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final id = docs[i].id;
                  final d = docs[i].data();

                  final code = (d['code'] ?? '').toString();
                  final type = (d['type'] ?? 'percent').toString();
                  final value = (d['value'] ?? 0) as num;
                  final desc = (d['description'] ?? '').toString();
                  final expiresAt = d['expiresAt'] as Timestamp?;
                  final usageLimit = (d['usageLimit'] is num)
                      ? (d['usageLimit'] as num).toInt()
                      : 0;
                  final usedCount = (d['usedCount'] is num)
                      ? (d['usedCount'] as num).toInt()
                      : 0;
                  final active = d['active'] == true;

                  final now = DateTime.now();
                  final isExpired = expiresAt != null &&
                      expiresAt.toDate().isBefore(now);

                  // แสดงข้อความจำนวนการใช้แบบไม่หลอกตา
                  final remaining = usageLimit == 0
                      ? 'ไม่จำกัด'
                      : (usageLimit - usedCount).clamp(0, usageLimit).toString();

                  final limitText = usageLimit == 0
                      ? 'ใช้ไปแล้ว $usedCount ครั้ง (ไม่จำกัด)'
                      : 'ใช้แล้ว $usedCount / $usageLimit ครั้ง (เหลือ $remaining)';

                  final expireText = expiresAt == null
                      ? 'ไม่มีวันหมดอายุ'
                      : (isExpired
                          ? 'หมดอายุแล้ว (${DateFormat('d MMM yyyy', 'th_TH').format(expiresAt.toDate())})'
                          : 'หมดอายุ ${DateFormat('d MMM yyyy', 'th_TH').format(expiresAt.toDate())}');

                  return Container(
                    decoration: BoxDecoration(
                      color: isExpired ? const Color(0xFFFFF3E0) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isExpired
                            ? const Color(0xFFFFCC80)
                            : const Color(0xFFFFE0B2),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: ListTile(
                      title: Text(
                        '$code (${type == "percent" ? "$value%" : "฿${money.format(value)}"})',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isExpired
                              ? Colors.grey
                              : const Color(0xFF5D4037),
                        ),
                      ),
                      subtitle: Text(
                        [
                          desc.isEmpty ? 'ไม่มีคำอธิบาย' : desc,
                          limitText,
                          expireText,
                          if (!active) 'สถานะ: ปิดการใช้งาน',
                        ].join('\n'),
                        style: TextStyle(
                          color: isExpired ? Colors.grey : Colors.brown,
                        ),
                      ),
                      leading: Switch(
                        value: active && !isExpired,
                        onChanged: isExpired
                            ? null // หมดอายุแล้ว ปิดสวิตช์
                            : (v) async {
                                await fs
                                    .collection('coupons')
                                    .doc(id)
                                    .update({
                                  'active': v,
                                  'updatedAt': FieldValue.serverTimestamp(),
                                });
                              },
                      ),
                      trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'edit') {
                              _openEditorDialog(docId: id, initial: d);
                            } else if (v == 'delete') {
                              // ⬇ กล่องยืนยันการลบ
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('ลบคูปองหรือไม่?'),
                                  content: Text('ต้องการลบคูปอง $code หรือไม่'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('ยกเลิก'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('ลบ'),
                                  ),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await fs.collection('coupons').doc(id).delete();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('ลบคูปองเรียบร้อยแล้ว'),
                                    behavior: SnackBarBehavior.floating,
                                 ),
                                );
                              }
                            }
                          }
                        },
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(value: 'edit', child: Text('แก้ไข')),
                          PopupMenuItem(value: 'delete', child: Text('ลบ')),
                           
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// 🪧 Dialog เพิ่ม/แก้ไขคูปอง
  Future<void> _openEditorDialog({
    String? docId,
    Map<String, dynamic>? initial,
  }) async {
    final form = GlobalKey<FormState>();

    final codeCtrl = TextEditingController(text: initial?['code'] ?? '');
    final descCtrl =
        TextEditingController(text: initial?['description'] ?? '');
    final valueCtrl =
        TextEditingController(text: '${initial?['value'] ?? ''}');
    final usageLimitCtrl =
        TextEditingController(text: '${initial?['usageLimit'] ?? 0}');

    bool percent = (initial?['type'] ?? 'percent') == 'percent';
    bool active = initial?['active'] ?? true;
    Timestamp? expiresAt = initial?['expiresAt'];

    // เก็บ usedCount เดิมไว้ (กันเผลอรีเซ็ตตอนแก้ไข)
    final existingUsedCount =
        (initial?['usedCount'] is num) ? (initial?['usedCount'] as num).toInt() : 0;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void rebuild() => setLocal(() {});

            return AlertDialog(
              title: Text(docId == null ? 'เพิ่มคูปอง' : 'แก้ไขคูปอง'),
              content: Form(
                key: form,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                     TextFormField(
                              controller: codeCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'รหัสคูปอง *',
                                prefixIcon: Icon(Icons.qr_code_2_rounded, color: Color(0xFF6D4C41)),
                                border: OutlineInputBorder(),
                              ),
                              enabled: docId == null, // ✅ แก้ได้เฉพาะตอนสร้างใหม่
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'กรุณากรอกรหัสคูปอง';
                                }
                                if (v.trim().length < 3) {
                                  return 'รหัสคูปองต้องมีอย่างน้อย 3 ตัวอักษร';
                                }
                                return null;
                              },
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                                color: Color(0xFF3E2723),
                              ),
                            ),

                      const SizedBox(height: 10),
                      TextFormField(
                        controller: descCtrl,
                        decoration: const InputDecoration(
                          labelText: 'รายละเอียด',
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: valueCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: percent
                                    ? 'ส่วนลด (%) *'
                                    : 'ส่วนลด (฿) *',
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'กรุณาใส่ค่า';
                                }
                                final n =
                                    double.tryParse(v.trim()) ?? -1;
                                if (n <= 0) {
                                  return 'ต้องมากกว่า 0';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(
                                value: true,
                                label: Text('%'),
                              ),
                              ButtonSegment(
                                value: false,
                                label: Text('฿'),
                              ),
                            ],
                            selected: {percent},
                            onSelectionChanged: (s) {
                              percent = s.first;
                              rebuild();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: usageLimitCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'จำนวนครั้งที่ใช้ได้ (0 = ไม่จำกัด)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('วันหมดอายุ'),
                        subtitle: Text(
                          expiresAt == null
                              ? 'ไม่กำหนด'
                              : DateFormat('d MMM yyyy', 'th_TH')
                                  .format(expiresAt!.toDate()),
                        ),
                        trailing:
                            const Icon(Icons.calendar_today, size: 20),
                        onTap: () async {
                          final now = DateTime.now();
                          final d = await showDatePicker(
                            context: ctx,
                            initialDate:
                                expiresAt?.toDate() ?? now,
                            firstDate: now,
                            lastDate: DateTime(2100),
                          );
                          if (d != null) {
                            expiresAt = Timestamp.fromDate(d);
                            rebuild();
                          }
                        },
                      ),
                      SwitchListTile(
                        title: const Text('เปิดใช้งานทันที'),
                        value: active,
                        onChanged: (v) {
                          active = v;
                          rebuild();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('ยกเลิก'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('บันทึก'),
                  onPressed: () async {
                    if (!(form.currentState?.validate() ?? false)) {
                      return;
                    }

                    final usageLimit =
                        int.tryParse(usageLimitCtrl.text.trim()) ?? 0;

                    final Map<String, dynamic> data = {
                          'code': codeCtrl.text.trim().toUpperCase(),
                          'description': descCtrl.text.trim(),
                          'type': percent ? 'percent' : 'fixed',
                          'value': double.tryParse(valueCtrl.text.trim()) ?? 0.0,
                          'usageLimit': usageLimit,
                          'usedCount': existingUsedCount,
                          'active': active,
                          'updatedAt': FieldValue.serverTimestamp(),
                        };

                        // ✅ ใส่ expiresAt เฉพาะถ้าเลือกจริง
                        if (expiresAt != null) {
                          data['expiresAt'] = expiresAt;
                        }


                    try {
                      if (docId == null) {
                          await fs.collection('coupons').add({
                            ...data,
                            'createdAt': FieldValue.serverTimestamp(),
                          });
                        } else {
                          await fs.collection('coupons').doc(docId).set({
                            ...data,
                            // ถ้าอันเก่าไม่มี createdAt เลย ใส่ให้หน่อย
                            if (!(initial?.containsKey('createdAt') ?? false))
                              'createdAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));
                        }


                      if (context.mounted) {
                          Navigator.of(ctx).pop(); // ⬅ ปิด Dialog ตรงนี้
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('บันทึกคูปองสำเร็จ'),
                              behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('เกิดข้อผิดพลาด: $e'),
                          behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}
