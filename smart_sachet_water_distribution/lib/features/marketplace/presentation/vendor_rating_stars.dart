import 'package:flutter/material.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/domain/vendor_rating.dart';

class VendorRatingStars extends StatelessWidget {
  const VendorRatingStars({
    super.key,
    required this.rating,
    this.size = 18,
    this.showLabel = true,
  });

  final VendorRating rating;
  final double size;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filled = rating.hasRatings ? rating.average.round().clamp(0, 5) : 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= filled ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: i <= filled ? Colors.amber.shade700 : Colors.grey.shade400,
          ),
        if (showLabel) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              rating.label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
