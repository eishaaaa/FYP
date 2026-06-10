import 'package:flutter/material.dart';
import '../theme.dart';
import '../blockchain/blockchain_service.dart';

class TransferWidget extends StatefulWidget {
  final String assetId;
  final String? tokenId; // For electronics
  final String? propertyId; // For land
  final String initialRecipientAddress;
  final int? maxFractions; // For land
  final bool isLand;
  final VoidCallback? onSuccess;

  const TransferWidget({
    super.key,
    required this.assetId,
    this.tokenId,
    this.propertyId,
    required this.initialRecipientAddress,
    this.maxFractions,
    required this.isLand,
    this.onSuccess,
  });

  @override
  State<TransferWidget> createState() => _TransferWidgetState();
}

class _TransferWidgetState extends State<TransferWidget> {
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();
  bool _isProcessing = false;
  final _blockchainService = BlockchainServiceEnhanced();

  @override
  void initState() {
    super.initState();
    _recipientController.text = widget.initialRecipientAddress;
    if (!widget.isLand) {
      _amountController.text = "1"; // NFTs are always 1
    }
  }

  Future<void> _handleTransfer() async {
    final recipient = _recipientController.text.trim();
    final amountStr = _amountController.text.trim();

    if (recipient.isEmpty) {
      _showError("Recipient address is required");
      return;
    }

    int amount = 1;
    if (widget.isLand) {
      amount = int.tryParse(amountStr) ?? 0;
      if (amount <= 0) {
        _showError("Valid amount is required");
        return;
      }
      if (widget.maxFractions != null && amount > widget.maxFractions!) {
        _showError("You only own ${widget.maxFractions} fractions");
        return;
      }
    }

    setState(() => _isProcessing = true);

    try {
      await _blockchainService.init();
      String? txHash;

      if (widget.isLand) {
        txHash = await _blockchainService.transferLandFraction(
          toAddress: recipient,
          propertyId: int.parse(widget.propertyId!),
          amount: amount,
        );
      } else {
        txHash = await _blockchainService.transferElectronics(
          toAddress: recipient,
          tokenId: int.parse(widget.tokenId!),
        );
      }

      if (txHash != null) {
        final success = await _blockchainService.waitForConfirmation(txHash);
        if (success) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Transfer Successful!"), backgroundColor: AppTheme.accent),
            );
            widget.onSuccess?.call();
            Navigator.pop(context);
          }
        } else {
          _showError("Transaction failed on blockchain");
        }
      } else {
        _showError("Transaction rejected or failed");
      }
    } catch (e) {
      _showError("Error: $e");
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.roundedBox(color: Colors.white),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isLand ? "Transfer Land Fractions" : "Transfer Electronics NFT",
            style: AppTheme.heading(18),
          ),
          const SizedBox(height: 16),
          Text("Recipient Address", style: AppTheme.body(14, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _recipientController,
            decoration: InputDecoration(
              hintText: "0x...",
              fillColor: AppTheme.background,
              hintStyle: AppTheme.body(14, color: AppTheme.textMid),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.primaryStart.withOpacity(0.2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.primaryStart.withOpacity(0.1)),
              ),
            ),
          ),
          if (widget.isLand) ...[
            const SizedBox(height: 16),
            Text("Amount of Fractions", style: AppTheme.body(14, weight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: "e.g. 10",
                helperText: widget.maxFractions != null ? "You own ${widget.maxFractions} fractions" : null,
                hintStyle: AppTheme.body(14, color: AppTheme.textMid),
                helperStyle: AppTheme.body(12, color: AppTheme.primaryStart),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.primaryStart.withOpacity(0.2)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.primaryStart.withOpacity(0.1)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _handleTransfer,
              style: AppTheme.elevatedButtonStyle(),
              child: _isProcessing
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text("Confirm Transfer", style: AppTheme.button(16)),
            ),
          ),
        ],
      ),
    );
  }
}
