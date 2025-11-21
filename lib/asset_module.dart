// lib/asset_module.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as imgpkg;
import 'package:permission_handler/permission_handler.dart';

final FirebaseAuth auth = FirebaseAuth.instance;
final FirebaseFirestore firestore = FirebaseFirestore.instance;

/// -----------------
/// Onboarding
/// -----------------
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  Future<void> _done(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seenOnboarding', true);
    if (!context.mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SplashScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return IntroductionScreen(
      pages: [
        PageViewModel(
          title: "Secure Ownership of Land & Electronics",
          body: "Immutable digital records for physical assets.",
          image: const Icon(Icons.shield, size: 140, color: Colors.green),
        ),
        PageViewModel(
          title: "Verify Authenticity with QR Codes",
          body: "Scan to verify products and deeds instantly.",
          image: const Icon(Icons.qr_code, size: 140, color: Colors.green),
        ),
        PageViewModel(
          title: "Invest in Real Assets (coming soon)",
          body: "Tokenization & NFTs planned for phase 2.",
          image: const Icon(Icons.token, size: 140, color: Colors.green),
        ),
      ],
      onDone: () => _done(context),
      done: const Text("Get Started", style: TextStyle(fontWeight: FontWeight.bold)),
      showSkipButton: true,
      skip: const Text("Skip"),
      next: const Icon(Icons.arrow_forward),
      dotsDecorator: const DotsDecorator(activeColor: Colors.green),
      globalBackgroundColor: Colors.grey[50],
    );
  }
}

/// -----------------
/// Splash Screen
/// -----------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 1), _route);
  }

  Future<void> _route() async {
    final user = auth.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AuthPage()));
      return;
    }
    final doc = await firestore.collection('users').doc(user.uid).get();
    final role = doc.data()?['role'] ?? 'user';
    if (!mounted) return;
    if (role == 'user') {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainUserScaffold()));
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MainSupplierScaffold(supplierType: role == 'supplier_land' ? 'land' : 'electronics'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.green,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.eco, size: 84, color: Colors.white),
          SizedBox(height: 12),
          Text('Digital Goods', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
          SizedBox(height: 12),
          CircularProgressIndicator(color: Colors.white),
        ]),
      ),
    );
  }
}

/// -----------------
/// Auth Page
/// -----------------
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  String loginAs = 'user';
  bool loading = false;

  Future<void> login() async {
    setState(() => loading = true);
    try {
      final cred = await auth.signInWithEmailAndPassword(email: emailCtrl.text.trim(), password: passCtrl.text);
      final u = cred.user!;
      final doc = await firestore.collection('users').doc(u.uid).get();
      final role = doc.data()?['role'] ?? 'user';
      if (!mounted) return;
      if (role == 'user') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainUserScaffold()));
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => MainSupplierScaffold(supplierType: role == 'supplier_land' ? 'land' : 'electronics'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login failed: $e')));
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Welcome', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Login to continue', style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 18),
                Row(children: [
                  ChoiceChip(
                    label: const Text('User'),
                    selected: loginAs == 'user',
                    onSelected: (_) => setState(() => loginAs = 'user'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Supplier'),
                    selected: loginAs == 'supplier',
                    onSelected: (_) => setState(() => loginAs = 'supplier'),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
                ),
                const SizedBox(height: 18),
                loading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton.icon(onPressed: login, icon: const Icon(Icons.login), label: const Text('Login')),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage())), child: const Text('Register')),
                  TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ForgotPasswordPage())), child: const Text('Forgot password?')),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// -----------------
/// Forgot Password
/// -----------------
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final emailCtrl = TextEditingController();
  bool loading = false;

  Future<void> sendReset() async {
    final email = emailCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter email')));
      return;
    }
    setState(() => loading = true);
    try {
      await auth.sendPasswordResetEmail(email: email);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reset email sent to $email')));
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            const Text('Enter your email to reset password', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 16),
            loading ? const CircularProgressIndicator() : ElevatedButton(onPressed: sendReset, child: const Text('Send Reset Email')),
          ]),
        ),
      ),
    );
  }
}

