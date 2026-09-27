import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/domain/vendor_rating.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/presentation/review_list_tile.dart';
import 'package:smart_sachet_water_distribution/features/marketplace/presentation/vendor_rating_stars.dart';
import 'package:smart_sachet_water_distribution/features/support/presentation/help_support_screen.dart';
import 'package:smart_sachet_water_distribution/features/vendor/data/vendor_api.dart';
import 'package:smart_sachet_water_distribution/features/vendor/presentation/vendor_auto_approve_screen.dart';

/// Vendor profile — store settings and shortcuts moved off the home dashboard.
class VendorAccountScreen extends StatelessWidget {
  const VendorAccountScreen({
    super.key,
    required this.pendingApprovals,
    required this.walletAvailableLabel,
    required this.onOpenOrders,
    required this.onOpenMap,
    required this.onOpenProducts,
    required this.onOpenWithdrawals,
    required this.onEditStoreProfile,
  });

  final int pendingApprovals;
  final String walletAvailableLabel;
  final VoidCallback onOpenOrders;
  final VoidCallback onOpenMap;
  final VoidCallback onOpenProducts;
  final VoidCallback onOpenWithdrawals;
  final VoidCallback onEditStoreProfile;

  void _openTab(BuildContext context, VoidCallback open) {
    Navigator.of(context).pop();
    open();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = roleAccent(UserRole.vendor);
    final user = context.select<AuthController, String>(
      (a) => a.session?.user.name ?? 'Vendor',
    );
    final email = context.select<AuthController, String>(
      (a) => a.session?.user.email ?? '',
    );

    return Theme(
      data: vendorAppTheme(),
      child: Scaffold(
      body: Container(
        decoration: roleGradientDecoration(UserRole.vendor),
        child: SafeArea(
          child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: HeaderIconButton(
                    icon: Icons.arrow_back_rounded,
                    onPressed: () => Navigator.of(context).maybePop(),
                    tooltip: 'Back',
                  ),
                ),
                const BrandHeader(
                  title: 'Account',
                  subtitle: 'Store profile and shortcuts',
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          email,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.88),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const _VendorProfileReviews(),
                const SizedBox(height: 16),
                Text(
                  'Shortcuts',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                _ShortcutTile(
                  icon: Icons.storefront_outlined,
                  title: 'Store profile',
                  subtitle: 'Business name, phone, and store GPS',
                  onTap: onEditStoreProfile,
                ),
                _ShortcutTile(
                  icon: Icons.fact_check_outlined,
                  title: 'Approve orders',
                  subtitle: pendingApprovals > 0
                      ? '$pendingApprovals waiting · approve before shipping'
                      : 'Review & approve every new order',
                  onTap: () => _openTab(context, onOpenOrders),
                ),
                _ShortcutTile(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Withdraw money',
                  subtitle: 'Available $walletAvailableLabel · bank or MoMo',
                  onTap: () => _openTab(context, onOpenWithdrawals),
                ),
                _ShortcutTile(
                  icon: Icons.support_agent_outlined,
                  title: 'Help & support',
                  subtitle: 'Gmail or WhatsApp · send a complaint',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const HelpSupportScreen(
                          role: UserRole.vendor,
                        ),
                      ),
                    );
                  },
                ),
                _ShortcutTile(
                  icon: Icons.schedule_rounded,
                  title: 'Auto-approve schedule',
                  subtitle:
                      'One-time window or weekly hours · stop anytime',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const VendorAutoApproveScreen(),
                      ),
                    );
                  },
                ),
                _ShortcutTile(
                  icon: Icons.person_pin_circle_outlined,
                  title: 'Customer map',
                  subtitle: 'GPS from customer checkouts',
                  onTap: () => _openTab(context, onOpenMap),
                ),
                _ShortcutTile(
                  icon: Icons.price_change_outlined,
                  title: 'Catalog',
                  subtitle: 'Products you sell',
                  onTap: () => _openTab(context, onOpenProducts),
                ),
                _ShortcutTile(
                  icon: Icons.payments_outlined,
                  title: 'Withdrawals',
                  subtitle: 'Bank or MoMo payout from paid orders',
                  onTap: () => _openTab(context, onOpenWithdrawals),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => context.read<AuthController>().logout(),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: roleAccent(UserRole.vendor).withValues(alpha: 0.15),
            child: Icon(icon, color: roleAccent(UserRole.vendor)),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _VendorProfileReviews extends StatefulWidget {
  const _VendorProfileReviews();

  @override
  State<_VendorProfileReviews> createState() => _VendorProfileReviewsState();
}

class _VendorProfileReviewsState extends State<_VendorProfileReviews> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _profile = {};
  List<Map<String, dynamic>> _reviews = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = context.read<AuthController>().token;
    if (token == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in to see reviews.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = VendorApi(context.read<Dio>());
      Map<String, dynamic> profile = {};
      try {
        profile = await api.getProfile(token);
      } catch (_) {}
      final reviews = await api.listReviews(token);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _reviews = reviews;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load reviews.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rating = VendorRating.fromVendorJson({
      ..._profile,
      if (_reviews.isNotEmpty) 'reviews': _reviews,
    });

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Customer reviews',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: kOnLight,
              ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: kOnLightMuted))
            else ...[
              VendorRatingStars(rating: rating),
              const SizedBox(height: 12),
              if (_reviews.isEmpty)
                const Text(
                  'No reviews yet. Customers can rate you after a delivery.',
                  style: TextStyle(color: kOnLightMuted, height: 1.35),
                )
              else
                ..._reviews.map((r) => ReviewListTile(review: r)),
            ],
          ],
        ),
      ),
    );
  }
}
