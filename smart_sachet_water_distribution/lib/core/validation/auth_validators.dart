import 'package:flutter/material.dart';

class AuthValidators {
  AuthValidators._();

  static final _email = RegExp(
    r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
  );

  static String? name(String? v, {required String label}) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return '$label is required';
    if (t.length < 2) return '$label must be at least 2 characters';
    if (t.length > 120) return '$label is too long';
    return null;
  }

  static String? email(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Email is required';
    if (!_email.hasMatch(t)) return 'Enter a valid email address';
    return null;
  }

  static String? passwordLogin(String? v) {
    final t = v ?? '';
    if (t.isEmpty) return 'Password is required';
    if (t.length < 8) return 'Password must be at least 8 characters';
    return null;
  }

  static String? passwordRegister(String? v) {
    final t = v ?? '';
    if (t.isEmpty) return 'Password is required';
    if (t.length < 8) return 'Use at least 8 characters';
    if (t.length > 128) return 'Password is too long';
    return null;
  }

  static String? passwordConfirm(String? password, String? confirm) {
    final c = passwordRegister(password);
    if (c != null) return c;
    if ((confirm ?? '') != (password ?? '')) {
      return 'Passwords do not match';
    }
    return null;
  }

  static String? resetCode(String? v) {
    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length != 6) {
      return 'Enter the 6-digit code from your email';
    }
    return null;
  }

  static String digitsOnly(String v) => v.replaceAll(RegExp(r'\D'), '');

  static String? addressLine(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Enter your delivery address';
    if (t.length < 4) return 'Address is too short';
    if (t.length > 255) return 'Address is too long';
    return null;
  }

  static String? city(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Enter your city';
    return null;
  }

  static String? phone(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Phone number is required';
    final digits = t.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9 || digits.length > 15) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  static String? optionalBusinessName(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    if (t.length < 2) return 'Business name must be at least 2 characters';
    if (t.length > 200) return 'Business name is too long';
    return null;
  }

  /// Ghana Card format: GHA-XXXXXXXXX-X (9 digits + check digit).
  static final _ghanaCard = RegExp(
    r'^GHA-\d{9}-\d$',
    caseSensitive: false,
  );

  static String? ghanaCardNumber(String? v) {
    final t = (v ?? '').trim().toUpperCase();
    if (t.isEmpty) return 'Ghana Card number is required';
    if (!_ghanaCard.hasMatch(t)) {
      return 'Use format GHA-XXXXXXXXX-X';
    }
    return null;
  }

  static String normalizeGhanaCard(String v) => v.trim().toUpperCase();
}

String firstFieldError(
  Map<String, List<String>> errors, {
  required List<String> keys,
}) {
  for (final k in keys) {
    final list = errors[k];
    if (list != null && list.isNotEmpty) {
      return list.first;
    }
  }
  return 'Please check the form and try again';
}

void showErrorSnackBar(BuildContext context, String message) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(_friendlyError(message)),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

String _friendlyError(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('timeoutexception') ||
      lower.contains('future not completed') ||
      lower.contains('timeout')) {
    return 'That took too long. Stay outdoors for GPS, keep Wi‑Fi on, then try Paystack again.';
  }
  return message;
}
