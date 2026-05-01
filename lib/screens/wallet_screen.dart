import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../theme.dart';
import 'package:showcaseview/showcaseview.dart';

// ─── Design Tokens ──────────────────────────────────────────
class _C {
  static const bg         = AppTheme.background;
  static const surface    = Colors.white;
  static const primary    = AppTheme.primaryStart;
  static const primaryDk  = AppTheme.primaryStartDark;
  static const accent     = AppTheme.accent;
  static const textDark   = AppTheme.textPrimary;
  static const textMid    = AppTheme.textSecondary;
  static const textLight  = AppTheme.textSecondary;
  static const sent       = AppTheme.error;
  static const received   = AppTheme.primaryStart;
  static const nft        = AppTheme.accent;
  static const contract   = Colors.orange;
  static final cardBorder = AppTheme.primaryStart.withOpacity(0.05);
  static final shimmer    = AppTheme.primaryStart.withOpacity(0.05);
}

// ─── Shadows ────────────────────────────────────────────────
BoxDecoration _card({double radius = 20}) => BoxDecoration(
  color: _C.surface,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: _C.cardBorder, width: 1),
  boxShadow: [
    BoxShadow(color: AppTheme.primaryStart.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4)),
  ],
);

// ════════════════════════════════════════════════════════════
// WIDGET
// ════════════════════════════════════════════════════════════
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> with SingleTickerProviderStateMixin {
  // ─── Services ───────────────────────────────────────────
  final SimpleWalletService _walletService = SimpleWalletService();
  final FirebaseAuth       _auth           = FirebaseAuth.instance;
  final FirebaseFirestore  _firestore      = FirebaseFirestore.instance;
  final ExplorerService    _explorer       = ExplorerService();
  late  Web3Client         _client;

  // ─── State ──────────────────────────────────────────────
  String? _address;
  String? _userName;
  double  _balance    = 0.0;
  bool    _connecting = false;
  bool    _loading    = false;
  bool    _hideBalance = false;
  List<TransactionModel> _transactions = [];
  int     _txCount  = 0;
  int     _nftCount = 0;

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  // ─── Amoy network info ──────────────────────────────────
  static final _amoyNetwork = ReownAppKitModalNetworkInfo(
    name:         'Polygon Amoy',
    chainId:      '80002',
    currency:     'MATIC',
    rpcUrl:       ContractConfig.rpcUrl,
    explorerUrl:  'https://amoy.polygonscan.com',
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

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.8, end: 1.0).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_walletService.isInitialized) await _walletService.init(context);
      _walletService.appKitModal.addListener(_onWalletNotify);
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
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _onWalletNotify() {
    if (!mounted) return;
    setState(() {
      if (!_walletService.appKitModal.isConnected || !_walletService.isConnected) {
        _address = null; _balance = 0.0;
      } else {
        _address = _walletService.address;
      }
    });
  }

  // ════════════════════════════════════════════════════════
  // AMOY CHAIN ENFORCEMENT
  // ════════════════════════════════════════════════════════
  Future<void> _enforceAmoyNetwork() async {
    try {
      await _walletService.appKitModal.selectChain(_amoyNetwork, switchChain: true);
      debugPrint("✅ Switched to Polygon Amoy (chain 80002)");
    } catch (e) {
      debugPrint("⚠️ Could not switch to Amoy: $e");
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
    _address  = data?["walletAddress"];
    _userName = data?["name"];
    if (_address != null) await _loadAllData();
    if (mounted) setState(() {});
  }

  Future<void> _connect() async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      if (!_walletService.isInitialized) await _walletService.init(context);
      final address = await _walletService.connect(context)
          .timeout(const Duration(seconds: 25), onTimeout: () => null);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!_walletService.appKitModal.isConnected || !_walletService.isConnected || address == null) {
        throw Exception("Wallet connection failed or cancelled");
      }
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
          SnackBar(
            content: const Text("Wallet connection failed or timed out"),
            backgroundColor: _C.sent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
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
        _address = null; _balance = 0.0;
        _transactions.clear(); _txCount = 0; _nftCount = 0;
      });
    } catch (e) { debugPrint("Disconnect error: $e"); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _switchAccount() async {
    if (_loading || _connecting) return;
    setState(() => _connecting = true);
    try {
      try { await _walletService.disconnect(); } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      final newAddress = await _walletService.connect(context);
      if (newAddress == null) return;
      await _enforceAmoyNetwork();
      final user = _auth.currentUser;
      if (user != null) await _saveWalletToFirestore(user.uid, newAddress);
      if (!mounted) return;
      setState(() { _address = newAddress; _loading = true; });
      await _loadAllData();
    } catch (e) { debugPrint("Switch error: $e"); }
    finally { if (mounted) setState(() { _connecting = false; _loading = false; }); }
  }

  Future<void> _removeWallet() async {
    if (_loading || _connecting) return;
    setState(() => _loading = true);
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      await _walletService.disconnect();
      await _firestore.collection("users").doc(user.uid)
          .update({"walletAddress": FieldValue.delete()});
      setState(() {
        _address = null; _balance = 0.0;
        _transactions.clear(); _txCount = 0; _nftCount = 0;
      });
    } catch (e) { debugPrint("Remove error: $e"); }
    finally { if (mounted) setState(() => _loading = false); }
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
      final nftTxs    = await _explorer.getNFTTransactions(_address!);
      List<TransactionModel> firestoreTxs = [];
      final user = _auth.currentUser;
      if (user != null) {
        final snap = await _firestore
            .collection("users").doc(user.uid).collection("transactions")
            .orderBy("time", descending: true).limit(10).get();
        firestoreTxs = snap.docs.map((doc) {
          final d = doc.data();
          return TransactionModel(
            type: d["type"] ?? "sent", title: d["title"] ?? "Transaction",
            to: d["to"] ?? "", value: d["value"]?.toString() ?? "0",
            gas: d["gas"]?.toString() ?? "0", time: d["time"]?.toString() ?? "0",
            success: true, hash: d["hash"] ?? "",
          );
        }).toList();
      }
      final seen = <String>{};
      final dedupedTxs = [...normalTxs, ...nftTxs, ...firestoreTxs]
          .where((tx) => tx.hash.isNotEmpty && seen.add(tx.hash)).toList()
        ..sort((a, b) => int.parse(b.time).compareTo(int.parse(a.time)));
      setState(() {
        _transactions = dedupedTxs.take(15).toList();
        _txCount  = normalTxs.length;
        _nftCount = nftTxs.length + firestoreTxs.where((tx) => tx.type == "nft").length;
      });
    } catch (e) {
      debugPrint("Load data error: $e");
      setState(() { _transactions = []; _txCount = 0; _nftCount = 0; });
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
    } catch (e) { debugPrint("Balance error: $e"); }
  }

  // ════════════════════════════════════════════════════════
  // FIRESTORE HELPERS
  // ════════════════════════════════════════════════════════
  Future<void> _saveWalletToFirestore(String uid, String newAddress) async {
    final userRef  = _firestore.collection("users").doc(uid);
    final doc      = await userRef.get();
    final oldAddress = doc.data()?["walletAddress"];
    await userRef.set({"walletAddress": newAddress}, SetOptions(merge: true));
    if (oldAddress != null && oldAddress != newAddress) {
      await userRef.collection("walletHistory").add({
        "oldWallet": oldAddress, "newWallet": newAddress,
        "changedAt": FieldValue.serverTimestamp(),
      });
    }
  }

  // ════════════════════════════════════════════════════════
  // UI HELPERS
  // ════════════════════════════════════════════════════════
  double _convertPolToPkr(double pol) => pol * 280.0;

  String _shorten(String addr) {
    if (addr.isEmpty) return "N/A";
    if (addr.length <= 10) return addr;
    return "${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}";
  }

  String _formatTime(String rawTime) {
    final time = DateTime.fromMillisecondsSinceEpoch(int.parse(rawTime) * 1000);
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return "${diff.inMinutes}m ago";
    if (diff.inHours   < 24) return "${diff.inHours}h ago";
    return "${diff.inDays}d ago";
  }

  void _confirmAction({required String title, required Future<void> Function() onConfirm}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: AppTheme.heading(20)),
        content: const Text("Are you sure you want to continue?", style: TextStyle(color: AppTheme.textMid)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel", style: TextStyle(color: AppTheme.textMid))),
          ElevatedButton(
            onPressed: () async { Navigator.pop(ctx); await onConfirm(); },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryStart, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text("Confirm"),
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
      backgroundColor: _C.bg,
      appBar: _buildAppBar(),
      body: _loading
          ? _buildSkeleton()
          : !_isWalletReady
          ? _buildConnectView()
          : _buildWalletView(),
    );
  }

  // ─── AppBar ──────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text("Wallet", style: AppTheme.heading(20, color: Colors.white)),
      flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.primaryGradient)),
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      actions: [
        if (_address != null)
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: _showWalletOptions,
          ),
      ],
    );
  }

  // ─── Loading Skeleton ────────────────────────────────────
  Widget _buildSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _shimmerBox(height: 200, radius: 24),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _shimmerBox(height: 90)),
          const SizedBox(width: 12),
          Expanded(child: _shimmerBox(height: 90)),
        ]),
        const SizedBox(height: 16),
        _shimmerBox(height: 60),
        const SizedBox(height: 8),
        _shimmerBox(height: 60),
        const SizedBox(height: 8),
        _shimmerBox(height: 60),
      ],
    );
  }

  Widget _shimmerBox({double height = 80, double radius = 16}) {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, __) => Opacity(
        opacity: _pulseAnim.value,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: _C.shimmer,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
    );
  }

  // ─── Connect View ────────────────────────────────────────
  Widget _buildConnectView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon container
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                color: _C.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.account_balance_wallet_outlined,
                  size: 48, color: _C.primary),
            ),
            const SizedBox(height: 28),
            Text(
              "Connect your wallet",
              style: AppTheme.heading(22),
            ),
            const SizedBox(height: 10),
            Text(
              "Link a Web3 wallet to view your balance, NFTs and transactions.",
              textAlign: TextAlign.center,
              style: AppTheme.body(14, color: _C.textMid),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_connecting || _loading) ? null : _connect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _C.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _C.primary.withOpacity(0.5),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: _connecting
                    ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
                    : const Icon(Icons.account_balance_wallet, size: 20),
                label: Text(
                  _connecting ? "Opening wallet…" : "Connect Wallet",
                  style: AppTheme.button(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Wallet View ─────────────────────────────────────────
  Widget _buildWalletView() {
    return RefreshIndicator(
      color: _C.primary,
      onRefresh: _loadAllData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          _buildBalanceCard(),
          const SizedBox(height: 16),
          _buildStatsRow(),
          const SizedBox(height: 24),
          _buildTransactions(),
        ],
      ),
    );
  }

  // ─── Balance Card ────────────────────────────────────────
  Widget _buildBalanceCard() {
    final pkr = _convertPolToPkr(_balance);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: AppTheme.primaryGradient,
        boxShadow: [
          BoxShadow(color: _C.primary.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User row
          Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _userName ?? "User",
                      style: AppTheme.heading(15, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _address ?? ""));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text("Address copied"),
                            backgroundColor: Colors.black87,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 1),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        );
                      },
                      child: Row(
                        children: [
                          Text(
                            _shorten(_address ?? ""),
                            style: AppTheme.body(12, color: Colors.white.withOpacity(0.8)),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.copy, size: 12, color: Colors.white.withOpacity(0.7)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Verified badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified, size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text("Verified", style: AppTheme.heading(11, color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),
          Text(
            "TOTAL BALANCE",
            style: AppTheme.heading(11, color: Colors.white60).copyWith(letterSpacing: 1.4),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  _hideBalance ? "••••••• POL" : "${_balance.toStringAsFixed(4)} POL",
                  style: AppTheme.heading(30, color: Colors.white).copyWith(letterSpacing: -0.8),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _hideBalance = !_hideBalance),
                child: Icon(
                  _hideBalance ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white70, size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "≈ ₨${pkr.toStringAsFixed(2)} PKR",
            style: AppTheme.body(13, color: Colors.white70),
          ),

          const SizedBox(height: 20),

          // Network pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 7, color: Colors.white),
                SizedBox(width: 6),
                Text(
                  "Polygon Amoy",
                  style: AppTheme.heading(12, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Stats Row ───────────────────────────────────────────
  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(child: _buildStatCard(
          label: "Transactions",
          value: "$_txCount",
          icon: Icons.swap_horiz_rounded,
          iconColor: _C.accent,
          iconBg: _C.accent.withOpacity(0.1),
        )),
        const SizedBox(width: 12),
        Expanded(child: _buildStatCard(
          label: "NFTs",
          value: "$_nftCount",
          icon: Icons.image_rounded,
          iconColor: _C.primary,
          iconBg: _C.primary.withOpacity(0.1),
        )),
      ],
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _card(),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: AppTheme.heading(22, color: _C.textDark).copyWith(letterSpacing: -0.5)),
              Text(label, style: AppTheme.body(12, color: _C.textLight)),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Transaction List ────────────────────────────────────
  Widget _buildTransactions() {
    if (_transactions.isEmpty) {
      return Column(
        children: [
          Row(
            children: [
              Text("Recent Activity", style: AppTheme.heading(16, color: _C.textDark)),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(32),
            decoration: _card(),
            child: Column(
              children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(color: _C.shimmer, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.receipt_long_outlined, color: _C.textLight, size: 32),
                ),
                const SizedBox(height: 12),
                Text("No transactions yet", style: AppTheme.body(14, color: _C.textMid)),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Recent Activity", style: AppTheme.heading(16, color: _C.textDark)),
            Text("${_transactions.length} items", style: AppTheme.body(12, color: _C.textLight)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: _card(),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _transactions.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: _C.cardBorder, indent: 72),
            itemBuilder: (_, i) => _buildTxTile(_transactions[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildTxTile(TransactionModel tx) {
    final isSent     = tx.type == "sent";
    final isNft      = tx.type == "nft";
    final isContract = tx.type == "contract";

    final Color iconColor = isNft      ? _C.nft
        : isContract ? _C.contract
        : isSent     ? _C.sent
        :              _C.received;

    final IconData iconData = isNft      ? Icons.image_rounded
        : isContract ? Icons.code
        : isSent     ? Icons.arrow_upward_rounded
        :              Icons.arrow_downward_rounded;

    final String label = isNft      ? tx.title
        : isContract ? "Contract Interaction"
        : isSent     ? "Sent POL"
        :              "Received POL";

    final String amountStr = (isNft || isContract)
        ? (isNft ? "NFT" : "Contract")
        : "${isSent ? '−' : '+'}${tx.value} POL";

    return InkWell(
      onTap: () async {
        final url = Uri.parse("https://amoy.polygonscan.com/tx/${tx.hash}");
        if (await canLaunchUrl(url)) launchUrl(url, mode: LaunchMode.externalApplication);
      },
      borderRadius: BorderRadius.circular(0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Icon
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(iconData, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),

            // Labels
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTheme.heading(14, color: _C.textDark)),
                  const SizedBox(height: 2),
                  Text(_shorten(tx.to), style: AppTheme.body(12, color: _C.textLight)),
                ],
              ),
            ),

            // Amount + time
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amountStr,
                  style: AppTheme.heading(13, color: isNft ? _C.nft : (isContract ? _C.contract : (isSent ? _C.sent : _C.received))),
                ),
                const SizedBox(height: 3),
                Text(_formatTime(tx.time), style: AppTheme.body(11, color: AppTheme.textLight)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.open_in_new, size: 10, color: AppTheme.textLight),
                    const SizedBox(width: 2),
                    Text("Explorer", style: AppTheme.body(10, color: AppTheme.textLight)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Wallet Options Bottom Sheet ─────────────────────────
  void _showWalletOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _C.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(color: _C.cardBorder, borderRadius: BorderRadius.circular(2)),
              ),

              // Address row
              Container(
                padding: const EdgeInsets.all(16),
                decoration: _card(radius: 16),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: _C.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.account_balance_wallet, color: _C.primary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _shorten(_address!),
                        style: AppTheme.heading(14, color: _C.textDark),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _C.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.verified, size: 12, color: _C.primary),
                          const SizedBox(width: 4),
                          Text("Verified", style: AppTheme.heading(11, color: _C.primary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              _buildActionButton(text: "Switch Account", icon: Icons.swap_horiz_rounded, color: _C.accent, onTap: () {
                Navigator.pop(ctx);
                _confirmAction(title: "Switch Account?", onConfirm: _switchAccount);
              }),
              const SizedBox(height: 10),
              _buildActionButton(text: "Disconnect Wallet", icon: Icons.link_off_rounded, color: _C.sent, onTap: () {
                Navigator.pop(ctx);
                _confirmAction(title: "Disconnect Wallet?", onConfirm: _disconnect);
              }),
              const SizedBox(height: 10),
              _buildActionButton(text: "Remove Wallet", icon: Icons.delete_outline_rounded, color: Colors.red.shade700, onTap: () {
                Navigator.pop(ctx);
                _confirmAction(title: "Remove Wallet permanently?", onConfirm: _removeWallet);
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String   text,
    required IconData icon,
    required Color    color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withOpacity(0.08),
          foregroundColor: color,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: color.withOpacity(0.2)),
          ),
        ),
        icon: Icon(icon, size: 18),
        label: Text(text, style: AppTheme.button(14)),
      ),
    );
  }
}