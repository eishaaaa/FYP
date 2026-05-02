enum TransactionStatus {
  pendingApproval,
  approved,
  active,
  returnPending,
  recallPending,
  completed,
  disputed,
}

class TransactionModel {
  final String type; // "sent", "received", "asset_upload", "asset_purchase", "rental"
  final String to; // recipient or asset id
  final String value; // POL amount
  final String gas;
  final String time; // unix timestamp
  final bool success;
  final String hash;
  final String title;

  // Rental specific fields
  final TransactionStatus status;
  final double depositAmount; // PKR
  final double rentalFee; // PKR per month
  final DateTime? startDate;
  final DateTime? expiryDate;
  final int leaseMonths; // default 6 months

  TransactionModel({
    required this.type,
    required this.to,
    required this.value,
    required this.gas,
    required this.time,
    required this.success,
    required this.hash,
    required this.title,
    this.status = TransactionStatus.completed,
    this.depositAmount = 0.0,
    this.rentalFee = 0.0,
    this.startDate,
    this.expiryDate,
    this.leaseMonths = 6,
  });
}
