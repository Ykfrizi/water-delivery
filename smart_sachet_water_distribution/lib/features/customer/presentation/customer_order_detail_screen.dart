import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/data/customer_api.dart';
import 'package:smart_sachet_water_distribution/features/customer/domain/order_display.dart';
import 'package:smart_sachet_water_distribution/features/customer/domain/order_receipt.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/order_tracking_screen.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/paystack_payment_flow.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/vendor_review_composer.dart';

/// Full-screen order detail — structured layout + cancel when pending.
class CustomerOrderDetailScreen extends StatefulWidget {
  const CustomerOrderDetailScreen({
    super.key,
    required this.orderNumber,
    this.summaryRow,
  });

  final String orderNumber;
  final Map<String, dynamic>? summaryRow;

  @override
  State<CustomerOrderDetailScreen> createState() =>
      _CustomerOrderDetailScreenState();
}

class _CustomerOrderDetailScreenState extends State<CustomerOrderDetailScreen> {
  Map<String, dynamic>? _order;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  Future<void> _fetch() async {
    final auth = context.read<AuthController>();
    final api = CustomerApi(context.read<Dio>());
    final token = auth.token;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final m = await api.getOrder(token, widget.orderNumber);
      if (!mounted) return;
      setState(() {
        _order = m;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _statusText(Map<String, dynamic> o) {
    final raw = o['status']?.toString() ?? '—';
    final lower = raw.toLowerCase();
    if (lower == 'pending' ||
        lower == 'awaiting_approval' ||
        lower == 'awaiting_vendor' ||
        lower == 'new') {
      return 'Awaiting vendor approval';
    }
    return raw;
  }

  bool _isPending(Map<String, dynamic> o) {
    final s = o['status']?.toString().toLowerCase() ?? '';
    return s == 'pending' ||
        s == 'awaiting_approval' ||
        s == 'awaiting_vendor' ||
        s == 'new';
  }

  bool _isPaid(Map<String, dynamic> o) {
    final paymentStatus = o['payment_status']?.toString().toLowerCase();
    final payment = o['payment'];
    final nestedStatus = payment is Map
        ? payment['status']?.toString().toLowerCase()
        : null;
    return paymentStatus == 'paid' ||
        nestedStatus == 'paid' ||
        o['paid_at'] != null;
  }

  bool _canPay(Map<String, dynamic> o) {
    final status = o['status']?.toString().toLowerCase();
    return !_isPaid(o) && status != 'cancelled' && status != 'delivered';
  }

  bool _isDelivered(Map<String, dynamic> o) => orderIsDelivered(o);

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (c) => AlertDialog(
        title: const Text('Cancel this order?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yes, cancel')),
        ],
      ),
    );
    if (ok != true) return;
    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) return;
    try {
      await CustomerApi(context.read<Dio>())
          .cancelOrder(token, widget.orderNumber);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
    }
  }

  Future<void> _payWithPaystack() async {
    final auth = context.read<AuthController>();
    final api = CustomerApi(context.read<Dio>());
    final token = auth.token;
    if (token == null) return;
    try {
      final verified = await runPaystackPaymentFlow(
        context: context,
        api: api,
        token: token,
        orderNumber: widget.orderNumber,
      );
      if (verified && mounted) await _fetch();
    } on ApiException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = customerAppTheme();
    const accent = kCustomerBlue;

    final data = _order ?? widget.summaryRow ?? {};
    final lines = orderLineItems(data);
    final shippingLines = customerShippingLines(data['shipping_address']);
    final totals = data['totals_by_currency'] ?? data['totals'] ?? data['total'];

    return Theme(
      data: theme,
      child: Scaffold(
        body: Container(
          decoration: authGradientDecoration(),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: Colors.white,
                      ),
                      Expanded(
                        child: Text(
                          'Order #${widget.orderNumber}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _loading ? null : _fetch,
                        icon: const Icon(Icons.refresh_rounded),
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    decoration: BoxDecoration(
                      color: kCustomerGray,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _error != null
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(_error!, textAlign: TextAlign.center),
                                        const SizedBox(height: 12),
                                        FilledButton(onPressed: _fetch, child: const Text('Retry')),
                                      ],
                                    ),
                                  ),
                                )
                              : ListView(
                                  padding: const EdgeInsets.all(18),
                                  children: [
                                    _StatusBanner(status: _statusText(data)),
                                    if (_isDelivered(data) &&
                                        (orderVendorSlug(data) ?? '')
                                            .isNotEmpty) ...[
                                      const SizedBox(height: 14),
                                      VendorReviewComposer(
                                        vendorSlug: orderVendorSlug(data)!,
                                        onSubmitted: _fetch,
                                      ),
                                    ],
                                    const SizedBox(height: 14),
                                    _SectionCard(
                                      title: 'Summary',
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          _kv('Status', _statusText(data)),
                                          if (data['created_at'] != null)
                                            _kv('Placed', data['created_at'].toString()),
                                          if (data['updated_at'] != null)
                                            _kv('Updated', data['updated_at'].toString()),
                                          if (data['voucher_code'] != null &&
                                              data['voucher_code']
                                                  .toString()
                                                  .isNotEmpty)
                                            _kv(
                                              'Voucher',
                                              data['voucher_code'].toString(),
                                            ),
                                          if ((num.tryParse(
                                                    '${data['discount_amount'] ?? ''}',
                                                  ) ??
                                                  0) >
                                              0)
                                            _kv(
                                              'Discount',
                                              prettyTotals(data['discount_amount']),
                                            ),
                                          if (data['notes'] != null &&
                                              data['notes'].toString().isNotEmpty)
                                            _kv('Notes', data['notes'].toString()),
                                        ],
                                      ),
                                    ),
                                    if (lines.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      _SectionCard(
                                        title: 'Items (${lines.length})',
                                        child: Column(
                                          children: [
                                            for (final line in lines)
                                              Padding(
                                                padding: const EdgeInsets.only(bottom: 10),
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        orderLineTitle(line),
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                    Text(
                                                      '×${orderLineQty(line) ?? '?'}',
                                                      style: theme.textTheme.bodyMedium,
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      orderLinePrice(line) ?? '',
                                                      style: theme.textTheme.bodyMedium?.copyWith(
                                                        color: accent,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    if (shippingLines.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      _SectionCard(
                                        title: 'Delivery address',
                                        child: Text(
                                          shippingLines.join('\n'),
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            height: 1.45,
                                            color: kOnLight,
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (totals != null) ...[
                                      const SizedBox(height: 12),
                                      _SectionCard(
                                        title: 'Totals',
                                        child: SelectableText(
                                          prettyTotals(totals),
                                          style: theme.textTheme.bodyMedium,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 18),
                                    FilledButton.icon(
                                      onPressed: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                OrderTrackingScreen(
                                              orderNumber: widget.orderNumber,
                                              initialOrder: data,
                                            ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.map_rounded),
                                      label: const Text('Track on map'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: accent,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    OutlinedButton.icon(
                                      onPressed: () async {
                                        try {
                                          await OrderReceipt.share(data);
                                        } catch (e) {
                                          if (context.mounted) {
                                            showErrorSnackBar(
                                              context,
                                              e.toString(),
                                            );
                                          }
                                        }
                                      },
                                      icon: const Icon(Icons.ios_share_rounded),
                                      label: const Text('Share receipt PDF'),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
                                    ),
                                    if (_canPay(data)) ...[
                                      const SizedBox(height: 10),
                                      FilledButton.icon(
                                        onPressed: _payWithPaystack,
                                        icon: const Icon(Icons.payment_rounded),
                                        label: const Text('Pay / confirm Paystack'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: accent,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                        ),
                                      ),
                                    ],
                                    if (_isPending(data)) ...[
                                      const SizedBox(height: 10),
                                      OutlinedButton.icon(
                                        onPressed: _cancel,
                                        icon: const Icon(Icons.cancel_outlined),
                                        label: const Text('Cancel order'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red.shade800,
                                          side: BorderSide(color: Colors.red.shade300),
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                        ),
                                      ),
                                    ],
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
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              k,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          ),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            kCustomerBlue.withValues(alpha: 0.15),
            kCustomerBlue.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCustomerBlue.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag_rounded, color: kCustomerBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Status',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                ),
                Text(
                  status,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
