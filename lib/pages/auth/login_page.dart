// lib/pages/auth/login_page.dart
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'register_page.dart';
import '../../widgets/pill_button.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; });
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _pass.text.trim(),
      );
      try {
        final user = cred.user ?? FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
            {'lastLogin': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
        }
      } catch (_) {}
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/home', (r) => false);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Sign in failed'),
            content: Text(e.message ?? 'Authentication error'),
            actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Error'),
            content: Text(e.toString()),
            actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openResetDialog() {
    showDialog(
      context: context,
      builder: (_) => _ResetPasswordDialogContent(initialEmail: _email.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = 'assets/images/bg1.jpg';
    final kb = MediaQuery.of(context).viewInsets.bottom;
    final hasKb = kb > 0;
    final topSpacing = hasKb ? 16.0 : MediaQuery.of(context).size.height * 0.24;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: _BgLayer(image: bg)),
          Positioned.fill(child: Container(color: Colors.black.withOpacity(.28))),
          SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(left: 24, right: 24, top: 16, bottom: kb + 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _HomeIcon(),
                  const SizedBox(height: 28),
                  const Text('WELCOME TO',
                      style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, height: 1.05)),
                  const SizedBox(height: 6),
                  const Text('Luminé J.',
                      style: TextStyle(fontFamily: 'PlayfairDisplay', color: Colors.white, fontSize: 38, fontWeight: FontWeight.w700)),
                  SizedBox(height: topSpacing),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                        decoration: BoxDecoration(
                          color: Colors.brown.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: Colors.white24, width: 1),
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextFormField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                style: const TextStyle(color: Colors.white),
                                decoration: _glassInput('Email', Icons.email_outlined),
                                validator: (v) {
                                  if (v == null || v.isEmpty) return 'กรุณากรอกอีเมล';
                                  if (!v.contains('@')) return 'อีเมลไม่ถูกต้อง';
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _pass,
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                style: const TextStyle(color: Colors.white),
                                decoration: _glassInput(
                                  'Password', Icons.lock_outline,
                                  suffix: IconButton(
                                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: Colors.white70),
                                    onPressed: () => setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                validator: (v) => (v == null || v.isEmpty) ? 'กรุณากรอกรหัสผ่าน' : null,
                              ),
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _openResetDialog,
                                  child: const Text(
                                    'Forgot password?',
                                    style: TextStyle(color: Color(0xFFFFE082), fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: 170, height: 50,
                                child: PillButton(
                                  label: _loading ? 'SIGNING IN...' : 'SIGN IN',
                                  filled: true,
                                  onPressed: _loading ? null : _signIn,
                                ),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: 190, height: 50,
                                child: OutlinedButton(
                                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage())),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.white),
                                    shape: const StadiumBorder(),
                                    backgroundColor: Colors.white.withOpacity(.06),
                                  ),
                                  child: const Text('REGISTER', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: .4)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _glassInput(String label, IconData icon, {Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: Colors.white70),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withOpacity(.10),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white38),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white),
      ),
      errorStyle: const TextStyle(color: Colors.amberAccent),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.white38),
      ),
    );
  }
}

class _BgLayer extends StatelessWidget {
  final String image;
  const _BgLayer({required this.image});
  @override
  Widget build(BuildContext context) => Image.asset(image, fit: BoxFit.cover);
}

class _HomeIcon extends StatelessWidget {
  const _HomeIcon();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54, height: 54,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.brown.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: const Icon(Icons.home_rounded, size: 30),
    );
  }
}

// ===== Reset Password Dialog =====
class _ResetPasswordDialogContent extends StatefulWidget {
  final String? initialEmail;
  const _ResetPasswordDialogContent({Key? key, this.initialEmail}) : super(key: key);

  @override
  State<_ResetPasswordDialogContent> createState() => _ResetPasswordDialogContentState();
}

class _ResetPasswordDialogContentState extends State<_ResetPasswordDialogContent> {
  late final TextEditingController _emailController;
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleSendResetLink() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: _emailController.text.trim());
      if (!mounted) return;
      setState(() { _isLoading = false; _isSuccess = true; });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = (e.code == 'user-not-found')
          ? 'ไม่พบอีเมลนี้ในระบบ'
          : e.message ?? 'เกิดข้อผิดพลาด';
      setState(() { _isLoading = false; _errorMessage = msg; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _isLoading = false; _errorMessage = 'เกิดข้อผิดพลาด: $e'; });
    }
  }

  InputDecoration _buildInputDecoration(String label) {
    const brandBrown = Color(0xFF7A4E3A);
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300, width: 1.2)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300, width: 1.2)),
      focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: brandBrown, width: 1.5)),
      errorBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Colors.red, width: 1.2)),
      focusedErrorBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Colors.red, width: 1.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    const ivory = Color(0xFFFCF7F5);
    return Dialog(
      backgroundColor: ivory,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
        child: _isSuccess ? _buildSuccessView() : _buildFormView(),
      ),
    );
  }

  Widget _buildFormView() {
    const brandBrown = Color(0xFF7A4E3A);
    return Padding(
      key: const ValueKey('formView'),
      padding: const EdgeInsets.all(24.0),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ลืมรหัสผ่าน?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF3E2C24))),
            const SizedBox(height: 8),
            const Text('กรอกอีเมลที่ใช้ลงทะเบียน เราจะส่งลิงก์สำหรับรีเซ็ตรหัสผ่านไปให้', style: TextStyle(fontSize: 14, color: Colors.black54)),
            const SizedBox(height: 20),
            TextFormField(
              controller: _emailController,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: _buildInputDecoration('อีเมล (Email)'),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'กรุณากรอกอีเมล';
                if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v)) return 'รูปแบบอีเมลไม่ถูกต้อง';
                return null;
              },
            ),
            const SizedBox(height: 12),
            if (_errorMessage != null) Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: _isLoading ? null : () => Navigator.pop(context), child: const Text('ยกเลิก', style: TextStyle(color: Colors.black54))),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _isLoading ? null : _handleSendResetLink,
                  style: FilledButton.styleFrom(backgroundColor: brandBrown, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                  child: _isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('ส่งลิงก์'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    const brandBrown = Color(0xFF7A4E3A);
    return Padding(
      key: const ValueKey('successView'),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), shape: BoxShape.circle, border: Border.all(color: Colors.green.withOpacity(0.3))),
            child: Icon(Icons.check_rounded, color: Colors.green.shade700, size: 40),
          ),
          const SizedBox(height: 16),
          const Text('ส่งสำเร็จ!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF3E2C24))),
          const SizedBox(height: 8),
          Text('เราได้ส่งลิงก์สำหรับตั้งรหัสผ่านใหม่ไปที่\n${_emailController.text.trim()}',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Colors.black54)),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(backgroundColor: brandBrown, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12)),
            child: const Text('ตกลง'),
          ),
        ],
      ),
    );
  }
}
