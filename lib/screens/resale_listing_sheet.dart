// lib/screens/resale_listing_sheet.dart
//
// ResaleListingSheet – modal bottom sheet that lets a buyer list their
// already-owned asset for resale.  Shows:
//   • Asset title + thumbnail
//   • Price input field
//   • Description input field
//   • Platform-fee breakdown (2 %)
//   • "Your receive" net amount
//   • NFT transparency notice
//   • Confirm / Cancel actions

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/resale_service.dart';
import 'shared_screens.dart'; // for buildAssetImage

class ResaleListingSheet extends StatefulWidget {
  final String              assetId;
  final Map<String, dynamic> assetData;   // must contain 'title', 'images', 'price'

  const ResaleListingSheet({
    super.key,
    required this.assetId,
    required this.assetData,
  });

  // ── Convenience helper: show the sheet and await result ──────────────────
  static Future<bool> show(
      BuildContext context, {
        required String              assetId,
        required Map<String, dynamic> assetData,
      }) async {
    final result = await showModalBottomSheet<bool>(
      context           : context,
      isScrollControlled: true,
      backgroundColor   : Colors.transparent,
      builder: (_) => ResaleListingSheet(assetId: assetId, assetData: assetData),
    );
    return result == true;
  }

  @override
  State<ResaleListingSheet> createState() => _ResaleListingSheetState();
}

class _ResaleListingSheetState extends State<ResaleListingSheet> {
  final _priceCtrl       = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _resaleSvc = ResaleService();
  bool   _submitting = false;
  num    _parsedPrice = 0;

  static const double _platformFeeRate = 0.02; // 2 %

  num get _platformFee   => (_parsedPrice * _platformFeeRate);
  num get _netReceivable => (_parsedPrice - _platformFee);

  void _onPriceChanged(String v) {
    setState(() => _parsedPrice = num.tryParse(v.replaceAll(',', '')) ?? 0);
  }

  Future<void> _confirm() async {
    final price = num.tryParse(_priceCtrl.text.replaceAll(',', ''));
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid price.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await _resaleSvc.listForResale(
        assetId    : widget.assetId,
        price      : price,
        description: _descriptionCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to list: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imgList  = widget.assetData['images'] as List?;
    final firstImg = (imgList != null && imgList.isNotEmpty && imgList.first is String)
        ? imgList.first as String
        : null;
    final title  = widget.assetData['title'] as String? ?? 'Asset';
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color        : Colors.white,
          borderRadius : BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── drag handle ──────────────────────────────────────────
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color        : Colors.grey[300],
                    borderRadius : BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Title ────────────────────────────────────────────────
              const Text(
                'List for Resale',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Set your asking price. Buyers will see the full NFT transfer history.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),

              // ── Asset summary card ───────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color        : Colors.grey[50],
                  borderRadius : BorderRadius.circular(12),
                  border       : Border.all(color: Colors.grey[200]!),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: buildAssetImage(firstImg, width: 52, height: 52),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(Icons.verified, size: 13, color: Colors.green[700]),
                              const SizedBox(width: 4),
                              Text('NFT Verified  •  Token ${widget.assetData['blockchainTokenId'] ?? '—'}',
                                  style: TextStyle(fontSize: 11, color: Colors.green[700])),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── Price input ──────────────────────────────────────────
              const Text('Your Asking Price',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller    : _priceCtrl,
                keyboardType  : const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d,.]'))],
                onChanged     : _onPriceChanged,
                decoration: InputDecoration(
                  prefixText     : 'PKR  ',
                  hintText       : '0',
                  border         : OutlineInputBorder(
                    borderRadius : BorderRadius.circular(12),
                    borderSide   : BorderSide(color: Colors.green[700]!),
                  ),
                  focusedBorder  : OutlineInputBorder(
                    borderRadius : BorderRadius.circular(12),
                    borderSide   : BorderSide(color: Colors.green[700]!, width: 2),
                  ),
                  contentPadding : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),

              // ── Description input ────────────────────────────────────
              const Text('Description (optional)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              TextField(
                controller  : _descriptionCtrl,
                keyboardType: TextInputType.multiline,
                maxLines    : 4,
                maxLength   : 500,
                decoration  : InputDecoration(
                  hintText       : 'Describe the condition, features, or any other details buyers should know…',
                  hintMaxLines   : 3,
                  border         : OutlineInputBorder(
                    borderRadius : BorderRadius.circular(12),
                    borderSide   : BorderSide(color: Colors.green[700]!),
                  ),
                  focusedBorder  : OutlineInputBorder(
                    borderRadius : BorderRadius.circular(12),
                    borderSide   : BorderSide(color: Colors.green[700]!, width: 2),
                  ),
                  contentPadding : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),

              // ── Fee breakdown ────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color        : Colors.grey[50],
                  borderRadius : BorderRadius.circular(10),
                  border       : Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  children: [
                    _feeRow('Asking price', 'PKR ${_fmt(_parsedPrice)}'),
                    const Divider(height: 14),
                    _feeRow('Platform fee (2%)', '− PKR ${_fmt(_platformFee)}',
                        valueColor: Colors.red[700]),
                    const Divider(height: 14),
                    _feeRow('You receive', 'PKR ${_fmt(_netReceivable)}',
                        isBold: true, valueColor: Colors.green[700]),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── NFT transparency notice ──────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color        : Colors.blue[50],
                  borderRadius : BorderRadius.circular(10),
                  border       : Border.all(color: Colors.blue[100]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.link, size: 16, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'The full NFT transfer history will be visible to all buyers for complete transparency and trust.',
                        style: TextStyle(fontSize: 12, color: Colors.blue[800]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Action buttons ───────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _confirm,
                  icon : _submitting
                      ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sell_outlined),
                  label: Text(_submitting ? 'Listing...' : 'List for Resale'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor : Colors.green[700],
                    foregroundColor : Colors.white,
                    shape           : RoundedRectangleBorder(
                      borderRadius : BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  onPressed: _submitting ? null : () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _feeRow(String label, String value,
      {bool isBold = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
              color    : isBold ? Colors.black : Colors.grey[700],
            )),
        Text(value,
            style: TextStyle(
              fontSize   : 13,
              fontWeight : isBold ? FontWeight.bold : FontWeight.normal,
              color      : valueColor ?? Colors.black,
            )),
      ],
    );
  }

  String _fmt(num v) {
    if (v == 0) return '0';
    // Show integers without decimal, otherwise 2dp
    return v == v.truncate()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(2);
  }
}