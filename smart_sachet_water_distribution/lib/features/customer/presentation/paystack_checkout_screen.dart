import 'package:flutter/material.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Result of an in-app Paystack checkout session.
class PaystackCheckoutResult {
  const PaystackCheckoutResult({
    required this.completed,
    this.reference,
    this.cancelled = false,
  });

  /// User finished (or reached a success/callback URL).
  final bool completed;
  final String? reference;
  final bool cancelled;
}

/// Opens Paystack's hosted page inside the app and detects return/callback.
class PaystackCheckoutScreen extends StatefulWidget {
  const PaystackCheckoutScreen({
    super.key,
    required this.authorizationUrl,
    this.initialReference,
  });

  final String authorizationUrl;
  final String? initialReference;

  /// HTTPS callback Paystack will redirect to; intercepted in the in-app WebView.
  static const callbackUrl = 'https://pay.smartsachet.local/paystack/callback';

  @override
  State<PaystackCheckoutScreen> createState() => _PaystackCheckoutScreenState();
}

class _PaystackCheckoutScreenState extends State<PaystackCheckoutScreen> {
  late final WebViewController _controller;
  var _loading = true;
  var _finishing = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            final handled = _handleUrl(request.url);
            if (handled) return NavigationDecision.prevent;
            return NavigationDecision.navigate;
          },
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) _handleUrl(url);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authorizationUrl));
  }

  bool _handleUrl(String url) {
    if (_finishing) return true;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;

    final ref = _referenceFromUri(uri) ?? widget.initialReference;

    // Custom app callback / dummy HTTPS return we intercept in-app.
    if (uri.scheme == 'smartsachet' ||
        uri.host.toLowerCase().contains('smartsachet.local') ||
        uri.path.toLowerCase().contains('paystack/callback') ||
        uri.path.toLowerCase().contains('payment/callback')) {
      _finish(
        PaystackCheckoutResult(completed: true, reference: ref),
      );
      return true;
    }

    // Paystack / backend success redirects often include reference + status.
    final looksSuccessful = _looksLikeSuccess(uri);
    final looksCancelled = _looksLikeCancel(uri);

    if (looksCancelled) {
      _finish(
        const PaystackCheckoutResult(completed: false, cancelled: true),
      );
      return true;
    }

    if (looksSuccessful && ref != null && ref.isNotEmpty) {
      _finish(PaystackCheckoutResult(completed: true, reference: ref));
      return true;
    }

    // Generic Paystack return: query has trxref/reference after leaving checkout.
    if (ref != null &&
        ref.isNotEmpty &&
        (uri.queryParameters.containsKey('trxref') ||
            uri.queryParameters.containsKey('reference')) &&
        !_isPaystackCheckoutHost(uri.host)) {
      _finish(PaystackCheckoutResult(completed: true, reference: ref));
      return true;
    }

    return false;
  }

  bool _isPaystackCheckoutHost(String host) {
    final h = host.toLowerCase();
    return h.contains('checkout.paystack.com') ||
        (h.contains('paystack.com') && h.startsWith('standard.'));
  }

  bool _looksLikeSuccess(Uri uri) {
    final s = uri.toString().toLowerCase();
    final status = (uri.queryParameters['status'] ??
            uri.queryParameters['payment_status'] ??
            '')
        .toLowerCase();
    if (status == 'success' || status == 'successful' || status == 'paid') {
      return true;
    }
    return s.contains('payment/success') ||
        s.contains('paystack/callback') ||
        s.contains('payment-success') ||
        s.contains('checkout/success');
  }

  bool _looksLikeCancel(Uri uri) {
    final s = uri.toString().toLowerCase();
    final status = (uri.queryParameters['status'] ?? '').toLowerCase();
    if (status == 'cancelled' || status == 'canceled' || status == 'failed') {
      return true;
    }
    return s.contains('payment/cancel') ||
        s.contains('checkout/cancel') ||
        s.contains('payment-cancelled');
  }

  String? _referenceFromUri(Uri uri) {
    for (final key in ['reference', 'trxref', 'txref', 'payment_reference']) {
      final v = uri.queryParameters[key]?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  void _finish(PaystackCheckoutResult result) {
    if (_finishing || !mounted) return;
    _finishing = true;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pay with Paystack'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => _finish(
            const PaystackCheckoutResult(completed: false, cancelled: true),
          ),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const LinearProgressIndicator(
              minHeight: 3,
              color: kCustomerBlue,
            ),
        ],
      ),
    );
  }
}
