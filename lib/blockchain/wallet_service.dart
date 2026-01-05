// ═══════════════════════════════════════════════════════════
// 1. SIMPLE WALLET SERVICE (Standard Modal + Signing Support)
// Place in: lib/blockchain/simple_wallet_service.dart
// ═══════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'contract_config.dart';

class SimpleWalletService {
  static final SimpleWalletService _instance = SimpleWalletService._internal();
  factory SimpleWalletService() => _instance;
  SimpleWalletService._internal();

  late ReownAppKitModal _modal;
  bool _initialized = false;
  String? _address;

  // Getters
  bool get isConnected => _address != null;
  String? get address => _address;
  // ✅ Expose modal for BlockchainService to sign transactions
  ReownAppKitModal get appKitModal => _modal;
  bool get isInitialized => _initialized;

  Future<void> init(BuildContext context) async {
    if (_initialized) return;

    final amoy = ReownAppKitModalNetworkInfo(
      name: 'Polygon Amoy',
      chainId: '80002',
      currency: 'MATIC',
      rpcUrl: ContractConfig.rpcUrl,
      explorerUrl: 'https://amoy.polygonscan.com',
      isTestNetwork: true,
    );

    ReownAppKitModalNetworks.addSupportedNetworks(
      'eip155',
      [amoy],
    );

    _modal = ReownAppKitModal(
      context: context,
      projectId: '8f60adc0059124b9d8a76eedb8777bdb',
      metadata: const PairingMetadata(
        name: 'DigitalGoods',
        description: 'FYP NFT Marketplace',
        url: 'https://digitalgoods.app',
        icons: ['https://digitalgoods.app/icon.png'],
        redirect: Redirect(
          native: 'digital goods://',
          universal: 'https://digitalgoods.app/link',
        ),
      ),
      optionalNamespaces: {
        'eip155': RequiredNamespace(
          chains: ['eip155:80002'],
          methods: [
            'eth_sendTransaction',
            'personal_sign',
            'eth_signTypedData_v4',
          ],
          events: ['accountsChanged', 'chainChanged'],
        ),
      },
    );

    await _modal.init();

    // Listen for session changes
    _modal.addListener(_onConnectionChanged);

    if (_modal.isConnected) {
      _extractAddress();
    }

    _initialized = true;
  }

  /// 🔹 OPEN STANDARD WALLET MODAL
  Future<String?> connect(BuildContext context) async {
    await init(context);

    if (isConnected) return _address;

    // This opens the official QR/List modal
    await _modal.openModalView();

    return await _waitForConnection();
  }

  Future<void> disconnect() async {
    if (_modal.isConnected) {
      await _modal.disconnect();
    }
    _address = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('wallet_address');
  }

  // Helper to handle session updates
  void _onConnectionChanged() {
    if (_modal.isConnected) {
      _extractAddress();
    } else {
      _address = null;
    }
  }

  void _extractAddress() async {
    final session = _modal.session;
    if (session == null) return;

    final accounts = session.namespaces?['eip155']?.accounts;
    if (accounts == null || accounts.isEmpty) return;

    _address = accounts.first.split(':').last;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wallet_address', _address!);
  }

  Future<String?> _waitForConnection() async {
    for (int i = 0; i < 30; i++) {
      if (isConnected) return _address;
      await Future.delayed(const Duration(seconds: 1));
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════════════
// UI HELPER: BUTTON & STATUS WIDGET
// ═══════════════════════════════════════════════════════════

Future<String?> showSimpleWalletConnect(BuildContext context) async {
  return await SimpleWalletService().connect(context);
}

class WalletStatusWidget extends StatefulWidget {
  const WalletStatusWidget({super.key});

  @override
  State<WalletStatusWidget> createState() => _WalletStatusWidgetState();
}

class _WalletStatusWidgetState extends State<WalletStatusWidget> {
  final _service = SimpleWalletService();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Periodically refresh UI to stay in sync with wallet state
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _shorten(String addr) =>
      '${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}';

  @override
  Widget build(BuildContext context) {
    if (!_service.isConnected) {
      return ElevatedButton.icon(
        onPressed: () => _service.connect(context),
        icon: const Icon(Icons.account_balance_wallet, size: 18),
        label: const Text('Connect'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      );
    }

    return PopupMenuButton(
      child: Chip(
        avatar: const Icon(Icons.check_circle, color: Colors.green, size: 18),
        label: Text(_shorten(_service.address!)),
        backgroundColor: Colors.green[50],
        side: BorderSide(color: Colors.green.shade200),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          child: const Text('Disconnect'),
          onTap: () => _service.disconnect(),
        ),
      ],
    );
  }
}