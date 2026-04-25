import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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

// ─── Notification Service ─────────────────────────────────────────────────────
class PushNotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static final PushNotificationService _instance =
  PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  Future<void> deleteNotification(String docId) async {
    try {
      await _db.collection('notifications').doc(docId).delete();
    } catch (e) {
      debugPrint('❌ Error deleting notification: $e');
    }
  }

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
        'metadata': {'platform': 'flutter_app', 'version': '1.0.0'},
      });
    } catch (e) {
      debugPrint('❌ Error storing in-app notification: $e');
    }
  }

  Stream<QuerySnapshot> notificationsStream(String userUid) {
    return _db
        .collection('notifications')
        .where('receiverId', isEqualTo: userUid)
        .orderBy('timestamp', descending: true)
        .limit(50)
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

    // Staggered entrance
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

const kCardBg = Colors.white;

// ─── Notifications Screen ─────────────────────────────────────────────────────
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _headerController;
  late Animation<double> _headerFade;

  @override
  void initState() {
    super.initState();
    _headerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();
    _headerFade =
        CurvedAnimation(parent: _headerController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _headerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String currentUserUid =
        FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: kScaffoldBg,
      body: Column(
        children: [
          // ── Gradient Header ──
          FadeTransition(
            opacity: _headerFade,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [kTealDark, kTeal],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 16, 24),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: Colors.white, size: 18),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Notifications',
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
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
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.25),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '$unread unread',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
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
                          PushNotificationService()
                              .markAllAsRead(currentUserUid);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('All marked as read',
                                  style: GoogleFonts.poppins()),
                              backgroundColor: kTeal,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.done_all_rounded,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Body ──
          Expanded(
            child: currentUserUid.isEmpty
                ? _buildEmptyState('Please log in to see notifications',
                Icons.lock_outline_rounded)
                : StreamBuilder<QuerySnapshot>(
              stream: PushNotificationService()
                  .notificationsStream(currentUserUid),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _buildEmptyState(
                      'Something went wrong', Icons.error_outline_rounded);
                }
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: kTeal),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return _buildEmptyState(
                    'No notifications yet',
                    Icons.notifications_off_rounded,
                    subtitle:
                    "You're all caught up! We'll notify you when something happens.",
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 16, bottom: 24),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
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
                        FirebaseFirestore.instance
                            .collection('notifications')
                            .doc(docId)
                            .delete();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Notification deleted',
                                style: GoogleFonts.poppins()),
                            backgroundColor: Colors.red.shade400,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        );
                      },
                      child: NotificationTile(
                        data: data,
                        index: index,
                        onTap: () =>
                            PushNotificationService().markAsRead(docId),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
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
                decoration: BoxDecoration(
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