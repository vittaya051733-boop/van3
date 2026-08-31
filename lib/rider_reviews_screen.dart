import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'l10n/l10n.dart';
import 'utils/app_colors.dart';

class RiderReviewsScreen extends StatelessWidget {
  const RiderReviewsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim();
    if (uid == null || uid.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(L10n.customerReviews),
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
        ),
        body: Center(child: Text(L10n.signInRequiredFirst)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.customerReviews),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('rider_reviews')
            .where('riderId', isEqualTo: uid)
            .limit(100)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  L10n.reviewsLoadFailedWithError(snapshot.error!),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final docs = (snapshot.data?.docs ?? const [])
              .where((doc) => (doc.data()['status'] as String?) == 'visible')
              .toList(growable: false)
            ..sort((left, right) {
              final leftData = left.data();
              final rightData = right.data();
              final leftTs = leftData['updatedAt'] ?? leftData['createdAt'];
              final rightTs = rightData['updatedAt'] ?? rightData['createdAt'];
              final leftMs =
                  leftTs is Timestamp ? leftTs.millisecondsSinceEpoch : 0;
              final rightMs =
                  rightTs is Timestamp ? rightTs.millisecondsSinceEpoch : 0;
              return rightMs.compareTo(leftMs);
            });

          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  L10n.noCustomerReviewsYet,
                  style: const TextStyle(color: Colors.black54, fontSize: 15),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final review = docs[index].data();
              final orderId = (review['orderId'] as String?)?.trim();
              return _RiderReviewCard(review: review, orderId: orderId);
            },
          );
        },
      ),
    );
  }
}

class _RiderReviewCard extends StatelessWidget {
  const _RiderReviewCard({required this.review, this.orderId});

  final Map<String, dynamic> review;
  final String? orderId;

  @override
  Widget build(BuildContext context) {
    final rating = (review['rating'] as num?)?.toInt() ?? 0;
    final comment = (review['comment'] as String?)?.trim() ?? '';
    final imageUrls = ((review['imageUrls'] as List?) ?? const <dynamic>[])
        .whereType<String>()
        .where((url) => url.trim().isNotEmpty)
        .toList(growable: false);
    final updatedAt = review['updatedAt'] ?? review['createdAt'];
    final dateLabel = updatedAt is Timestamp
        ? _formatReviewDate(updatedAt.toDate())
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.delivery_dining_rounded, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  orderId != null && orderId!.isNotEmpty
                      ? L10n.reviewForOrder(orderId!)
                      : L10n.reviewService,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              if (dateLabel != null)
                Text(
                  dateLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              for (var index = 1; index <= 5; index++)
                Icon(
                  index <= rating
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 18,
                  color: const Color(0xFFF59E0B),
                ),
            ],
          ),
          if (comment.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              comment,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF374151),
                height: 1.4,
              ),
            ),
          ],
          if (imageUrls.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: imageUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      imageUrls[index],
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 64,
                        height: 64,
                        color: const Color(0xFFF3F4F6),
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            L10n.reviewsReadOnlyCustomer,
            style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }
}

String _formatReviewDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year;
  return '$day/$month/$year';
}
