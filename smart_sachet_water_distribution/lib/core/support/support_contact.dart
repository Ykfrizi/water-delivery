import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';

/// Support inbox for customer and vendor complaints.
class SupportContact {
  SupportContact._();

  static const email = 'thisaxamebless@gmail.com';
  static const whatsappE164 = '233544826939';
  static const whatsappDisplay = '+233 54 482 6939';

  /// Support WhatsApp must never be used as a customer delivery number.
  static bool isReservedSupportPhone(String? raw) {
    final digits = (raw ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return false;
    if (digits == whatsappE164 || digits == '0544826939' || digits == '544826939') {
      return true;
    }
    return digits.endsWith('544826939');
  }

  /// Profile/session phones that belong to support are treated as empty.
  static String customerPhoneOrEmpty(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty || isReservedSupportPhone(t)) return '';
    return t;
  }

  static Uri emailUri({String? subject, String? body}) {
    return Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {
        if (subject != null && subject.trim().isNotEmpty) 'subject': subject.trim(),
        if (body != null && body.trim().isNotEmpty) 'body': body.trim(),
      },
    );
  }

  static Uri gmailComposeUri({String? subject, String? body}) {
    return Uri.https('mail.google.com', '/mail/', {
      'view': 'cm',
      'fs': '1',
      'to': email,
      if (subject != null && subject.trim().isNotEmpty) 'su': subject.trim(),
      if (body != null && body.trim().isNotEmpty) 'body': body.trim(),
    });
  }

  static Uri whatsappUri({String? message}) {
    return Uri.https('wa.me', '/$whatsappE164', {
      if (message != null && message.trim().isNotEmpty) 'text': message.trim(),
    });
  }
}

Future<void> launchSupportUri(BuildContext context, Uri uri) async {
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    showErrorSnackBar(context, 'Could not open that app. Try again.');
  }
}
