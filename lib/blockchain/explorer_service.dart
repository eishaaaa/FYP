import 'dart:convert';
import 'package:http/http.dart' as http;
import '../screens/transaction_model.dart';

class ExplorerService {
  static const String apiKey = "YOUR_POLYGONSCAN_API_KEY";

  Future<List<TransactionModel>> getTransactions(String address) async {
    final url =
        "https://api-amoy.polygonscan.com/api?module=account&action=txlist&address=$address&sort=desc&apikey=$apiKey";

    final response = await http.get(Uri.parse(url));
    final data = json.decode(response.body);

    if (data["status"] != "1") return [];

    final List list = data["result"];

    return list.take(10).map((tx) {
      final isSent =
          tx["from"].toLowerCase() == address.toLowerCase();

      return TransactionModel(
        type: isSent ? "sent" : "received",
        to: isSent ? tx["to"] : tx["from"],
        value: tx["value"],
        gas: tx["gasPrice"],
        time: tx["timeStamp"],
        success: tx["isError"] == "0",
      );
    }).toList();
  }
}