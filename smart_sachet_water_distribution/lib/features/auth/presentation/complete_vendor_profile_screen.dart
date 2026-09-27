import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';

/// Shown after vendor login when the account has no Ghana Card / vendor profile.
class CompleteVendorProfileScreen extends StatefulWidget {
  const CompleteVendorProfileScreen({
    super.key,
    required this.email,
    required this.password,
  });

  final String email;
  final String password;

  @override
  State<CompleteVendorProfileScreen> createState() =>
      _CompleteVendorProfileScreenState();
}

class _CompleteVendorProfileScreenState
    extends State<CompleteVendorProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _business = TextEditingController();
  final _ghanaCard = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _business.dispose();
    _ghanaCard.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await context.read<AuthController>().completeVendorProfile(
            email: widget.email,
            password: widget.password,
            ghanaCardNumber: _ghanaCard.text,
            businessName: _business.text.trim().isEmpty
                ? null
                : _business.text.trim(),
          );
    } on ApiException catch (e) {
      if (!mounted) return;
      final msg = e.fieldErrors.isNotEmpty
          ? firstFieldError(
              e.fieldErrors,
              keys: ['ghana_card_number', 'ghana_card', 'business_name', 'email'],
            )
          : e.message;
      showErrorSnackBar(context, msg);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const role = UserRole.vendor;
    final accent = roleAccent(role);

    return Scaffold(
            body: Container(
              decoration: roleGradientDecoration(role),
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            onPressed: _busy
                                ? null
                                : () => Navigator.of(context).maybePop(),
                            style: IconButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.12),
                            ),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const BrandMark(compact: true, showTagline: false),
                        const SizedBox(height: 16),
                        Text(
                          'Finish your vendor profile',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Enter your Ghana Card number so an admin can approve your store.',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.88),
                                    height: 1.4,
                                  ),
                        ),
                        const SizedBox(height: 20),
                        Material(
                          elevation: 8,
                          borderRadius: BorderRadius.circular(24),
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Required details',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 18),
                                  TextFormField(
                                    initialValue: widget.email,
                                    enabled: false,
                                    decoration: const InputDecoration(
                                      labelText: 'Email',
                                      prefixIcon:
                                          Icon(Icons.mail_outline_rounded),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _business,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Business name (optional)',
                                      prefixIcon: Icon(
                                        Icons.store_mall_directory_outlined,
                                      ),
                                    ),
                                    validator:
                                        AuthValidators.optionalBusinessName,
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _ghanaCard,
                                    textInputAction: TextInputAction.done,
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    onFieldSubmitted: (_) => _submit(),
                                    decoration: const InputDecoration(
                                      labelText: 'Ghana Card number *',
                                      hintText: 'GHA-123456789-0',
                                      prefixIcon: Icon(Icons.badge_outlined),
                                    ),
                                    validator: AuthValidators.ghanaCardNumber,
                                  ),
                                  const SizedBox(height: 22),
                                  FilledButton(
                                    onPressed: _busy ? null : _submit,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: accent,
                                    ),
                                    child: _busy
                                        ? const SizedBox(
                                            height: 22,
                                            width: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Text('Continue'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
  }
}
