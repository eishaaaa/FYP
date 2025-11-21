// lib/screens/auth_screens.dart
// Unified auth screens: Onboarding, Splash, Login, Register, Forgot Password
// Clean Material3-friendly UI. Google sign-in for Login and Register (only for user role).
// Password eye toggles work correctly. Register is scrollable and supplier form fields appear when Supplier is selected.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:introduction_screen/introduction_screen.dart';

import 'user_screens.dart';
import 'supplier_screens.dart';

final FirebaseAuth auth = FirebaseAuth.instance;
final FirebaseFirestore db = FirebaseFirestore.instance;

/// -----------------------------
/// Onboarding
/// -----------------------------
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  Future<void> _complete(BuildContext ctx) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding', true);
    if (!ctx.mounted) return;
    Navigator.pushReplacement(ctx, MaterialPageRoute(builder: (_) => const SplashScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return IntroductionScreen(
      globalBackgroundColor: Theme.of(context).colorScheme.background,
      pages: [
        PageViewModel(
          title: "Secure Ownership",
          body: "Digital verification for land & electronic assets.",
          image: const Icon(Icons.security, size: 140, color: Colors.green),
        ),
        PageViewModel(
          title: "QR Verification",
          body: "Instant verification using QR codes.",
          image: const Icon(Icons.qr_code_scanner, size: 140, color: Colors.green),
        ),
        PageViewModel(
          title: "Future Tokenization",
          body: "Invest in tokenized assets in Phase 2.",
          image: const Icon(Icons.token, size: 140, color: Colors.green),
        ),
      ],
      done: const Text("Get Started", style: TextStyle(fontWeight: FontWeight.bold)),
      onDone: () => _complete(context),
      next: const Icon(Icons.arrow_forward),
      showSkipButton: true,
      skip: const Text("Skip"),
      dotsDecorator: const DotsDecorator(activeColor: Colors.green),
    );
  }
}

