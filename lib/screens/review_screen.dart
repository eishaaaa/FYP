// FILE 2: lib/screens/review_screen.dart
// =====================================================
import 'package:flutter/material.dart';
import '../blockchain/blockchain_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write a review')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser!;

      // 1. Store review in Firebase
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

      // 2. Store hash on-chain (electronics only for now)
      if (widget.blockchainTokenId != null && widget.assetType == 'electronics') {
        await _blockchainService.init();

        if (!_blockchainService.isConnected) {
          await _blockchainService.connectWallet(context);
        }

        final txHash = await _blockchainService.submitElectronicsReview(
          tokenId: widget.blockchainTokenId!,
          reviewText: _reviewController.text.trim(),
        );

        if (txHash != null) {
          // Update review with blockchain hash
          await reviewDoc.update({
            'blockchainTxHash': txHash,
            'blockchainVerified': true,
          });
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Review submitted successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Write a Review')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rating',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _rating,
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: _rating.toStringAsFixed(1),
                    onChanged: (value) {
                      setState(() => _rating = value);
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        _rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            const Text(
              'Your Review',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reviewController,
              decoration: InputDecoration(
                hintText: 'Share your experience with this asset...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                // alignedLabelStyle: const TextStyle(height: 0.5),
              ),
              maxLines: 6,
              maxLength: 500,
            ),

            const SizedBox(height: 16),

            if (widget.blockchainTokenId != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue),
                ),
                child: Row(
                  children: [
                    Icon(Icons.verified, color: Colors.blue[700]),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Your review will be verified on blockchain',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submitReview,
                icon: _submitting
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                    : const Icon(Icons.send),
                label: Text(_submitting ? 'Submitting...' : 'Submit Review'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              '* Reviews are stored publicly and cannot be edited after submission',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}