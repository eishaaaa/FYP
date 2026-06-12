import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core_platform_interface/src/pigeon/messages.pigeon.dart';
import 'package:firebase_auth_platform_interface/src/pigeon/messages.pigeon.dart' as auth_pigeon;
import 'package:cloud_firestore_platform_interface/src/pigeon/messages.pigeon.dart' as firestore_pigeon;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart' as firestore_interface;
import 'package:cloud_firestore_platform_interface/src/method_channel/utils/firestore_message_codec.dart';
import 'package:digitalgoods/services/chat_services.dart';
import 'package:digitalgoods/blockchain/blockchain_service.dart';

class TestFirestoreHostCodec extends FirestoreMessageCodec {
  const TestFirestoreHostCodec();

  @override
  void writeValue(WriteBuffer buffer, Object? value) {
    if (value is firestore_pigeon.AggregateQuery) {
      buffer.putUint8(128);
      writeValue(buffer, value.encode());
    } else if (value is firestore_pigeon.AggregateQueryResponse) {
      buffer.putUint8(129);
      writeValue(buffer, value.encode());
    } else if (value is firestore_pigeon.DocumentReferenceRequest) {
      buffer.putUint8(130);
      writeValue(buffer, value.encode());
    } else if (value is firestore_pigeon.FirestorePigeonFirebaseApp) {
      buffer.putUint8(131);
      writeValue(buffer, value.encode());
    } else if (value is firestore_pigeon.PigeonDocumentChange) {
      buffer.putUint8(132);
      writeValue(buffer, value.encode());
    } else if (value is firestore_pigeon.PigeonDocumentOption) {
      buffer.putUint8(133);
      writeValue(buffer, value.encode());
    } else if (value is firestore_pigeon.PigeonDocumentSnapshot) {
      buffer.putUint8(134);
      writeValue(buffer, value.encode());
    } else if (value is firestore_pigeon.PigeonFirebaseSettings) {
      buffer.putUint8(135);
      writeValue(buffer, value.encode());
    } else if (value is firestore_pigeon.PigeonGetOptions) {
      buffer.putUint8(136);
      writeValue(buffer, value.encode());
    } else if (value is firestore_pigeon.PigeonQueryParameters) {
      buffer.putUint8(137);
      writeValue(buffer, value.encode());
    } else if (value is firestore_pigeon.PigeonQuerySnapshot) {
      buffer.putUint8(138);
      writeValue(buffer, value.encode());
    } else if (value is firestore_pigeon.PigeonSnapshotMetadata) {
      buffer.putUint8(139);
      writeValue(buffer, value.encode());
    } else if (value is firestore_pigeon.PigeonTransactionCommand) {
      buffer.putUint8(140);
      writeValue(buffer, value.encode());
    } else {
      super.writeValue(buffer, value);
    }
  }

