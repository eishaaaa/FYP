import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

// ─── Brand Colors ─────────────────────────────────────────────────────────────
const kTeal = Color(0xFF2D7D7D);
const kTealDark = Color(0xFF1F5C5C);
const kTealLight = Color(0xFFE8F4F4);
const kTealAccent = Color(0xFF3AAFA9);
const kScaffoldBg = Color(0xFFF5F8F8);
const kTextPrimary = Color(0xFF1A2E2E);
const kTextSecondary = Color(0xFF6B8E8E);
const kCardBg = Colors.white;

// ─── Background message handler (must be top-level) ──────────────────────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // App is in background or killed — FCM shows the notification automatically.
  // Nothing extra needed here unless you want to write to Firestore.
  debugPrint('📨 Background FCM message: ${message.notification?.title}');
}

// ─── Notification Service ─────────────────────────────────────────────────────
class PushNotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  static final PushNotificationService _instance =
  PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  // ── Initialize everything (call once in main.dart) ──────────────────────────
  Future<void> initialize() async {
    // Background handler is registered in main.dart before runApp — do not re-register here.

    // 1. Request permission
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('🔔 FCM permission: ${settings.authorizationStatus}');

    // 3. Setup local notifications (for foreground display)
    const androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(initSettings);

    // Create notification channel (Android 8+)
    const channel = AndroidNotificationChannel(
      'digital_goods_channel',
      'Digital Goods Notifications',
      description: 'Notifications for transfers, messages, and updates',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 3. Show notification when app is in FOREGROUND
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification != null) {
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'digital_goods_channel',
              'Digital Goods Notifications',
              channelDescription:
              'Notifications for transfers, messages, and updates',
              importance: Importance.high,
              priority: Priority.high,
              color: kTeal,
            ),
          ),
        );
      }
    });

    // 4. Save FCM token to Firestore so you can target specific users
    await _saveTokenToFirestore();

    // Token refresh
    _fcm.onTokenRefresh.listen(_saveTokenOnRefresh);
  }

  Future<void> _saveTokenToFirestore() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final token = await _fcm.getToken();
      if (token == null) return;
      await _db.collection('users').doc(uid).set(
        {'fcmToken': token, 'fcmUpdatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      debugPrint('✅ FCM token saved: $token');
    } catch (e) {
      debugPrint('❌ Error saving FCM token: $e');
    }
  }

  void _saveTokenOnRefresh(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set(
      {'fcmToken': token, 'fcmUpdatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  // ── In-app notification (Firestore) ─────────────────────────────────────────
  // This writes to root 'notifications' collection with receiverId field.
  // The NotificationsScreen below queries this same collection.
  Future<void> sendInAppNotification({
    required String receiverUid,
    required String title,
    required String body,
    String type = 'general',
    String? relatedId,
    Map<String, dynamic>? payload,
  }) async {
    try {
      await _db.collection('notifications').add({
        'receiverId': receiverUid,
        'title': title,
        'body': body,
        'type': type,
        'relatedId': relatedId,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
        'payload': payload ?? {},
      });
    } catch (e) {
      debugPrint('❌ Error storing in-app notification: $e');
    }
  }

  Stream<QuerySnapshot> notificationsStream(String userUid) {
    // No orderBy at all — fully sorted client-side to avoid any index requirement.
    return _db
        .collection('notifications')
        .where('receiverId', isEqualTo: userUid)
        .snapshots();
  }

  Future<void> markAsRead(String docId) async {
    try {
      await _db
          .collection('notifications')
          .doc(docId)
          .update({'isRead': true});
    } catch (e) {
      debugPrint('❌ Error marking as read: $e');
    }
  }

  Future<void> markAllAsRead(String userUid) async {
    final batch = _db.batch();
    final query = await _db
        .collection('notifications')
        .where('receiverId', isEqualTo: userUid)
        .where('isRead', isEqualTo: false)
        .get();
    for (var doc in query.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  Future<void> deleteNotification(String docId) async {
    try {
      await _db.collection('notifications').doc(docId).delete();
    } catch (e) {
      debugPrint('❌ Error deleting notification: $e');
    }
  }
}

// ─── Notification Tile ────────────────────────────────────────────────────────
class NotificationTile extends StatefulWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final int index;

  const NotificationTile({
    super.key,
    required this.data,
    required this.onTap,
    required this.index,
  });

  @override
  State<NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends State<NotificationTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    Future.delayed(Duration(milliseconds: 60 * widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isRead = widget.data['isRead'] ?? false;
    final String type = widget.data['type'] ?? 'general';
    final DateTime? timestamp =
    (widget.data['timestamp'] as Timestamp?)?.toDate();

    final iconConfig = _iconConfig(type);

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            decoration: BoxDecoration(
              color: isRead ? kCardBg : kTealLight,
              borderRadius: BorderRadius.circular(16),
              border: isRead
                  ? Border.all(color: Colors.grey.shade100)
                  : Border.all(color: kTeal.withOpacity(0.2)),
              boxShadow: [
                BoxShadow(
                  color: kTeal.withOpacity(isRead ? 0.04 : 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: iconConfig['color'].withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      iconConfig['icon'],
                      color: iconConfig['color'],
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.data['title'] ?? 'Notification',
                                style: GoogleFonts.poppins(
                                  fontWeight: isRead
                                      ? FontWeight.w500
                                      : FontWeight.w700,
                                  fontSize: 14,
                                  color: kTextPrimary,
                                ),
                              ),
                            ),
                            if (!isRead)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: kTeal,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.data['body'] ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            color: kTextSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        if (timestamp != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.access_time_rounded,
                                  size: 11, color: kTextSecondary),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat('MMM dd, hh:mm a').format(timestamp),
                                style: GoogleFonts.poppins(
                                  color: kTextSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _iconConfig(String type) {
    switch (type) {
      case 'product_sold':
        return {'icon': Icons.payments_rounded, 'color': Colors.green};
      case 'transfer':
        return {'icon': Icons.swap_horiz_rounded, 'color': Colors.orange};
      case 'verified':
        return {'icon': Icons.verified_rounded, 'color': kTeal};
      case 'message':
        return {'icon': Icons.chat_bubble_rounded, 'color': kTealAccent};
      default:
        return {'icon': Icons.notifications_rounded, 'color': kTeal};
    }
  }
}

// ─── Notifications Screen ─────────────────────────────────────────────────────
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String currentUserUid =
        FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: kScaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kTealLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: kTeal, size: 18),
          ),
        ),
        title: Text(
          'Notifications',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: kTextPrimary,
          ),
        ),
        actions: [
          // Unread badge
          if (currentUserUid.isNotEmpty)
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('notifications')
                  .where('receiverId', isEqualTo: currentUserUid)
                  .where('isRead', isEqualTo: false)
                  .snapshots(),
              builder: (context, snap) {
                final unread = snap.data?.docs.length ?? 0;
                return unread > 0
                    ? Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: kTealLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$unread unread',
                    style: GoogleFonts.poppins(
                      color: kTeal,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
                    : const SizedBox.shrink();
              },
            ),
          // Mark all read button
          GestureDetector(
            onTap: () {
              PushNotificationService().markAllAsRead(currentUserUid);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content:
                  Text('All marked as read', style: GoogleFonts.poppins()),
                  backgroundColor: kTeal,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kTealLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.done_all_rounded, color: kTeal, size: 20),
            ),
          ),
        ],
      ),
      body: currentUserUid.isEmpty
          ? _buildEmptyState(
          'Please log in to see notifications',
          Icons.lock_outline_rounded)
          : StreamBuilder<QuerySnapshot>(
        stream: PushNotificationService()
            .notificationsStream(currentUserUid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildEmptyState(
                'Error: ${snapshot.error}', Icons.error_outline_rounded);
          }
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: kTeal),
            );
          }

          // Sort client-side by timestamp descending (avoids composite index)
          final docs = (snapshot.data?.docs ?? [])
            ..sort((a, b) {
              final aTs = (a.data() as Map)['timestamp'] as Timestamp?;
              final bTs = (b.data() as Map)['timestamp'] as Timestamp?;
              if (aTs == null && bTs == null) return 0;
              if (aTs == null) return 1;
              if (bTs == null) return -1;
              return bTs.compareTo(aTs);
            });

          if (docs.isEmpty) {
            return _buildEmptyState(
              'No notifications yet',
              Icons.notifications_off_rounded,
              subtitle:
              "You're all caught up! We'll notify you when something happens.",
            );
          }

          return ListView.builder(
            padding:
            const EdgeInsets.only(top: 16, bottom: 24),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data =
              doc.data() as Map<String, dynamic>;
              final docId = doc.id;

              return Dismissible(
                key: Key(docId),
                direction: DismissDirection.endToStart,
                background: Container(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 5),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade400,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.delete_rounded,
                          color: Colors.white, size: 26),
                      const SizedBox(height: 4),
                      Text(
                        'Delete',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                onDismissed: (_) {
                  PushNotificationService()
                      .deleteNotification(docId);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Notification deleted',
                          style: GoogleFonts.poppins()),
                      backgroundColor: Colors.red.shade400,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(10)),
                    ),
                  );
                },
                child: NotificationTile(
                  data: data,
                  index: index,
                  onTap: () =>
                      PushNotificationService()
                          .markAsRead(docId),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(String title, IconData icon, {String? subtitle}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: child,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: const BoxDecoration(
                  color: kTealLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 52, color: kTeal),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: kTextPrimary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: kTextSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}