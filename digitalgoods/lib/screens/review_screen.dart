// lib/screens/review_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ── Design tokens ───────────────────────────────────────────
const Color _darkTeal   = Color(0xFF00695C);
const Color _surfaceTint = Color(0xFFE7F3F1);
const Color _borderTint  = Color(0xFFD7E8E4);
const Color _titleColor  = Color(0xFF151726);
const Color _mutedText   = Color(0xFF6D7A86);

/// Person-to-person review shown after a transfer is completed.
/// Both the buyer and the seller can review each other about communication,
/// responsiveness and cooperation — NOT about the asset itself.
class ReviewScreen extends StatefulWidget {
  /// UID of the user writing the review.
  final String reviewerUid;
  /// UID of the user being reviewed.
  final String revieweeUid;
  /// Display name of the user being reviewed.
  final String revieweeName;
  /// Firestore transaction doc ID — used for duplicate detection and to
  /// mark buyerReviewed / sellerReviewed on the transaction document.
  final String transactionId;
  /// Asset doc ID — stored on the review record for reference.
  final String assetId;
  /// 'buyer' or 'seller' — the role of the person writing the review.
  final String reviewerRole;

  const ReviewScreen({
    super.key,
    required this.reviewerUid,
    required this.revieweeUid,
    required this.revieweeName,
    required this.transactionId,
    required this.assetId,
    required this.reviewerRole,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _db                = FirebaseFirestore.instance;
  final _commentController = TextEditingController();

  int    _rating          = 0;
  bool   _submitting      = false;
  bool?  _alreadyReviewed; // null = still checking
  bool   _submitted       = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkAlreadyReviewed();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  // ── Duplicate check ─────────────────────────────────────────

  Future<void> _checkAlreadyReviewed() async {
    try {
      final snap = await _db
          .collection('reviews')
          .where('reviewerUid',   isEqualTo: widget.reviewerUid)
          .where('transactionId', isEqualTo: widget.transactionId)
          .limit(1)
          .get();
      if (mounted) setState(() => _alreadyReviewed = snap.docs.isNotEmpty);
    } catch (_) {
      if (mounted) setState(() => _alreadyReviewed = false);
    }
  }

  // ── Submit ──────────────────────────────────────────────────

  Future<void> _submitReview() async {
    if (_rating == 0) {
      setState(() => _error = 'Please select a star rating before submitting.');
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      await _db.collection('reviews').add({
        'reviewerUid'  : widget.reviewerUid,
        'revieweeUid'  : widget.revieweeUid,
        'revieweeName' : widget.revieweeName,
        'transactionId': widget.transactionId,
        'assetId'      : widget.assetId,
        'rating'       : _rating,
        'comment'      : _commentController.text.trim(),
        'reviewerRole' : widget.reviewerRole,
        'createdAt'    : FieldValue.serverTimestamp(),
      });

      // Flag on the transaction so both sides know who has reviewed
      final field = widget.reviewerRole == 'buyer' ? 'buyerReviewed' : 'sellerReviewed';
      if (widget.transactionId.isNotEmpty) {
        await _db.collection('transactions').doc(widget.transactionId).update({field: true});
      }

      if (mounted) setState(() { _submitted = true; _submitting = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error      = e.toString().replaceFirst('Exception: ', '');
          _submitting = false;
        });
      }
    }
  }

  // ── Build ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_alreadyReviewed == null) {
      return Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: _buildAppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: _buildAppBar(),
      body: _alreadyReviewed!
          ? _buildAlreadyReviewedView()
          : _submitted
          ? _buildThankYouView()
          : _buildReviewForm(),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
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
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: const Icon(Icons.chevron_left_rounded, color: _titleColor, size: 28),
        ),
      ),
    ),
    title: const Text('Leave a Review', style: TextStyle(color: _titleColor, fontWeight: FontWeight.w700, fontSize: 20)),
  );

  // ── Review form ─────────────────────────────────────────────

  Widget _buildReviewForm() {
    final otherRole = widget.reviewerRole == 'buyer' ? 'Seller' : 'Buyer';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Header card
          _card(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: _surfaceTint, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.rate_review_rounded, color: _darkTeal, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('How was your experience?',
                        style: TextStyle(color: _titleColor, fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text('Reviewing ${widget.revieweeName} ($otherRole)',
                        style: const TextStyle(color: _mutedText, fontSize: 13)),
                  ],
                )),
              ]),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _surfaceTint,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _borderTint),
                ),
                child: const Text(
                  'This review is about the person and the transfer process — '
                      'communication, responsiveness, and cooperation. Not about the asset.',
                  style: TextStyle(color: _darkTeal, fontSize: 12, height: 1.5),
                ),
              ),
            ],
          )),

          const SizedBox(height: 20),

          // Star rating
          const _SectionLabel(label: 'Your Rating'),
          const SizedBox(height: 12),
          _card(child: Column(children: [
            SizedBox(
              width: double.infinity,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: List.generate(5, _buildStar)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _ratingLabel(_rating),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _rating > 0 ? _darkTeal : Colors.grey.shade400,
                fontSize: 13, fontWeight: FontWeight.w600,
              ),
            ),
          ])),

          const SizedBox(height: 20),

          // Comment
          const _SectionLabel(label: 'Write a comment (optional)'),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _borderTint),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: TextField(
              controller: _commentController,
              maxLines: 5, maxLength: 500,
              style: const TextStyle(fontSize: 14, height: 1.6, color: _titleColor),
              decoration: InputDecoration(
                hintText: 'e.g. "Very responsive, smooth process, would deal with them again…"',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                border:        OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: _darkTeal, width: 1.5)),
                filled: true, fillColor: Colors.white,
                counterStyle: TextStyle(color: Colors.grey.shade400, fontSize: 11),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Error
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.error_outline, color: Colors.red[700], size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_error!, style: TextStyle(color: Colors.red[800], fontSize: 13, height: 1.4))),
              ]),
            ),
            const SizedBox(height: 16),
          ],

          // Submit
          SizedBox(
            width: double.infinity, height: 54,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submitReview,
              style: ElevatedButton.styleFrom(
                backgroundColor: _darkTeal,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _darkTeal.withOpacity(0.5),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _submitting
                  ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
                Icon(Icons.send_rounded, size: 18),
                SizedBox(width: 8),
                Text('Submit Review', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),

          const SizedBox(height: 14),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Skip for now', style: TextStyle(color: _mutedText)),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Reviews are public and cannot be edited after submission.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade400),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ── Thank-you view ──────────────────────────────────────────

  Widget _buildThankYouView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: const BoxDecoration(color: Color(0xFFFFF8E1), shape: BoxShape.circle),
          child: const Icon(Icons.star_rounded, color: Color(0xFFF4B400), size: 72),
        ),
        const SizedBox(height: 28),
        const Text('Review Submitted!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _titleColor)),
        const SizedBox(height: 12),
        Text(
          'Thank you for reviewing ${widget.revieweeName}. '
              'Your feedback helps build trust across the marketplace.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: _mutedText, height: 1.6),
        ),
        const SizedBox(height: 36),
        SizedBox(
          width: 180, height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: _darkTeal, foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Done', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    ),
  );

  // ── Already-reviewed view ───────────────────────────────────

  Widget _buildAlreadyReviewedView() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.all(28),
          decoration: const BoxDecoration(color: _surfaceTint, shape: BoxShape.circle),
          child: const Icon(Icons.check_circle_rounded, color: _darkTeal, size: 72),
        ),
        const SizedBox(height: 28),
        const Text('Already Reviewed',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _titleColor)),
        const SizedBox(height: 12),
        Text(
          'You have already submitted a review for ${widget.revieweeName} '
              'for this transaction.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: _mutedText, height: 1.6),
        ),
        const SizedBox(height: 36),
        SizedBox(
          width: 180, height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: _darkTeal, foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Go Back', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    ),
  );

  // ── Card wrapper ─────────────────────────────────────────────

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
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
      child: child,
    );
  }

  // ── Star builder ─────────────────────────────────────────────

  Widget _buildStar(int index) {
    final filled = _rating > index;
    return GestureDetector(
      onTap: () => setState(() => _rating = index + 1),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: filled ? const Color(0xFFFFF5D6) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: filled ? const Color(0xFFFFD873) : _borderTint),
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

  String _ratingLabel(int r) {
    switch (r) {
      case 1: return 'Poor — major issues with communication or process';
      case 2: return 'Fair — some issues, but transfer completed';
      case 3: return 'Good — generally smooth experience';
      case 4: return 'Very Good — responsive and cooperative';
      case 5: return 'Excellent — outstanding throughout!';
      default: return 'Tap a star to rate';
    }
  }
}

// ── Shared label widget ─────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _titleColor, letterSpacing: 0.1),
  );
}