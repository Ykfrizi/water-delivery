import 'package:flutter/material.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/customer/data/customer_api.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/paystack_checkout_screen.dart';
import 'package:url_launcher/url_launcher.dart';

String? orderNumberFromCheckout(Map<String, dynamic> data) {
  final numbers = orderNumbersFromCheckout(data);
  return numbers.isEmpty ? null : numbers.first;
}

/// Collects one or more order numbers from a checkout / payment payload.
List<String> orderNumbersFromCheckout(Map<String, dynamic> data) {
  final found = <String>[];

  void add(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty || found.contains(v)) return;
    found.add(v);
  }

  void addFromList(dynamic raw) {
    if (raw is! List) return;
    for (final item in raw) {
      if (item is Map) {
        add(
          _deepString(Map<String, dynamic>.from(item), const [
            'order_number',
            'orderNumber',
            'id',
          ]),
        );
      } else {
        add(item?.toString());
      }
    }
  }

  addFromList(data['order_numbers']);
  addFromList(data['orderNumbers']);
  addFromList(data['orders']);

  add(
    _deepString(data, const [
      'order_number',
      'orderNumber',
      'id',
    ]),
  );

  final order = data['order'];
  if (order is Map) {
    add(
      _deepString(Map<String, dynamic>.from(order), const [
        'order_number',
        'orderNumber',
        'id',
      ]),
    );
  }

  for (final nestedKey in const ['data', 'payment', 'result', 'meta']) {
    final nested = data[nestedKey];
    if (nested is! Map) continue;
    final map = Map<String, dynamic>.from(nested);
    addFromList(map['order_numbers']);
    addFromList(map['orderNumbers']);
    addFromList(map['orders']);
    add(
      _deepString(map, const [
        'order_number',
        'orderNumber',
        'id',
      ]),
    );
  }

  return found;
}