/// -----------------
/// Register Page
/// -----------------
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final nameCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  final companyCtrl = TextEditingController();
  final cnicCtrl = TextEditingController();
  final cityCtrl = TextEditingController();

  String role = 'user';
  String supplierSub = 'supplier_land';
  Uint8List? profilePhoto;
  bool loading = false;

  Future<void> pickProfile() async {
    final status = await Permission.photos.request();
    if (!status.isGranted && !status.isLimited) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permission denied')));
      return;
    }
    final XFile? f = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f != null) {
      final b = await f.readAsBytes();
      setState(() => profilePhoto = b);
    }
  }

  Future<void> register() async {
    if (nameCtrl.text.trim().isEmpty || emailCtrl.text.trim().isEmpty || passCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill required fields')));
      return;
    }
    if (passCtrl.text != confirmCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwords do not match')));
      return;
    }
    setState(() => loading = true);
    try {
      final cred = await auth.createUserWithEmailAndPassword(email: emailCtrl.text.trim(), password: passCtrl.text);
      final uid = cred.user!.uid;
      final map = <String, dynamic>{
        'uid': uid,
        'name': nameCtrl.text.trim(),
        'email': emailCtrl.text.trim(),
        'phone': phoneCtrl.text.trim(),
        'role': role == 'user' ? 'user' : supplierSub,
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (role == 'supplier') {
        map['company'] = companyCtrl.text.trim();
        map['cnic'] = cnicCtrl.text.trim();
        map['city'] = cityCtrl.text.trim();
      }
      if (profilePhoto != null) map['profilePhotoBase64'] = base64Encode(profilePhoto!);
      await firestore.collection('users').doc(uid).set(map);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registered. Please login.')));
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    passCtrl.dispose();
    confirmCtrl.dispose();
    companyCtrl.dispose();
    cnicCtrl.dispose();
    cityCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Register')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Create Account', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(children: [
              ChoiceChip(label: const Text('User'), selected: role == 'user', onSelected: (_) => setState(() => role = 'user')),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('Supplier'), selected: role == 'supplier', onSelected: (_) => setState(() => role = 'supplier')),
            ]),
            const SizedBox(height: 12),
            if (role == 'supplier')
              Row(children: [
                ChoiceChip(label: const Text('Land'), selected: supplierSub == 'supplier_land', onSelected: (_) => setState(() => supplierSub = 'supplier_land')),
                const SizedBox(width: 8),
                ChoiceChip(label: const Text('Electronics'), selected: supplierSub == 'supplier_electronics', onSelected: (_) => setState(() => supplierSub = 'supplier_electronics')),
              ]),
            const SizedBox(height: 12),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full name')),
            const SizedBox(height: 8),
            TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 8),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
            const SizedBox(height: 8),
            TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
            const SizedBox(height: 8),
            TextField(controller: confirmCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm Password')),
            const SizedBox(height: 12),
            if (role == 'supplier') ...[
              TextField(controller: companyCtrl, decoration: const InputDecoration(labelText: 'Company / Brand')),
              const SizedBox(height: 8),
              TextField(controller: cnicCtrl, decoration: const InputDecoration(labelText: 'CNIC / NTN')),
              const SizedBox(height: 8),
              TextField(controller: cityCtrl, decoration: const InputDecoration(labelText: 'City')),
            ],
            const SizedBox(height: 12),
            Row(children: [
              ElevatedButton.icon(onPressed: pickProfile, icon: const Icon(Icons.photo), label: const Text('Profile')),
              const SizedBox(width: 8),
              if (profilePhoto != null) const Text('Selected', style: TextStyle(color: Colors.green)),
            ]),
            const SizedBox(height: 12),
            loading ? const Center(child: CircularProgressIndicator()) : ElevatedButton(onPressed: register, child: const Text('Register')),
          ]),
        ),
      ),
    );
  }
}
/// -----------------
/// Main User Scaffold
/// -----------------
class MainUserScaffold extends StatefulWidget {
  const MainUserScaffold({super.key});
  @override
  State<MainUserScaffold> createState() => _MainUserScaffoldState();
}

