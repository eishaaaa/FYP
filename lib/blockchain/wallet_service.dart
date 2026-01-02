import 'package:flutter/material.dart';
import 'package:reown_appkit/reown_appkit.dart';

class WalletService {
  static final WalletService _instance = WalletService._internal();
  factory WalletService() => _instance;
  WalletService._internal();

  ReownAppKitModal? _appKitModal;

  /// Returns the active AppKitModal instance.
  /// Throws error if accessed before init(context).
  ReownAppKitModal get appKitModal {
    if (_appKitModal == null) {
      throw Exception('WalletService not initialized. Call init(context) first.');
    }
    return _appKitModal!;
  }

  bool get isInitialized => _appKitModal != null;

  /// Initialize the AppKit Modal (Requires Context for UI)
  Future<void> init(BuildContext context) async {
    if (_appKitModal != null) return;

    try {
      _appKitModal = ReownAppKitModal(
        context: context,
        projectId: '8f60adc0059124b9d8a76eedb8777bdb',
        metadata: const PairingMetadata(
          name: 'Digital Goods',
          description: 'Blockchain-based Digital Goods Marketplace',
          url: 'https://digitalgoods.app',
          icons: ['https://walletconnect.com/walletconnect-logo.png'],
          redirect: Redirect(
            native: 'digitalgoods://',
            universal: 'https://digitalgoods.app',
          ),
        ),
      );

      await _appKitModal!.init();
      print('✅ WalletService Initialized');
    } catch (e) {
      print('❌ WalletService Init Error: $e');
    }
  }
}