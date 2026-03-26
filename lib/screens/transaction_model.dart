class TransactionModel {
  final String type; // "sent", "received", "asset_upload", "asset_purchase"
  final String to;   // recipient or asset id
  final String value; // POL amount
  final String gas;
  final String time; // unix timestamp
  final bool success;
  final String hash;
  final String title;

  TransactionModel({
    required this.type,
    required this.to,
    required this.value,
    required this.gas,
    required this.time,
    required this.success,
    required this.hash,
    required this.title,
  });
}