class _MainUserScaffoldState extends State<MainUserScaffold> {
  int idx = 0;
  static const _pages = <Widget>[
    UserHomePage(),
    QRScanLauncher(),
    MyAssetsPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => setState(() => idx = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.qr_code_scanner), label: 'Scan'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'My Assets'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

/// -----------------
/// Main Supplier Scaffold
/// -----------------
class MainSupplierScaffold extends StatefulWidget {
  final String supplierType;
  const MainSupplierScaffold({super.key, required this.supplierType});
  @override
  State<MainSupplierScaffold> createState() => _MainSupplierScaffoldState();
}

class _MainSupplierScaffoldState extends State<MainSupplierScaffold> {
  int idx = 0;
  late final List<Widget> pages;

  @override
  void initState() {
    super.initState();
    pages = [
      SupplierDashboardHome(supplierType: widget.supplierType),
      SupplierAssetsModule(supplierType: widget.supplierType),
      const ProfilePage(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[idx],
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => setState(() => idx = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.inventory_outlined), label: 'Assets'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

/// Supplier Dashboard
class SupplierDashboardHome extends StatelessWidget {
  final String supplierType;
  const SupplierDashboardHome({super.key, required this.supplierType});

  @override
  Widget build(BuildContext context) {
    final uid = auth.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: Text(supplierType == 'land' ? 'Land Supplier' : 'Electronics Supplier')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory, color: Colors.green),
              title: const Text('Total Listed Assets'),
              subtitle: StreamBuilder<QuerySnapshot>(
                stream: firestore.collection('assets').where('ownerId', isEqualTo: uid).snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData) return const Text('0');
                  return Text('${snap.data!.docs.length}');
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddAssetAdvancedPage(supplierType: supplierType))),
            icon: const Icon(Icons.add),
            label: const Text('Add New Asset'),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupplierTransactionsPage())),
            icon: const Icon(Icons.list_alt),
            label: const Text('View Transactions'),
          ),
        ]),
      ),
    );
  }
}

/// Supplier Assets Module
class SupplierAssetsModule extends StatelessWidget {
  final String supplierType;
  const SupplierAssetsModule({super.key, required this.supplierType});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Assets'),
          bottom: const TabBar(tabs: [Tab(text: 'Add'), Tab(text: 'Manage')]),
        ),
        body: TabBarView(
          children: [
            AddAssetAdvancedPage(supplierType: supplierType),
            const ManageAssetsAdvancedPage(),
          ],
        ),
      ),
    );
  }
}
/// -----------------
/// Add Asset Advanced (Supplier)
/// -----------------
class AddAssetAdvancedPage extends StatefulWidget {
  final String supplierType;
  const AddAssetAdvancedPage({super.key, required this.supplierType});
  @override
  State<AddAssetAdvancedPage> createState() => _AddAssetAdvancedPageState();
}

class _AddAssetAdvancedPageState extends State<AddAssetAdvancedPage> {
  final titleCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  // land
  final plotCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  String ownership = 'Full';
  // electronics
  final brandCtrl = TextEditingController();
  final modelCtrl = TextEditingController();
  final serialCtrl = TextEditingController();
  final warrantyCtrl = TextEditingController();
  String conditionVal = 'New';

  Uint8List? imageBytes;
  String? docBase64;
  bool loading = false;

