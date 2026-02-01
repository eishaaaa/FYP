import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// IMPORTANT: Replace with your actual FCM Server Key from Firebase Console
/// Go to: Firebase Console > Project Settings > Cloud Messaging > Server Key
const String _FCM_SERVER_KEY = 'REPLACE_WITH_YOUR_FCM_SERVER_KEY';

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Background message: ${message.messageId}');

  if (message.data.isNotEmpty) {
    final type = message.data['type'];
    print('Notification type: $type');
  }
}

class PushNotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  /// Initialize push notifications
  Future<void> initializeForUser(String userUid) async {
    try {
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ User granted notification permission');
      } else {
        print('⚠️ User declined notification permission');
        return;
      }

      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      final token = await _fcm.getToken();

      if (token != null) {
        print('📱 FCM Token: ${token.substring(0, 20)}...');

        await _db.collection('users').doc(userUid).update({
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        });
      }

      _fcm.onTokenRefresh.listen((newToken) {
        _db.collection('users').doc(userUid).update({
          'fcmToken': newToken,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      print('❌ Error initializing notifications: $e');
    }
  }

  void listenForegroundNotifications() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📨 Foreground message received');
      final notification = message.notification;
      if (notification != null) {
        print('Title: ${notification.title}');
        print('Body: ${notification.body}');
      }
    });
  }

  void onNotificationOpened() {
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('📬 App opened from notification');
      final data = message.data;
      if (data.isNotEmpty) {
        print('Notification type: ${data['type']}');
      }
    });

    _fcm.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        print('📭 App launched from notification');
      }
    });
  }

  Future<bool> sendPushMessage({
    required String token,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      if (_FCM_SERVER_KEY == 'REPLACE_WITH_YOUR_FCM_SERVER_KEY') {
        print('⚠️ WARNING: FCM Server Key not configured!');
        return false;
      }

      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/fcm/send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=$_FCM_SERVER_KEY',
        },
        body: jsonEncode({
          'to': token,
          'priority': 'high',
          'notification': {
            'title': title,
            'body': body,
            'sound': 'default',
            'badge': '1',
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          },
          'data': {
            ...?data,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          },
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Push notification sent successfully');
        return true;
      } else {
        print('❌ Failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ Error: $e');
      return false;
    }
  }

  Future<void> sendToMultipleUsers({
    required List<String> userIds,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    for (final userId in userIds) {
      try {
        final userDoc = await _db.collection('users').doc(userId).get();
        final token = userDoc.data()?['fcmToken'];

        if (token != null) {
          await sendPushMessage(token: token, title: title, body: body, data: data);
        }
      } catch (e) {
        print('Error sending to user $userId: $e');
      }
    }
  }

  Future<void> subscribeToTopic(String topic) async {
    try {
      await _fcm.subscribeToTopic(topic);
      print('✅ Subscribed to topic: $topic');
    } catch (e) {
      print('❌ Error: $e');
    }
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _fcm.unsubscribeFromTopic(topic);
      print('✅ Unsubscribed from topic: $topic');
    } catch (e) {
      print('❌ Error: $e');
    }
  }

  Future<bool> isNotificationEnabled() async {
    final settings = await _fcm.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  Future<bool> requestPermission() async {
    final settings = await _fcm.requestPermission(alert: true, badge: true, sound: true);
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }
}