import 'package:flutter/material.dart';
import 'package:web3dart/web3dart.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../blockchain/wallet_service.dart';
import '../blockchain/contract_config.dart';
import '../blockchain/explorer_service.dart';
import '../screens/transaction_model.dart';

final ExplorerService _explorer = ExplorerService();

List<TransactionModel> _transactions = [];
int _txCount = 0;
int _nftCount = 0; // placeholder (real NFT needs contract)


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

  @override
  void initState() {
    super.initState();
    _client = Web3Client(ContractConfig.rpcUrl, http.Client());
    _checkExistingConnection();
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
        await _loadBalance();
      }

      setState(() {});
    }
  }

  // ===============================
  // CONNECT WALLET
  // ===============================
  Future<void> _connect() async {
    setState(() => _loading = true);

    final address = await _walletService.connect(context);

    if (address == null) {
      setState(() => _loading = false);
      return;
    }

    final user = _auth.currentUser;
    if (user == null) return;

    await _saveWalletToFirestore(user.uid, address);

    _address = address;
    await _loadBalance();

    setState(() => _loading = false);
  }

  // ===============================
  // DISCONNECT
  // ===============================
  Future<void> _disconnect() async {
    await _walletService.disconnect();

    setState(() {
      _address = null;
      _balance = 0.0;
    });
  }

  // ===============================
  // SWITCH ACCOUNT
  // ===============================
  Future<void> _switchAccount() async {
    await _walletService.disconnect();
    await _connect();
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

    await _loadBalance(); // ✅ keep original

    final txs = await _explorer.getTransactions(_address!);

    _transactions = txs;
    _txCount = txs.length;

    setState(() => _loading = false);
  }

  String _shorten(String addr) =>
      "${addr.substring(0, 6)}...${addr.substring(addr.length - 4)}";

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
  // UI
  // ===============================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Wallet")),
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

          const Text("\$12.34",
              style: TextStyle(color: Colors.white70)), // optional
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
    return Column(
      children: _transactions.map((tx) {
        return ListTile(
          leading: Icon(
            tx.type == "sent"
                ? Icons.arrow_upward
                : Icons.arrow_downward,
            color: tx.type == "sent" ? Colors.red : Colors.green,
          ),
          title: Text(
            tx.type == "sent"
                ? "Sent ${tx.value} POL"
                : "Received",
          ),
          subtitle: Text(_shorten(tx.to)),
          trailing: Text(tx.time),
        );
      }).toList(),
    );
  }
  // ===============================
  // INFO CARD
  // ===============================
  Widget _buildInfoCard() {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _shorten(_address!),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _disconnect,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text("Disconnect"),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _switchAccount,
              child: const Text("Switch Account"),
            ),
          ],
        ),
      ),
    );
  }
}