  Future<void> pickImage() async {
    final status = await Permission.photos.request();
    if (!status.isGranted && !status.isLimited) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo permission required')));
      return;
    }
    final XFile? f = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f != null) {
      final bytes = await f.readAsBytes();
      final compressed = await _compress(bytes);
      setState(() => imageBytes = compressed);
    }
  }

  Future<Uint8List> _compress(Uint8List input) async {
    try {
      final img = imgpkg.decodeImage(input);
      if (img == null) return input;
      final resized = imgpkg.copyResize(img, width: 1200);
      final jpg = imgpkg.encodeJpg(resized, quality: 80);
      return Uint8List.fromList(jpg);
    } catch (_) {
      return input;
    }
  }

  Future<void> pickDoc() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (res != null && res.files.single.bytes != null) {
      docBase64 = base64Encode(res.files.single.bytes!);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Document attached')));
    }
  }

  Future<void> submit() async {
    if (titleCtrl.text.trim().isEmpty || descCtrl.text.trim().isEmpty || priceCtrl.text.trim().isEmpty || imageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fill required fields & add image')));
      return;
    }
    setState(() => loading = true);
    try {
      final assetId = const Uuid().v4();
      final map = <String, dynamic>{
        'assetId': assetId,
        'ownerId': auth.currentUser!.uid,
        'title': titleCtrl.text.trim(),
        'description': descCtrl.text.trim(),
        'price': priceCtrl.text.trim(),
        'category': widget.supplierType == 'land' ? 'land' : 'electronics',
        'imageBase64': base64Encode(imageBytes!),
        'documentBase64': docBase64,
        'createdAt': FieldValue.serverTimestamp(),
        'verified': false,
        'status': 'available',
      };
      if (widget.supplierType == 'land') {
        map['plotArea'] = plotCtrl.text.trim();
        map['city'] = cityCtrl.text.trim();
        map['ownershipType'] = ownership;
      } else {
        map['brand'] = brandCtrl.text.trim();
        map['model'] = modelCtrl.text.trim();
        map['serial'] = serialCtrl.text.trim();
        map['warrantyPeriod'] = warrantyCtrl.text.trim();
        map['condition'] = conditionVal;
      }
      await firestore.collection('assets').doc(assetId).set(map);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Asset uploaded')));
      _resetForm();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => loading = false);
    }
  }

  void _resetForm() {
    titleCtrl.clear(); descCtrl.clear(); priceCtrl.clear();
    plotCtrl.clear(); cityCtrl.clear();
    brandCtrl.clear(); modelCtrl.clear(); serialCtrl.clear(); warrantyCtrl.clear();
    setState(() {
      imageBytes = null;
      docBase64 = null;
    });
  }

  @override
  void dispose() {
    titleCtrl.dispose(); descCtrl.dispose(); priceCtrl.dispose();
    plotCtrl.dispose(); cityCtrl.dispose();
    brandCtrl.dispose(); modelCtrl.dispose(); serialCtrl.dispose(); warrantyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLand = widget.supplierType == 'land';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title', prefixIcon: Icon(Icons.title))),
        const SizedBox(height: 12),
        TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'Description', prefixIcon: Icon(Icons.description)), maxLines: 3),
        const SizedBox(height: 12),
        TextField(controller: priceCtrl, decoration: const InputDecoration(labelText: 'Price (PKR)', prefixIcon: Icon(Icons.attach_money)), keyboardType: TextInputType.number),
        const SizedBox(height: 16),
        if (isLand) ...[
          TextField(controller: plotCtrl, decoration: const InputDecoration(labelText: 'Plot Area (marla/kanal)', prefixIcon: Icon(Icons.square_foot))),
          const SizedBox(height: 12),
          TextField(controller: cityCtrl, decoration: const InputDecoration(labelText: 'City / Address', prefixIcon: Icon(Icons.location_city))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: ownership,
            items: const [
              DropdownMenuItem(value: 'Full', child: Text('Full Ownership')),
              DropdownMenuItem(value: 'Fractional', child: Text('Fractional')),
            ],
            onChanged: (v) => setState(() => ownership = v!),
            decoration: const InputDecoration(labelText: 'Ownership Type', prefixIcon: Icon(Icons.account_balance)),
          ),
        ] else ...[
          TextField(controller: brandCtrl, decoration: const InputDecoration(labelText: 'Brand', prefixIcon: Icon(Icons.branding_watermark))),
          const SizedBox(height: 12),
          TextField(controller: modelCtrl, decoration: const InputDecoration(labelText: 'Model', prefixIcon: Icon(Icons.model_training))),
          const SizedBox(height: 12),
          TextField(controller: serialCtrl, decoration: const InputDecoration(labelText: 'Serial / IMEI', prefixIcon: Icon(Icons.pin))),
          const SizedBox(height: 12),
          TextField(controller: warrantyCtrl, decoration: const InputDecoration(labelText: 'Warranty (months)', prefixIcon: Icon(Icons.verified))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: conditionVal,
            items: const [
              DropdownMenuItem(value: 'New', child: Text('New')),
              DropdownMenuItem(value: 'Used', child: Text('Used')),
            ],
            onChanged: (v) => setState(() => conditionVal = v!),
            decoration: const InputDecoration(labelText: 'Condition', prefixIcon: Icon(Icons.build)),
          ),
        ],
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: pickImage,
              icon: const Icon(Icons.image),
              label: const Text('Pick Image'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: pickDoc,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Attach PDF'),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        if (imageBytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(imageBytes!, height: 200, width: double.infinity, fit: BoxFit.cover),
          ),
        const SizedBox(height: 20),
        loading
            ? const CircularProgressIndicator()
            : ElevatedButton(
          onPressed: submit,
          child: const Text('Submit Asset'),
        ),
      ]),
    );
  }
}

/// -----------------
/// Manage Assets (Supplier)
/// -----------------
class ManageAssetsAdvancedPage extends StatelessWidget {
  const ManageAssetsAdvancedPage({super.key});

