import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_sachet_water_distribution/app/brand.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/support/support_contact.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';

class HelpSupportScreen extends StatefulWidget {
  const HelpSupportScreen({super.key, required this.role});

  final UserRole role;

  @override
  State<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends State<HelpSupportScreen> {
  final _message = TextEditingController();

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  String get _who => widget.role == UserRole.vendor ? 'Vendor' : 'Customer';

  String _composedMessage() {
    final extra = _message.text.trim();
    final buffer = StringBuffer('Hello, this is a $_who complaint from ${AppBrand.name}.');
    if (extra.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln()
        ..write(extra);
    }
    return buffer.toString();
  }

  Future<void> _email() async {
    final body = _composedMessage();
    final subject = '${AppBrand.name} $_who support';
    try {
      await launchSupportUri(
        context,
        SupportContact.gmailComposeUri(subject: subject, body: body),
      );
    } catch (_) {
      if (!mounted) return;
      await launchSupportUri(
        context,
        SupportContact.emailUri(subject: subject, body: body),
      );
    }
  }

  Future<void> _whatsapp() async {
    await launchSupportUri(
      context,
      SupportContact.whatsappUri(message: _composedMessage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = roleAppTheme(widget.role);
    final accent = roleAccent(widget.role);

    return Theme(
      data: theme,
      child: Scaffold(
        body: Container(
          decoration: roleGradientDecoration(widget.role),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BrandHeader(
                  title: 'Help & support',
                  subtitle: 'Send a complaint to Gmail or WhatsApp',
                  actions: [
                    HeaderIconButton(
                      icon: Icons.close_rounded,
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: ListView(
                      children: [
                        Text(
                          'Your message goes to ${SupportContact.email} or WhatsApp ${SupportContact.whatsappDisplay}.',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _message,
                          minLines: 4,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            labelText: 'Describe your complaint',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _email,
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.mail_outline_rounded),
                          label: const Text('Send to Gmail'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _whatsapp,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF128C7E),
                            side: const BorderSide(color: Color(0xFF128C7E)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: const Icon(Icons.chat_rounded),
                          label: const Text('Send on WhatsApp'),
                        ),
                        const SizedBox(height: 18),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.alternate_email_rounded),
                          title: const Text(SupportContact.email),
                          subtitle: const Text('Tap to copy'),
                          onTap: () async {
                            await Clipboard.setData(
                              const ClipboardData(text: SupportContact.email),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Email copied'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.phone_rounded),
                          title: const Text(SupportContact.whatsappDisplay),
                          subtitle: const Text('Tap to copy'),
                          onTap: () async {
                            await Clipboard.setData(
                              const ClipboardData(
                                text: '+${SupportContact.whatsappE164}',
                              ),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('WhatsApp number copied'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
