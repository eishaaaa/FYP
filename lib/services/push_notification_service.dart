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
