// FILE 2: lib/screens/review_screen.dart
// =====================================================
import 'package:flutter/material.dart';
import '../blockchain/blockchain_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const Color _darkTeal = Color(0xFF00695C);
const Color _surfaceTint = Color(0xFFE7F3F1);
const Color _borderTint = Color(0xFFD7E8E4);
const Color _titleColor = Color(0xFF151726);
const Color _mutedText = Color(0xFF6D7A86);

class ReviewScreen extends StatefulWidget {
  final String assetId;
  final int? blockchainTokenId;
  final String assetType;

  const ReviewScreen({
    super.key,
    required this.assetId,
    this.blockchainTokenId,
    required this.assetType,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _reviewController = TextEditingController();
  final _blockchainService = BlockchainServiceEnhanced();
  double _rating = 5.0;
  bool _submitting = false;

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _submitReview() async {
    if (_reviewController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please write a review')));
      return;
    }

    setState(() => _submitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;

      final reviewData = {
        'assetId': widget.assetId,
        'userId': user.uid,
        'userName': user.displayName ?? 'Anonymous',
        'rating': _rating,
        'text': _reviewController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'blockchainVerified': false,
      };

      final reviewDoc = await FirebaseFirestore.instance
          .collection('reviews')
          .add(reviewData);

      if (widget.blockchainTokenId != null &&
          widget.assetType == 'electronics') {
        await _blockchainService.init();

        if (!_blockchainService.isConnected) {
          await _blockchainService.connectWallet(context);
        }

        final txHash = await _blockchainService.submitElectronicsReview(
          tokenId: widget.blockchainTokenId!,
          reviewText: _reviewController.text.trim(),
        );

        if (txHash != null) {
          await reviewDoc.update({
            'blockchainTxHash': txHash,
            'blockchainVerified': true,
          });
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Review submitted successfully!'),
          backgroundColor: _darkTeal,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Builds a single star icon based on index vs rating
  Widget _buildStar(int index) {
    final filled = index < _rating;
    return GestureDetector(
      onTap: () => setState(() => _rating = (index + 1).toDouble()),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: filled ? const Color(0xFFFFF5D6) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: filled ? const Color(0xFFFFD873) : _borderTint,
          ),
        ),
        child: Icon(
          filled ? Icons.star_rounded : Icons.star_outline_rounded,
          key: ValueKey('$index-$filled'),
          color: filled ? const Color(0xFFF4B400) : Colors.grey.shade300,
          size: 28,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leadingWidth: 72,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.pop(context),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.chevron_left_rounded,
                color: _titleColor,
                size: 28,
              ),
            ),
          ),
        ),
        title: const Text(
          'Write a Review',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _borderTint),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Share your experience',
                    style: TextStyle(
                      color: _titleColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Your feedback helps other buyers make better decisions.',
                    style: TextStyle(
                      color: _mutedText,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Rating Section ──────────────────────────────
            _SectionLabel(label: 'Your Rating'),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _borderTint),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, _buildStar),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _ratingLabel(_rating),
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Review Text Section ─────────────────────────
            _SectionLabel(label: 'Your Review'),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _borderTint),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: TextField(
                controller: _reviewController,
                maxLines: 7,
                maxLength: 500,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.6,
                  color: _titleColor,
                ),
                decoration: InputDecoration(
                  hintText: 'Share your experience with this asset…',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                  ),
                  contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: _darkTeal, width: 1.5),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  counterStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 11,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Blockchain Badge ────────────────────────────
            if (widget.blockchainTokenId != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: _surfaceTint,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _darkTeal.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.verified_outlined,
                      color: _darkTeal,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Your review will be verified on blockchain',
                        style: TextStyle(
                          fontSize: 13,
                          color: _darkTeal,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Submit Button ───────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submitReview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _darkTeal,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _darkTeal.withOpacity(0.5),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send_rounded, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Submit a Review',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Disclaimer ──────────────────────────────────
            Center(
              child: Text(
                'Reviews are public and cannot be edited after submission',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _ratingLabel(double rating) {
    if (rating >= 5) return 'Excellent';
    if (rating >= 4) return 'Very Good';
    if (rating >= 3) return 'Good';
    if (rating >= 2) return 'Fair';
    return 'Poor';
  }
}

// ── Helper Widgets ──────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: _titleColor,
        letterSpacing: 0.1,
      ),
    );
  }
}
