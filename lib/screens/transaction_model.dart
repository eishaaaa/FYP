class TransactionModel {
  final String type; // sent, received, contract
  final String to;
  final String value;
  final String gas;
  final String time;
  final bool success;

  TransactionModel({
    required this.type,
    required this.to,
    required this.value,
    required this.gas,
    required this.time,
    required this.success,
  });
}