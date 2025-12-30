import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String otherUserId;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.otherUserId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _controller = TextEditingController();
  bool _isTyping = false;

  String get myUid => _auth.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _setOnlineStatus(true);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _db.collection('chats').doc(widget.chatId).set({
        'unread_$myUid': 0,
      }, SetOptions(merge: true));

      _markMessagesSeen();
    });
  }

  @override
  void dispose() {
    _setOnlineStatus(false);
    _controller.dispose();
    super.dispose();
  }

  void _setOnlineStatus(bool online) {
    _db.collection('users').doc(myUid).set(
      {
        'online': online,
        'lastSeen': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    setState(() => _isTyping = false);

    final chatRef = _db.collection('chats').doc(widget.chatId);

    await chatRef.collection('messages').add({
      'text': text,
      'senderId': myUid,
      'timestamp': FieldValue.serverTimestamp(),
      'seen': false,
    });

    await chatRef.set({
      'participants': [myUid, widget.otherUserId],
      'lastMessage': text,
      'lastMessageTime': FieldValue.serverTimestamp(),

      // ✅ unread count ONLY ONCE
      'unread_${widget.otherUserId}': FieldValue.increment(1),
    }, SetOptions(merge: true));
    await _db.collection('chats').doc(widget.chatId).update({
      'typing': false,
    });

  }



  Future<void> _markMessagesSeen() async {
    final msgs = await _db
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .where('senderId', isNotEqualTo: myUid)
        .where('seen', isEqualTo: false)
        .get();

    for (var m in msgs.docs) {
      m.reference.update({'seen': true});
    }

    // Reset unread count for self
    await _db.collection('chats').doc(widget.chatId).update({
      'unreadCount.$myUid': 0,
    });
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<DocumentSnapshot>(
          stream: _db.collection('users').doc(widget.otherUserId).snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Text('Chat');

            final u = snap.data!.data() as Map<String, dynamic>;
            final online = u['online'] == true;

            return Row(
              children: [
                CircleAvatar(
                  backgroundImage: u['photoUrl'] != null
                      ? NetworkImage(u['photoUrl'])
                      : null,
                  child: u['photoUrl'] == null
                      ? const Icon(Icons.person)
                      : null,
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u['name'] ?? 'User'),
                    Text(
                      online
                          ? 'online'
                          : 'last seen ${_formatTime(u['lastSeen'])}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                )
              ],
            );
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('Say hello 👋'));
                }

                return ListView.builder(
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final m = docs[i];
                    final msg = m.data() as Map<String, dynamic>;
                    final isMe = msg['senderId'] == myUid;

                    if (!isMe && msg['seen'] == false) {
                      m.reference.update({'seen': true});
                    }

                    return _messageBubble(msg, isMe);
                  },
                );
              },
            ),
          ),

          if (_isTyping)
            const Padding(
              padding: EdgeInsets.only(left: 12, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('typing...'),
              ),
            ),
          StreamBuilder<DocumentSnapshot>(
            stream: _db.collection('chats').doc(widget.chatId).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData || !snap.data!.exists) {
                return const SizedBox();
              }

              final data = snap.data!.data() as Map<String, dynamic>;
              final isTyping = data['typing'] == true;

              return isTyping
                  ? const Padding(
                padding: EdgeInsets.only(left: 12, bottom: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'typing...',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              )
                  : const SizedBox();
            },
          ),
          SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onChanged: (value) {
                      _db.collection('chats').doc(widget.chatId).set({
                        'typing': value.isNotEmpty,
                      }, SetOptions(merge: true));
                    },
                    onSubmitted: (value) => _sendMessage(),
                    decoration: const InputDecoration(
                      hintText: 'Type a message',
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageBubble(Map<String, dynamic> msg, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 260),
        decoration: BoxDecoration(
          color: isMe ? Colors.green.shade200 : Colors.grey.shade300,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              msg['text'] ?? '',
              style: TextStyle(
                  color: isMe ? Colors.black87 : Colors.black87),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(msg['timestamp']),
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe ? Colors.black54 : Colors.black54,
                  ),
                ),
                if (isMe)
                  const SizedBox(width: 4),
                if (isMe)
                  Icon(
                    msg['seen'] == true ? Icons.done_all : Icons.check,
                    size: 14,
                    color: msg['seen'] == true ? Colors.blue : Colors.black54,
                  ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