/// -----------------------------
/// Splash: route to login or app home based on Firestore role
/// -----------------------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 900), _check);
  }

  Future<void> _check() async {
    final user = auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }
    final snapshot = await db.collection('users').doc(user.uid).get();
    final role = snapshot.data()?['role'] as String? ?? 'user';
    if (!mounted) return;
    if (role == 'user') {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const UserHomeScreen()));
    } else {
      final type = role.contains('land') ? 'land' : 'electronics';
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SupplierHomeScreen(type: type)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.eco, size: 84, color: Colors.white),
            SizedBox(height: 16),
            Text('Digital Goods',
                style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

/// -----------------------------
/// Helper: create Firestore user doc (for Google or new users)
/// -----------------------------
Future<void> createUserDocIfNotExists(User user, {String role = 'user', String? photoBase64}) async {
  final docRef = db.collection('users').doc(user.uid);
  final snap = await docRef.get();
  if (!snap.exists) {
    await docRef.set({
      'uid': user.uid,
      'name': user.displayName ?? '',
      'email': user.email ?? '',
      'phone': user.phoneNumber ?? '',
      'photoBase64': photoBase64 ?? '',
      'role': role,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

/// -----------------------------
/// Google Sign-In (returns User if success)
/// -----------------------------
Future<User?> signInWithGoogle(BuildContext ctx) async {
  try {
    final GoogleSignInAccount? gUser = await GoogleSignIn().signIn();
    if (gUser == null) return null; // user cancelled
    final GoogleSignInAuthentication gAuth = await gUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: gAuth.accessToken,
      idToken: gAuth.idToken,
    );
    final userCred = await auth.signInWithCredential(credential);
    final user = userCred.user;
    if (user != null) {
      // ensure firestore doc exists
      await createUserDocIfNotExists(user);
    }
    return user;
  } catch (e) {
    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Google sign-in failed: $e')));
    return null;
  }
}

/// -----------------------------
/// Login Screen
/// -----------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _pass = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _loading = true);
    try {
      final cred = await auth.signInWithEmailAndPassword(email: _email.text.trim(), password: _pass.text.trim());
      final user = cred.user;
      if (user == null) throw Exception('Login returned null user');

      final doc = await db.collection('users').doc(user.uid).get();
      final role = doc.data()?['role'] as String? ?? 'user';

      if (!mounted) return;
      if (role == 'user') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const UserHomeScreen()));
      } else {
        final type = role.contains('land') ? 'land' : 'electronics';
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SupplierHomeScreen(type: type)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleLogin() async {
    setState(() => _loading = true);
    final user = await signInWithGoogle(context);
    if (user != null) {
      final snapshot = await db.collection('users').doc(user.uid).get();
      final role = snapshot.data()?['role'] as String? ?? 'user';
      if (!mounted) return;
      if (role == 'user') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const UserHomeScreen()));
      } else {
        final type = role.contains('land') ? 'land' : 'electronics';
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SupplierHomeScreen(type: type)));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Widget _glassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.85),
            borderRadius: BorderRadius.circular(16),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = _glassCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Welcome back', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            decoration: _inputDecoration('Email', prefix: const Icon(Icons.email_outlined)),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            decoration: _inputDecoration(
              'Password',
              prefix: const Icon(Icons.lock_outline),
              suffix: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            obscureText: _obscure,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Login'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())), child: const Text('Register')),
            const SizedBox(width: 8),
            TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())), child: const Text('Forgot?')),
          ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loading ? null : _googleLogin,
            icon: Image.network(
              'https://developers.google.com/identity/images/g-logo.png',
              height: 20,
              width: 20,
              errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata),
            ),
            label: const Text('Continue with Google'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          ),
        ],
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.eco, size: 78, color: Colors.green),
                const SizedBox(height: 12),
                Text('Digital Goods', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                card,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// -----------------------------
/// Register Screen
/// -----------------------------
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();
  final TextEditingController _companyCtrl = TextEditingController();
  final TextEditingController _cnicCtrl = TextEditingController();
  final TextEditingController _cityCtrl = TextEditingController();

  String _role = 'user';
  String _supplierType = 'land';
  Uint8List? _photo;
  bool _loading = false;
  bool _obscure = true;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _companyCtrl.dispose();
    _cnicCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final status = await Permission.photos.request();
    if (!status.isGranted) return;
    final XFile? img = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (img != null) {
      _photo = await img.readAsBytes();
      setState(() {});
    }
  }

  Future<void> _register() async {
    if (_passCtrl.text != _confirmCtrl.text) {
      _msg('Passwords do not match');
      return;
    }
    if (_emailCtrl.text.isEmpty || _passCtrl.text.isEmpty) {
      _msg('Email and password required');
      return;
    }
    setState(() => _loading = true);
    try {
      final userCred = await auth.createUserWithEmailAndPassword(email: _emailCtrl.text.trim(), password: _passCtrl.text.trim());
      final uid = userCred.user!.uid;
      final roleString = _role == 'user' ? 'user' : 'supplier_$_supplierType';
      final Map<String, dynamic> data = {
        'uid': uid,
        'name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'role': roleString,
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (_role == 'supplier') {
        data.addAll({
          'company': _companyCtrl.text.trim(),
          'cnic': _cnicCtrl.text.trim(),
          'city': _cityCtrl.text.trim(),
        });
      }
      if (_photo != null) data['photoBase64'] = base64Encode(_photo!);
      await db.collection('users').doc(uid).set(data);
      await userCred.user!.updateDisplayName(roleString);
      if (!mounted) return;
      _msg('Account created. Please login.');
      Navigator.pop(context);
    } catch (e) {
      _msg('Error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _googleRegisterOrLogin() async {
    // Only offer google registration/login for user role (not supplier)
    setState(() => _loading = true);
    final user = await signInWithGoogle(context);
    if (user != null) {
      final docRef = db.collection('users').doc(user.uid);
      final snap = await docRef.get();
      if (!snap.exists) {
        // new Google user -> create with default role = user
        await docRef.set({
          'uid': user.uid,
          'name': user.displayName ?? '',
          'email': user.email ?? '',
          'phone': user.phoneNumber ?? '',
          'photoBase64': '',
          'role': 'user',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      final role = (await docRef.get()).data()?['role'] as String? ?? 'user';
      if (!mounted) return;
      if (role == 'user') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const UserHomeScreen()));
      } else {
        final type = role.contains('land') ? 'land' : 'electronics';
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SupplierHomeScreen(type: type)));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    // Make register form scrollable (handles long supplier form on small displays)
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: _pickPhoto,
                        child: CircleAvatar(
                          radius: 45,
                          backgroundImage: _photo != null ? MemoryImage(_photo!) : null,
                          child: _photo == null ? const Icon(Icons.camera_alt, size: 30) : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Role selection
                    Row(
                      children: [
                        ChoiceChip(label: const Text('User'), selected: _role == 'user', onSelected: (_) => setState(() => _role = 'user')),
                        const SizedBox(width: 12),
                        ChoiceChip(label: const Text('Supplier'), selected: _role == 'supplier', onSelected: (_) => setState(() => _role = 'supplier')),
                      ],
                    ),
                    if (_role == 'supplier') ...[
                      const SizedBox(height: 12),
                      Row(children: [
                        ChoiceChip(label: const Text('Land'), selected: _supplierType == 'land', onSelected: (_) => setState(() => _supplierType = 'land')),
                        const SizedBox(width: 12),
                        ChoiceChip(label: const Text('Electronics'), selected: _supplierType == 'electronics', onSelected: (_) => setState(() => _supplierType = 'electronics')),
                      ]),
                    ],
                    const SizedBox(height: 20),

                    TextField(controller: _nameCtrl, decoration: _inputDecoration('Full Name')),
                    const SizedBox(height: 10),
                    TextField(controller: _emailCtrl, decoration: _inputDecoration('Email'), keyboardType: TextInputType.emailAddress),
                    const SizedBox(height: 10),
                    TextField(controller: _phoneCtrl, decoration: _inputDecoration('Phone')),
                    const SizedBox(height: 10),
                    TextField(controller: _passCtrl, decoration: _inputDecoration('Password', suffix: IconButton(icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _obscure = !_obscure))), obscureText: _obscure),
                    const SizedBox(height: 10),
                    TextField(controller: _confirmCtrl, decoration: _inputDecoration('Confirm Password', suffix: IconButton(icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _obscure = !_obscure))), obscureText: _obscure),

                    if (_role == 'supplier') ...[
                      const SizedBox(height: 10),
                      TextField(controller: _companyCtrl, decoration: _inputDecoration('Company/Brand')),
                      const SizedBox(height: 10),
                      TextField(controller: _cnicCtrl, decoration: _inputDecoration('CNIC/NTN')),
                      const SizedBox(height: 10),
                      TextField(controller: _cityCtrl, decoration: _inputDecoration('City')),
                    ],

                    const SizedBox(height: 20),
                    _loading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(onPressed: _register, style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: const Text('Register')),
                    const SizedBox(height: 16),

                    // Only show Google button for user role — requirement: suppliers must not register with Google
                    if (_role == 'user') ...[
                      InkWell(
                        onTap: _loading ? null : _googleRegisterOrLogin,
                        child: Container(
                          height: 48,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black12),
                            color: Colors.white,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.network(
                                'https://developers.google.com/identity/images/g-logo.png',
                                height: 20,
                                width: 20,
                                errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata),
                              ),
                              const SizedBox(width: 10),
                              const Text('Register with Google'),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// -----------------------------
/// Forgot Password
/// -----------------------------
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _emailCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter email')));
      return;
    }
    setState(() => _loading = true);
    try {
      await auth.sendPasswordResetEmail(email: email);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reset email sent')));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          TextField(controller: _emailCtrl, decoration: _inputDecoration('Email'), keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 20),
          _loading ? const CircularProgressIndicator() : ElevatedButton(onPressed: _reset, style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)), child: const Text('Send Reset Link')),
        ]),
      ),
    );
  }
}

/// -----------------------------
/// Input decoration helper (accepts optional prefix widget and optional suffix widget)
/// -----------------------------
InputDecoration _inputDecoration(String label, {Widget? prefix, Widget? suffix}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: prefix,
    suffixIcon: suffix,
    filled: true,
    fillColor: Colors.transparent,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
  );
}