/// In-app Paystack checkout → auto-verify on return (no manual "I have paid").
Future<bool> runPaystackPaymentFlow({
  required BuildContext context,
  required CustomerApi api,
  required String token,
  required String orderNumber,
  List<String>? orderNumbers,
  Map<String, dynamic>? checkoutOrInitPayload,
}) async {
  final numbers = <String>[
    ...?orderNumbers,
    if (orderNumber.trim().isNotEmpty) orderNumber.trim(),
  ];
  final uniqueNumbers = <String>[];
  for (final n in numbers) {
    final t = n.trim();
    if (t.isNotEmpty && !uniqueNumbers.contains(t)) uniqueNumbers.add(t);
  }
  if (uniqueNumbers.isEmpty) {
    if (context.mounted) {
      showErrorSnackBar(context, 'Missing order number for Paystack.');
    }
    return false;
  }

  final label = uniqueNumbers.length == 1
      ? 'Order #${uniqueNumbers.first}'
      : 'Orders ${uniqueNumbers.map((n) => '#$n').join(', ')}';

  // Recover a MoMo charge that already succeeded if verify never ran.
  if (checkoutOrInitPayload == null) {
    try {
      await api.verifyPaystackPayment(token, orderNumbers: uniqueNumbers);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label paid successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return true;
    } catch (_) {}
  }

  Map<String, dynamic> init = checkoutOrInitPayload ?? {};
  var authUrl = paystackAuthorizationUrl(init);
  String? reference = _deepString(init, const [
    'reference',
    'payment_reference',
    'paymentReference',
    'access_code',
  ]);

  if (authUrl == null || authUrl.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opening Paystack…'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        init = await api.initializePaystackPayment(
          token,
          orderNumbers: uniqueNumbers,
          callbackUrl: PaystackCheckoutScreen.callbackUrl,
        );
        lastError = null;
        break;
      } catch (e) {
        lastError = e;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }
      }
    }
    if (lastError != null) {
      if (context.mounted) {
        if (lastError is ApiException) {
          showErrorSnackBar(context, lastError.message);
        } else {
          showErrorSnackBar(context, lastError.toString());
        }
      }
      return false;
    }
    if (!context.mounted) return false;
    authUrl = paystackAuthorizationUrl(init);
    reference ??= _deepString(init, const [
      'reference',
      'payment_reference',
      'paymentReference',
      'access_code',
    ]);
  }

  if (authUrl == null || authUrl.isEmpty) {
    if (context.mounted) {
      showErrorSnackBar(
        context,
        'Paystack did not return a payment link. Try Pay with Paystack on the order.',
      );
    }
    return false;
  }

  // Prefer in-app WebView so we can detect the return URL and auto-verify.
  final checkoutResult = await Navigator.of(context).push<PaystackCheckoutResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PaystackCheckoutScreen(
        authorizationUrl: authUrl!,
        initialReference: reference,
      ),
    ),
  );

  if (!context.mounted) return false;

  if (checkoutResult == null || checkoutResult.cancelled) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label — payment cancelled.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return false;
  }

  if (!checkoutResult.completed) {
    // Fallback: open external browser + offer verify (rare WebView failure path).
    final opened = await openPaystackUrl(authUrl);
    if (!context.mounted) return false;
    if (!opened) {
      showErrorSnackBar(
        context,
        'Could not open Paystack. Check that a browser is available, then try again.',
      );
      return false;
    }
    final verify = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Complete payment on Paystack'),
        content: const Text(
          'Finish paying in the browser, then return here to verify.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Verify later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('I have paid, verify'),
          ),
        ],
      ),
    );
    if (verify != true || !context.mounted) return false;
  }

  final refToVerify = () {
    final fromCheckout = checkoutResult.reference?.trim();
    if (fromCheckout != null && fromCheckout.isNotEmpty) return fromCheckout;
    return reference;
  }();

  var loaderShown = false;
  try {
    if (context.mounted) {
      loaderShown = true;
      showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Confirming payment…'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    await api.verifyPaystackPayment(
      token,
      orderNumbers: uniqueNumbers,
      reference: refToVerify,
    );

    if (context.mounted) {
      if (loaderShown) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label paid successfully'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return true;
  } on ApiException catch (e) {
    if (context.mounted) {
      if (loaderShown) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      showErrorSnackBar(context, e.message);
    }
    return false;
  } catch (e) {
    if (context.mounted) {
      if (loaderShown) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      showErrorSnackBar(context, e.toString());
    }
    return false;
  }
}

/// Finds Paystack's hosted checkout URL in common API response shapes.
String? paystackAuthorizationUrl(Map<String, dynamic> data) {
  return _deepString(data, const [
    'authorization_url',
    'authorizationUrl',
    'checkout_url',
    'checkoutUrl',
    'payment_url',
    'paymentUrl',
    'redirect_url',
    'redirectUrl',
    'url',
  ]);
}

Future<bool> openPaystackUrl(String authUrl) async {
  final uri = Uri.tryParse(authUrl.trim());
  if (uri == null) return false;

  final modes = <LaunchMode>[
    LaunchMode.inAppBrowserView,
    LaunchMode.externalApplication,
    LaunchMode.platformDefault,
  ];

  for (final mode in modes) {
    try {
      if (await canLaunchUrl(uri)) {
        final ok = await launchUrl(uri, mode: mode);
        if (ok) return true;
      } else {
        final ok = await launchUrl(uri, mode: mode);
        if (ok) return true;
      }
    } catch (_) {
      continue;
    }
  }
  return false;
}

String? _deepString(Map<String, dynamic> data, List<String> keys) {
  final direct = _firstString(data, keys);
  if (direct != null) return direct;

  for (final nestedKey in const [
    'data',
    'payment',
    'paystack',
    'meta',
    'result',
    'attributes',
  ]) {
    final nested = data[nestedKey];
    if (nested is Map) {
      final found = _deepString(Map<String, dynamic>.from(nested), keys);
      if (found != null) return found;
    }
  }
  return null;
}

String? _firstString(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  return null;
}
