import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({
    super.key,
    required this.role,
    required this.email,
  });

  final UserRole role;
  final String email;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _token = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _resending = false;
  bool _obscure = true;
  int _resendIn = 60;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), _onResendTick);
  }

  void _onResendTick(Timer timer) {
    if (!mounted) {
      timer.cancel();
      return;
    }
    if (_resendIn <= 1) {
      timer.cancel();
      setState(() => _resendIn = 0);
      return;
    }
    setState(() => _resendIn -= 1);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _token.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), _onResendTick);
  }

  Future<void> _resend() async {
    if (_resendIn > 0 || _resending || _busy) return;
    final auth = context.read<AuthController>();
    setState(() => _resending = true);
    try {
      await auth.forgotPassword(role: widget.role, email: widget.email);
      if (!mounted) return;
      _startResendCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A new code was sent. Check your email.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      final msg = e.fieldErrors.isNotEmpty
          ? firstFieldError(e.fieldErrors, keys: ['email'])
          : e.message;
      showErrorSnackBar(context, msg);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e.toString());
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = context.read<AuthController>();
    setState(() => _busy = true);
    try {
      await auth.resetPassword(
        role: widget.role,
        email: widget.email,
        token: AuthValidators.digitsOnly(_token.text),
        password: _password.text,
        passwordConfirmation: _confirm.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated. You can sign in now.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).popUntil((r) => r.isFirst || r.settings.name == null);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final msg = e.fieldErrors.isNotEmpty
          ? firstFieldError(
              e.fieldErrors,
              keys: ['token', 'code', 'password', 'email'],
            )
          : e.message;
      showErrorSnackBar(context, msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnackBar(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = roleAccent(widget.role);
    final theme = Theme.of(context);
    final resendLabel = _resendIn > 0
        ? 'Resend code in ${_resendIn}s'
        : 'Resend code';

    return Scaffold(
        body: Container(
          decoration: authGradientDecoration(),
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
                              Colors.white.withValues(alpha: 0.12),
                        ),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const BrandMark(compact: true, showTagline: false),
                    const SizedBox(height: 16),
                    Text(
                      'Enter your code',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'We emailed a 6-digit code to ${widget.email}. '
                      'It expires in 15 minutes. Check spam if you do not see it.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      elevation: 8,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _token,
                                keyboardType: TextInputType.number,
                                textInputAction: TextInputAction.next,
                                maxLength: 6,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: const InputDecoration(
                                  labelText: '6-digit code',
                                  counterText: '',
                                  prefixIcon: Icon(Icons.pin_outlined),
                                ),
                                validator: AuthValidators.resetCode,
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _password,
                                obscureText: _obscure,
                                decoration: InputDecoration(
                                  labelText: 'New password',
                                  prefixIcon:
                                      const Icon(Icons.lock_outline_rounded),
                                  suffixIcon: IconButton(
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                  ),
                                ),
                                validator: AuthValidators.passwordRegister,
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _confirm,
                                obscureText: _obscure,
                                decoration: const InputDecoration(
                                  labelText: 'Confirm password',
                                  prefixIcon:
                                      Icon(Icons.verified_user_outlined),
                                ),
                                validator: (v) =>
                                    AuthValidators.passwordConfirm(
                                  _password.text,
                                  v,
                                ),
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
                                    : const Text('Update password'),
                              ),
                              TextButton(
                                onPressed: (_resendIn > 0 || _resending || _busy)
                                    ? null
                                    : _resend,
                                child: _resending
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(resendLabel),
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
