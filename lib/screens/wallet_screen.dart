import 'package:flutter/material.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../blockchain/wallet_service.dart';
import '../blockchain/contract_config.dart';
import '../blockchain/explorer_service.dart';
import '../screens/transaction_model.dart';
import 'package:url_launcher/url_launcher.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final SimpleWalletService _walletService = SimpleWalletService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late Web3Client _client;

  String? _address;
  String? _userName;
  double _balance = 0.0;
  bool _loading = false;

  final ExplorerService _explorer = ExplorerService();

  List<TransactionModel> _transactions = [];
  int _txCount = 0;
  int _nftCount = 0; // placeholder (real NFT needs contract)

  @override
  void initState() {
    super.initState();
    _client = Web3Client(ContractConfig.rpcUrl, http.Client());
    _checkExistingConnection();
  }
   // pol to usd conversion
  double _convertPolToUsd(double polAmount) {
    // Example fixed rate: 1 POL = 1.23 USD
    const double polToUsdRate = 1.23;
    return polAmount * polToUsdRate;
  }
  // ===============================
  // LOAD USER + WALLET FROM FIREBASE
  // ===============================
  Future<void> _checkExistingConnection() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc =
    await _firestore.collection("users").doc(user.uid).get();

    if (doc.exists) {
      final data = doc.data();

      _address = data?["walletAddress"];
      _userName = data?["name"]; // 🔥 fetch user name

      if (_address != null) {
        await _loadAllData();
      }

      setState(() {});
    }
  }

  // ===============================
  // CONNECT WALLET
  // ===============================
  Future<void> _connect() async {
    setState(() => _loading = true);

    try {
      final address = await _walletService.connect(context);

      if (address == null) {
        setState(() => _loading = false);
        return;
      }

      final user = _auth.currentUser;
      if (user == null) {
        setState(() => _loading = false);
        return;
      }

      await _saveWalletToFirestore(user.uid, address);

      if (!mounted) return;

      setState(() {
        _address = address;
      });

      await _loadAllData();
    } catch (e) {
      debugPrint("Connect error: $e");
    }

    if (!mounted) return;

    setState(() => _loading = false);
  }

  // ===============================
  // DISCONNECT
  // ===============================
  Future<void> _disconnect() async {
    setState(() => _loading = true);

    try {
      await _walletService.disconnect();

      setState(() {
        _address = null;
        _balance = 0.0;
        _transactions.clear();
        _txCount = 0;
        _nftCount = 0;
      });
    } catch (e) {
      debugPrint("Disconnect error: $e");
    }

    setState(() => _loading = false);
  }

  // ===============================
  // SWITCH ACCOUNT
  // ===============================
  Future<void> _switchAccount() async {
    setState(() => _loading = true);

    try {
      await _walletService.disconnect();

      final newAddress = await _walletService.connect(context);

      if (newAddress == null) {
        setState(() => _loading = false);
        return;
      }

      final user = _auth.currentUser;
      if (user != null) {
        await _saveWalletToFirestore(user.uid, newAddress);
      }

      setState(() {
        _address = newAddress;
      });

      await _loadAllData();
    } catch (e) {
      debugPrint("Switch error: $e");
    }

    setState(() => _loading = false);
  }

  // ===============================
  // LOAD REAL BALANCE
  // ===============================
  Future<void> _loadBalance() async {
    if (_address == null) return;

    try {
      final ethAddress = EthereumAddress.fromHex(_address!);
      final balanceWei = await _client.getBalance(ethAddress);

      final balanceInEther =
      balanceWei.getValueInUnit(EtherUnit.ether);

      _balance = balanceInEther;
    } catch (e) {
      debugPrint("Balance error: $e");
    }
  }

  // ===============================
  // LOAD Data
  // ===============================
  Future<void> _loadAllData() async {
    if (_address == null) return;

    setState(() => _loading = true);

    try {
      await _loadBalance();

      // ✅ Fetch from Polygonscan
      final normalTxs = await _explorer.getTransactions(_address!);
      final nftTxs = await _explorer.getNFTTransactions(_address!);

      // ✅ Fetch from Firestore
      final user = _auth.currentUser;
      List<TransactionModel> firestoreTxs = [];

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

      // ✅ Merge all three sources
      final allTxs = [...normalTxs, ...nftTxs, ...firestoreTxs];

      // ✅ Deduplicate by hash (in case Polygonscan + Firestore overlap)
      final seen = <String>{};
      final dedupedTxs = allTxs.where((tx) {
        if (tx.hash.isEmpty || seen.contains(tx.hash)) return false;
        seen.add(tx.hash);
        return true;
      }).toList();

      // ✅ Sort by time descending
      dedupedTxs.sort((a, b) =>
          int.parse(b.time).compareTo(int.parse(a.time)));

      // ✅ Update state
      setState(() {
        _transactions = dedupedTxs.take(15).toList();
        _txCount = normalTxs.length;
        _nftCount = nftTxs.length + firestoreTxs.where((tx) => tx.type == "nft").length;
      });

      if (allTxs.isEmpty) {
        debugPrint("No transactions found");
      }

    } catch (e) {
      debugPrint("Load data error: $e");
      setState(() {
        _transactions = [];
        _txCount = 0;
        _nftCount = 0;
      });
    }

    setState(() => _loading = false);
  }

  String _shorten(String addr) {
    if (addr.isEmpty) return "N/A";
    if (addr.length <= 10) return addr; // return as-is if too short to shorten
    return "${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}";
  }

  // ===============================
  // SAVE WALLET IN FIREBASE
  // ===============================
  Future<void> _saveWalletToFirestore(
      String uid, String newAddress) async {
    final userRef = _firestore.collection("users").doc(uid);

    final doc = await userRef.get();
    final oldAddress = doc.data()?["walletAddress"];

    if (oldAddress != newAddress) {
      await userRef.collection("walletHistory").add({
        "oldWallet": oldAddress,
        "newWallet": newAddress,
        "changedAt": FieldValue.serverTimestamp(),
      });

      await userRef.update({
        "walletAddress": newAddress,
      });
    }
  }
  // ===============================
  // remove WALLET IN FIREBASE
  // ===============================
  Future<void> _removeWallet() async {
    setState(() => _loading = true);

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _walletService.disconnect();

      await _firestore.collection("users").doc(user.uid).update({
        "walletAddress": FieldValue.delete(),
      });

      setState(() {
        _address = null;
        _balance = 0.0;
        _transactions.clear();
        _txCount = 0;
        _nftCount = 0;
      });
    } catch (e) {
      debugPrint("Remove error: $e");
    }

    setState(() => _loading = false);
  }

  // ===============================
  // UI
  // ===============================
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
          : _address == null
          ? _buildConnectView()
          : _buildWalletView(),
    );
  }

  Widget _buildConnectView() {
    return Center(
      child: ElevatedButton.icon(
        onPressed: _connect,
        icon: const Icon(Icons.account_balance_wallet),
        label: const Text("Connect Wallet"),
      ),
    );
  }

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

  // ===============================
  // BALANCE CARD
  // ===============================
  Widget _buildBalanceCard() {
    final usdBalance = _convertPolToUsd(_balance);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Colors.deepPurple, Colors.blue],
        ),
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
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text("Verified",
                    style: TextStyle(color: Colors.white, fontSize: 12)),
              )
            ],
          ),

          const SizedBox(height: 10),

          Text(
            _shorten(_address!),
            style: const TextStyle(color: Colors.white70),
          ),

          const SizedBox(height: 16),

          Text(
            "${_balance.toStringAsFixed(4)} POL",
            style: const TextStyle(
                fontSize: 28,
                color: Colors.white,
                fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 6),

          Text(
            "\$${usdBalance.toStringAsFixed(2)}",
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  // ===============================
  // Build Stats
  // ===============================
  Widget _buildStats() {
    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Column(
              children: [
                Text("$_txCount",
                    style: const TextStyle(fontSize: 18)),
                const Text("Transactions"),
              ],
            ),
            Column(
              children: [
                Text("$_nftCount",
                    style: const TextStyle(fontSize: 18)),
                const Text("NFTs"),
              ],
            ),
          ],
        ),
      ),
    );
  }
  // ===============================
  // build Transactions
  // ===============================
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
        final time = DateTime.fromMillisecondsSinceEpoch(int.parse(tx.time) * 1000);
        final diff = DateTime.now().difference(time);
        String formattedTime = diff.inMinutes < 60
            ? "${diff.inMinutes} min ago"
            : diff.inHours < 24
            ? "${diff.inHours} hr ago"
            : "${diff.inDays} d ago";

        return ListTile(
          leading: Icon(
            tx.type == "sent" ? Icons.arrow_upward
                : tx.type == "nft" ? Icons.image
                : tx.type == "contract" ? Icons.code   // ← ADD THIS
                : Icons.arrow_downward,
            color: tx.type == "sent" ? Colors.red
                : tx.type == "nft" ? Colors.blue
                : tx.type == "contract" ? Colors.orange  // ← ADD THIS
                : Colors.green,
          ),
          title: Text(
            tx.type == "sent" ? "Sent ${tx.value} POL"
                : tx.type == "nft" ? tx.title
                : tx.type == "contract" ? "Contract Interaction"  // ← ADD THIS
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
                  final url = Uri.parse("https://amoy.polygonscan.com/tx/${tx.hash}");

                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text(
                  "View on Explorer",
                  style: TextStyle(color: Colors.blue, fontSize: 10),
                ),
              )
            ],
          ),
        );
      }).toList(),
    );
  }

  // ===============================
  // wallet options
  // ===============================
  void _showWalletOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Wallet Info
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_shorten(_address!)),
                  ),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text("Verified",
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                  )
                ],
              ),

              const SizedBox(height: 20),

              // Switch Account
              _buildActionButton(
                text: "Switch Account",
                color: Colors.blue,
                onTap: () {
                  Navigator.pop(context);
                  _confirmAction(
                    title: "Switch Account?",
                    onConfirm: _switchAccount,
                  );
                },
              ),

              const SizedBox(height: 10),

              // Disconnect
              _buildActionButton(
                text: "Disconnect Wallet",
                color: Colors.red,
                onTap: () {
                  Navigator.pop(context);
                  _confirmAction(
                    title: "Disconnect Wallet?",
                    onConfirm: _disconnect,
                  );
                },
              ),

              const SizedBox(height: 10),

              // Remove Wallet
              _buildActionButton(
                text: "Remove Wallet",
                color: Colors.red,
                onTap: () {
                  Navigator.pop(context);
                  _confirmAction(
                    title: "Remove Wallet permanently?",
                    onConfirm: _removeWallet,
                  );
                },
              ),
            ],
          ),
        );
      },
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(text),
      ),
    );
  }
  // ===============================
  // Confirm Action of wallet settings buttons
  // ===============================
  void _confirmAction({
    required String title,
    required Future<void> Function() onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
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
        );
      },
    );
  }
}