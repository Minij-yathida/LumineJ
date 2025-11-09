import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/material.dart';
import '../../widgets/pill_button.dart';
import '../../services/auth_service.dart';
// duplicate import removed
import 'package:firebase_auth/firebase_auth.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  // Controllers for text fields
  final emailCtrl = TextEditingController();
  final pwdCtrl = TextEditingController();
  final confirmPwdCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final addressCtrl = TextEditingController();

  bool obscure1 = true;
  bool obscure2 = true;
  bool loading = false;

  final AuthService _authService = AuthService();

  @override
  void dispose() {
    emailCtrl.dispose();
    pwdCtrl.dispose();
    confirmPwdCtrl.dispose();
    nameCtrl.dispose();
    phoneCtrl.dispose();
    addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final email = emailCtrl.text.trim();
    final pass = pwdCtrl.text.trim();
    final conf = confirmPwdCtrl.text.trim();
    final name = nameCtrl.text.trim();
    final phone = phoneCtrl.text.trim();
    final address = addressCtrl.text.trim();

    if (email.isEmpty || pass.isEmpty || conf.isEmpty || name.isEmpty || phone.isEmpty || address.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Missing fields'),
          content: const Text('Please fill in all fields'),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
        ),
      );
      return;
    }
    
    if (pass != conf) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Password mismatch'),
          content: const Text('Passwords do not match'),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
        ),
      );
      return;
    }

    if (pass.length < 6) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Weak password'),
          content: const Text('Password must be at least 6 characters'),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
        ),
      );
      return;
    }

    try {
      setState(() => loading = true);

      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: pass,
      );
      
      final user = userCredential.user;

      if (user != null) {
        // Call createUserDocument without the profile image
        await _authService.createUserDocument(
          user,
          role: 'customer',
          displayName: name,
          phoneNumber: phone,
          address: address,
        );

        // Ensure a newly registered email starts with an empty cart on this device.
        // Remove legacy guest cart keys so the CartProvider won't fall back and load previous guest data.
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('cart_items_v1');
          await prefs.remove('cart_selected_v1');
          await prefs.remove('cart_meta_v1');
        } catch (_) {}
      }

      if (!mounted) return;

      // ⭐️⭐️⭐️ นี่คือจุดที่แก้ไข ⭐️⭐️⭐️
      // 1. แสดงข้อความว่าลงทะเบียนสำเร็จ (popup)
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Registration Successful'),
          content: const Text('Your account has been created. Please log in.'),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
        ),
      );
      
      // 2. กลับไปยังหน้าก่อนหน้า (ซึ่งก็คือหน้า Login)
      Navigator.pop(context);

    } on FirebaseAuthException catch (e) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Registration failed'),
          content: Text(e.message ?? 'Registration failed'),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error'),
          content: Text('An unexpected error occurred: ${e.toString()}'),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
        ),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // 🎨 Adjusted Input Decoration to match the image style
  InputDecoration _inputDecoration(String hintText, IconData icon) {
    return InputDecoration(
      labelText: hintText,
      labelStyle: const TextStyle(color: Colors.white70),
      hintText: hintText,
      hintStyle: const TextStyle(color: Colors.white30),
      prefixIcon: Icon(icon, color: Colors.white),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15), // Softer corners
        borderSide: BorderSide(color: Colors.white.withOpacity(0.4), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Colors.white, width: 1.5),
      ),
      filled: true,
      fillColor: Colors.transparent, // Let the blurred background show through
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String hintText,
    required bool obscureText,
    required VoidCallback toggleObscure,
    required IconData prefixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white),
      decoration: _inputDecoration(hintText, prefixIcon).copyWith(
        suffixIcon: IconButton(
          icon: Icon(
            obscureText ? Icons.visibility_off : Icons.visibility,
            color: Colors.white70,
          ),
          onPressed: toggleObscure,
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/bg1.jpg', // Make sure you have this image
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.5), // Dark overlay for readability
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "CREATE ACCOUNT", // Changed text for better fit
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                  ),
                  const SizedBox(height: 30),

                  // 🎨 Form container with blur effect and brownish tint
                  ClipRRect(
                    borderRadius: BorderRadius.circular(25),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        width: size.width,
                        padding: const EdgeInsets.all(25),
                        decoration: BoxDecoration(
                          // 🎨 Changed color to a warmer brown tint
                          color: Colors.brown.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(color: Colors.white.withOpacity(0.2)),
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: nameCtrl,
                              keyboardType: TextInputType.text,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration("Full Name", Icons.person_outline),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: phoneCtrl,
                              keyboardType: TextInputType.phone,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration("Phone Number", Icons.phone_outlined),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: addressCtrl,
                              keyboardType: TextInputType.multiline,
                              maxLines: 3,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration("Shipping Address", Icons.home_outlined),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              style: const TextStyle(color: Colors.white),
                              decoration: _inputDecoration("Email", Icons.email_outlined),
                            ),
                            const SizedBox(height: 20),
                            _passwordField(
                              controller: pwdCtrl,
                              hintText: "Password",
                              obscureText: obscure1,
                              prefixIcon: Icons.lock_outline,
                              toggleObscure: () => setState(() => obscure1 = !obscure1),
                            ),
                            const SizedBox(height: 20),
                            _passwordField(
                              controller: confirmPwdCtrl,
                              hintText: "Confirm Password",
                              obscureText: obscure2,
                              prefixIcon: Icons.lock_outline,
                              toggleObscure: () => setState(() => obscure2 = !obscure2),
                            ),
                            const SizedBox(height: 30),
                            // 🎨 Register button with solid orange/gold color
                            PillButton(
                              label: loading ? "REGISTERING..." : "REGISTER",
                              filled: true,
                              onPressed: loading ? null : _register,
                              color: const Color(0xFFFFA000), // Solid orange/gold color
                            ),
                            const SizedBox(height: 18),
                            // 🎨 Changed to TextButton to remove the outline
                            TextButton(
                              onPressed: loading ? null : () => Navigator.pop(context),
                              child: const Text(
                                "Already have an account? Sign In",
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
