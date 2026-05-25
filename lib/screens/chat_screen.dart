// lib/screens/chat_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'transfer_screen.dart';
import '../blockchain/blockchain_service.dart';
import '../services/push_notification_service.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import '../blockchain/ipfs_service.dart';
import 'package:device_info_plus/device_info_plus.dart';

// ─── Brand Colors ─────────────────────────────────────────────────────────────
const kTeal        = Color(0xFF2D7D7D);
const kTealDark    = Color(0xFF1F5C5C);
const kTealLight   = Color(0xFFE8F4F4);
const kTealAccent  = Color(0xFF3AAFA9);
const kScaffoldBg  = Color(0xFFF5F8F8);
const kTextPrimary = Color(0xFF1A2E2E);
const kTextSecondary = Color(0xFF6B8E8E);

// ─── Chat Screen ──────────────────────────────────────────────────────────────
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

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final _auth           = FirebaseAuth.instance;
  final _db             = FirebaseFirestore.instance;
  final _controller     = TextEditingController();
  final _pushService    = PushNotificationService();
  final _scrollCtrl     = ScrollController();
  final _ipfs           = IPFSService();

  bool _isTyping          = false;
  bool _isMarkingMessages = false;
  int  _messageLimit      = 20;

  // Header entrance animation
  late AnimationController _headerCtrl;
  late Animation<double>   _headerFade;

  String get myUid => _auth.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _headerCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..forward();
    _headerFade =
        CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);
    _setOnlineStatus(true);
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    _setOnlineStatus(false);
    _controller.dispose();
    _scrollCtrl.dispose();
    _db.collection('chats').doc(widget.chatId).set(
      {'typing': false},
      SetOptions(merge: true),
    ).catchError((_) {});
    super.dispose();
  }

  // ── File send ────────────────────────────────────────────────────────────
  Future<void> _sendFile() async {
    final result = await FilePicker.platform.pickFiles(
      type             : FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx'],
      withData         : true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null || file.bytes!.isEmpty) {
      _showSnack('File is empty');
      return;
    }
    if (file.bytes!.length > 100 * 1024 * 1024) {
      _showSnack('File too large (max 100MB)');
      return;
    }

    _showSnack('Uploading to IPFS…',
        duration: const Duration(seconds: 60));

    try {
      final uploadResult = await _ipfs.uploadFile(
        fileBytes: file.bytes!,
        fileName : file.name,
      );
      if (!uploadResult.success || uploadResult.ipfsHash == null) {
        throw Exception(uploadResult.error ?? 'IPFS upload failed');
      }

      final isImage  = ['jpg', 'jpeg', 'png']
          .contains(file.extension?.toLowerCase());
      final chatRef  = _db.collection('chats').doc(widget.chatId);

      await chatRef.collection('messages').add({
        'senderId'     : myUid,
        'timestamp'    : FieldValue.serverTimestamp(),
        'seen'         : false,
        'type'         : isImage ? 'image' : 'file',
        'fileName'     : file.name,
        'fileExtension': file.extension ?? '',
        'fileSize'     : file.bytes!.length,
        'ipfsHash'     : uploadResult.ipfsHash,
        'ipfsUrl'      : uploadResult.ipfsUrl,
        'sha256'       : uploadResult.sha256Hash ?? '',
        'text'         : '',
      });

      await chatRef.set({
        'participants'               : [myUid, widget.otherUserId],
        'lastMessage'                : isImage ? '📷 Image' : '📎 ${file.name}',
        'lastMessageTime'            : FieldValue.serverTimestamp(),
        'unread_${widget.otherUserId}': FieldValue.increment(1),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(_snackBar('File sent ✓',
              color: Colors.green,
              duration: const Duration(seconds: 2)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(_snackBar('Upload failed: $e', color: Colors.red));
      }
    }
  }

  // ── File download ─────────────────────────────────────────────────────────
  Future<void> _downloadFile(String ipfsHash, String fileName) async {
    if (ipfsHash.isEmpty) { _showSnack('No file available'); return; }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white)),
          const SizedBox(width: 12),
          Text('Downloading…', style: GoogleFonts.poppins()),
        ]),
        backgroundColor: kTeal,
        behavior       : SnackBarBehavior.floating,
        duration       : const Duration(seconds: 30),
        shape          : RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ));
    }

    try {
      final bytes = await _ipfs.retrieveFile(ipfsHash);
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Could not retrieve file from IPFS');
      }

      if (Platform.isAndroid) {
        final info = await DeviceInfoPlugin().androidInfo;
        if (info.version.sdkInt < 33) {
          final status = await Permission.storage.request();
          if (!status.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                    _snackBar('Storage permission denied',
                        color: Colors.red));
            }
            return;
          }
        }
      }

      final dir = Directory('/storage/emulated/0/Download');
      if (!await dir.exists()) await dir.create(recursive: true);

      String path  = '${dir.path}/$fileName';
      int    count = 1;
      while (await File(path).exists()) {
        final dot   = fileName.lastIndexOf('.');
        final name  = dot != -1 ? fileName.substring(0, dot) : fileName;
        final ext   = dot != -1 ? fileName.substring(dot) : '';
        path = '${dir.path}/${name}_$count$ext';
        count++;
      }
      await File(path).writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(_snackBar('✓ Saved to Downloads',
              color: Colors.green,
              duration: const Duration(seconds: 4)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(_snackBar('Download failed: $e', color: Colors.red));
      }
    }
  }

  // ── Online status ─────────────────────────────────────────────────────────
  void _setOnlineStatus(bool online) async {
    if (_auth.currentUser == null) return;
    try {
      final doc = await _db.collection('users').doc(myUid).get();
      if (doc.data()?['lastSeenEnabled'] == false) return;
      _db.collection('users').doc(myUid).set({
        'online'  : online,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  // ── Send message ──────────────────────────────────────────────────────────
  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    setState(() => _isTyping = false);

    try {
      final chatRef = _db.collection('chats').doc(widget.chatId);
      await chatRef.collection('messages').add({
        'text'     : text,
        'type'     : 'text',
        'senderId' : myUid,
        'timestamp': FieldValue.serverTimestamp(),
        'seen'     : false,
        'status'   : 'sent',
      });
      await chatRef.set({
        'participants'               : [myUid, widget.otherUserId],
        'lastMessage'                : text,
        'lastMessageTime'            : FieldValue.serverTimestamp(),
        'unread_${widget.otherUserId}': FieldValue.increment(1),
        'typing'                     : false,
      }, SetOptions(merge: true));
    } catch (e) {
      if (mounted) _showSnack('Send failed: $e', color: Colors.red);
    }
  }

  // ── Mark seen ─────────────────────────────────────────────────────────────
  Future<void> _markMessagesSeen() async {
    if (_isMarkingMessages) return;
    _isMarkingMessages = true;
    try {
      final msgs = await _db
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .where('seen', isEqualTo: false)
          .get();
      final batch = _db.batch();
      for (var m in msgs.docs) {
        if ((m.data())['senderId'] != myUid) {
          batch.update(m.reference, {'seen': true});
        }
      }
      await batch.commit();
      await _db
          .collection('chats')
          .doc(widget.chatId)
          .update({'unread_$myUid': 0});
    } catch (_) {} finally {
      _isMarkingMessages = false;
    }
  }

  String _formatTime(Timestamp? ts) {
    if (ts == null) return '';
    final d      = ts.toDate();
    final minute = d.minute.toString().padLeft(2, '0');
    final amPm   = d.hour >= 12 ? 'PM' : 'AM';
    int   hour   = d.hour % 12;
    if (hour == 0) hour = 12;
    return '$hour:$minute $amPm';
  }

  // ── Transfer area ─────────────────────────────────────────────────────────
  Widget _buildCheckoutArea(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('chats').doc(widget.chatId).snapshots(),
      builder: (context, chatSnap) {
        if (!chatSnap.hasData || !chatSnap.data!.exists) {
          return const SizedBox();
        }
        final chatData    = chatSnap.data!.data() as Map<String, dynamic>;
        final assetId     = chatData['assetId']    as String?;
        final sellerUid   = chatData['sellerUid']  as String?;
        final assetTypeStr =
            (chatData['assetType'] ?? chatData['category'] ?? 'electronics')
                .toString();
        final chatTxId = (chatData['transactionId'] ?? widget.chatId).toString().trim();

        if (assetId == null || sellerUid == null) return const SizedBox();
        if (myUid != sellerUid) return const SizedBox();

        return StreamBuilder<QuerySnapshot>(
          stream: _db
              .collection('transactions')
              .where('assetId',   isEqualTo: assetId)
              .where('sellerUid', isEqualTo: sellerUid)
              .where('status',    whereIn: ['pending', 'accepted', 'approved'])
              .limit(1)
              .snapshots(),
          builder: (context, txSnap) {
            final txDoc  = txSnap.hasData && txSnap.data!.docs.isNotEmpty
                ? txSnap.data!.docs.first
                : null;
            final txId   = txDoc?.id;
            final txData = txDoc != null
                ? txDoc.data() as Map<String, dynamic>
                : <String, dynamic>{};

            return _buildTransferButton(
                assetId, assetTypeStr, sellerUid, chatTxId, txId, txData);
          },
        );
      },
    );
  }

  Widget _buildTransferButton(
      String assetId,
      String assetTypeStr,
      String sellerUid,
      String chatTransactionId,
      String? transactionId,
      Map<String, dynamic> txData,
      ) {
    return Container(
      margin : const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        gradient    : const LinearGradient(
          colors: [Color(0xFFE65100), Color(0xFFFF8F00)],
          begin : Alignment.topLeft,
          end   : Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow   : [
          BoxShadow(
            color     : Colors.orange.withOpacity(0.3),
            blurRadius: 12,
            offset    : const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color       : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            try {
              String resolvedTxId;
              Map<String, dynamic> resolvedTxData;

              final candidateIds = <String>[
                if (transactionId != null && transactionId.trim().isNotEmpty)
                  transactionId.trim(),
                if (chatTransactionId.isNotEmpty) chatTransactionId,
              ];

              DocumentSnapshot<Map<String, dynamic>>? txSnap;
              for (final candidateId in candidateIds.toSet()) {
                final snap = await _db
                    .collection('transactions')
                    .doc(candidateId)
                    .get();
                if (snap.exists) {
                  txSnap = snap;
                  break;
                }
              }

              if (txSnap == null) {
                final existing = await _db
                    .collection('transactions')
                    .where('assetId', isEqualTo: assetId)
                    .where('sellerUid', isEqualTo: sellerUid)
                    .where('status', whereIn: ['pending', 'accepted', 'approved'])
                    .limit(10)
                    .get();
                for (final doc in existing.docs) {
                  final data = doc.data();
                  if (data['buyerUid'] == widget.otherUserId) {
                    txSnap = doc;
                    break;
                  }
                }
              }

              if (txSnap != null) {
                resolvedTxId = txSnap.id;
                resolvedTxData = txSnap.data() ?? <String, dynamic>{};
              } else {
                final assetSnap  = await _db.collection('assets').doc(assetId).get();
                final assetTitle = assetSnap.data()?['title'] ?? 'Asset';
                final docRef     = await _db.collection('transactions').add({
                  'transactionId': '',
                  'assetId'  : assetId,
                  'assetType': assetTypeStr,
                  'sellerUid': sellerUid,
                  'buyerUid' : widget.otherUserId,
                  'status'   : 'approved',
                  'assetTitle': assetTitle,
                  'category': assetTypeStr,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                await docRef.update({'transactionId': docRef.id});
                resolvedTxId   = docRef.id;
                resolvedTxData = {};
              }
              if (mounted) {
                _navigateToTransferScreen(
                    context, assetId, assetTypeStr,
                    sellerUid, resolvedTxId, resolvedTxData);
              }
            } catch (e) {
              if (mounted) _showSnack('Error: $e', color: Colors.red);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.swap_horiz_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(
                  'Proceed to Transfer',
                  style: GoogleFonts.poppins(
                    color     : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize  : 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToTransferScreen(
      BuildContext context,
      String assetId,
      String assetType,
      String sellerUid,
      String transactionId,
      Map<String, dynamic> txData,
      ) async {
    try {
      final assetSnap = await _db.collection('assets').doc(assetId).get();
      if (!assetSnap.exists) {
        if (mounted) _showSnack('Asset not found', color: Colors.red);
        return;
      }
      final assetData = assetSnap.data() as Map<String, dynamic>;
      final tokenId   = assetData['blockchainTokenId'] as int?;
      final price     = assetData['price'];

      int? resolvedFractionAmount;
      if (assetType == 'land' && tokenId != null) {
        try {
          final bs = BlockchainServiceEnhanced();
          await bs.init();
          if (bs.isConnected && bs.connectedAddress != null) {
            resolvedFractionAmount =
            await bs.getUserFractions(bs.connectedAddress!, tokenId);
          }
        } catch (_) {
          resolvedFractionAmount = assetData['totalFractions'] as int?;
        }
      }

      final buyerSnap = await _db
          .collection('users')
          .doc(widget.otherUserId)
          .get();
      final buyerName = buyerSnap.data()?['name'] ?? 'the buyer';

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TransferScreen(
            assetId      : assetId,
            assetType    : assetType == 'electronics'
                ? AssetType.electronics
                : AssetType.land,
            transactionId: transactionId,
            buyerUid     : widget.otherUserId,
            sellerUid    : sellerUid,
            tokenId      : assetType == 'electronics' ? tokenId : null,
            propertyId   : assetType == 'land' ? tokenId : null,
            fractionAmount: assetType == 'land' ? resolvedFractionAmount : null,
            assetPrice   : price?.toString() ?? '0',
            buyerName    : buyerName,
          ),
        ),
      );
    } catch (e) {
      if (mounted) _showSnack('Error: $e', color: Colors.red);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _showSnack(String msg,
      {Color? color, Duration duration = const Duration(seconds: 3)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      _snackBar(msg, color: color, duration: duration),
    );
  }

  SnackBar _snackBar(String msg,
      {Color? color, Duration duration = const Duration(seconds: 3)}) {
    return SnackBar(
      content        : Text(msg, style: GoogleFonts.poppins()),
      backgroundColor: color ?? kTeal,
      behavior       : SnackBarBehavior.floating,
      shape          : RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
      duration       : duration,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kScaffoldBg,
      appBar          : _buildAppBar(),
      body            : Column(
        children: [
          // Messages
          Expanded(child: _buildMessageList()),

          // Typing indicator
          _buildTypingIndicator(),

          // Transfer button
          _buildCheckoutArea(context),

          // Input bar
          _buildInputBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: kTeal,
      elevation      : 0,
      flexibleSpace  : Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kTealDark, kTeal],
            begin : Alignment.topLeft,
            end   : Alignment.bottomRight,
          ),
        ),
      ),
      leading: IconButton(
        icon    : Container(
          padding   : const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color       : Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 16),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: FadeTransition(
        opacity: _headerFade,
        child  : StreamBuilder<DocumentSnapshot>(
          stream : _db
              .collection('users')
              .doc(widget.otherUserId)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return Text('Chat',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w700, color: Colors.white));
            }
            final u               = snap.data!.data() as Map<String, dynamic>? ?? {};
            final online          = u['online'] == true;
            final lastSeenEnabled = u['lastSeenEnabled'] ?? true;
            final photoBase64     = u['photoBase64'] as String?;

            String subtitle;
            if (online) {
              subtitle = 'Online';
            } else if (lastSeenEnabled) {
              final ts = u['lastSeen'] as Timestamp?;
              subtitle = ts != null
                  ? 'last seen ${_formatTime(ts)}'
                  : 'Offline';
            } else {
              subtitle = 'last seen recently';
            }

            return Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius         : 20,
                      backgroundColor: Colors.white.withOpacity(0.3),
                      backgroundImage: photoBase64 != null &&
                          photoBase64.isNotEmpty
                          ? null
                          : null,
                      child: photoBase64 == null || photoBase64.isEmpty
                          ? Text(
                        (u['name'] as String? ?? 'U')[0].toUpperCase(),
                        style: GoogleFonts.poppins(
                            color     : Colors.white,
                            fontWeight: FontWeight.w700),
                      )
                          : null,
                    ),
                    if (online)
                      Positioned(
                        bottom: 0,
                        right : 0,
                        child : Container(
                          width : 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color : Colors.green,
                            shape : BoxShape.circle,
                            border: Border.all(color: kTeal, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u['name'] ?? 'User',
                      style: GoogleFonts.poppins(
                        fontSize  : 15,
                        fontWeight: FontWeight.w700,
                        color     : Colors.white,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color   : online
                            ? Colors.greenAccent.shade100
                            : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(_messageLimit)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasData && snap.data!.docs.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 500),
              _markMessagesSeen);
        }
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: kTeal));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding   : const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: kTealLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chat_bubble_outline_rounded,
                      size: 42, color: kTeal),
                ),
                const SizedBox(height: 16),
                Text('Say hello 👋',
                    style: GoogleFonts.poppins(
                      fontSize  : 16,
                      fontWeight: FontWeight.w600,
                      color     : kTextPrimary,
                    )),
                const SizedBox(height: 6),
                Text('Start the conversation',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: kTextSecondary)),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _scrollCtrl,
          reverse   : true,
          padding   : const EdgeInsets.symmetric(vertical: 12),
          itemCount : docs.length + 1,
          itemBuilder: (context, i) {
            if (i == docs.length) {
              return Center(
                child: TextButton(
                  onPressed: () =>
                      setState(() => _messageLimit += 20),
                  child: Text('Load earlier messages',
                      style: GoogleFonts.poppins(
                          color: kTeal, fontWeight: FontWeight.w600)),
                ),
              );
            }
            final msg  = docs[i].data() as Map<String, dynamic>;
            final isMe = msg['senderId'] == myUid;
            return _AnimatedBubble(
              index: i,
              child: _messageBubble(msg, isMe),
            );
          },
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return StreamBuilder<DocumentSnapshot>(
      stream : _db.collection('chats').doc(widget.chatId).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) return const SizedBox();
        final data      = snap.data!.data() as Map<String, dynamic>;
        final typing    = data['typing'] == true;
        if (!typing) return const SizedBox();
        return Padding(
          padding: const EdgeInsets.only(left: 18, bottom: 6),
          child  : Row(
            children: [
              _TypingDots(),
              const SizedBox(width: 8),
              Text('typing…',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: kTextSecondary)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputBar() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('chats').doc(widget.chatId).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final isLocked = data?['isLocked'] == true;

        if (isLocked) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              border: Border(top: BorderSide(color: Colors.orange.shade100)),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_clock_rounded, size: 18, color: Colors.orange.shade800),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Chat is locked until the owner approves the request.',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: kTeal.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Attach button
                GestureDetector(
                  onTap: _sendFile,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kTealLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.attach_file_rounded,
                        color: kTeal, size: 20),
                  ),
                ),
                const SizedBox(width: 8),

                // Text field
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: kScaffoldBg,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: kTeal.withOpacity(0.15)),
                    ),
                    child: TextField(
                      controller: _controller,
                      style: GoogleFonts.poppins(fontSize: 14, color: kTextPrimary),
                      onChanged: (val) {
                        _db.collection('chats').doc(widget.chatId).set(
                          {'typing': val.isNotEmpty},
                          SetOptions(merge: true),
                        );
                      },
                      onSubmitted: (_) => _sendMessage(),
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        hintText: 'Type a message…',
                        hintStyle: GoogleFonts.poppins(color: kTextSecondary, fontSize: 14),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Send button
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    padding: const EdgeInsets.all(11),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [kTealDark, kTealAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x442D7D7D),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Message Bubble ────────────────────────────────────────────────────────
  Widget _messageBubble(Map<String, dynamic> msg, bool isMe) {
    final type = msg['type'] ?? 'text';
    Widget content;

    if (type == 'image') {
      final ipfsUrl = msg['ipfsUrl'] ?? '';
      content = GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (_) => Dialog(
            backgroundColor: Colors.black87,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                child: Image.network(
                  ipfsUrl,
                  loadingBuilder: (_, child, p) => p == null
                      ? child
                      : const Center(
                      child: CircularProgressIndicator(color: kTeal)),
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(32),
                    child  : Icon(Icons.broken_image_rounded,
                        color: Colors.white70, size: 60),
                  ),
                ),
              ),
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            ipfsUrl,
            width : 200,
            height: 200,
            fit   : BoxFit.cover,
            loadingBuilder: (_, child, p) => p == null
                ? child
                : Container(
              width: 200, height: 200,
              color: kTealLight,
              child: const Center(
                  child: CircularProgressIndicator(color: kTeal)),
            ),
            errorBuilder: (_, __, ___) => Container(
              width : 200,
              height: 200,
              color : kTealLight,
              child : const Icon(Icons.broken_image_rounded,
                  color: kTeal, size: 40),
            ),
          ),
        ),
      );
    } else if (type == 'file') {
      final ipfsHash = msg['ipfsHash'] ?? '';
      final fileName = msg['fileName'] ?? 'file';
      final fileSize = msg['fileSize'] as int?;
      final sizeText = fileSize != null
          ? fileSize < 1048576
          ? '${(fileSize / 1024).toStringAsFixed(1)} KB'
          : '${(fileSize / 1048576).toStringAsFixed(1)} MB'
          : '';

      content = GestureDetector(
        onTap: () => ipfsHash.isNotEmpty
            ? _downloadFile(ipfsHash, fileName)
            : _showSnack('File not available'),
        child: Container(
          padding   : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color       : Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children    : [
              Container(
                padding   : const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color       : Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_fileIcon(msg['fileExtension'] ?? ''),
                    color: isMe ? Colors.white : kTeal, size: 22),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize  : 13,
                        color     : isMe ? Colors.white : kTextPrimary,
                        decoration: TextDecoration.underline,
                        decorationColor:
                        isMe ? Colors.white : kTextPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      sizeText.isNotEmpty
                          ? '$sizeText · Tap to download'
                          : 'Tap to download',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color   : isMe
                            ? Colors.white70
                            : kTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.download_rounded,
                  size : 18,
                  color: isMe ? Colors.white70 : kTeal),
            ],
          ),
        ),
      );
    } else {
      content = Text(
        msg['text'] ?? '',
        style: GoogleFonts.poppins(
          fontSize: 14,
          color   : isMe ? Colors.white : kTextPrimary,
          height  : 1.4,
        ),
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child    : Container(
        margin     : EdgeInsets.only(
          left  : isMe ? 60 : 14,
          right : isMe ? 14 : 60,
          bottom: 4,
        ),
        padding    : const EdgeInsets.all(12),
        decoration : BoxDecoration(
          gradient: isMe
              ? const LinearGradient(
            colors: [kTealDark, kTealAccent],
            begin : Alignment.topLeft,
            end   : Alignment.bottomRight,
          )
              : null,
          color        : isMe ? null : Colors.white,
          borderRadius : BorderRadius.only(
            topLeft    : const Radius.circular(16),
            topRight   : const Radius.circular(16),
            bottomLeft : Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color     : kTeal.withOpacity(0.08),
              blurRadius: 8,
              offset    : const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            content,
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children    : [
                Text(
                  _formatTime(msg['timestamp']),
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    color   : isMe
                        ? Colors.white60
                        : kTextSecondary,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    msg['seen'] == true
                        ? Icons.done_all_rounded
                        : Icons.check_rounded,
                    size : 14,
                    color: msg['seen'] == true
                        ? Colors.lightBlueAccent
                        : Colors.white60,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _fileIcon(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }
}

// ─── Animated bubble wrapper ──────────────────────────────────────────────────
class _AnimatedBubble extends StatefulWidget {
  final Widget child;
  final int    index;
  const _AnimatedBubble({required this.child, required this.index});

  @override
  State<_AnimatedBubble> createState() => _AnimatedBubbleState();
}

class _AnimatedBubbleState extends State<_AnimatedBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _fade;
  late Animation<Offset>   _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300))
      ..forward();
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
        begin: const Offset(0, 0.1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity : _fade,
    child   : SlideTransition(position: _slide, child: widget.child),
  );
}

// ─── Typing dots animation ────────────────────────────────────────────────────
class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder  : (_, __) {
        return Row(
          children: List.generate(3, (i) {
            final delay  = i / 3;
            final t      = ((_ctrl.value - delay) % 1.0).abs();
            final opacity= (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.3, 1.0);
            return Container(
              margin   : const EdgeInsets.symmetric(horizontal: 2),
              width    : 6,
              height   : 6,
              decoration: BoxDecoration(
                color: kTeal.withOpacity(opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
