import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme.dart';

// ─── Brand Colors ─────────────────────────────────────────────────────────────
const kTeal = AppTheme.primaryStart;
const kTealDark = AppTheme.primaryStartDark;
const kTealLight = AppTheme.primaryLight;
const kTealAccent = AppTheme.primaryEnd;
const kScaffoldBg = AppTheme.background;
const kTextPrimary = AppTheme.textPrimary;
const kTextSecondary = AppTheme.textMid;
const kCardBg = AppTheme.surface;

// ─── Notification Types ───────────────────────────────────────────────────────
/// All supported notification type strings.
/// Use these constants when calling [PushNotificationService.sendInAppNotification]
/// or any of the helper methods below.
class NotificationType {
  // Transaction events
  static const String transactionSent       = 'transaction_sent';
  static const String transactionReceived   = 'transaction_received';
  static const String transactionFailed     = 'transaction_failed';
  static const String transactionPending    = 'transaction_pending';
  static const String transactionCancelled  = 'transaction_cancelled';
  static const String transactionRefunded   = 'transaction_refunded';

  // Product / sale events
  static const String productSold          = 'product_sold';
  static const String productPurchased     = 'product_purchased';
  static const String productListed        = 'product_listed';

  // Transfer events
  static const String transfer             = 'transfer';
  static const String transferReceived     = 'transfer_received';

  // Verification events
  static const String verificationStarted  = 'verification_started';
  static const String verificationApproved = 'verification_approved';
  static const String verificationRejected = 'verification_rejected';
  static const String verificationPending  = 'verification_pending';
  static const String kycRequired          = 'kyc_required';

  // Wallet / balance events
  static const String walletTopUp          = 'wallet_topup';
  static const String walletWithdrawal     = 'wallet_withdrawal';
  static const String lowBalance           = 'low_balance';

  // Security events
  static const String loginAlert           = 'login_alert';
  static const String passwordChanged      = 'password_changed';
  static const String suspiciousActivity   = 'suspicious_activity';

  // General
  static const String message              = 'message';
  static const String general              = 'general';
  static const String systemAlert          = 'system_alert';
}

// ─── Background message handler (must be top-level) ──────────────────────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('📨 Background FCM message: ${message.notification?.title}');
}

