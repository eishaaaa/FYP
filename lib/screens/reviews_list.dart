// lib/screens/reviews_list.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ── Design tokens (matching review_screen.dart) ─────────────
const Color _darkTeal    = Color(0xFF00695C);
const Color _surfaceTint = Color(0xFFE7F3F1);
const Color _borderTint  = Color(0xFFD7E8E4);
const Color _titleColor  = Color(0xFF151726);
const Color _mutedText   = Color(0xFF6D7A86);

/// Displays all reviews written ABOUT a specific user (revieweeUid).
///
/// Used on a user's profile to show their reputation as a buyer/seller.
/// Query: reviews where revieweeUid == [revieweeUid], ordered by newest first.
///
/// Usage:
/// ```dart
/// ReviewsList(revieweeUid: profileUser.uid)
/// ```
///
/// ⚠️  NOTE: review_screen.dart should also store `reviewerName` on the
/// review document so names can be shown here without extra Firestore reads.
/// Add this line to the reviewData map in review_screen.dart's _submitReview():
///   'reviewerName': FirebaseAuth.instance.currentUser?.displayName ?? '',
class ReviewsList extends StatelessWidget {
  /// UID of the user whose reviews we want to display.
  final String revieweeUid;

  const ReviewsList({super.key, required this.revieweeUid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('reviews')
          .where('revieweeUid', isEqualTo: revieweeUid)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _errorView();
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snapshot.data!.docs;

        if (docs.isEmpty) {
          return _emptyView();
        }

        final reviews = docs
            .map((d) => d.data() as Map<String, dynamic>)
            .toList();

        // Compute average rating for the summary header
        final avg = reviews
            .map((r) => (r['rating'] as num?)?.toDouble() ?? 0.0)
            .fold(0.0, (a, b) => a + b) /
            reviews.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Summary header ───────────────────────────────────
            _RatingSummary(average: avg, total: reviews.length),
            const SizedBox(height: 16),

            // ── Review cards ─────────────────────────────────────
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: reviews.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _ReviewCard(review: reviews[index]),
            ),
          ],
        );
      },
    );
  }

  // ── Empty / error states ──────────────────────────────────────────────────

  Widget _emptyView() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: _surfaceTint,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.rate_review_outlined, size: 44, color: _darkTeal),
        ),
        const SizedBox(height: 16),
        const Text(
          'No reviews yet',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _titleColor),
        ),
        const SizedBox(height: 6),
        const Text(
          'Reviews will appear here after completed transfers.',
          style: TextStyle(fontSize: 13, color: _mutedText),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );

  Widget _errorView() => Padding(
    padding: const EdgeInsets.all(24),
    child: Row(children: [
      Icon(Icons.error_outline, color: Colors.red[400], size: 18),
      const SizedBox(width: 8),
      const Text('Could not load reviews.', style: TextStyle(color: _mutedText)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Rating summary header
// ─────────────────────────────────────────────────────────────────────────────

class _RatingSummary extends StatelessWidget {
  final double average;
  final int total;

  const _RatingSummary({required this.average, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderTint),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          // Big average number
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                average.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: _titleColor,
                  height: 1,
                ),
              ),
              const SizedBox(height: 6),
              _StarRow(rating: average, size: 18),
              const SizedBox(height: 4),
              Text(
                '$total review${total == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, color: _mutedText),
              ),
            ],
          ),
          const SizedBox(width: 24),
          // Per-star breakdown bars
          Expanded(
            child: Column(
              children: List.generate(5, (i) {
                final star = 5 - i;
                final count = _countForStar(star, total);
                return _BarRow(star: star, fraction: count);
              }),
            ),
          ),
        ],
      ),
    );
  }

  // Approximate fraction based only on average + total (no per-star data stored)
  // Returns 0.0–1.0 for the bar width. Uses a simple heuristic.
  double _countForStar(int star, int total) {
    if (total == 0) return 0;
    // Weight each star by how close it is to the average
    final diff = (star - average).abs();
    final weight = (1.0 - diff / 4.0).clamp(0.0, 1.0);
    return weight;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Individual review card
// ─────────────────────────────────────────────────────────────────────────────

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final rating       = (review['rating'] as num?)?.toInt() ?? 0;
    final comment      = (review['comment'] as String?)?.trim() ?? '';
    final reviewerRole = (review['reviewerRole'] as String?) ?? '';
    // reviewerName is stored if review_screen.dart has the extra field;
    // falls back gracefully to the role label if missing.
    final reviewerName = (review['reviewerName'] as String?)?.trim() ?? '';
    final displayName  = reviewerName.isNotEmpty
        ? reviewerName
        : (reviewerRole == 'buyer' ? 'Verified Buyer' : 'Verified Seller');
    final initial = displayName[0].toUpperCase();

    final createdAt = review['createdAt'];
    String dateStr = '';
    if (createdAt is Timestamp) {
      final dt = createdAt.toDate();
      dateStr = '${dt.day} ${_month(dt.month)} ${dt.year}';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderTint),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: avatar + name + role badge + date ───────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              CircleAvatar(
                radius: 20,
                backgroundColor: _surfaceTint,
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: _darkTeal,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name + role badge
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: _titleColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (reviewerRole.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          _RoleBadge(role: reviewerRole),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Stars
                    _StarRow(rating: rating.toDouble(), size: 15),
                  ],
                ),
              ),
              // Date
              if (dateStr.isNotEmpty)
                Text(
                  dateStr,
                  style: const TextStyle(fontSize: 11, color: _mutedText),
                ),
            ],
          ),

          // ── Comment ──────────────────────────────────────────
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              comment,
              style: const TextStyle(
                fontSize: 13,
                color: _titleColor,
                height: 1.55,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _month(int m) => const [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ][m];
}

// ─────────────────────────────────────────────────────────────────────────────
// Small helpers
// ─────────────────────────────────────────────────────────────────────────────

class _StarRow extends StatelessWidget {
  final double rating;
  final double size;
  const _StarRow({required this.rating, required this.size});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating.round();
        return Icon(
          filled ? Icons.star_rounded : Icons.star_outline_rounded,
          color: filled ? const Color(0xFFF4B400) : Colors.grey.shade300,
          size: size,
        );
      }),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role; // 'buyer' or 'seller'
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final isBuyer = role == 'buyer';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isBuyer ? const Color(0xFFE8F5E9) : _surfaceTint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isBuyer ? const Color(0xFFA5D6A7) : _borderTint,
        ),
      ),
      child: Text(
        isBuyer ? 'Buyer' : 'Seller',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isBuyer ? const Color(0xFF2E7D32) : _darkTeal,
        ),
      ),
    );
  }
}

/// A bar row used inside the rating summary breakdown.
class _BarRow extends StatelessWidget {
  final int star;
  final double fraction; // 0.0 – 1.0
  const _BarRow({required this.star, required this.fraction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$star', style: const TextStyle(fontSize: 11, color: _mutedText)),
          const SizedBox(width: 4),
          const Icon(Icons.star_rounded, size: 11, color: Color(0xFFF4B400)),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: Colors.grey.shade100,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFF4B400)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}