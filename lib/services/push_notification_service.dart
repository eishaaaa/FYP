import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Add intl to your pubspec.yaml for date formatting
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PushNotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static final PushNotificationService _instance =
  PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  /// Delete a specific notification
  Future<void> deleteNotification(String docId) async {
    try {
      await _db.collection('notifications').doc(docId).delete();
    } catch (e) {
      print('❌ Error deleting notification: $e');
    }
  }

  /// Add a notification to Firestore
  Future<void> sendInAppNotification({
    required String receiverUid,
    required String title,
    required String body,
    String type = 'general',
    String? relatedId,
    // Using a Map for additional data keeps the top-level schema clean
    Map<String, dynamic>? payload,
  }) async {
    try {
      final Map<String, dynamic> notificationData = {
        'receiverId': receiverUid,
        'title': title,
        'body': body,
        'type': type,
        'relatedId': relatedId,
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
        // Nesting extra data prevents field name collisions
        'payload': payload ?? {},
        'metadata': {
          'platform': 'flutter_app',
          'version': '1.0.0',
        },
      };

      await _db.collection('notifications').add(notificationData);
      print('✅ In-app notification stored for $receiverUid');
    } catch (e) {
      print('❌ Error storing in-app notification: $e');
    }
  }

  /// Listen for notifications for a specific user
  /// Note: Ensure you have created a Firestore Index for receiverId + timestamp
  Stream<QuerySnapshot> notificationsStream(String userUid) {
    return _db
        .collection('notifications')
        .where('receiverId', isEqualTo: userUid)
        .orderBy('timestamp', descending: true)
        .limit(50) // Recommended to limit for performance
        .snapshots();
  }

  /// Mark notification as read
  Future<void> markAsRead(String docId) async {
    try {
      await _db.collection('notifications').doc(docId).update({'isRead': true});
    } catch (e) {
      print('❌ Error marking notification as read: $e');
    }
  }

  /// Bulk mark all as read (Useful for a "Clear All" button)
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


class NotificationTile extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const NotificationTile({
    super.key,
    required this.data,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final bool isRead = data['isRead'] ?? false;
    final String type = data['type'] ?? 'general';
    final DateTime? timestamp = (data['timestamp'] as Timestamp?)?.toDate();

    return Container(
      // Light blue background for unread, white for read
      color: isRead ? Colors.transparent : Colors.blue.withValues(alpha: 0.05),
      child: ListTile(
        onTap: onTap,
        leading: _buildIcon(type, isRead),
        title: Text(
          data['title'] ?? 'Notification',
          style: TextStyle(
            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
            fontSize: 15,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              data['body'] ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
            if (timestamp != null) ...[
              const SizedBox(height: 6),
              Text(
                DateFormat('MMM dd, hh:mm a').format(timestamp),
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
              ),
            ],
          ],
        ),
        trailing: isRead
            ? null
            : const CircleAvatar(radius: 4, backgroundColor: Colors.blue),
      ),
    );
  }

  /// Helper to return specific icons/colors based on notification type
  Widget _buildIcon(String type, bool isRead) {
    IconData iconData;
    Color iconColor;

    switch (type) {
      case 'product_sold':
        iconData = Icons.payments_outlined;
        iconColor = Colors.green;
        break;
      case 'transfer':
        iconData = Icons.swap_horiz_rounded;
        iconColor = Colors.orange;
        break;
      default:
        iconData = Icons.notifications_none_rounded;
        iconColor = Colors.blueGrey;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(iconData, color: iconColor, size: 24),
    );
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String currentUserUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            onPressed: () => PushNotificationService().markAllAsRead(currentUserUid),
            tooltip: 'Mark all as read',
          ),
        ],
      ),
      body: currentUserUid.isEmpty
          ? const Center(child: Text('Please log in to see notifications'))
          : StreamBuilder<QuerySnapshot>(
        stream: PushNotificationService().notificationsStream(currentUserUid),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Something went wrong'));
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return const Center(child: Text('No notifications yet!'));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final docId = doc.id;

              // --- SWIPE TO DELETE WRAPPER ---
              return Dismissible(
                key: Key(docId),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.red,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (direction) {
                  // Delete from Firestore
                  FirebaseFirestore.instance
                      .collection('notifications')
                      .doc(docId)
                      .delete();

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Notification deleted')),
                  );
                },
                child: NotificationTile(
                  data: data,
                  onTap: () {
                    PushNotificationService().markAsRead(docId);
                    // Add your navigation logic here
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';


class PushNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Initialize and save token
  Future<void> initializeForUser(String userUid) async {
    await _fcm.requestPermission(alert: true, badge: true, sound: true);
    final token = await _fcm.getToken();
    if (token != null) {
      await _db.collection('users').doc(userUid).update({'fcmToken': token});
    }
  }

  void listenForegroundNotifications() {
    FirebaseMessaging.onMessage.listen((message) {
      if (message.notification != null) {
        print('Notification: ${message.notification!.title}');
      }
    });
  }

  void onNotificationOpened() {
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      print('App opened from notification');
    });
  }

  Future<void> sendPushMessage({
    required String token,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'key=YOUR_SERVER_KEY', // replace with FCM server key
        },
        body: jsonEncode(<String, dynamic>{
          'to': token,
          'notification': {'title': title, 'body': body},
          'data': data ?? {},
        }),
      );
    } catch (e) {
      print('Error sending push message: $e');
    }
  }
}