// ─── Notification Service ─────────────────────────────────────────────────────
class PushNotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();

  static final PushNotificationService _instance =
  PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  // ── Channel IDs ──────────────────────────────────────────────────────────────
  static const String _txChannelId   = 'transactions_channel';
  static const String _txChannelName = 'Transaction Alerts';

  static const String _verChannelId   = 'verification_channel';
  static const String _verChannelName = 'Verification Updates';

  static const String _secChannelId   = 'security_channel';
  static const String _secChannelName = 'Security Alerts';

  static const String _genChannelId   = 'digital_goods_channel';
  static const String _genChannelName = 'Digital Goods Notifications';

  // ── Tracks whether FCM (push) is available on this device ───────────────────
  bool _fcmAvailable = false;
  bool _initialized  = false;

  // ── Initialize everything (call once in main.dart) ───────────────────────────
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 1. Setup local notifications first — this works even without Play Services
    const androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _localNotifications.initialize(initSettings);

    // 2. Create notification channels (Android 8+)
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _txChannelId,
        _txChannelName,
        description: 'Alerts for payments, transfers, and purchases',
        importance: Importance.max,
        playSound: true,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _verChannelId,
        _verChannelName,
        description: 'Updates on KYC and account verification',
        importance: Importance.high,
        playSound: true,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _secChannelId,
        _secChannelName,
        description: 'Security events and suspicious activity alerts',
        importance: Importance.max,
        playSound: true,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _genChannelId,
        _genChannelName,
        description: 'General notifications for messages and updates',
        importance: Importance.high,
      ),
    );

    // 3. Try to initialise FCM — may fail on emulators or devices without
    //    Google Play Services properly configured (DEVELOPER_ERROR).
    //    We catch every exception so the app never crashes here.
    try {
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('⚠️ FCM permission request timed out — Play Services unavailable');
          throw Exception('FCM timeout');
        },
      );

      debugPrint('🔔 FCM permission: ${settings.authorizationStatus}');

      // Only proceed with FCM if permission was granted
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {

        // 4. Show local notification when app is FOREGROUND
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          final notification = message.notification;
          if (notification == null) return;

          final type       = message.data['type'] ?? NotificationType.general;
          final channelId  = _channelIdForType(type);
          final channelName = _channelNameForType(type);

          _localNotifications.show(
            notification.hashCode,
            notification.title,
            notification.body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                channelId,
                channelName,
                importance: Importance.max,
                priority : Priority.high,
                color    : _colorForType(type),
                icon     : '@mipmap/ic_launcher',
              ),
            ),
          );
        });

        // 5. Save FCM token — wrapped in its own try/catch because
        //    getToken() is the call most likely to throw DEVELOPER_ERROR
        await _saveTokenToFirestore();
        _fcm.onTokenRefresh.listen(_saveTokenOnRefresh);
        _fcmAvailable = true;
        debugPrint('✅ FCM fully initialised');
      }
    } catch (e) {
      // DEVELOPER_ERROR, MissingPluginException, timeout, etc.
      // App continues normally — in-app Firestore notifications still work.
      debugPrint('⚠️ FCM unavailable (${e.runtimeType}): $e');
      debugPrint('ℹ️ In-app notifications via Firestore will still work.');
      _fcmAvailable = false;
    }
  }

  // ── Token management ─────────────────────────────────────────────────────────
  Future<void> _saveTokenToFirestore() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      // getToken() is the call that throws DEVELOPER_ERROR when SHA-1 is wrong
      final token = await _fcm.getToken().timeout(
        const Duration(seconds: 6),
        onTimeout: () {
          debugPrint('⚠️ FCM getToken() timed out');
          return null;
        },
      );
      if (token == null) return;

      await _db.collection('users').doc(uid).set(
        {'fcmToken': token, 'fcmUpdatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      debugPrint('✅ FCM token saved: ${token.substring(0, 20)}…');
    } catch (e) {
      // DEVELOPER_ERROR lands here — silently skip, Firestore notifications still work
      debugPrint('⚠️ Could not save FCM token: $e');
    }
  }

  void _saveTokenOnRefresh(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).set(
      {'fcmToken': token, 'fcmUpdatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  // ── Core: In-app notification (writes to Firestore) ──────────────────────────
  /// Stores a notification document in Firestore.
  /// Also shows a local heads-up notification when FCM is not available
  /// (e.g. emulator, missing SHA-1, DEVELOPER_ERROR).
  Future<void> sendInAppNotification({
    required String receiverUid,
    required String title,
    required String body,
    String type = NotificationType.general,
    String? relatedId,
    Map<String, dynamic>? payload,
  }) async {
    try {
      final dedupeKey = _notificationDedupeKey(
        receiverUid: receiverUid,
        type: type,
        relatedId: relatedId,
      );
      final normalizedPayload = payload ?? <String, dynamic>{};

      if (dedupeKey != null) {
        final existing = await _db
            .collection('notifications')
            .where('dedupeKey', isEqualTo: dedupeKey)
            .limit(1)
            .get();

        if (existing.docs.isNotEmpty) {
          await existing.docs.first.reference.update({
            'title': title,
            'body': body,
            'isRead': false,
            'timestamp': FieldValue.serverTimestamp(),
            'payload': normalizedPayload,
          });
          return;
        }
      }

      await _db.collection('notifications').add({
        'receiverId': receiverUid,
        'title'     : title,
        'body'      : body,
        'type'      : type,
        'relatedId' : relatedId,
        'dedupeKey' : dedupeKey,
        'isRead'    : false,
        'timestamp' : FieldValue.serverTimestamp(),
        'payload'   : normalizedPayload,
      });

      // If this notification is for the currently logged-in user AND FCM
      // is not available, show it as a local heads-up so they still see it
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (!_fcmAvailable && currentUid == receiverUid) {
        _showLocalNotification(title: title, body: body, type: type);
      }
    } catch (e) {
      debugPrint('❌ Error storing in-app notification: $e');
    }
  }

  /// Shows a local (device-level) notification immediately.
  /// Used as fallback when FCM / Play Services are unavailable.
  void _showLocalNotification({
    required String title,
    required String body,
    String type = NotificationType.general,
  }) {
    final channelId  = _channelIdForType(type);
    final channelName = _channelNameForType(type);
    _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: Importance.max,
          priority  : Priority.high,
          color     : _colorForType(type),
          icon      : '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  // ── Core: External push notification via FCM ──────────────────────────────────
  Future<void> sendExternalPushNotification({
    required String receiverUid,
    required String title,
    required String body,
    String type = NotificationType.general,
    String? relatedId,
    Map<String, dynamic>? data,
  }) async {
    // Skip silently if FCM could not be initialised on this device
    if (!_fcmAvailable) {
      debugPrint('ℹ️ FCM unavailable — skipping external push for $receiverUid');
      return;
    }

    try {
      final dedupeKey = _notificationDedupeKey(
        receiverUid: receiverUid,
        type: type,
        relatedId: relatedId,
      );

      if (dedupeKey != null) {
        final existing = await _db
            .collection('pending_pushes')
            .where('dedupeKey', isEqualTo: dedupeKey)
            .limit(1)
            .get();

        if (existing.docs.isNotEmpty) {
          debugPrint('ℹ️ Duplicate push skipped for $dedupeKey');
          return;
        }
      }

      final userDoc  = await _db.collection('users').doc(receiverUid).get();
      final fcmToken = userDoc.data()?['fcmToken'] as String?;
      if (fcmToken == null) {
        debugPrint('⚠️ No FCM token found for user $receiverUid');
        return;
      }

      await _db.collection('pending_pushes').add({
        'to'          : fcmToken,
        'receiverUid' : receiverUid,
        'notification': {'title': title, 'body': body},
        'data'        : {
          'type'     : type,
          'relatedId': relatedId ?? '',
          ...?data,
        },
        'dedupeKey': dedupeKey,
        'status'   : 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint('📤 External push queued for $receiverUid');
    } catch (e) {
      debugPrint('❌ Error queuing push notification: $e');
    }
  }

  /// Convenience method: sends BOTH in-app (Firestore) and external push (FCM)
  /// in a single call. Use this for all transaction and verification events.
  Future<void> notify({
    required String receiverUid,
    required String title,
    required String body,
    String type = NotificationType.general,
    String? relatedId,
    Map<String, dynamic>? payload,
  }) async {
    await Future.wait([
      sendInAppNotification(
        receiverUid: receiverUid,
        title: title,
        body: body,
        type: type,
        relatedId: relatedId,
        payload: payload,
      ),
      sendExternalPushNotification(
        receiverUid: receiverUid,
        title: title,
        body: body,
        type: type,
        relatedId: relatedId,
        data: payload,
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TRANSACTION NOTIFICATION HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Call when a user successfully sends money/product.
  Future<void> notifyTransactionSent({
    required String senderUid,
    required String amount,
    required String currency,
    required String recipientName,
    String? transactionId,
  }) =>
      notify(
        receiverUid: senderUid,
        title: '✅ Transfer Sent',
        body: 'You sent $amount $currency to $recipientName successfully.',
        type: NotificationType.transactionSent,
        relatedId: transactionId,
        payload: {'amount': amount, 'currency': currency, 'recipient': recipientName},
      );

  /// Call when a user receives money/product.
  Future<void> notifyTransactionReceived({
    required String receiverUid,
    required String amount,
    required String currency,
    required String senderName,
    String? transactionId,
  }) =>
      notify(
        receiverUid: receiverUid,
        title: '💰 Payment Received',
        body: 'You received $amount $currency from $senderName.',
        type: NotificationType.transactionReceived,
        relatedId: transactionId,
        payload: {'amount': amount, 'currency': currency, 'sender': senderName},
      );

  /// Call when a transaction fails for any reason.
  Future<void> notifyTransactionFailed({
    required String userUid,
    required String amount,
    required String currency,
    required String reason,
    String? transactionId,
  }) =>
      notify(
        receiverUid: userUid,
        title: '❌ Transaction Failed',
        body: 'Your transaction of $amount $currency failed. Reason: $reason.',
        type: NotificationType.transactionFailed,
        relatedId: transactionId,
        payload: {'amount': amount, 'currency': currency, 'reason': reason},
      );

  /// Call when a transaction is pending (e.g. awaiting confirmation).
  Future<void> notifyTransactionPending({
    required String userUid,
    required String amount,
    required String currency,
    String? transactionId,
  }) =>
      notify(
        receiverUid: userUid,
        title: '⏳ Transaction Pending',
        body: 'Your transaction of $amount $currency is being processed.',
        type: NotificationType.transactionPending,
        relatedId: transactionId,
        payload: {'amount': amount, 'currency': currency},
      );

  /// Call when a transaction is cancelled.
  Future<void> notifyTransactionCancelled({
    required String userUid,
    required String amount,
    required String currency,
    String? transactionId,
  }) =>
      notify(
        receiverUid: userUid,
        title: '🚫 Transaction Cancelled',
        body: 'Your transaction of $amount $currency has been cancelled.',
        type: NotificationType.transactionCancelled,
        relatedId: transactionId,
        payload: {'amount': amount, 'currency': currency},
      );

  /// Call when a refund is issued.
  Future<void> notifyTransactionRefunded({
    required String userUid,
    required String amount,
    required String currency,
    String? transactionId,
  }) =>
      notify(
        receiverUid: userUid,
        title: '↩️ Refund Issued',
        body: 'A refund of $amount $currency has been credited to your wallet.',
        type: NotificationType.transactionRefunded,
        relatedId: transactionId,
        payload: {'amount': amount, 'currency': currency},
      );

  // ─── Product / Sale helpers ──────────────────────────────────────────────────

  /// Call when the seller's product is purchased.
  Future<void> notifyProductSold({
    required String sellerUid,
    required String productName,
    required String amount,
    String? orderId,
  }) =>
      notify(
        receiverUid: sellerUid,
        title: '🎉 Item Sold!',
        body: '"$productName" was purchased for $amount.',
        type: NotificationType.productSold,
        relatedId: orderId,
        payload: {'product': productName, 'amount': amount},
      );

  /// Call when a buyer completes a purchase.
  Future<void> notifyProductPurchased({
    required String buyerUid,
    required String productName,
    required String amount,
    String? orderId,
  }) =>
      notify(
        receiverUid: buyerUid,
        title: '🛍️ Purchase Successful',
        body: 'You purchased "$productName" for $amount.',
        type: NotificationType.productPurchased,
        relatedId: orderId,
        payload: {'product': productName, 'amount': amount},
      );

  // ─── Transfer helpers ────────────────────────────────────────────────────────

  /// Notify both sender and receiver about a transfer simultaneously.
  Future<void> notifyTransfer({
    required String senderUid,
    required String receiverUid,
    required String amount,
    required String currency,
    required String senderName,
    required String receiverName,
    String? transferId,
  }) =>
      Future.wait([
        notify(
          receiverUid: senderUid,
          title: '↗️ Transfer Sent',
          body: 'You transferred $amount $currency to $receiverName.',
          type: NotificationType.transfer,
          relatedId: transferId,
          payload: {'amount': amount, 'currency': currency, 'to': receiverName},
        ),
        notify(
          receiverUid: receiverUid,
          title: '↙️ Transfer Received',
          body: '$senderName transferred $amount $currency to you.',
          type: NotificationType.transferReceived,
          relatedId: transferId,
          payload: {'amount': amount, 'currency': currency, 'from': senderName},
        ),
      ]);

  // ─── Wallet helpers ──────────────────────────────────────────────────────────

  /// Call when a user tops up their wallet.
  Future<void> notifyWalletTopUp({
    required String userUid,
    required String amount,
    required String currency,
    String? referenceId,
  }) =>
      notify(
        receiverUid: userUid,
        title: '💳 Wallet Topped Up',
        body: '$amount $currency has been added to your wallet.',
        type: NotificationType.walletTopUp,
        relatedId: referenceId,
        payload: {'amount': amount, 'currency': currency},
      );

  /// Call when a user withdraws from their wallet.
  Future<void> notifyWalletWithdrawal({
    required String userUid,
    required String amount,
    required String currency,
    String? referenceId,
  }) =>
      notify(
        receiverUid: userUid,
        title: '🏦 Withdrawal Initiated',
        body: '$amount $currency withdrawal is being processed.',
        type: NotificationType.walletWithdrawal,
        relatedId: referenceId,
        payload: {'amount': amount, 'currency': currency},
      );

  /// Call when the wallet balance drops below a threshold.
  Future<void> notifyLowBalance({
    required String userUid,
    required String currentBalance,
    required String currency,
  }) =>
      notify(
        receiverUid: userUid,
        title: '⚠️ Low Balance',
        body: 'Your wallet balance is low: $currentBalance $currency remaining.',
        type: NotificationType.lowBalance,
        payload: {'balance': currentBalance, 'currency': currency},
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // VERIFICATION NOTIFICATION HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Call when verification/KYC process begins.
  Future<void> notifyVerificationStarted({
    required String userUid,
    String? verificationId,
  }) =>
      notify(
        receiverUid: userUid,
        title: '🔍 Verification Started',
        body: 'Your account verification has begun. We\'ll notify you of the outcome.',
        type: NotificationType.verificationStarted,
        relatedId: verificationId,
      );

  /// Call when verification is under review.
  Future<void> notifyVerificationPending({
    required String userUid,
    String? verificationId,
  }) =>
      notify(
        receiverUid: userUid,
        title: '⏳ Verification Under Review',
        body: 'Your documents are being reviewed. This may take up to 24 hours.',
        type: NotificationType.verificationPending,
        relatedId: verificationId,
      );

  /// Call when verification is approved.
  Future<void> notifyVerificationApproved({
    required String userUid,
    String? verificationId,
  }) =>
      notify(
        receiverUid: userUid,
        title: '✅ Account Verified!',
        body: 'Congratulations! Your account has been verified. You now have full access.',
        type: NotificationType.verificationApproved,
        relatedId: verificationId,
      );

  /// Call when verification is rejected.
  Future<void> notifyVerificationRejected({
    required String userUid,
    required String reason,
    String? verificationId,
  }) =>
      notify(
        receiverUid: userUid,
        title: '❌ Verification Failed',
        body: 'Your verification was not approved. Reason: $reason. Please try again.',
        type: NotificationType.verificationRejected,
        relatedId: verificationId,
        payload: {'reason': reason},
      );

  /// Call when the user must complete KYC before proceeding.
  Future<void> notifyKycRequired({
    required String userUid,
    required String reason,
  }) =>
      notify(
        receiverUid: userUid,
        title: '📋 KYC Required',
        body: 'Please complete identity verification to $reason.',
        type: NotificationType.kycRequired,
        payload: {'reason': reason},
      );

  // ═══════════════════════════════════════════════════════════════════════════
  // SECURITY NOTIFICATION HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Call on login from a new device or location.
  Future<void> notifyLoginAlert({
    required String userUid,
    required String device,
    required String location,
  }) =>
      notify(
        receiverUid: userUid,
        title: '🔐 New Login Detected',
        body: 'New login from $device in $location. Not you? Secure your account immediately.',
        type: NotificationType.loginAlert,
        payload: {'device': device, 'location': location},
      );

  /// Call when the user changes their password.
  Future<void> notifyPasswordChanged({required String userUid}) =>
      notify(
        receiverUid: userUid,
        title: '🔑 Password Changed',
        body: 'Your account password was changed. If this wasn\'t you, contact support.',
        type: NotificationType.passwordChanged,
      );

  /// Call when suspicious activity is detected.
  Future<void> notifySuspiciousActivity({
    required String userUid,
    required String detail,
  }) =>
      notify(
        receiverUid: userUid,
        title: '🚨 Suspicious Activity',
        body: 'Unusual activity detected on your account: $detail.',
        type: NotificationType.suspiciousActivity,
        payload: {'detail': detail},
      );

  // ─── Stream & CRUD helpers ───────────────────────────────────────────────────

  Stream<QuerySnapshot> notificationsStream(String userUid) {
    return _db
        .collection('notifications')
        .where('receiverId', isEqualTo: userUid)
        .snapshots();
  }

  Future<void> markAsRead(String docId) async {
    try {
      await _db.collection('notifications').doc(docId).update({'isRead': true});
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

  Future<void> deleteNotification(String docId, {String? dedupeKey}) async {
    try {
      final normalizedDedupeKey = dedupeKey?.trim() ?? '';
      if (normalizedDedupeKey.isNotEmpty) {
        final duplicates = await _db
            .collection('notifications')
            .where('dedupeKey', isEqualTo: normalizedDedupeKey)
            .get();

        if (duplicates.docs.isNotEmpty) {
          final batch = _db.batch();
          for (final duplicate in duplicates.docs) {
            batch.delete(duplicate.reference);
          }
          await batch.commit();
          return;
        }
      }

      await _db.collection('notifications').doc(docId).delete();
    } catch (e) {
      debugPrint('❌ Error deleting notification: $e');
    }
  }

  // ─── Internal helpers ────────────────────────────────────────────────────────

  String? _notificationDedupeKey({
    required String receiverUid,
    required String type,
    String? relatedId,
  }) {
    final normalizedRelatedId = relatedId?.trim() ?? '';
    if (normalizedRelatedId.isEmpty) return null;
    return '$receiverUid|$type|$normalizedRelatedId';
  }

  String _channelIdForType(String type) {
    if (_isTransactionType(type)) return _txChannelId;
    if (_isVerificationType(type)) return _verChannelId;
    if (_isSecurityType(type)) return _secChannelId;
    return _genChannelId;
  }

  String _channelNameForType(String type) {
    if (_isTransactionType(type)) return _txChannelName;
    if (_isVerificationType(type)) return _verChannelName;
    if (_isSecurityType(type)) return _secChannelName;
    return _genChannelName;
  }

  Color _colorForType(String type) {
    if (_isTransactionType(type)) return Colors.green;
    if (_isVerificationType(type)) return kTeal;
    if (_isSecurityType(type)) return Colors.red;
    return kTeal;
  }

  bool _isTransactionType(String type) => const {
    NotificationType.transactionSent,
    NotificationType.transactionReceived,
    NotificationType.transactionFailed,
    NotificationType.transactionPending,
    NotificationType.transactionCancelled,
    NotificationType.transactionRefunded,
    NotificationType.productSold,
    NotificationType.productPurchased,
    NotificationType.productListed,
    NotificationType.transfer,
    NotificationType.transferReceived,
    NotificationType.walletTopUp,
    NotificationType.walletWithdrawal,
    NotificationType.lowBalance,
  }.contains(type);

  bool _isVerificationType(String type) => const {
    NotificationType.verificationStarted,
    NotificationType.verificationApproved,
    NotificationType.verificationRejected,
    NotificationType.verificationPending,
    NotificationType.kycRequired,
  }.contains(type);

  bool _isSecurityType(String type) => const {
    NotificationType.loginAlert,
    NotificationType.passwordChanged,
    NotificationType.suspiciousActivity,
  }.contains(type);
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
    final String type = widget.data['type'] ?? NotificationType.general;
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
                  // Icon badge
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (iconConfig['color'] as Color).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      iconConfig['icon'] as IconData,
                      color: iconConfig['color'] as Color,
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
                        const SizedBox(height: 6),
                        // Type chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (iconConfig['color'] as Color).withOpacity(0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _labelForType(
                                widget.data['type'] ?? NotificationType.general),
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: iconConfig['color'] as Color,
                            ),
                          ),
                        ),
                        if (timestamp != null) ...[
                          const SizedBox(height: 6),
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
    // Transaction
      case NotificationType.transactionSent:
        return {'icon': Icons.arrow_upward_rounded, 'color': Colors.blue};
      case NotificationType.transactionReceived:
        return {'icon': Icons.arrow_downward_rounded, 'color': Colors.green};
      case NotificationType.transactionFailed:
        return {'icon': Icons.cancel_rounded, 'color': Colors.red};
      case NotificationType.transactionPending:
        return {'icon': Icons.hourglass_top_rounded, 'color': Colors.orange};
      case NotificationType.transactionCancelled:
        return {'icon': Icons.block_rounded, 'color': Colors.grey};
      case NotificationType.transactionRefunded:
        return {'icon': Icons.replay_rounded, 'color': Colors.purple};
    // Product / Sale
      case NotificationType.productSold:
        return {'icon': Icons.payments_rounded, 'color': Colors.green};
      case NotificationType.productPurchased:
        return {'icon': Icons.shopping_bag_rounded, 'color': kTealAccent};
      case NotificationType.productListed:
        return {'icon': Icons.store_rounded, 'color': kTeal};
    // Transfer
      case NotificationType.transfer:
        return {'icon': Icons.swap_horiz_rounded, 'color': Colors.orange};
      case NotificationType.transferReceived:
        return {'icon': Icons.move_to_inbox_rounded, 'color': Colors.green};
    // Wallet
      case NotificationType.walletTopUp:
        return {'icon': Icons.account_balance_wallet_rounded, 'color': Colors.teal};
      case NotificationType.walletWithdrawal:
        return {'icon': Icons.savings_rounded, 'color': Colors.indigo};
      case NotificationType.lowBalance:
        return {'icon': Icons.warning_amber_rounded, 'color': Colors.amber};
    // Verification
      case NotificationType.verificationStarted:
        return {'icon': Icons.manage_search_rounded, 'color': kTeal};
      case NotificationType.verificationPending:
        return {'icon': Icons.pending_rounded, 'color': Colors.orange};
      case NotificationType.verificationApproved:
        return {'icon': Icons.verified_rounded, 'color': Colors.green};
      case NotificationType.verificationRejected:
        return {'icon': Icons.gpp_bad_rounded, 'color': Colors.red};
      case NotificationType.kycRequired:
        return {'icon': Icons.badge_rounded, 'color': Colors.deepOrange};
    // Security
      case NotificationType.loginAlert:
        return {'icon': Icons.login_rounded, 'color': Colors.deepOrange};
      case NotificationType.passwordChanged:
        return {'icon': Icons.lock_reset_rounded, 'color': Colors.blue};
      case NotificationType.suspiciousActivity:
        return {'icon': Icons.report_gmailerrorred_rounded, 'color': Colors.red};
    // General
      case NotificationType.message:
        return {'icon': Icons.chat_bubble_rounded, 'color': kTealAccent};
      case NotificationType.systemAlert:
        return {'icon': Icons.info_rounded, 'color': kTeal};
      default:
        return {'icon': Icons.notifications_rounded, 'color': kTeal};
    }
  }

  String _labelForType(String type) {
    const labels = {
      NotificationType.transactionSent:      'Sent',
      NotificationType.transactionReceived:  'Received',
      NotificationType.transactionFailed:    'Failed',
      NotificationType.transactionPending:   'Pending',
      NotificationType.transactionCancelled: 'Cancelled',
      NotificationType.transactionRefunded:  'Refunded',
      NotificationType.productSold:          'Sale',
      NotificationType.productPurchased:     'Purchase',
      NotificationType.productListed:        'Listed',
      NotificationType.transfer:             'Transfer',
      NotificationType.transferReceived:     'Transfer In',
      NotificationType.walletTopUp:          'Top Up',
      NotificationType.walletWithdrawal:     'Withdrawal',
      NotificationType.lowBalance:           'Low Balance',
      NotificationType.verificationStarted:  'Verification',
      NotificationType.verificationPending:  'In Review',
      NotificationType.verificationApproved: 'Verified',
      NotificationType.verificationRejected: 'Rejected',
      NotificationType.kycRequired:          'KYC',
      NotificationType.loginAlert:           'Security',
      NotificationType.passwordChanged:      'Security',
      NotificationType.suspiciousActivity:   'Alert',
      NotificationType.message:              'Message',
      NotificationType.systemAlert:          'System',
    };
    return labels[type] ?? 'General';
  }
}

// ─── Notifications Screen ─────────────────────────────────────────────────────
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  Widget build(BuildContext context) {
    final String currentUserUid =
        FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: kScaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
              color: AppTheme.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppTheme.primaryStart, size: 18),
          ),
        ),
        title: Text(
          'Notifications',
          style: AppTheme.heading(18, color: AppTheme.textPrimary),
        ),
        actions: [
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
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$unread unread',
                    style: AppTheme.body(
                      12,
                      color: AppTheme.primaryStart,
                      weight: FontWeight.w600,
                    ),
                  ),
                )
                    : const SizedBox.shrink();
              },
            ),
          // Mark all read
          GestureDetector(
            onTap: () {
              PushNotificationService().markAllAsRead(currentUserUid);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('All marked as read', style: AppTheme.body(14)),
                  backgroundColor: AppTheme.primaryStart,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.done_all_rounded,
                color: AppTheme.primaryStart,
                size: 20,
              ),
            ),
          ),
        ],
      ),
      body: currentUserUid.isEmpty
          ? _buildEmptyState(
          'Please log in to see notifications',
          Icons.lock_outline_rounded)
          : _NotificationListView(userUid: currentUserUid),
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
                decoration: const BoxDecoration(
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

// ─── Notification list ────────────────────────────────────────────────────────
class _NotificationListView extends StatelessWidget {
  final String userUid;

  const _NotificationListView({
    required this.userUid,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: PushNotificationService().notificationsStream(userUid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _emptyState(
              'Error: ${snapshot.error}', Icons.error_outline_rounded);
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: kTeal));
        }

        final docs = (snapshot.data?.docs ?? [])
            .toList()
          ..sort((a, b) {
            final aTs = (a.data() as Map)['timestamp'] as Timestamp?;
            final bTs = (b.data() as Map)['timestamp'] as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs);
          });

        final seenKeys = <String>{};
        final dedupedDocs = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final dedupeKey = data['dedupeKey']?.toString().trim();
          final fallbackKey =
              '${data['receiverId'] ?? ''}|${data['type'] ?? ''}|${data['relatedId'] ?? doc.id}';
          return seenKeys.add(
            dedupeKey != null && dedupeKey.isNotEmpty ? dedupeKey : fallbackKey,
          );
        }).toList();

        if (dedupedDocs.isEmpty) {
          return _emptyState(
            'No notifications yet',
            Icons.notifications_off_rounded,
            subtitle: "You're all caught up!",
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 16, bottom: 24),
          itemCount: dedupedDocs.length,
          itemBuilder: (context, index) {
            final doc = dedupedDocs[index];
            final data = doc.data() as Map<String, dynamic>;
            final docId = doc.id;

            return Dismissible(
              key: Key(docId),
              direction: DismissDirection.endToStart,
              background: Container(
                margin:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
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
                PushNotificationService().deleteNotification(
                  docId,
                  dedupeKey: data['dedupeKey']?.toString(),
                );
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
                onTap: () => PushNotificationService().markAsRead(docId),
              ),
            );
          },
        );
      },
    );
  }

  Widget _emptyState(String title, IconData icon, {String? subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: const BoxDecoration(
                  color: kTealLight, shape: BoxShape.circle),
              child: Icon(icon, size: 52, color: kTeal),
            ),
            const SizedBox(height: 20),
            Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: kTextPrimary)),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: kTextSecondary, height: 1.5)),
            ],
          ],
        ),
      ),
    );
  }
}