  Future<void> _delete(BuildContext ctx, String id) async {
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Delete Asset?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await firestore.collection('assets').doc(id).delete();
      if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Asset deleted')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = auth.currentUser?.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: firestore.collection('assets').where('ownerId', isEqualTo: uid).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snap.hasData || snap.data!.docs.isEmpty) return const Center(child: Text('No assets listed'));

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: snap.data!.docs.length,
          itemBuilder: (context, i) {
            final asset = snap.data!.docs[i];
            final img = asset['imageBase64'] as String?;
            return Card(
              child: ListTile(
                leading: img != null
                    ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(base64Decode(img), width: 60, height: 60, fit: BoxFit.cover))
                    : const Icon(Icons.image, size: 40),
                title: Text(asset['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('PKR ${asset['price']} • ${asset['category']}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'qr') {
                      showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('QR Code'),
                          content: QrImageView(data: 'asset://${asset['assetId']}', size: 220),
                          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                        ),
                      );
                    } else if (v == 'delete') {
                      await _delete(context, asset['assetId']);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'qr', child: Text('Show QR')),
                    PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// -----------------
/// User Home Page (Browse Assets)
/// -----------------
class UserHomePage extends StatefulWidget {
  const UserHomePage({super.key});
  @override
  State<UserHomePage> createState() => _UserHomePageState();
}

class _UserHomePageState extends State<UserHomePage> {
  String tab = 'land';
  final searchCtrl = TextEditingController();

  Query getQuery() => firestore.collection('assets').where('category', isEqualTo: tab).orderBy('createdAt', descending: true);

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Digital Goods'),
          bottom: TabBar(
            onTap: (i) => setState(() => tab = i == 0 ? 'land' : 'electronics'),
            tabs: const [Tab(text: 'Land'), Tab(text: 'Electronics')],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.favorite),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesPage())),
            ),
          ],
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search by title or city',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: getQuery().snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snap.hasData || snap.data!.docs.isEmpty) return const Center(child: Text('No assets found'));

                var docs = snap.data!.docs;
                final query = searchCtrl.text.trim().toLowerCase();
                if (query.isNotEmpty) {
                  docs = docs.where((d) {
                    final title = (d['title'] ?? '').toString().toLowerCase();
                    final city = (d['city'] ?? '').toString().toLowerCase();
                    return title.contains(query) || city.contains(query);
                  }).toList();
                }
                if (docs.isEmpty) return const Center(child: Text('No matching assets'));

                return GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.75,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final asset = docs[i];
                    final img = asset['imageBase64'] as String?;
                    return GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssetDetailFullPage(assetId: asset['assetId']))),
                      child: Card(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                              child: img != null
                                  ? Image.memory(base64Decode(img), width: double.infinity, fit: BoxFit.cover)
                                  : Container(color: Colors.grey[300], child: const Icon(Icons.image, size: 50)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(asset['title'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text('PKR ${asset['price']}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                          ),
                        ]),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

/// -----------------
/// Asset Detail Page
/// -----------------
class AssetDetailFullPage extends StatefulWidget {
  final String assetId;
  const AssetDetailFullPage({super.key, required this.assetId});
  @override
  State<AssetDetailFullPage> createState() => _AssetDetailFullPageState();
}

class _AssetDetailFullPageState extends State<AssetDetailFullPage> {
  DocumentSnapshot<Map<String, dynamic>>? doc;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snap = await firestore.collection('assets').doc(widget.assetId).get();
    setState(() {
      doc = snap as DocumentSnapshot<Map<String, dynamic>>?;
      loading = false;
    });
  }

  Future<void> requestBuy() async {
    final user = auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please login')));
      return;
    }
    final txId = const Uuid().v4();
    await firestore.collection('transactions').doc(txId).set({
      'transactionId': txId,
      'assetId': widget.assetId,
      'buyerId': user.uid,
      'sellerId': doc!['ownerId'],
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Purchase request sent')));
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (doc == null || !doc!.exists) return const Scaffold(body: Center(child: Text('Asset not found')));

    final data = doc!.data()!;
    final img = data['imageBase64'] as String?;
    return Scaffold(
      appBar: AppBar(title: Text(data['title'] ?? 'Asset')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (img != null)
            ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.memory(base64Decode(img), width: double.infinity, fit: BoxFit.cover)),
          const SizedBox(height: 16),
          Text(data['title'] ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('PKR ${data['price']}', style: const TextStyle(fontSize: 20, color: Colors.green, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Text(data['description'] ?? '', style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 16),
          if (data['category'] == 'land') ...[
            _infoChip(Icons.location_city, 'Location: ${data['city'] ?? 'N/A'}'),
            _infoChip(Icons.square_foot, 'Plot: ${data['plotArea'] ?? 'N/A'}'),
          ] else ...[
            _infoChip(Icons.branding_watermark, 'Brand: ${data['brand'] ?? 'N/A'}'),
            _infoChip(Icons.model_training, 'Model: ${data['model'] ?? 'N/A'}'),
          ],
          const SizedBox(height: 16),
          if (data['documentBase64'] != null)
            ElevatedButton.icon(
              onPressed: () async {
                final dir = await getTemporaryDirectory();
                final file = File('${dir.path}/${widget.assetId}.pdf');
                await file.writeAsBytes(base64Decode(data['documentBase64']));
                if (!mounted) return;
                Navigator.push(context, MaterialPageRoute(builder: (_) => PDFViewPage(file: file)));
              },
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('View Document'),
            ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: ElevatedButton(onPressed: requestBuy, child: const Text('Request to Buy / Invest'))),
            const SizedBox(width: 12),
            IconButton(
              icon: const Icon(Icons.favorite_border),
              onPressed: () async {
                final user = auth.currentUser;
                if (user == null) return;
                await firestore.collection('favorites').add({
                  'userId': user.uid,
                  'assetId': widget.assetId,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to favorites')));
              },
            ),
          ]),
          const SizedBox(height: 20),
          Center(child: QrImageView(data: 'asset://${widget.assetId}', size: 160)),
        ]),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 20, color: Colors.green),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 15)),
      ]),
    );
  }
}

