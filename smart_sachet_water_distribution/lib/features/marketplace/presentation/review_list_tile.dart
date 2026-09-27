import 'package:flutter/material.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/domain/review_display.dart';

class ReviewListTile extends StatelessWidget {
  const ReviewListTile({super.key, required this.review});

  final Map<String, dynamic> review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rating = reviewStarRating(review);
    final comment = reviewComment(review);
    final created = reviewDateLabel(review);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      reviewAuthorName(review),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: kOnLight,
                      ),
                    ),
                  ),
                  if (created.isNotEmpty)
                    Text(
                      created,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: kOnLightMuted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (var i = 1; i <= 5; i++)
                    Icon(
                      i <= rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 18,
                      color: i <= rating
                          ? Colors.amber.shade700
                          : Colors.grey.shade400,
                    ),
                ],
              ),
              if (comment.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  comment,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.35,
                    color: kOnLight,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
