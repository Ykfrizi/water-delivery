import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.role});

  final UserRole role;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _business = TextEditingController();
  final _ghanaCard = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;
  /// Local busy — avoid watching [AuthController] on this disposable route.
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _business.dispose();
    _ghanaCard.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String _formHint() {
    return switch (widget.role) {
      UserRole.customer => 'Create an account to order water.',
      UserRole.vendor =>
        'Ghana Card is required. An admin will approve your store.',
      UserRole.admin => '',
    };
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = context.read<AuthController>();
    setState(() => _busy = true);
    try {
      if (widget.role == UserRole.customer) {
        await auth.registerCustomer(
          name: _name.text,
          email: _email.text,
          phone: _phone.text,
          password: _password.text,
          passwordConfirmation: _confirm.text,
        );
      } else if (widget.role == UserRole.vendor) {
        await auth.registerVendor(
          name: _name.text,
          email: _email.text,
          password: _password.text,
          passwordConfirmation: _confirm.text,
          ghanaCardNumber: _ghanaCard.text,
          businessName: _business.text.trim().isEmpty
              ? null
              : _business.text.trim(),
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final msg = e.fieldErrors.isNotEmpty
          ? firstFieldError(e.fieldErrors, keys: [
              'name',
              'email',
              'phone',
              'password',
              'password_confirmation',
              'business_name',
              'ghana_card_number',
              'ghana_card',
            ])
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
    if (widget.role == UserRole.admin) {
      return const Scaffold(
        body: Center(child: Text('Admin registration is not available.')),
      );
    }

    final accent = roleAccent(widget.role);

    return Scaffold(
            body: Container(
              decoration: roleGradientDecoration(widget.role),
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
                          'Create account',
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
                          widget.role.displayName,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.88),
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
                                    'Details',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _formHint(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline,
                                        ),
                                  ),
                                  const SizedBox(height: 18),
                                  TextFormField(
                                    controller: _name,
                                    textInputAction: TextInputAction.next,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    decoration: const InputDecoration(
                                      labelText: 'Full name',
                                      prefixIcon:
                                          Icon(Icons.person_outline_rounded),
                                    ),
                                    validator: (v) =>
                                        AuthValidators.name(v, label: 'Name'),
                                  ),
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _email,
                                    keyboardType: TextInputType.emailAddress,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Email',
                                      prefixIcon:
                                          Icon(Icons.mail_outline_rounded),
                                    ),
                                    validator: AuthValidators.email,
                                  ),
                                  if (widget.role == UserRole.customer) ...[
                                    const SizedBox(height: 14),
                                    TextFormField(
                                      controller: _phone,
                                      keyboardType: TextInputType.phone,
                                      textInputAction: TextInputAction.next,
                                      decoration: const InputDecoration(
                                        labelText: 'Phone number',
                                        hintText: '024 123 4567',
                                        prefixIcon:
                                            Icon(Icons.phone_outlined),
                                      ),
                                      validator: AuthValidators.phone,
                                    ),
                                  ],
                                  if (widget.role == UserRole.vendor) ...[
                                    const SizedBox(height: 14),
                                    TextFormField(
                                      controller: _business,
                                      textInputAction: TextInputAction.next,
                                      decoration: const InputDecoration(
                                        labelText: 'Business name (optional)',
                                        prefixIcon: Icon(
                                            Icons.store_mall_directory_outlined),
                                      ),
                                      validator:
                                          AuthValidators.optionalBusinessName,
                                    ),
                                    const SizedBox(height: 14),
                                    TextFormField(
                                      controller: _ghanaCard,
                                      textInputAction: TextInputAction.next,
                                      textCapitalization:
                                          TextCapitalization.characters,
                                      decoration: const InputDecoration(
                                        labelText: 'Ghana Card number *',
                                        hintText: 'GHA-123456789-0',
                                        prefixIcon: Icon(Icons.badge_outlined),
                                      ),
                                      validator: AuthValidators.ghanaCardNumber,
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  TextFormField(
                                    controller: _password,
                                    obscureText: _obscure1,
                                    textInputAction: TextInputAction.next,
                                    decoration: InputDecoration(
                                      labelText: 'Password',
                                      prefixIcon: const Icon(
                                          Icons.lock_outline_rounded),
                                      suffixIcon: IconButton(
                                        onPressed: () => setState(
                                            () => _obscure1 = !_obscure1),
                                        icon: Icon(
                                          _obscure1
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
                                    obscureText: _obscure2,
                                    textInputAction: TextInputAction.done,
                                    onFieldSubmitted: (_) => _submit(),
                                    decoration: InputDecoration(
                                      labelText: 'Confirm password',
                                      prefixIcon: const Icon(
                                          Icons.verified_user_outlined),
                                      suffixIcon: IconButton(
                                        onPressed: () => setState(
                                            () => _obscure2 = !_obscure2),
                                        icon: Icon(
                                          _obscure2
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                        ),
                                      ),
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
                                        : const Text('Create account'),
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