/// -----------------
/// PDF Viewer
/// -----------------
class PDFViewPage extends StatelessWidget {
  final File file;
  const PDFViewPage({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Document')),
      body: PDFView(filePath: file.path),
    );
  }
}

/// -----------------
/// QR Scanner
/// -----------------
class QRScanLauncher extends StatelessWidget {
  const QRScanLauncher({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Scan QR Code')), body: const QRScannerPage());
}

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});
  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  final controller = MobileScannerController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _handle(String raw) async {
    if (raw.startsWith('asset://')) {
      final id = raw.replaceFirst('asset://', '');
      final snap = await firestore.collection('assets').doc(id).get();
      if (!snap.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Asset not found')));
        return;
      }
      if (!mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => AssetDetailFullPage(assetId: id)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid QR Code')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      controller: controller,
      onDetect: (capture) {
        final code = capture.barcodes.firstOrNull?.rawValue;
        if (code != null && code.isNotEmpty) _handle(code);
      },
    );
  }
}

/// -----------------
/// My Assets (User Owned)
/// -----------------
class MyAssetsPage extends StatelessWidget {
  const MyAssetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = auth.currentUser?.uid;
    if (uid == null) return const Scaffold(body: Center(child: Text('Login required')));

    return Scaffold(
      appBar: AppBar(title: const Text('My Assets')),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestore.collection('assets').where('ownerId', isEqualTo: uid).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snap.hasData || snap.data!.docs.isEmpty) return const Center(child: Text('No assets owned'));

