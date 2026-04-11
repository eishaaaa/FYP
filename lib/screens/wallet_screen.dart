import 'package:flutter/material.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:url_launcher/url_launcher.dart';

import '../blockchain/wallet_service.dart';
import '../blockchain/contract_config.dart';
import '../blockchain/explorer_service.dart';
import '../screens/transaction_model.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  // ─── Services ───────────────────────────────────────────
  final SimpleWalletService _walletService = SimpleWalletService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ExplorerService _explorer = ExplorerService();
  late Web3Client _client;

  // ─── State ──────────────────────────────────────────────
  String? _address;
  String? _userName;
  double _balance = 0.0;
  bool _connecting = false;
  bool _loading = false;
  List<TransactionModel> _transactions = [];
  int _txCount = 0;
  int _nftCount = 0;

  // ─── Amoy network info (mirrors wallet_service.dart) ────
  static final _amoyNetwork = ReownAppKitModalNetworkInfo(
    name: 'Polygon Amoy',
    chainId: '80002',
    currency: 'MATIC',
    rpcUrl: ContractConfig.rpcUrl,
    explorerUrl: 'https://amoy.polygonscan.com',
    isTestNetwork: true,
  );

  // ════════════════════════════════════════════════════════
  // LIFECYCLE
  // ════════════════════════════════════════════════════════
  @override
  void initState() {
    super.initState();
    _client = Web3Client(ContractConfig.rpcUrl, http.Client());
    _checkExistingConnection();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // init() must run first — _modal is late and uninitialized until then
      if (!_walletService.isInitialized) {
        await _walletService.init(context);
      }

      // Safe to access appKitModal now
      _walletService.appKitModal.addListener(_onWalletNotify);

      // Auto-connect: restore previous WalletConnect session if it exists
      if (_walletService.appKitModal.isConnected &&
          _walletService.isConnected &&
          _walletService.address != null) {
        if (mounted) {
          setState(() => _address = _walletService.address);
          await _loadAllData();
        }
      }
    });
  }

  @override
  void dispose() {
    _walletService.appKitModal.removeListener(_onWalletNotify);
    super.dispose();
  }

  void _onWalletNotify() {
    if (!mounted) return;
    setState(() {
      if (!_walletService.appKitModal.isConnected || !_walletService.isConnected) {
        _address = null;
        _balance = 0.0;
      } else {
        _address = _walletService.address;
      }
    });
  }

  // ════════════════════════════════════════════════════════
  // AMOY CHAIN ENFORCEMENT
  // ════════════════════════════════════════════════════════

  /// Switches MetaMask to Polygon Amoy using the already-registered
  /// network in wallet_service.dart. No raw RPC needed.
  Future<void> _enforceAmoyNetwork() async {
    try {
      await _walletService.appKitModal.selectChain(
        _amoyNetwork,
        switchChain: true,
      );
      debugPrint("✅ Switched to Polygon Amoy (chain 80002)");
    } catch (e) {
      debugPrint("⚠️ Could not switch to Amoy: $e");
      // Non-fatal — user may have already approved Amoy via the modal
    }
  }

  // ════════════════════════════════════════════════════════
  // WALLET OPERATIONS
  // ════════════════════════════════════════════════════════

  Future<void> _checkExistingConnection() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = await _firestore.collection("users").doc(user.uid).get();
    if (!doc.exists) return;

    final data = doc.data();
    _address = data?["walletAddress"];
    _userName = data?["name"];

    if (_address != null) await _loadAllData();
    if (mounted) setState(() {});
  }

  Future<void> _connect() async {
    if (_connecting) return;
    setState(() => _connecting = true);

    try {
      if (!_walletService.isInitialized) {
        await _walletService.init(context);
      }

      final address = await _walletService
          .connect(context)
          .timeout(const Duration(seconds: 25), onTimeout: () => null);

      // Allow modal state to settle
      await Future.delayed(const Duration(milliseconds: 500));

      if (!_walletService.appKitModal.isConnected ||
          !_walletService.isConnected ||
          address == null) {
        throw Exception("Wallet connection failed or cancelled");
      }

      // 🔑 Force Polygon Amoy — fixes "Invalid Id" / wrong-network errors
      await _enforceAmoyNetwork();

      final user = _auth.currentUser;
      if (user != null) await _saveWalletToFirestore(user.uid, address);

      if (!mounted) return;
      setState(() => _address = address);

      await _loadAllData();
    } catch (e) {
      debugPrint("Connect error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Wallet connection failed or timed out")),
        );
      }
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    if (_loading || _connecting) return;
    setState(() => _loading = true);

    try {
      if (_walletService.isConnected) await _walletService.disconnect();
      setState(() {
        _address = null;
        _balance = 0.0;
        _transactions.clear();
        _txCount = 0;
        _nftCount = 0;
      });
    } catch (e) {
      debugPrint("Disconnect error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switchAccount() async {
    if (_loading || _connecting) return;
    setState(() => _connecting = true);

    try {
      try {
        await _walletService.disconnect();
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      final newAddress = await _walletService.connect(context);
      if (newAddress == null) return;

      // 🔑 Re-enforce Amoy after account switch
      await _enforceAmoyNetwork();

      final user = _auth.currentUser;
      if (user != null) await _saveWalletToFirestore(user.uid, newAddress);

      if (!mounted) return;
      setState(() {
        _address = newAddress;
        _loading = true;
      });

      await _loadAllData();
    } catch (e) {
      debugPrint("Switch error: $e");
    } finally {
      if (mounted) setState(() { _connecting = false; _loading = false; });
    }
  }

  Future<void> _removeWallet() async {
    if (_loading || _connecting) return;
    setState(() => _loading = true);

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _walletService.disconnect();
      await _firestore
          .collection("users")
          .doc(user.uid)
          .update({"walletAddress": FieldValue.delete()});

      setState(() {
        _address = null;
        _balance = 0.0;
        _transactions.clear();
        _txCount = 0;
        _nftCount = 0;
      });
    } catch (e) {
      debugPrint("Remove error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ════════════════════════════════════════════════════════
  // DATA LOADING
  // ════════════════════════════════════════════════════════

  bool get _isWalletReady =>
      _walletService.isConnected &&
          _walletService.appKitModal.isConnected &&
          _address != null;

  Future<void> _loadAllData() async {
    if (_address == null) return;
    setState(() => _loading = true);

    try {
      await _loadBalance();

      final normalTxs = await _explorer.getTransactions(_address!);
      final nftTxs = await _explorer.getNFTTransactions(_address!);

      List<TransactionModel> firestoreTxs = [];
      final user = _auth.currentUser;
      if (user != null) {
        final snap = await _firestore
            .collection("users")
            .doc(user.uid)
            .collection("transactions")
            .orderBy("time", descending: true)
            .limit(10)
            .get();

        firestoreTxs = snap.docs.map((doc) {
          final d = doc.data();
          return TransactionModel(
            type: d["type"] ?? "sent",
            title: d["title"] ?? "Transaction",
            to: d["to"] ?? "",
            value: d["value"]?.toString() ?? "0",
            gas: d["gas"]?.toString() ?? "0",
            time: d["time"]?.toString() ?? "0",
            success: true,
            hash: d["hash"] ?? "",
          );
        }).toList();
      }

      final seen = <String>{};
      final dedupedTxs = [...normalTxs, ...nftTxs, ...firestoreTxs]
          .where((tx) => tx.hash.isNotEmpty && seen.add(tx.hash))
          .toList()
        ..sort((a, b) => int.parse(b.time).compareTo(int.parse(a.time)));

      setState(() {
        _transactions = dedupedTxs.take(15).toList();
        _txCount = normalTxs.length;
        _nftCount =
            nftTxs.length + firestoreTxs.where((tx) => tx.type == "nft").length;
      });
    } catch (e) {
      debugPrint("Load data error: $e");
      setState(() {
        _transactions = [];
        _txCount = 0;
        _nftCount = 0;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadBalance() async {
    if (_address == null) return;
    try {
      final ethAddress = EthereumAddress.fromHex(_address!);
      final balanceWei = await _client.getBalance(ethAddress);
      _balance = balanceWei.getValueInUnit(EtherUnit.ether);
    } catch (e) {
      debugPrint("Balance error: $e");
    }
  }

  // ════════════════════════════════════════════════════════
  // FIRESTORE HELPERS
  // ════════════════════════════════════════════════════════

  Future<void> _saveWalletToFirestore(String uid, String newAddress) async {
    final userRef = _firestore.collection("users").doc(uid);
    final doc = await userRef.get();
    final oldAddress = doc.data()?["walletAddress"];

    await userRef.set({"walletAddress": newAddress}, SetOptions(merge: true));

    if (oldAddress != null && oldAddress != newAddress) {
      await userRef.collection("walletHistory").add({
        "oldWallet": oldAddress,
        "newWallet": newAddress,
        "changedAt": FieldValue.serverTimestamp(),
      });
    }
  }

  // ════════════════════════════════════════════════════════
  // UI HELPERS
  // ════════════════════════════════════════════════════════

  double _convertPolToPkr(double polAmount) => polAmount * 280.0;

  String _shorten(String addr) {
    if (addr.isEmpty) return "N/A";
    if (addr.length <= 10) return addr;
    return "${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}";
  }

  void _confirmAction({
    required String title,
    required Future<void> Function() onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text("Are you sure you want to continue?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await onConfirm();
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Wallet"),
        actions: [
          if (_address != null)
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: _showWalletOptions,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_isWalletReady
          ? _buildConnectView()
          : _buildWalletView(),
    );
  }

  // ─── Connect View ────────────────────────────────────────
  Widget _buildConnectView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              size: 72, color: Colors.deepPurple),
          const SizedBox(height: 24),
          const Text("Connect your wallet",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text(
            "Link a Web3 wallet to view your\nbalance and transactions.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: 220,
            child: ElevatedButton.icon(
              onPressed: (_connecting || _loading) ? null : _connect,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: _connecting
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.account_balance_wallet),
              label: Text(_connecting ? "Opening wallet..." : "Connect Wallet"),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Wallet View ─────────────────────────────────────────
  Widget _buildWalletView() {
    return RefreshIndicator(
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildBalanceCard(),
          const SizedBox(height: 16),
          _buildStats(),
          const SizedBox(height: 16),
          _buildTransactions(),
        ],
      ),
    );
  }

  // ─── Balance Card ────────────────────────────────────────
  Widget _buildBalanceCard() {
    final pkrBalance = _convertPolToPkr(_balance);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [Colors.deepPurple, Colors.blue]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Connected User:", style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                _userName ?? "User",
                style: const TextStyle(
                    fontSize: 20,
                    color: Colors.white,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text("Verified",
                    style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(_shorten(_address!),
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          Text(
            "${_balance.toStringAsFixed(4)} POL",
            style: const TextStyle(
                fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text("₨${pkrBalance.toStringAsFixed(2)}",
              style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  // ─── Stats ───────────────────────────────────────────────
  Widget _buildStats() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(children: [
              Text("$_txCount", style: const TextStyle(fontSize: 18)),
              const Text("Transactions"),
            ]),
            Column(children: [
              Text("$_nftCount", style: const TextStyle(fontSize: 18)),
              const Text("NFTs"),
            ]),
          ],
        ),
      ),
    );
  }

  // ─── Transaction List ────────────────────────────────────
  Widget _buildTransactions() {
    if (_transactions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text("No transactions found"),
        ),
      );
    }

    return Column(
      children: _transactions.map((tx) {
        final time =
        DateTime.fromMillisecondsSinceEpoch(int.parse(tx.time) * 1000);
        final diff = DateTime.now().difference(time);
        final formattedTime = diff.inMinutes < 60
            ? "${diff.inMinutes} min ago"
            : diff.inHours < 24
            ? "${diff.inHours} hr ago"
            : "${diff.inDays} d ago";

        final isSent = tx.type == "sent";
        final isNft = tx.type == "nft";
        final isContract = tx.type == "contract";

        return ListTile(
          leading: Icon(
            isNft
                ? Icons.image
                : isContract
                ? Icons.code
                : isSent
                ? Icons.arrow_upward
                : Icons.arrow_downward,
            color: isNft
                ? Colors.blue
                : isContract
                ? Colors.orange
                : isSent
                ? Colors.red
                : Colors.green,
          ),
          title: Text(
            isNft
                ? tx.title
                : isContract
                ? "Contract Interaction"
                : isSent
                ? "Sent ${tx.value} POL"
                : "Received ${tx.value} POL",
          ),
          subtitle: Text(_shorten(tx.to)),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(formattedTime, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 2),
              InkWell(
                onTap: () async {
                  final url = Uri.parse(
                      "https://amoy.polygonscan.com/tx/${tx.hash}");
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text("View on Explorer",
                    style: TextStyle(color: Colors.blue, fontSize: 10)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ─── Wallet Options Bottom Sheet ─────────────────────────
  void _showWalletOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet),
                const SizedBox(width: 10),
                Expanded(child: Text(_shorten(_address!))),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Text("Verified",
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildActionButton(
              text: "Switch Account",
              color: Colors.blue,
              onTap: () {
                Navigator.pop(context);
                _confirmAction(
                    title: "Switch Account?", onConfirm: _switchAccount);
              },
            ),
            const SizedBox(height: 10),
            _buildActionButton(
              text: "Disconnect Wallet",
              color: Colors.red,
              onTap: () {
                Navigator.pop(context);
                _confirmAction(
                    title: "Disconnect Wallet?", onConfirm: _disconnect);
              },
            ),
            const SizedBox(height: 10),
            _buildActionButton(
              text: "Remove Wallet",
              color: Colors.red,
              onTap: () {
                Navigator.pop(context);
                _confirmAction(
                    title: "Remove Wallet permanently?",
                    onConfirm: _removeWallet);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String text,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}