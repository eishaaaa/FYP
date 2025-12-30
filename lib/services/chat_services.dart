import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChatService {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static String get uid => _auth.currentUser!.uid;

  static Future<void> setOnline(bool online) async {
    await _db.collection('users').doc(uid).update({
      'online': online,
      'lastSeen': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> setTyping(String chatId, bool typing) async {
    await _db.collection('chats').doc(chatId).update({
      'typing.$uid': typing,
    });
  }

  static Future<void> sendMessage({
    required String chatId,
    required String text,
    required String receiverId,
  }) async {
    final msg = {
      'text': text,
      'senderId': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'seen': false,
    };

    await _db.collection('chats').doc(chatId).set({
      'users': [uid, receiverId],
      'lastMessage': text,
      'lastMessageTime': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add(msg);
  }

  static Future<void> markSeen(String chatId) async {
    final q = await _db
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('senderId', isNotEqualTo: uid)
        .where('seen', isEqualTo: false)
        .get();

    for (var d in q.docs) {
      d.reference.update({'seen': true});
    }
  }
}
