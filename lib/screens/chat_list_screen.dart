import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('participants', arrayContains: uid)
            .orderBy('lastMessageTime', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return _chatSkeleton();
          }

          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const Center(child: Text('No chats yet'));
          }

          final chats = snap.data!.docs;

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, i) {
              final chat = chats[i];
              final chatData = chat.data() as Map<String, dynamic>? ?? {};
              final participants = List<String>.from(chatData['participants'] ?? []);

              // Skip chat if participants invalid
              if (participants.length < 2) return const SizedBox();

              // Find the other user
              final otherUid = participants.firstWhere(
                    (u) => u != uid,
                orElse: () => '',
              );
              if (otherUid.isEmpty) return const SizedBox();

              return StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(otherUid)
                    .snapshots(),
                builder: (context, userSnap) {
                  if (!userSnap.hasData || !userSnap.data!.exists) {
                    return _chatSkeletonItem();
                  }

                  final userData = userSnap.data!.data() as Map<String, dynamic>? ?? {};
                  final unread = (chatData['unread_$uid'] ?? 0) as int;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: userData['photoUrl'] != null
                          ? NetworkImage(userData['photoUrl'])
                          : null,
                      child: userData['photoUrl'] == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text(userData['name'] ?? 'User'),
                    subtitle: Text(
                      chatData['lastMessage'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: unread > 0
                        ? CircleAvatar(
                      radius: 10,
                      backgroundColor: Colors.red,
                      child: Text(
                        unread.toString(),
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white),
                      ),
                    )
                        : null,
                    onTap: () async {
                      // Reset unread safely
                      await FirebaseFirestore.instance
                          .collection('chats')
                          .doc(chat.id)
                          .update({'unread_$uid': 0});

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            chatId: chat.id,
                            otherUserId: otherUid,
                          ),
                        ),
                      );
                    },
                    onLongPress: () => _deleteChat(context, chat.id),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _chatSkeleton() {
    return ListView.builder(
      itemCount: 6,
      itemBuilder: (_, __) => _chatSkeletonItem(),
    );
  }

  Widget _chatSkeletonItem() {
    return const ListTile(
      leading: CircleAvatar(backgroundColor: Colors.grey),
      title: SizedBox(
        height: 10,
        child: DecoratedBox(
          decoration: BoxDecoration(color: Colors.grey),
        ),
      ),
      subtitle: SizedBox(height: 8),
    );
  }

  void _deleteChat(BuildContext context, String chatId) async {
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).delete();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Failed to delete chat')));
    }
  }
}
