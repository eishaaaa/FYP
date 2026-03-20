import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'transfer_screen.dart';
import '../blockchain/blockchain_service.dart';
import '../blockchain/wallet_service.dart'; // Ensure you have this for buyer wallet connect
import '../services/push_notification_service.dart';

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
  final _pushService = PushNotificationService();
  bool _isTyping = false;

  String get myUid => _auth.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _setOnlineStatus(true);
    _markMessagesSeen();
  }

  @override
  void dispose() {
    _setOnlineStatus(false);
    _controller.dispose();
    super.dispose();
  }

  void _setOnlineStatus(bool online) {
    if (_auth.currentUser == null) return;
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
      'unread_${widget.otherUserId}': FieldValue.increment(1),
    }, SetOptions(merge: true));

    await chatRef.update({'typing': false});
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
      'unread_$myUid': 0,
    });
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final minute = d.minute.toString().padLeft(2, '0');
    final amPm = d.hour >= 12 ? 'PM' : 'AM';
    int hour = d.hour % 12;
    if (hour == 0) hour = 12;
    return '${d.day}/${d.month}/${d.year} at $hour:$minute $amPm';
  }

  // ----------------------------------------------------------------------
  // 🟢 CHECKOUT FLOW LOGIC
  // ----------------------------------------------------------------------

  /// Main widget to handle the Checkout UI area
  Widget _buildCheckoutArea(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('chats').doc(widget.chatId).snapshots(),
      builder: (context, chatSnap) {
        if (!chatSnap.hasData || !chatSnap.data!.exists) return const SizedBox();

        final chatData = chatSnap.data!.data() as Map<String, dynamic>;
        final assetId = chatData['assetId'] as String?;
        final sellerUid = chatData['sellerUid'] as String?;
        final assetTypeStr = chatData['assetType'] as String? ?? 'electronics';

        if (assetId == null || sellerUid == null) return const SizedBox();

        final isSeller = (myUid == sellerUid);

        // Listen to the specific transaction for this asset/users
        return StreamBuilder<QuerySnapshot>(
          stream: _db
              .collection('transactions')
              .where('assetId', isEqualTo: assetId)
              .where('sellerUid', isEqualTo: sellerUid)
              .where('status', whereIn: ['pending', 'accepted', 'approved'])
              .limit(1)
              .snapshots(),
          builder: (context, txSnap) {

            // State 1: No Transaction Started
            if (!txSnap.hasData || txSnap.data!.docs.isEmpty) {
              if (isSeller) {
                return _buildStartCheckoutButton(assetId, assetTypeStr, sellerUid);
              } else {
                return const SizedBox(); // Buyer sees nothing until started
              }
            }

            final txDoc = txSnap.data!.docs.first;
            final txData = txDoc.data() as Map<String, dynamic>;
            final status = txData['status'] as String? ?? 'pending';
            final transactionId = txDoc.id;

            // State 2: Transaction Pending (Buyer needs to Accept/Reject)
            if (status == 'pending') {
              if (isSeller) {
                return _buildStatusCard(
                  'Waiting for Buyer...',
                  'Request sent. Waiting for buyer to accept.',
                  Colors.orange.shade100,
                  Icons.hourglass_empty,
                );
              } else {
                // Buyer View: Accept/Reject
                return _buildBuyerDecisionCard(transactionId, assetTypeStr, sellerUid);
              }
            }

            // State 3: Transaction Accepted (Seller can now Transfer)
            if (status == 'accepted' || status == 'approved') {
              if (isSeller) {
                return _buildSellerTransferButton(
                  context,
                  assetId,
                  assetTypeStr,
                  sellerUid,
                  transactionId,
                  txData,
                );
              } else {
                return _buildStatusCard(
                  'Checkout Accepted',
                  'Waiting for supplier to transfer ownership.',
                  Colors.green.shade100,
                  Icons.check_circle,
                );
              }
            }

            return const SizedBox();
          },
        );
      },
    );
  }

  /// 1️⃣ Supplier: Start Checkout Button
  Widget _buildStartCheckoutButton(String assetId, String assetType, String sellerUid) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.shopping_cart_checkout),
          label: const Text('Proceed to Checkout'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onPressed: () => _initiateCheckout(assetId, assetType, sellerUid),
        ),
      ),
    );
  }

  /// 🟡 Buyer: Decision Card (Accept/Reject)
  Widget _buildBuyerDecisionCard(String txId, String assetType, String sellerUid) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.orange),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Checkout Request',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text('The supplier wants to checkout this product. Do you accept?'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _handleBuyerDecision(txId, sellerUid, false),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _handleBuyerDecision(txId, sellerUid, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 🚀 Seller: Transfer Button (Active only after Buyer Accepts)
  Widget _buildSellerTransferButton(
      BuildContext context,
      String assetId,
      String assetTypeStr,
      String sellerUid,
      String transactionId,
      Map<String, dynamic> txData,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green),
            ),
            child: const Row(
              children: [
                Icon(Icons.check, size: 16, color: Colors.green),
                SizedBox(width: 8),
                Expanded(child: Text('Buyer accepted. Ready to transfer.')),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Proceed to Transfer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () {
                _navigateToTransferScreen(
                  context,
                  assetId,
                  assetTypeStr,
                  sellerUid,
                  transactionId,
                  txData,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Generic Status Card
  Widget _buildStatusCard(String title, String subtitle, Color bgColor, IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.black54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(subtitle, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------------
  // ⚙️ LOGIC METHODS
  // ----------------------------------------------------------------------

  Future<void> _initiateCheckout(String assetId, String assetType, String sellerUid) async {
    // Check if tx exists
    final q = await _db.collection('transactions')
        .where('assetId', isEqualTo: assetId)
        .where('sellerUid', isEqualTo: sellerUid)
        .where('status', isNotEqualTo: 'rejected')
        .limit(1).get();

    String txId;
    if (q.docs.isNotEmpty) {
      txId = q.docs.first.id;
      // Reset to pending if it was stuck
      await _db.collection('transactions').doc(txId).update({'status': 'pending'});
    } else {
      // Create new
      final docRef = await _db.collection('transactions').add({
        'assetId': assetId,
        'assetType': assetType,
        'sellerUid': sellerUid,
        'buyerUid': widget.otherUserId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      txId = docRef.id;
    }

    // Notify Buyer
    _sendNotification(
      uid: widget.otherUserId,
      title: 'Checkout Request',
      body: 'Supplier wants to checkout this product.',
      txId: txId,
    );

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request sent to buyer')));
  }

  Future<void> _handleBuyerDecision(String txId, String sellerUid, bool accepted) async {
    if (accepted) {
      // 1. Update Status
      await _db.collection('transactions').doc(txId).update({'status': 'accepted'});

      // 2. Notify Supplier
      _sendNotification(
        uid: sellerUid,
        title: 'Checkout Accepted',
        body: 'Buyer accepted. Please proceed to transfer.',
        txId: txId,
      );

      // 3. Connect Wallet Flow (For Buyer)
      if (mounted) {
        _promptWalletConnection();
      }

    } else {
      // Reject
      await _db.collection('transactions').doc(txId).update({'status': 'rejected'});
      _sendNotification(
        uid: sellerUid,
        title: 'Checkout Rejected',
        body: 'Buyer rejected the checkout process.',
        txId: txId,
      );
    }
  }

  Future<void> _promptWalletConnection() async {
    // Show Dialog
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect Wallet'),
        content: const Text('To proceed with the purchase, please connect your crypto wallet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Connect')),
        ],
      ),
    );

    if (proceed == true) {
      final walletService = SimpleWalletService();
      final address = await walletService.connect(context);

      if (address != null) {
        // Save buyer wallet
        await _db.collection('users').doc(myUid).update({'walletAddress': address});
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connected: ${address.substring(0,6)}...')));
        }
      }
    }
  }

  Future<void> _sendNotification({
    required String uid,
    required String title,
    required String body,
    required String txId,
  }) async {
    final userDoc = await _db.collection('users').doc(uid).get();
    final token = userDoc.data()?['fcmToken'];
    if (token != null) {
      await _pushService.sendPushMessage(
        token: token,
        title: title,
        body: body,
        data: {'transactionId': txId},
      );
    }
  }

  void _navigateToTransferScreen(
      BuildContext context,
      String assetId,
      String assetType,
      String sellerUid,
      String transactionId,
      Map<String, dynamic> txData,
      ) {
    // Get Blockchain Token ID/Property ID from transaction data or fetch asset
    // Assuming txData might have it, or we pass it from Asset Details.
    // Ideally, fetching asset doc here is safer.
    _db.collection('assets').doc(assetId).get().then((assetSnap) {
      if(!assetSnap.exists) return;
      final assetData = assetSnap.data() as Map<String, dynamic>;
      final tokenId = assetData['blockchainTokenId'];

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TransferScreen(
            assetId: assetId,
            assetType: assetType == 'electronics' ? AssetType.electronics : AssetType.land,
            transactionId: transactionId,
            buyerUid: widget.otherUserId, // Buyer is the "other" one for Seller
            sellerUid: sellerUid,
            tokenId: assetType == 'electronics' ? tokenId : null,
            propertyId: assetType == 'land' ? tokenId : null,
            fractionAmount: null, // Logic for fractional amount if needed
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<DocumentSnapshot>(
          stream: _db.collection('users').doc(widget.otherUserId).snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Text('Chat');
            if (!snap.data!.exists) return const Text('User');
            final u = snap.data!.data() as Map<String, dynamic>;
            final online = u['online'] == true;
            return Row(
              children: [
                CircleAvatar(backgroundImage: u['photoUrl'] != null ? NetworkImage(u['photoUrl']) : null, child: u['photoUrl'] == null ? const Icon(Icons.person) : null),
                const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(u['name'] ?? 'User'), Text(online ? 'online' : 'last seen ${_formatTime(u['lastSeen'])}', style: const TextStyle(fontSize: 12))]),
              ],
            );
          },
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db.collection('chats').doc(widget.chatId).collection('messages').orderBy('timestamp', descending: true).snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs;
                if (docs.isEmpty) return const Center(child: Text('Say hello 👋'));
                return ListView.builder(
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final msg = docs[i].data() as Map<String, dynamic>;
                    return _messageBubble(msg, msg['senderId'] == myUid);
                  },
                );
              },
            ),
          ),
          if (_isTyping) const Padding(padding: EdgeInsets.only(left: 12, bottom: 4), child: Align(alignment: Alignment.centerLeft, child: Text('typing...'))),

          // 🟢 CHECKOUT UI AREA
          _buildCheckoutArea(context),

          SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onChanged: (val) => _db.collection('chats').doc(widget.chatId).set({'typing': val.isNotEmpty}, SetOptions(merge: true)),
                    onSubmitted: (_) => _sendMessage(),
                    decoration: const InputDecoration(hintText: 'Type a message', contentPadding: EdgeInsets.all(12)),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send), onPressed: _sendMessage),
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
        decoration: BoxDecoration(color: isMe ? Colors.green.shade200 : Colors.grey.shade300, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          Text(msg['text'] ?? '', style: const TextStyle(color: Colors.black87)),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_formatTime(msg['timestamp']), style: const TextStyle(fontSize: 10, color: Colors.black54)),
            if (isMe) ...[const SizedBox(width: 4), Icon(msg['seen'] == true ? Icons.done_all : Icons.check, size: 14, color: msg['seen'] == true ? Colors.blue : Colors.black54)],
          ])
        ]),
      ),
    );
  }
}