          return ListView.builder(
            itemCount: snap.data!.docs.length,
            itemBuilder: (context, i) {
              final asset = snap.data!.docs[i];
              final img = asset['imageBase64'] as String?;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  leading: img != null
                      ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(base64Decode(img), width: 60, height: 60, fit: BoxFit.cover))
                      : const Icon(Icons.image),
                  title: Text(asset['title'] ?? ''),
                  subtitle: Text('PKR ${asset['price']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.picture_as_pdf),
                    onPressed: () async {
                      final dir = await getTemporaryDirectory();
                      final file = File('${dir.path}/${asset['assetId']}_cert.txt');
                      await file.writeAsString('Ownership: ${asset['title']}\nOwner: ${auth.currentUser!.email}\nDate: ${DateTime.now()}');
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Certificate saved')));
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// -----------------
/// Profile Page
/// -----------------
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  DocumentSnapshot<Map<String, dynamic>>? userDoc;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = auth.currentUser;
    if (user == null) {
      setState(() => loading = false);
      return;
    }
    final snap = await firestore.collection('users').doc(user.uid).get();
    setState(() {
      userDoc = snap as DocumentSnapshot<Map<String, dynamic>>?;
      loading = false;
    });
  }

  Future<void> _pickAndSavePhoto() async {
    final XFile? f = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    await firestore.collection('users').doc(auth.currentUser!.uid).update({'profilePhotoBase64': base64Encode(bytes)});
    _load();
  }

  Future<void> _changePassword() async {
    final user = auth.currentUser;
    if (user?.email == null) return;
    await auth.sendPasswordResetEmail(email: user!.email!);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset email sent')));
  }

  Future<void> _logout() async {
    await auth.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AuthPage()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (userDoc == null) return const Scaffold(body: Center(child: Text('No profile data')));

    final d = userDoc!.data()!;
    final img = d['profilePhotoBase64'] as String?;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          CircleAvatar(radius: 50, backgroundImage: img != null ? MemoryImage(base64Decode(img)) : null, child: img == null ? const Icon(Icons.person, size: 50) : null),
          const SizedBox(height: 16),
          Text(d['name'] ?? '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(d['email'] ?? '', style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton.icon(onPressed: _pickAndSavePhoto, icon: const Icon(Icons.photo), label: const Text('Change Photo')),
          const SizedBox(height: 12),
          ElevatedButton.icon(onPressed: _changePassword, icon: const Icon(Icons.lock_reset), label: const Text('Reset Password')),
          const SizedBox(height: 12),
          ElevatedButton.icon(onPressed: _logout, icon: const Icon(Icons.logout), label: const Text('Logout'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red)),
        ]),
      ),
    );
  }
}

/// -----------------
/// Favorites Page
/// -----------------
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = auth.currentUser?.uid;
    if (uid == null) return const Scaffold(body: Center(child: Text('Login required')));

    return Scaffold(
      appBar: AppBar(title: const Text('Favorites')),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestore.collection('favorites').where('userId', isEqualTo: uid).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snap.hasData || snap.data!.docs.isEmpty) return const Center(child: Text('No favorites yet'));

          return ListView.builder(
            itemCount: snap.data!.docs.length,
            itemBuilder: (context, i) {
              final fav = snap.data!.docs[i];
              return FutureBuilder<DocumentSnapshot>(
                future: firestore.collection('assets').doc(fav['assetId']).get(),
                builder: (context, assetSnap) {
                  if (!assetSnap.hasData) return const SizedBox();
                  final asset = assetSnap.data!;
                  return ListTile(
                    leading: const Icon(Icons.favorite, color: Colors.red),
                    title: Text(asset['title'] ?? ''),
                    subtitle: Text('PKR ${asset['price']}'),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssetDetailFullPage(assetId: asset['assetId']))),
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

/// -----------------
/// Supplier Transactions
/// -----------------
class SupplierTransactionsPage extends StatelessWidget {
  const SupplierTransactionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = auth.currentUser?.uid;
    if (uid == null) return const Scaffold(body: Center(child: Text('Login required')));

    return Scaffold(
      appBar: AppBar(title: const Text('Purchase Requests')),
      body: StreamBuilder<QuerySnapshot>(
        stream: firestore.collection('transactions').where('sellerId', isEqualTo: uid).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snap.hasData || snap.data!.docs.isEmpty) return const Center(child: Text('No requests'));

          return ListView.builder(
            itemCount: snap.data!.docs.length,
            itemBuilder: (context, i) {
              final tx = snap.data!.docs[i];
              final status = tx['status'];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text('Asset ID: ${tx['assetId']}'),
                  subtitle: Text('Buyer: ${tx['buyerId']} • Status: $status'),
                  trailing: status == 'pending'
                      ? Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.green),
                      onPressed: () async {
                        await firestore.runTransaction((t) async {
                          final assetRef = firestore.collection('assets').doc(tx['assetId']);
                          final assetSnap = await t.get(assetRef);
                          if (!assetSnap.exists) throw 'Asset not found';
                          t.update(assetRef, {'ownerId': tx['buyerId'], 'status': 'sold'});
                          t.update(tx.reference, {'status': 'approved', 'handledAt': FieldValue.serverTimestamp()});
                        });
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => tx.reference.update({'status': 'rejected', 'handledAt': FieldValue.serverTimestamp()}),
                    ),
                  ])
                      : Text(status, style: TextStyle(color: status == 'approved' ? Colors.green : Colors.red)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}