  @override
  Object? readValueOfType(int type, ReadBuffer buffer) {
    try {
      switch (type) {
        case 128:
          return firestore_pigeon.AggregateQuery.decode(readValue(buffer)!);
        case 129:
          return firestore_pigeon.AggregateQueryResponse.decode(readValue(buffer)!);
        case 130:
          return firestore_pigeon.DocumentReferenceRequest.decode(readValue(buffer)!);
        case 131:
          return firestore_pigeon.FirestorePigeonFirebaseApp.decode(readValue(buffer)!);
        case 132:
          return firestore_pigeon.PigeonDocumentChange.decode(readValue(buffer)!);
        case 133:
          return firestore_pigeon.PigeonDocumentOption.decode(readValue(buffer)!);
        case 134:
          return firestore_pigeon.PigeonDocumentSnapshot.decode(readValue(buffer)!);
        case 135:
          return firestore_pigeon.PigeonFirebaseSettings.decode(readValue(buffer)!);
        case 136:
          return firestore_pigeon.PigeonGetOptions.decode(readValue(buffer)!);
        case 137:
          return firestore_pigeon.PigeonQueryParameters.decode(readValue(buffer)!);
        case 138:
          return firestore_pigeon.PigeonQuerySnapshot.decode(readValue(buffer)!);
        case 139:
          return firestore_pigeon.PigeonSnapshotMetadata.decode(readValue(buffer)!);
        case 140:
          return firestore_pigeon.PigeonTransactionCommand.decode(readValue(buffer)!);
        
        // Handle the server timestamp and other FieldValues that are only decoded during tests:
        case 184: // _kArrayUnion
          final List<dynamic> val = readValue(buffer)! as List<dynamic>;
          return firestore_interface.FieldValuePlatform(firestore_interface.FieldValueFactoryPlatform.instance.arrayUnion(val));
        case 185: // _kArrayRemove
          final List<dynamic> val = readValue(buffer)! as List<dynamic>;
          return firestore_interface.FieldValuePlatform(firestore_interface.FieldValueFactoryPlatform.instance.arrayRemove(val));
        case 186: // _kDelete
          return firestore_interface.FieldValuePlatform(firestore_interface.FieldValueFactoryPlatform.instance.delete());
        case 187: // _kServerTimestamp
          return firestore_interface.FieldValuePlatform(firestore_interface.FieldValueFactoryPlatform.instance.serverTimestamp());
        case 189: // _kIncrementDouble
          final double val = readValue(buffer)! as double;
          return firestore_interface.FieldValuePlatform(firestore_interface.FieldValueFactoryPlatform.instance.increment(val));
        case 190: // _kIncrementInteger
          final int val = readValue(buffer)! as int;
          return firestore_interface.FieldValuePlatform(firestore_interface.FieldValueFactoryPlatform.instance.increment(val));
        case 192: // _kFieldPath
          final int size = readSize(buffer);
          final List<String> segments = <String>[];
          for (int i = 0; i < size; i++) {
            segments.add(readValue(buffer)! as String);
          }
          return firestore_interface.FieldPath(segments);

        default:
          return super.readValueOfType(type, buffer);
      }
    } catch (e, stack) {
      print('TestFirestoreHostCodec readValueOfType error for type $type: $e\n$stack');
      rethrow;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock data store representing our database
  Map<String, Map<String, dynamic>> firestoreDb = {};

  setUpAll(() async {
    // Build the mock current user data encoded as expected by FirebaseAuth Platform Pigeon decode
    final mockUserInfoEncoded = [
      'mock_uid_123', // uid
      'eisha@kinnaird.edu.pk', // email
      'Eisha', // displayName
      null, // photoUrl
      null, // phoneNumber
      false, // isAnonymous
      true, // isEmailVerified
      null, // providerId
      null, // tenantId
      null, // refreshToken
      null, // creationTimestamp
      null, // lastSignInTimestamp
    ];
    final mockProviderDataEncoded = <Map<Object?, Object?>?>[];
    final mockCurrentUserEncoded = [
      mockUserInfoEncoded,
      mockProviderDataEncoded,
    ];

    // 1. Mock Firebase Core Pigeon Channels using BasicMessageChannel with the pigeonChannelCodec
    final mockOptions = CoreFirebaseOptions(
      apiKey: 'mock-api-key',
      appId: 'mock-app-id',
      messagingSenderId: 'mock-sender-id',
      projectId: 'mock-project-id',
    );

    final mockResponse = CoreInitializeResponse(
      name: '[DEFAULT]',
      options: mockOptions,
      pluginConstants: {
        'plugins.flutter.io/firebase_auth': {
          'APP_CURRENT_USER': mockCurrentUserEncoded,
        },
      },
    );

    const BasicMessageChannel coreChannel = BasicMessageChannel(
      'dev.flutter.pigeon.firebase_core_platform_interface.FirebaseCoreHostApi.initializeCore',
      FirebaseCoreHostApi.pigeonChannelCodec,
    );
    coreChannel.setMockMessageHandler((dynamic message) async {
      return [ // Pigeon envelope wrapper
        [ // Actual return value (List of CoreInitializeResponse)
          mockResponse
        ]
      ];
    });

    const BasicMessageChannel appChannel = BasicMessageChannel(
      'dev.flutter.pigeon.firebase_core_platform_interface.FirebaseCoreHostApi.initializeApp',
      FirebaseCoreHostApi.pigeonChannelCodec,
    );
    appChannel.setMockMessageHandler((dynamic message) async {
      final List args = message as List;
      final String appName = args[0] as String;
      final CoreFirebaseOptions options = args[1] as CoreFirebaseOptions;
      return [ // Pigeon envelope wrapper
        CoreInitializeResponse(
          name: appName,
          options: options,
          pluginConstants: {},
        )
      ];
    });

    // 2. Mock Firebase Auth Pigeon Host API Channels
    const BasicMessageChannel registerIdTokenChannel = BasicMessageChannel(
      'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.registerIdTokenListener',
      auth_pigeon.FirebaseAuthHostApi.pigeonChannelCodec,
    );
    registerIdTokenChannel.setMockMessageHandler((dynamic message) async {
      return ['mock_id_token_channel'];
    });

    const BasicMessageChannel registerAuthStateChannel = BasicMessageChannel(
      'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.registerAuthStateListener',
      auth_pigeon.FirebaseAuthHostApi.pigeonChannelCodec,
    );
    registerAuthStateChannel.setMockMessageHandler((dynamic message) async {
      return ['mock_auth_state_channel'];
    });

    // Helper to convert Pigeon request data to a Map<String, dynamic> while resolving FieldPath keys
    Map<String, dynamic> convertPigeonMap(Map<Object?, Object?>? data) {
      final Map<String, dynamic> converted = {};
      if (data != null) {
        data.forEach((key, val) {
          String keyStr;
          if (key is firestore_interface.FieldPath) {
            keyStr = key.components.join('.');
          } else {
            keyStr = key.toString();
          }
          converted[keyStr] = val;
        });
      }
      return converted;
    }

    // 3. Mock Firebase Firestore Pigeon Host API Channels
    const BasicMessageChannel setChannel = BasicMessageChannel(
      'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.documentReferenceSet',
      TestFirestoreHostCodec(),
    );
    setChannel.setMockMessageHandler((dynamic message) async {
      final List args = message as List;
      final req = args[1] as firestore_pigeon.DocumentReferenceRequest;
      firestoreDb[req.path] = convertPigeonMap(req.data);
      return [null];
    });

    const BasicMessageChannel updateChannel = BasicMessageChannel(
      'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.documentReferenceUpdate',
      TestFirestoreHostCodec(),
    );
    updateChannel.setMockMessageHandler((dynamic message) async {
      final List args = message as List;
      final req = args[1] as firestore_pigeon.DocumentReferenceRequest;
      final existing = firestoreDb[req.path] ?? {};
      firestoreDb[req.path] = {
        ...existing,
        ...convertPigeonMap(req.data),
      };
      return [null];
    });

    const BasicMessageChannel getChannel = BasicMessageChannel(
      'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.documentReferenceGet',
      TestFirestoreHostCodec(),
    );
    getChannel.setMockMessageHandler((dynamic message) async {
      final List args = message as List;
      final req = args[1] as firestore_pigeon.DocumentReferenceRequest;
      
      final data = firestoreDb[req.path];
      final exists = data != null;

      final snapshot = firestore_pigeon.PigeonDocumentSnapshot(
        path: req.path,
        data: exists ? data.cast<String?, Object?>() : null,
        metadata: firestore_pigeon.PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false),
      );

      return [snapshot];
    });

    const BasicMessageChannel deleteChannel = BasicMessageChannel(
      'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.documentReferenceDelete',
      TestFirestoreHostCodec(),
    );
    deleteChannel.setMockMessageHandler((dynamic message) async {
      final List args = message as List;
      final req = args[1] as firestore_pigeon.DocumentReferenceRequest;
      firestoreDb.remove(req.path);
      return [null];
    });

    const BasicMessageChannel queryGetChannel = BasicMessageChannel(
      'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi.queryGet',
      TestFirestoreHostCodec(),
    );
    queryGetChannel.setMockMessageHandler((dynamic message) async {
      // Return a query snapshot with Eisha user
      final userSnapshot = firestore_pigeon.PigeonDocumentSnapshot(
        path: 'users/mock_uid_123',
        data: {
          'walletAddress': '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
          'username': 'Eisha',
        },
        metadata: firestore_pigeon.PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false),
      );
      final querySnapshot = firestore_pigeon.PigeonQuerySnapshot(
        documents: [userSnapshot],
        documentChanges: [],
        metadata: firestore_pigeon.PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false),
      );
      return [querySnapshot];
    });

    // Initialize Firebase
    await Firebase.initializeApp();
  });

  setUp(() {
    firestoreDb.clear();
  });

  group('Zainub - Firebase Chat Service Integration Tests', () {
    test('1. Verify Firebase Connection & Auth Mock State', () {
      expect(FirebaseAuth.instance.currentUser, isNotNull);
      expect(FirebaseAuth.instance.currentUser!.uid, 'mock_uid_123');
    });

    test('2. Chat message correctly writes to Firestore', () async {
      const chatId = 'chat_eisha_areeba';
      const messageText = 'Hello Areeba, verified the smart contracts on-chain!';
      const receiverId = 'areeba_uid_456';

      await ChatService.sendMessage(
        chatId: chatId,
        text: messageText,
        receiverId: receiverId,
      );

      expect(firestoreDb.containsKey('chats/$chatId'), isTrue);
      final chatData = firestoreDb['chats/$chatId']!;
      expect(chatData['users'], containsAll(['mock_uid_123', receiverId]));
      expect(chatData['lastMessage'], messageText);
    });
  });

  group('Zainub - Blockchain & Firebase Self-Healing Integration Tests', () {
    late MockBlockchainService blockchainService;

    setUp(() {
      blockchainService = MockBlockchainService();
    });

    test('3. Recreate deleted Firestore asset document from Blockchain', () async {
      const firestoreDocId = 'land_dha_1';
      expect(firestoreDb.containsKey('assets/$firestoreDocId'), isFalse);

      final healthy = await blockchainService.verifyAndHealAsset(
        type: 'land',
        blockchainId: 1,
        firestoreDocId: firestoreDocId,
        firestore: FirebaseFirestore.instance,
      );

      expect(healthy, isFalse);
      expect(firestoreDb.containsKey('assets/$firestoreDocId'), isTrue);
      final restoredData = firestoreDb['assets/$firestoreDocId']!;
      expect(restoredData['location'], 'DHA Phase 5, Lahore');
      expect(restoredData['totalArea'], 10);
    });

    test('4. Auto-heal tampered owner details from Blockchain', () async {
      const firestoreDocId = 'electronics_samsung_s24';
      
      firestoreDb['assets/$firestoreDocId'] = {
        'serialNumber': 'IMEI123456789',
        'currentOwnerAddress': '0xTAMPERED_ADDRESS_9999999999999999999',
        'ownerId': 'hacker_uid_666',
        'createdAt': Timestamp.fromDate(DateTime.now().subtract(const Duration(minutes: 10))),
      };

      final healthy = await blockchainService.verifyAndHealAsset(
        type: 'electronics',
        blockchainId: 1,
        firestoreDocId: firestoreDocId,
        firestore: FirebaseFirestore.instance,
      );

      expect(healthy, isFalse);
      final healedData = firestoreDb['assets/$firestoreDocId']!;
      expect(healedData['currentOwnerAddress'], '0x70997970C51812dc3A010C7d01b50e0d17dc79C8');
      expect(healedData['ownerId'], 'mock_uid_123');
    });

    test('5. Skip healing if within grace period to prevent transaction conflicts', () async {
      const firestoreDocId = 'electronics_samsung_s24';

      firestoreDb['assets/$firestoreDocId'] = {
        'serialNumber': 'IMEI123456789',
        'currentOwnerAddress': '0xTAMPERED_ADDRESS_9999999999999999999',
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      };

      final healthy = await blockchainService.verifyAndHealAsset(
        type: 'electronics',
        blockchainId: 1,
        firestoreDocId: firestoreDocId,
        firestore: FirebaseFirestore.instance,
      );

      expect(healthy, isTrue);
      final currentData = firestoreDb['assets/$firestoreDocId']!;
      expect(currentData['currentOwnerAddress'], '0xTAMPERED_ADDRESS_9999999999999999999');
    });
  });
}

class MockBlockchainService extends BlockchainServiceEnhanced {
  MockBlockchainService() : super.internal();

  @override
  Future<void> init() async {
  }

  @override
  Future<Map<String, dynamic>?> getDevice(int tokenId) async {
    return {
      'serialNumber': 'IMEI123456789',
      'brand': 'Samsung',
      'model': 'Galaxy S24',
      'status': 0,
    };
  }

  @override
  Future<String?> getOwnerOf(String type, int tokenId) async {
    return '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';
  }

  @override
  Future<void> restoreAssetFromBlockchain({
    required String type,
    required int tokenId,
    required FirebaseFirestore firestore,
  }) async {
    final docRef = firestore.collection('assets').doc('land_dha_1');
    await docRef.set({
      'location': 'DHA Phase 5, Lahore',
      'totalArea': 10,
      'areaUnit': 'marla',
      'currentOwnerAddress': '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
    });
  }
}
