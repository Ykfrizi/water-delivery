import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/support/presentation/help_support_screen.dart';

/// Shown after vendor signup/login until an admin approves the account.
///
/// Does not [watch] [AuthController] — this screen is removed when approval
/// flips, and watching during that notify causes `_dependents.isEmpty` crashes.
class VendorPendingApprovalScreen extends StatefulWidget {
  const VendorPendingApprovalScreen({super.key});

  @override
  State<VendorPendingApprovalScreen> createState() =>
      _VendorPendingApprovalScreenState();
}

class _VendorPendingApprovalScreenState
    extends State<VendorPendingApprovalScreen> {
  bool _busy = false;

  Future<void> _checkApproval() async {
    final auth = context.read<AuthController>();
    setState(() => _busy = true);
    try {
      await auth.refreshSession();
      if (!mounted) return;
      if (auth.session?.user.canAccessVendorDashboard == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account approved — welcome!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final rejected = auth.session?.user.isVendorRejected == true;
      setState(() => _busy = false);
      showErrorSnackBar(
        context,
        rejected
            ? 'Still rejected. Contact an admin.'
            : 'Still pending approval.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnackBar(context, e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnackBar(context, e.toString());
    }
  }

  Future<void> _signOut() async {
    final auth = context.read<AuthController>();
    setState(() => _busy = true);
    try {
      await auth.logout();
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    final user = auth.session?.user;
    final rejected = user?.isVendorRejected == true;
    final theme = Theme.of(context);
    final accent = roleAccent(UserRole.vendor);

    return Scaffold(
        body: Container(
          decoration: roleGradientDecoration(UserRole.vendor),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(child: AppLogo(size: 64, showShadow: true)),
                        const SizedBox(height: 18),
                        Icon(
                          rejected
                              ? Icons.block_rounded
                              : Icons.hourglass_top_rounded,
                          size: 36,
                          color: rejected ? Colors.red.shade700 : accent,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          rejected
                              ? 'Registration rejected'
                              : 'Awaiting admin approval',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          rejected
                              ? 'Your vendor account was not approved. Contact support or try registering with a valid Ghana Card.'
                              : 'Thanks for registering. An admin must approve your Ghana Card details before you can access the vendor dashboard.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline,
                            height: 1.4,
                          ),
                        ),
                        if (user?.ghanaCardNumber != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Ghana Card: ${user!.ghanaCardNumber}',
                              textAlign: TextAlign.center,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                        if (user?.email != null && user!.email.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            user.email,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: _busy ? null : _checkApproval,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh_rounded),
                          label: const Text('Check approval status'),
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const HelpSupportScreen(
                                  role: UserRole.vendor,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.support_agent_rounded),
                          label: const Text('Help & support'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _signOut,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Sign out'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    );
  }
}
