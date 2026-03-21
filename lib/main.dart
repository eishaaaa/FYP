// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'screens/auth_screens.dart';
import 'screens/user_screens.dart';
import 'screens/supplier_screens.dart';
import 'screens/admin_screen.dart';
import 'screens/transfer_screen.dart';
import 'services/push_notification_service.dart';

/// Global navigator key for navigation from notification handlers
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Background message: ${message.messageId}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Set background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

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
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
   /*   // Initialize push notifications
      final pushService = PushNotificationService();
      await pushService.initializeForUser(user.uid);
      pushService.listenForegroundNotifications();
      pushService.onNotificationOpened();    */

      // Setup notification listeners
      _setupNotificationHandlers();

      try {
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
      } catch (e) {
        debugPrint('Error loading theme: $e');
        setState(() => _darkMode = false);
      }
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  /// Setup notification handlers for navigation
  void _setupNotificationHandlers() {
    // Handle notification when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Foreground notification received');

      if (message.notification != null) {
        // Show dialog or snackbar
        _showNotificationDialog(message);
      }
    });

    // Handle notification when app is opened from background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('Notification opened app from background');
      _handleNotificationNavigation(message);
    });

    // Check if app was opened from terminated state
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        print('Notification opened app from terminated state');
        // Delay navigation until app is fully loaded
        Future.delayed(const Duration(seconds: 2), () {
          _handleNotificationNavigation(message);
        });
      }
    });
  }

  /// Show notification as dialog when app is in foreground
  void _showNotificationDialog(RemoteMessage message) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final notification = message.notification;
    if (notification == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(notification.title ?? 'Notification'),
        content: Text(notification.body ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Dismiss'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleNotificationNavigation(message);
            },
            child: const Text('View'),
          ),
        ],
      ),
    );
  }

  /// Navigate based on notification type
  void _handleNotificationNavigation(RemoteMessage message) {
    final data = message.data;
    if (data.isEmpty) return;

    final type = data['type'];
    final context = navigatorKey.currentContext;
    if (context == null) return;

    switch (type) {
      case 'checkout_request':
      // Navigate to transfer screen for buyer
        final transactionId = data['transactionId'];
        if (transactionId != null) {
          _navigateToTransferScreen(context, transactionId);
        }
        break;

      case 'checkout_accepted':
      case 'checkout_rejected':
      // Navigate to chat or show notification
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(type == 'checkout_accepted' ? 'Checkout Accepted' : 'Checkout Rejected'),
            content: Text(message.notification?.body ?? ''),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        break;

      case 'transfer_complete':
      case 'product_sold':
      // Show success notification
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Success'),
              ],
            ),
            content: Text(message.notification?.body ?? ''),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        break;
    }
  }

  /// Navigate to transfer screen
  Future<void> _navigateToTransferScreen(BuildContext context, String transactionId) async {
    try {
      // Fetch transaction details
      final txDoc = await FirebaseFirestore.instance
          .collection('transaction')
          .doc(transactionId)
          .get();

      if (!txDoc.exists) {
        throw Exception('Transaction not found');
      }

      final txData = txDoc.data()!;
      final assetType = txData['assetType'] == 'electronics'
          ? AssetType.electronics
          : AssetType.land;

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TransferScreen(
              assetType: assetType,
              assetId: txData['assetId'],
              transactionId: transactionId,
              buyerUid: txData['buyerUid'],
              sellerUid: txData['sellerUid'],
              tokenId: txData['blockchainTokenId'],
              propertyId: txData['blockchainTokenId'],
              fractionAmount: txData['fractionAmount'],
            ),
          ),
        );
      }
    } catch (e) {
      print('Error navigating to transfer screen: $e');
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
      navigatorKey: navigatorKey,
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
          final type = role.contains('land') ? 'land' : 'electronics';
          return SupplierHomeScreen(type: type);
        } else {
          return const UserHomeScreen();
        }
      },
    );
  }
}