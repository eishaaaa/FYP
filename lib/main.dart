// lib/main.dart
// Complete integrated main entry with role-based routing
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'screens/auth_screens.dart';
import 'screens/user_screens.dart';
import 'screens/supplier_screens.dart';
import 'screens/admin_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  runApp(const DigitalGoodsApp());
}

class DigitalGoodsApp extends StatefulWidget {
  const DigitalGoodsApp({super.key});

  @override
  State<DigitalGoodsApp> createState() => _DigitalGoodsAppState();
}

class _DigitalGoodsAppState extends State<DigitalGoodsApp> {
  bool _darkMode = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        setState(() {
          _darkMode = false;
          _loading = false;
        });
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data();
        if (data != null && data.containsKey('darkMode')) {
          setState(() => _darkMode = data['darkMode'] == true);
        }
      }

      setState(() => _loading = false);
    } catch (e) {
      debugPrint('Error loading theme: $e');
      setState(() {
        _darkMode = false;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final theme = ThemeData(
      brightness: _darkMode ? Brightness.dark : Brightness.light,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0D47A1),
        brightness: _darkMode ? Brightness.dark : Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0D47A1),
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 2,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0D47A1),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          minimumSize: const Size(double.infinity, 48),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );

    return MaterialApp(
      title: 'Digital Goods',
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: const AppEntry(),
    );
  }
}

class AppEntry extends StatefulWidget {
  const AppEntry({super.key});

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  bool _loading = true;
  bool _seenOnboarding = false;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    _seenOnboarding = prefs.getBool('onboarding') ?? false;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return _seenOnboarding ? const SplashScreen() : const OnboardingScreen();
  }
}

/// Role-based router after authentication
class RoleBasedRouter extends StatelessWidget {
  const RoleBasedRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const LoginScreen();
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const LoginScreen();
        }

        final userData = snapshot.data!.data() as Map<String, dynamic>;
        final role = userData['role'] as String? ?? 'user';

        // Route based on role
        if (role == 'admin') {
          return const AdminHomeScreen();
        } else if (role.contains('supplier')) {
          // Extract supplier type (land/electronics)
          final type = role.contains('land') ? 'land' : 'electronics';
          return SupplierHomeScreen(type: type);
        } else {
          return const UserHomeScreen();
        }
      },
    );
  }
}