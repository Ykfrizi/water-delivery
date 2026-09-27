import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/complete_vendor_profile_screen.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/forgot_password_screen.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.initialRole});

  final UserRole initialRole;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  /// Local busy — do not [watch] [AuthController] here; that registers this
  /// route as a Provider dependent and crashes when the auth tree is swapped.
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthController>();
    setState(() => _busy = true);
    try {
      await auth.login(
        role: widget.initialRole,
        email: _email.text,
        password: _password.text,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      if (widget.initialRole == UserRole.vendor &&
          _isIncompleteVendorProfile(e)) {
        await Navigator.of(context).push(
          roleThemedRoute(
            role: UserRole.vendor,
            builder: (_) => CompleteVendorProfileScreen(
              email: _email.text.trim(),
              password: _password.text,
            ),
          ),
        );
        return;
      }
      final msg = e.fieldErrors.isNotEmpty
          ? firstFieldError(e.fieldErrors, keys: ['email', 'password'])
          : e.message;
      showErrorSnackBar(context, msg);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isIncompleteVendorProfile(ApiException e) {
    final parts = <String>[
      e.message,
      ...e.fieldErrors.values.expand((v) => v),
    ];
    final text = parts.join(' ').toLowerCase();
    return text.contains('incomplete') && text.contains('ghana card');
  }

  @override
  Widget build(BuildContext context) {
    final accent = roleAccent(widget.initialRole);

    return Scaffold(
            body: Container(
              decoration: roleGradientDecoration(widget.initialRole),
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
                            onPressed: () => Navigator.of(context).maybePop(),
                            style: IconButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.14),
                            ),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const BrandMark(compact: true, showTagline: false),
                        const SizedBox(height: 16),
                        Text(
                          'Welcome back',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sign in as ${widget.initialRole.displayName}',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.88),
                                  ),
                        ),
                        const SizedBox(height: 22),
                        Material(
                          elevation: 0,
                          borderRadius: BorderRadius.circular(26),
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Credentials',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Use your ${widget.initialRole.displayName.toLowerCase()} account, or admin email and password.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                          height: 1.35,
                                        ),
                                  ),
                                  const SizedBox(height: 18),
                                  TextFormField(
                                    controller: _email,
                                    keyboardType: TextInputType.emailAddress,
                                    autofillHints: const [AutofillHints.email],
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Email',
                                      prefixIcon:
                                          Icon(Icons.mail_outline_rounded),
                                    ),
                                    validator: AuthValidators.email,
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _password,
                                    obscureText: _obscure,
                                    autofillHints: const [
                                      AutofillHints.password
                                    ],
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _submit(),
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      prefixIcon: const Icon(
                                          Icons.lock_outline_rounded),
                                      suffixIcon: IconButton(
                                        tooltip: _obscure ? 'Show' : 'Hide',
                                        onPressed: () => setState(
                                            () => _obscure = !_obscure),
                                        icon: Icon(
                                          _obscure
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                        ),
                                      ),
                                    ),
                                    validator: AuthValidators.passwordLogin,
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
                                        : const Text('Sign in'),
                                  ),
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () {
                                            Navigator.of(context).push(
                                              roleThemedRoute(
                                                role: widget.initialRole,
                                                builder: (_) =>
                                                    ForgotPasswordScreen(
                                                  role: widget.initialRole,
                                                ),
                                              ),
                                            );
                                          },
                                    child: const Text('Forgot password?'),
                                  ),
                                  if (widget.initialRole.canRegister) ...[
                                    const SizedBox(height: 12),
                                    Center(
                                      child: TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () {
                                                Navigator.of(context).push(
                                                  roleThemedRoute(
                                                    role: widget.initialRole,
                                                    builder: (_) =>
                                                        RegisterScreen(
                                                      role: widget.initialRole,
                                                    ),
                                                  ),
                                                );
                                              },
                                        child: const Text('Create an account'),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (widget.initialRole == UserRole.admin)
                          Text(
                            'Admin accounts are created by the platform — there is no public registration.',
                            textAlign: TextAlign.center,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color:
                                          Colors.white.withValues(alpha: 0.8),
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
