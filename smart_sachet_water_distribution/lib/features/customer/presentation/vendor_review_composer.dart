import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/data/customer_api.dart';

/// Shown only after the vendor has marked the customer's order delivered.
class VendorReviewComposer extends StatefulWidget {
  const VendorReviewComposer({
    super.key,
    required this.vendorSlug,
    required this.onSubmitted,
  });

  final String vendorSlug;
  final VoidCallback onSubmitted;

  @override
  State<VendorReviewComposer> createState() => _VendorReviewComposerState();
}

class _VendorReviewComposerState extends State<VendorReviewComposer> {
  int _rating = 5;
  final _comment = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthController>();
    final token = auth.session?.token;
    if (token == null) return;

    setState(() => _submitting = true);
    try {
      await CustomerApi(context.read<Dio>()).submitVendorReview(
        token,
        widget.vendorSlug,
        rating: _rating,
        comment: _comment.text.trim().isEmpty ? null : _comment.text,
      );
      if (!mounted) return;
      _comment.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thanks for your review'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      widget.onSubmitted();
    } on ApiException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.rate_review_rounded, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Rate this vendor',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Share how the water quality and delivery went.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: List.generate(5, (i) {
                final star = i + 1;
                final filled = star <= _rating;
                return IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  onPressed:
                      _submitting ? null : () => setState(() => _rating = star),
                  icon: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: filled ? Colors.amber.shade700 : Colors.grey,
                    size: 32,
                  ),
                );
              }),
            ),
            TextField(
              controller: _comment,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Comment (optional)',
                filled: true,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: kCustomerBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit review'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
