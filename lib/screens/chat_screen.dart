import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'transfer_screen.dart';
import '../blockchain/blockchain_service.dart';
import '../blockchain/wallet_service.dart';
import '../services/push_notification_service.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import '../blockchain/ipfs_service.dart';
import 'package:device_info_plus/device_info_plus.dart';


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
  final _scrollController = ScrollController();
  final _ipfs = IPFSService();
  bool _isTyping = false;
  bool _isMarkingMessages = false; // Prevent concurrent marking
  int _messageLimit = 20; // Pagination

  String get myUid => _auth.currentUser!.uid;


  @override
  void initState() {
    super.initState();
    _setOnlineStatus(true);
    // Don't call _markMessagesSeen() here - do it with debounce instead
  }

  @override
  void dispose() {
    _setOnlineStatus(false);
    _controller.dispose();
    _scrollController.dispose();
    _db.collection('chats').doc(widget.chatId).set(
      {'typing': false},
      SetOptions(merge: true),
    ).catchError((_) {}); // Ignore errors on dispose
    super.dispose();
  }

  // In _sendFile() method
  Future<void> _sendFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null || file.bytes!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File is empty')),
        );
      }
      return;
    }

    // 100MB max (IPFS handles large files, not Firestore)
    const int maxFileSize = 100 * 1024 * 1024;
    if (file.bytes!.length > maxFileSize) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File too large (max 100MB)')),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Uploading to IPFS...'), duration: Duration(seconds: 60)),
      );
    }

    try {
      // ✅ Upload to IPFS via Pinata
      final uploadResult = await _ipfs.uploadFile(
        fileBytes: file.bytes!,
        fileName: file.name,
      );

      if (!uploadResult.success || uploadResult.ipfsHash == null) {
        throw Exception(uploadResult.error ?? 'IPFS upload failed');
      }

      final isImage = ['jpg', 'jpeg', 'png'].contains(file.extension?.toLowerCase());
      final chatRef = _db.collection('chats').doc(widget.chatId);

      // ✅ Only store IPFS hash in Firestore — NOT the file bytes
      await chatRef.collection('messages').add({
        'senderId': myUid,
        'timestamp': FieldValue.serverTimestamp(),
        'seen': false,
        'type': isImage ? 'image' : 'file',
        'fileName': file.name,
        'fileExtension': file.extension ?? '',
        'fileSize': file.bytes!.length,
        'ipfsHash': uploadResult.ipfsHash,       // ✅ IPFS hash
        'ipfsUrl': uploadResult.ipfsUrl,         // ✅ IPFS URL
        'sha256': uploadResult.sha256Hash ?? '', // ✅ integrity check
        'text': '',
      });

      await chatRef.set({
        'participants': [myUid, widget.otherUserId],
        'lastMessage': isImage ? '📷 Image' : '📎 ${file.name}',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unread_${widget.otherUserId}': FieldValue.increment(1),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: Text('File sent ✓'),
            duration: Duration(seconds: 2),
          ));
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
      debugPrint('File send error: $e');
    }
  }

  Future<void> _downloadFile(String ipfsHash, String fileName) async {
    try {
      if (ipfsHash.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No file available')),
          );
        }
        return;
      }

      // Show downloading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                SizedBox(width: 12),
                Text('Downloading...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }

      // ✅ Fetch from IPFS
      final bytes = await _ipfs.retrieveFile(ipfsHash);
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Could not retrieve file from IPFS');
      }

      // ✅ Handle permissions based on Android version
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt < 33) {
          // Android 12 and below need storage permission
          final status = await Permission.storage.request();
          if (!status.isGranted) {
            if (mounted) {
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(const SnackBar(content: Text('Storage permission denied')));
            }
            return;
          }
        }
        // Android 13+ doesn't need permission for Downloads folder
      }

      // ✅ Save to public Downloads folder
      final downloadsDir = Directory('/storage/emulated/0/Download');
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }

      // ✅ Handle duplicate filenames
      String filePath = '${downloadsDir.path}/$fileName';
      int counter = 1;
      while (await File(filePath).exists()) {
        final dotIndex = fileName.lastIndexOf('.');
        final nameWithoutExt = dotIndex != -1 ? fileName.substring(0, dotIndex) : fileName;
        final ext = dotIndex != -1 ? fileName.substring(dotIndex) : '';
        filePath = '${downloadsDir.path}/${nameWithoutExt}_$counter$ext';
        counter++;
      }

      // ✅ Write to Downloads
      await File(filePath).writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('✓ Saved to Downloads: $filePath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ));
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.red,
          ));
      }
      debugPrint('Download error: $e');
    }
  }

  void _setOnlineStatus(bool online) async {
    if (_auth.currentUser == null) return;

    try {
      final userDoc = await _db.collection('users').doc(myUid).get();
      final lastSeenEnabled = userDoc.data()?['lastSeenEnabled'] ?? true;

      if (!lastSeenEnabled) return;

      _db.collection('users').doc(myUid).set(
        {
          'online': online,
          'lastSeen': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Online status error: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    setState(() => _isTyping = false);

    try {
      final chatRef = _db.collection('chats').doc(widget.chatId);

      await chatRef.collection('messages').add({
        'text': text,
        'type': 'text',
        'senderId': myUid,
        'timestamp': FieldValue.serverTimestamp(),
        'seen': false,
        'status': 'sent',
      });

      await chatRef.set({
        'participants': [myUid, widget.otherUserId],
        'lastMessage': text,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'unread_${widget.otherUserId}': FieldValue.increment(1),
        'typing': false,
      }, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Send failed: $e')),
        );
      }
      debugPrint('Send message error: $e');
    }
  }

  //  Debounced marking with flag to prevent concurrent operations
  Future<void> _markMessagesSeen() async {
    if (_isMarkingMessages) return;
    _isMarkingMessages = true;

    try {
      // ✅ Only filter by 'seen' — no compound query, no index needed
      final msgs = await _db
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .where('seen', isEqualTo: false)
          .get();

      final batch = _db.batch();
      for (var m in msgs.docs) {
        final senderId = (m.data())['senderId'];
        // ✅ Filter out my own messages in code, not in query
        if (senderId != myUid) {
          batch.update(m.reference, {'seen': true});
        }
      }
      await batch.commit();

      await _db.collection('chats').doc(widget.chatId).update({
        'unread_$myUid': 0,
      });
    } catch (e) {
      debugPrint('Mark seen error: $e');
    } finally {
      _isMarkingMessages = false;
    }
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


  // ── CHECKOUT FLOW LOGIC ──
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
        // isResale = true when the seller is not the original minter but a buyer
        // who received the asset via transfer and is now reselling it.
        // We detect this by checking if the asset's previousOwnerId is set,
        // which _finalizeOwnership writes on every transfer.
        final isResale = chatData['isResale'] == true ||
            (chatData['previousOwnerId'] != null &&
                (chatData['previousOwnerId'] as String).isNotEmpty);
        final sellerLabel = isResale ? 'Seller' : 'Supplier';

        return StreamBuilder<QuerySnapshot>(
          stream: _db
              .collection('transactions')
              .where('assetId', isEqualTo: assetId)
              .where('sellerUid', isEqualTo: sellerUid)
              .where('status', whereIn: ['pending', 'accepted', 'approved'])
              .limit(1)
              .snapshots(),
          builder: (context, txSnap) {
            if (!txSnap.hasData || txSnap.data!.docs.isEmpty) {
              if (isSeller) {
                return _buildStartCheckoutButton(assetId, assetTypeStr, sellerUid);
              } else {
                return const SizedBox();
              }
            }

            final txDoc = txSnap.data!.docs.first;
            final txData = txDoc.data() as Map<String, dynamic>;
            final status = txData['status'] as String? ?? 'pending';
            final transactionId = txDoc.id;

            if (status == 'pending') {
              if (isSeller) {
                return _buildStatusCard(
                  'Waiting for Buyer...',
                  'Request sent. Waiting for buyer to accept.',
                  Colors.orange.shade100,
                  Icons.hourglass_empty,
                );
              } else {
                return _buildBuyerDecisionCard(transactionId, assetTypeStr, sellerUid, sellerLabel);
              }
            }

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
                return const SizedBox();
              }
            }

            return const SizedBox();
          },
        );
      },
    );
  }

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

  Widget _buildBuyerDecisionCard(String txId, String assetType, String sellerUid, String sellerLabel) {
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
          Text('The $sellerLabel wants to proceed with checkout. Do you accept?'),
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
      child: SizedBox(
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
    );
  }

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

  // ── LOGIC METHODS ──

  Future<void> _initiateCheckout(String assetId, String assetType, String sellerUid) async {
    try {
      final q = await _db.collection('transactions')
          .where('assetId', isEqualTo: assetId)
          .where('sellerUid', isEqualTo: sellerUid)
          .where('status', isNotEqualTo: 'rejected')
          .limit(1).get();

      String txId;
      if (q.docs.isNotEmpty) {
        txId = q.docs.first.id;
        await _db.collection('transactions').doc(txId).update({'status': 'pending'});
      } else {
        final docRef = await _db.collection('transactions').add({
          'assetId': assetId,
          'assetType': assetType,
          'sellerUid': sellerUid,
          'buyerUid': widget.otherUserId,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          // ✅ Fetch and save asset title
        });
        txId = docRef.id;

//      ✅ Save assetTitle separately after creation
        final assetSnap = await _db.collection('assets').doc(assetId).get();
        final assetTitle = assetSnap.data()?['title'] ?? 'Asset';
        await _db.collection('transactions').doc(txId).update({
          'assetTitle': assetTitle,
        });

        _sendNotification(
          uid: widget.otherUserId,
          title: 'Checkout Request',
          body: 'The seller wants to proceed with checkout.',
          txId: txId,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Request sent to buyer')),
          );
        }
      }
    }catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      debugPrint('Checkout error: $e');
    }
  }
  Future<void> _handleBuyerDecision(String txId, String sellerUid, bool accepted) async {
    try {
      if (accepted) {
        await _db.collection('transactions').doc(txId).update({
          'status': 'accepted',
          'acceptedAt': FieldValue.serverTimestamp(),
        });

        _sendNotification(
          uid: sellerUid,
          title: 'Checkout Accepted',
          body: 'Buyer accepted. Please proceed to transfer.',
          txId: txId,
        );

        if (mounted) {
          // ✅ Check if buyer wallet already connected
          await _checkAndConnectWallet();
        }
      } else {
        await _db.collection('transactions').doc(txId).update({
          'status': 'rejected',
          'rejectedAt': FieldValue.serverTimestamp(),
        });
        _sendNotification(
          uid: sellerUid,
          title: 'Checkout Rejected',
          body: 'Buyer rejected the checkout.',
          txId: txId,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You rejected the checkout')),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _checkAndConnectWallet() async {
    // ✅ Check if buyer already has a wallet saved
    final userDoc = await _db.collection('users').doc(myUid).get();
    final existingWallet = userDoc.data()?['walletAddress'] as String?;

    if (existingWallet != null && existingWallet.isNotEmpty) {
      // ✅ Already connected — show confirmation and proceed
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.account_balance_wallet, color: Colors.green),
                SizedBox(width: 8),
                Text('Wallet Ready'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Your wallet is already connected:'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${existingWallet.substring(0, 6)}...${existingWallet.substring(existingWallet.length - 4)}',
                    style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Waiting for supplier to proceed with transfer.', style: TextStyle(fontSize: 13)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
    } else {
      // ✅ No wallet — prompt to connect
      await _promptWalletConnection();
    }
  }

  Future<void> _promptWalletConnection() async {
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Connect Wallet'),
        content: const Text(
          'To receive the asset, you need to connect your crypto wallet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Connect Wallet'),
          ),
        ],
      ),
    );

    if (proceed == true && mounted) {
      try {
        final walletService = SimpleWalletService();
        final address = await walletService.connect(context);

        if (address != null && mounted) {
          await _db.collection('users').doc(myUid).update({'walletAddress': address});
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Wallet connected: ${address.substring(0, 6)}...'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Wallet connection failed: $e')),
        );
      }
    }
  }

  Future<void> _sendNotification({
    required String uid,
    required String title,
    required String body,
    required String txId,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'receiverId': uid,
        'title': title,
        'body': body,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      debugPrint('Notification error: $e');
    }
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
      // ✅ Fetch asset data
      final assetSnap = await _db.collection('assets').doc(assetId).get();
      if (!assetSnap.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Asset not found')),
          );
        }
        return;
      }

      final assetData = assetSnap.data() as Map<String, dynamic>;
      final tokenId = assetData['blockchainTokenId'] as int?;
      final price = assetData['price'];  // ✅ for payment

      // ── Resolve land fraction amount ──────────────────────────────────────
      // For the ORIGINAL supplier totalFractions == their balance (they minted
      // everything).  For a RESELLER the minted supply is irrelevant — they may
      // only hold a subset.  Always ask the chain for the seller's real balance.
      int? resolvedFractionAmount;
      if (assetType == 'land' && tokenId != null) {
        try {
          final bs = BlockchainServiceEnhanced();
          await bs.init();
          if (bs.isConnected && bs.connectedAddress != null) {
            resolvedFractionAmount =
            await bs.getUserFractions(bs.connectedAddress!, tokenId);
          }
        } catch (e) {
          debugPrint('getUserFractions error (falling back to totalFractions): $e');
          resolvedFractionAmount = assetData['totalFractions'] as int?;
        }
      }

      // ✅ Fetch buyer name to show seller later
      final buyerSnap = await _db.collection('users').doc(widget.otherUserId).get();
      final buyerName = buyerSnap.data()?['name'] ?? 'the buyer';

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TransferScreen(
            assetId: assetId,
            assetType: assetType == 'electronics' ? AssetType.electronics : AssetType.land,
            transactionId: transactionId,
            buyerUid: widget.otherUserId,
            sellerUid: sellerUid,
            tokenId: assetType == 'electronics' ? tokenId : null,
            propertyId: assetType == 'land' ? tokenId : null,
            fractionAmount: assetType == 'land' ? resolvedFractionAmount : null,
            assetPrice: price?.toString() ?? '0', // ✅ for payment
            buyerName: buyerName, // ✅ for seller notification
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      debugPrint('Navigation error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<DocumentSnapshot>(
          stream: _db.collection('users').doc(widget.otherUserId).snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Text('Chat');
            final u = snap.data!.data() as Map<String, dynamic>? ?? {};
            final online = u['online'] == true;
            final lastSeenEnabled = u['lastSeenEnabled'] ?? true;

            String subtitle;
            if (online) {
              subtitle = 'online';
            } else if (lastSeenEnabled) {
              subtitle = 'last seen ${_formatTime(u['lastSeen'])}';
            } else {
              subtitle = 'last seen recently';
            }

            return Row(
              children: [
                CircleAvatar(
                  backgroundImage: u['photoUrl'] != null ? NetworkImage(u['photoUrl']) : null,
                  child: u['photoUrl'] == null ? const Icon(Icons.person) : null,
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u['name'] ?? 'User'),
                    Text(subtitle, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            );
          },
        ),
      ),
      body: Column(
        children: [
          // ── Messages list with pagination ──
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .limit(_messageLimit)
                  .snapshots(),
              builder: (context, snap) {
                // ✅ Call mark seen with delay to prevent blocking
                if (snap.hasData && snap.data!.docs.isNotEmpty) {
                  Future.delayed(const Duration(milliseconds: 500), () {
                    _markMessagesSeen();
                  });
                }

                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('Say hello 👋'));
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  itemCount: docs.length + 1,
                  itemBuilder: (context, i) {
                    // Load more button
                    if (i == docs.length) {
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Center(
                          child: TextButton(
                            onPressed: () {
                              setState(() => _messageLimit += 20);
                            },
                            child: const Text('Load earlier messages'),
                          ),
                        ),
                      );
                    }

                    final msg = docs[i].data() as Map<String, dynamic>;
                    return _messageBubble(msg, msg['senderId'] == myUid);
                  },
                );
              },
            ),
          ),

          // ── Typing indicator ──
          StreamBuilder<DocumentSnapshot>(
            stream: _db.collection('chats').doc(widget.chatId).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData || !snap.data!.exists) return const SizedBox();
              final data = snap.data!.data() as Map<String, dynamic>;
              final otherTyping = data['typing'] == true;
              if (!otherTyping) return const SizedBox();
              return const Padding(
                padding: EdgeInsets.only(left: 16, bottom: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'typing...',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              );
            },
          ),

          // ── Checkout area ──
          _buildCheckoutArea(context),

          // ── Input row ──
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: const Offset(0, -1),
                  )
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file, color: Colors.grey),
                    onPressed: _sendFile,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onChanged: (val) {
                        _db.collection('chats').doc(widget.chatId).set(
                          {'typing': val.isNotEmpty},
                          SetOptions(merge: true),
                        );
                      },
                      onSubmitted: (_) => _sendMessage(),
                      textInputAction: TextInputAction.send,
                      decoration: InputDecoration(
                        hintText: 'Type a message',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  CircleAvatar(
                    backgroundColor: Theme.of(context).primaryColor,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 18),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageBubble(Map<String, dynamic> msg, bool isMe) {
    final type = msg['type'] ?? 'text';
    Widget content;

    if (type == 'image') {
      final ipfsHash = msg['ipfsHash'] ?? '';
      final ipfsUrl = msg['ipfsUrl'] ?? '';

      content = GestureDetector(
        onTap: () {
          // Full screen preview
          showDialog(
            context: context,
            builder: (_) => Dialog(
              backgroundColor: Colors.black,
              child: InteractiveViewer(
                child: Image.network(
                  ipfsUrl,
                  loadingBuilder: (_, child, progress) =>
                  progress == null ? child : const Center(child: CircularProgressIndicator()),
                  errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image, color: Colors.white, size: 60),
                ),
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            ipfsUrl,
            width: 200,
            height: 200,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : Container(
              width: 200,
              height: 200,
              color: Colors.grey[200],
              child: const Center(child: CircularProgressIndicator()),
            ),
            errorBuilder: (_, __, ___) => Container(
              width: 200,
              height: 200,
              color: Colors.grey[200],
              child: const Icon(Icons.broken_image),
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
        onTap: () {
          if (ipfsHash.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('File not available')),
            );
            return;
          }
          _downloadFile(ipfsHash, fileName);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_fileIcon(msg['fileExtension'] ?? ''),
                  color: Colors.blue.shade700, size: 28),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      sizeText.isNotEmpty ? '$sizeText · Tap to download' : 'Tap to download',
                      style: const TextStyle(fontSize: 10, color: Colors.black45),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.download, size: 18, color: Colors.blue.shade700),
            ],
          ),
        ),
      );
    } else {
      content = Text(
        msg['text'] ?? '',
        style: const TextStyle(color: Colors.black87),
      );
    }

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
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            content,
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(msg['timestamp']),
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    msg['seen'] == true ? Icons.done_all : Icons.check,
                    size: 14,
                    color: msg['seen'] == true ? Colors.blue : Colors.black54,
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
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }
}