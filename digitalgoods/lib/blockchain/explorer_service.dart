// lib/blockchain/explorer_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../screens/transaction_model.dart';

class ExplorerService {
  // ✅ Amoy Testnet Endpoint
  static const String baseUrl = "https://api-amoy.polygonscan.com/api";

  // Polygonscan API key here
  static const String _apiKey = "IWEN41KGG1YAV457I4HD34GFXCTQ7RNQSJ";
  static const String polygonscanApiKey = String.fromEnvironment('IWEN41KGG1YAV457I4HD34GFXCTQ7RNQSJ');
  Future<List<TransactionModel>> getTransactions(String address) async {
    try {
      final url =
          "$baseUrl?module=account&action=txlist&address=$address&sort=desc&apikey=$_apiKey";

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        print("API Error: ${response.statusCode}");
        return [];
      }

      final data = json.decode(response.body);

      if (data["status"] != "1") {
        print("No transactions or API issue: ${data["message"]}");
        return [];
      }

      final List list = data["result"];

      return list.take(15).map((tx) {
        final from = tx["from"].toLowerCase();
        final isSent = from == address.toLowerCase();

        // 🔥 Detect contract interaction
        String type;
        if (tx["input"] != "0x") {
          type = "contract";
        } else {
          type = isSent ? "sent" : "received";
        }

        // ✅ Value conversion
        final valueWei = BigInt.parse(tx["value"]);
        final value =
        (valueWei / BigInt.from(10).pow(18)).toStringAsFixed(4);

        // ✅ Gas fee (gas * gasPrice)
        final gas = BigInt.parse(tx["gas"]);
        final gasPrice = BigInt.parse(tx["gasPrice"]);
        final gasFee =
        (gas * gasPrice / BigInt.from(10).pow(18)).toStringAsFixed(6);

        return TransactionModel(
          type: type,
          to: isSent ? tx["to"] : tx["from"],
          title: "POL Transfer",
          value: value,
          gas: gasFee,
          time: tx["timeStamp"],
          success: tx["isError"] == "0",
          hash: tx["hash"],
        );
      }).toList();
    } catch (e) {
      print("Explorer error: $e");
      return [];
    }
  }

  Future<List<TransactionModel>> getNFTTransactions(String address) async {
    try {
      final url =
          "$baseUrl?module=account&action=tokennfttx&address=$address&sort=desc&apikey=$_apiKey";

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return [];

      final data = json.decode(response.body);

      if (data["status"] != "1") {
        print("No NFT transactions or API issue: ${data["message"]}");
        return [];
      }

      final List list = data["result"];

      return list.take(10).map((tx) {
        final isReceived =
            tx["to"].toLowerCase() == address.toLowerCase();

        return TransactionModel(
          type: "nft",
          to: isReceived ? tx["from"] : tx["to"],
          title: tx["tokenName"] ?? "NFT Asset",
          value: tx["tokenName"] ?? "NFT",
          gas: "0",
          time: tx["timeStamp"],
          success: true,
          hash: tx["hash"],
        );
      }).toList();
    } catch (e) {
      print("NFT error: $e");
      return [];
    }
  }
}