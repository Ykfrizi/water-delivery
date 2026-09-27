import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/location/device_location_service.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/domain/order_display.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/map_location_parser.dart';
import 'package:smart_sachet_water_distribution/features/maps/presentation/order_location_preview.dart';
import 'package:smart_sachet_water_distribution/features/vendor/data/vendor_api.dart';
import 'package:smart_sachet_water_distribution/features/vendor/data/vendor_auto_approve_store.dart';
import 'package:smart_sachet_water_distribution/features/vendor/domain/delivery_share.dart';
import 'package:smart_sachet_water_distribution/features/vendor/domain/vendor_order_status.dart';
import 'package:smart_sachet_water_distribution/features/vendor/presentation/vendor_auto_approve_screen.dart';
import 'package:smart_sachet_water_distribution/features/vendor/presentation/vendor_delivery_nav_screen.dart';
import 'package:url_launcher/url_launcher.dart';

/// GET/PATCH /vendor/orders — every new order must be approved or rejected.
class VendorOrdersScreen extends StatefulWidget {
  const VendorOrdersScreen({super.key, this.onOpenCustomerMap});

  final VoidCallback? onOpenCustomerMap;

  @override
  State<VendorOrdersScreen> createState() => _VendorOrdersScreenState();
}

class _VendorOrdersScreenState extends State<VendorOrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  String? _error;
  Timer? _poll;

  /// Default to pending so the approval queue is front and center.
  String? _statusFilter = 'pending';

  static const _filters = <String?>[
    'pending',
    null,
    'processing',
    'shipped',
    'delivered',
    'cancelled',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final token = context.read<AuthController>().session?.token;
      if (token != null) {
        await context.read<VendorAutoApproveStore>().ensureLoaded(token);
      }
      if (mounted) _load();
    });
    _poll = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) return;
    final api = VendorApi(context.read<Dio>());
    final hasOrders = _orders.isNotEmpty;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await api.listOrders(
        token,
        status: _statusFilter,
      );
      if (!mounted) return;
      setState(() {
        _orders = list.where(orderIsPaidForVendor).toList();
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (silent && hasOrders) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (silent && hasOrders) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _label(Map<String, dynamic> o) {
    final n = o['order_number'] ?? o['orderNumber'] ?? o['id'];
    return n == null ? 'Order' : '#$n';
  }

  String? _orderNumber(Map<String, dynamic> o) {
    final n = (o['order_number'] ?? o['orderNumber'] ?? o['id'])?.toString();
    if (n == null || n.isEmpty) return null;
    return n;
  }

  Future<void> _dialCustomer(String? raw) async {
    final phone = raw?.trim() ?? '';
    if (phone.isEmpty) {
      if (mounted) {
        showErrorSnackBar(
          context,
          'This customer has not shared a phone number yet.',
        );
      }
      return;
    }
    final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final ok = await launchUrl(Uri(scheme: 'tel', path: digits));
    if (!ok && mounted) {
      showErrorSnackBar(context, 'Could not open the phone dialer.');
    }
  }

  Future<void> _approve(Map<String, dynamic> summary) async {
    final num = _orderNumber(summary);
    if (num == null) return;
    final auth = context.read<AuthController>();
    final api = VendorApi(context.read<Dio>());
    final token = auth.token;
    if (token == null) return;
    try {
      await api.approveOrder(token, num);
      try {
        await api.patchOrder(token, num, {
          'status': 'out_for_delivery',
        });
      } catch (_) {}
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order #$num accepted — starting directions')),
      );
      await _load();
      if (!mounted) return;
      await startVendorDeliveryNavigation(
        context,
        orderNumber: num,
        order: summary,
      );
    } on ApiException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
    }
  }

  Future<void> _reject(Map<String, dynamic> summary) async {
    final num = _orderNumber(summary);
    if (num == null) return;

    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (c) => AlertDialog(
        title: const Text('Reject this order?'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            hintText: 'Out of stock, outside zone…',
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true) {
      reasonCtrl.dispose();
      return;
    }

    final auth = context.read<AuthController>();
    final api = VendorApi(context.read<Dio>());
    final token = auth.token;
    if (token == null) {
      reasonCtrl.dispose();
      return;
    }
    try {
      await api.rejectOrder(token, num, reason: reasonCtrl.text);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Order #$num rejected')));
      await _load();
    } on ApiException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
    } finally {
      reasonCtrl.dispose();
    }
  }

  Future<void> _open(Map<String, dynamic> summary) async {
    final num = _orderNumber(summary);
    if (num == null) return;

    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) return;
    final api = VendorApi(context.read<Dio>());

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFAFAFA),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            maxChildSize: 0.94,
            minChildSize: 0.45,
            builder: (context, scroll) {
              return FutureBuilder<Map<String, dynamic>>(
                future: api.getOrder(token, num),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(snap.error.toString()),
                    );
                  }
                  final data = snap.data ?? {};
                  final lines = orderLineItems(data);
                  final shippingLines = customerShippingLines(
                    data['shipping_address'],
                  );
                  final totals =
                      data['totals_by_currency'] ??
                      data['totals'] ??
                      data['total'];
                  final statusText = data['status']?.toString() ?? '—';
                  final needsApproval = orderNeedsVendorApproval(statusText);
                  final accent = roleAccent(UserRole.vendor);
                  final customerPhone = customerPhoneFrom(data);

                  return ListView(
                    controller: scroll,
                    padding: const EdgeInsets.all(20),
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _label(summary),
                        style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _VendorOrderStatusChip(
                        status: statusText,
                        label: vendorOrderStatusLabel(statusText),
                        accent: accent,
                        needsApproval: needsApproval,
                      ),
                      const SizedBox(height: 14),
                      _VendorOrderDetailSection(
                        title: needsApproval
                            ? 'Customer location (before you approve)'
                            : 'Customer location',
                        child: OrderLocationPreview(order: data),
                      ),
                      const SizedBox(height: 14),
                      _VendorOrderDetailSection(
                        title: 'Summary',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _VendorOrderKv('Status', statusText),
                            _VendorOrderKv(
                              'Payment',
                              vendorPaymentKindLabel(data),
                            ),
                            if (data['created_at'] != null)
                              _VendorOrderKv(
                                'Placed',
                                data['created_at'].toString(),
                              ),
                            if (data['updated_at'] != null)
                              _VendorOrderKv(
                                'Updated',
                                data['updated_at'].toString(),
                              ),
                            if (data['notes'] != null &&
                                data['notes'].toString().isNotEmpty)
                              _VendorOrderKv('Notes', data['notes'].toString()),
                            if (customerPhone != null)
                              _VendorOrderKv('Customer phone', customerPhone),
                          ],
                        ),
                      ),
                      if (customerPhone != null) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _dialCustomer(customerPhone),
                          icon: const Icon(Icons.call_rounded),
                          label: Text('Call $customerPhone'),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _ShareDeliveryLinkButton(
                        api: api,
                        token: token,
                        orderNumber: num,
                        order: data,
                      ),
                      if (lines.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _VendorOrderDetailSection(
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
                                        style: Theme.of(
                                          ctx,
                                        ).textTheme.bodyMedium,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        orderLinePrice(line) ?? '',
                                        style: Theme.of(ctx)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
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
                        _VendorOrderDetailSection(
                          title: 'Delivery address',
                          child: Text(
                            shippingLines.join('\n'),
                            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                              height: 1.45,
                              color: kOnLight,
                            ),
                          ),
                        ),
                      ],
                      if (totals != null) ...[
                        const SizedBox(height: 12),
                        _VendorOrderDetailSection(
                          title: 'Totals',
                          child: SelectableText(
                            prettyTotals(totals),
                            style: Theme.of(ctx).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _VendorPaymentBanner(order: data),
                      const SizedBox(height: 12),
                      if (needsApproval)
                        _VendorOrderApprovalActions(
                          onApprove: () async {
                            try {
                              await api.approveOrder(token, num);
                              try {
                                await api.patchOrder(token, num, {
                                  'status': 'out_for_delivery',
                                });
                              } catch (_) {}
                              if (ctx.mounted) Navigator.pop(ctx);
                              await _load();
                              if (mounted) {
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Order #$num accepted — starting directions',
                                    ),
                                  ),
                                );
                                await startVendorDeliveryNavigation(
                                  this.context,
                                  orderNumber: num,
                                  order: data,
                                );
                              }
                            } on ApiException catch (e) {
                              if (ctx.mounted) {
                                showErrorSnackBar(ctx, e.message);
                              }
                            }
                          },
                          onReject: () async {
                            Navigator.pop(ctx);
                            await _reject(summary);
                          },
                        )
                      else
                        _VendorOrderStatusSave(
                          api: api,
                          token: token,
                          orderNumber: num,
                          rawStatus: data['status']?.toString(),
                          onNavigate: () {
                            if (ctx.mounted) Navigator.pop(ctx);
                            startVendorDeliveryNavigation(
                              this.context,
                              orderNumber: num,
                              order: data,
                            );
                          },
                          onSaved: (status) {
                            if (ctx.mounted) Navigator.pop(ctx);
                            _load();
                            if (status == 'out_for_delivery' ||
                                status == 'shipped') {
                              startVendorDeliveryNavigation(
                                this.context,
                                orderNumber: num,
                                order: data,
                              );
                            }
                          },
                        ),
                    ],
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = roleAccent(UserRole.vendor);
    final pendingCount = _orders
        .where((o) => orderNeedsVendorApproval(o['status']?.toString()))
        .length;

    return Container(
        decoration: roleGradientDecoration(UserRole.vendor),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BrandHeader(
                title: 'Orders inbox',
                subtitle: 'Approve every new order before fulfillment',
                actions: [
                  HeaderIconButton(
                    icon: Icons.schedule_rounded,
                    tooltip: 'Auto-approve schedule',
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const VendorAutoApproveScreen(),
                        ),
                      );
                      if (mounted) _load();
                    },
                  ),
                  if (widget.onOpenCustomerMap != null)
                    HeaderIconButton(
                      icon: Icons.person_pin_circle_outlined,
                      tooltip: 'Customer map',
                      onPressed: widget.onOpenCustomerMap,
                    ),
                ],
              ),
              Builder(
                builder: (context) {
                  final store = context.watch<VendorAutoApproveStore>();
                  final active = store.schedule.isActiveAt(DateTime.now());
                  if (!store.schedule.enabled && !active) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const VendorAutoApproveScreen(),
                          ),
                        );
                      },
                      child: StatusBanner(
                        active: active,
                        activeTitle: 'Auto-approve is ON',
                        idleTitle: 'Scheduled · waiting for window',
                        trailing: TextButton(
                          onPressed: () async {
                            final token = context
                                .read<AuthController>()
                                .session
                                ?.token;
                            if (token == null) return;
                            await store.stop(token);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Auto-approve stopped'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                          child: const Text('Stop'),
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (_statusFilter == 'pending' &&
                  !_loading &&
                  _error == null &&
                  pendingCount > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Material(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.pending_actions_rounded,
                            color: Colors.amber.shade900,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$pendingCount order${pendingCount == 1 ? '' : 's'} waiting for your approval',
                              style: TextStyle(
                                color: Colors.amber.shade900,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: _filters.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final s = _filters[i];
                    final selected = _statusFilter == s;
                    final label = switch (s) {
                      'pending' => 'Needs approval',
                      null => 'All',
                      _ => s,
                    };
                    return HeaderFilterChip(
                      selected: selected,
                      label: label,
                      onSelected: (_) {
                        setState(() => _statusFilter = s);
                        _load();
                      },
                      accent: accent,
                    );
                  },
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  decoration: BoxDecoration(
                    color: kVendorMint,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: _loading && _orders.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_error!),
                                  FilledButton(
                                    onPressed: _load,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            color: accent,
                            onRefresh: _load,
                            child: _orders.isEmpty
                                ? ListView(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    children: [
                                      const SizedBox(height: 80),
                                      Center(
                                        child: Text(
                                          _statusFilter == 'pending'
                                              ? 'No orders waiting for approval'
                                              : 'No orders',
                                        ),
                                      ),
                                    ],
                                  )
                                : ListView.builder(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.all(14),
                                    itemCount: _orders.length,
                                    itemBuilder: (context, i) {
                                      final o = _orders[i];
                                      final status =
                                          o['status']?.toString() ?? '—';
                                      final needsApproval =
                                          orderNeedsVendorApproval(status);
                                      final phone = customerPhoneFrom(o);
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: Material(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          elevation: 2,
                                          child: Column(
                                            children: [
                                              ListTile(
                                                title: Text(
                                                  _label(o),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                                subtitle: Text(
                                                  [
                                                    vendorPaymentKindLabel(o),
                                                    vendorOrderStatusLabel(
                                                      status,
                                                    ),
                                                    ?phone,
                                                  ].join(' · '),
                                                ),
                                                trailing: needsApproval
                                                    ? Chip(
                                                        label: Text(
                                                          orderIsPayOnDelivery(o)
                                                              ? 'POD'
                                                              : 'Paid',
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                          ),
                                                        ),
                                                        backgroundColor:
                                                            orderIsPayOnDelivery(
                                                                  o,
                                                                )
                                                            ? Colors.orange.shade100
                                                            : Colors.green.shade100,
                                                        side: BorderSide.none,
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                      )
                                                    : Chip(
                                                        label: Text(
                                                          vendorPaymentKindLabel(o),
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                        backgroundColor:
                                                            orderIsPayOnDelivery(
                                                                  o,
                                                                )
                                                            ? Colors.orange.shade50
                                                            : Colors.green.shade50,
                                                        side: BorderSide.none,
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                      ),
                                                onTap: () => _open(o),
                                              ),
                                              if (needsApproval)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                        12,
                                                        0,
                                                        12,
                                                        12,
                                                      ),
                                                  child: Column(
                                                    children: [
                                                      _VendorPaymentBanner(
                                                        order: o,
                                                      ),
                                                      const SizedBox(
                                                        height: 10,
                                                      ),
                                                      OrderLocationPreview(
                                                        order: o,
                                                        height: 148,
                                                      ),
                                                      const SizedBox(
                                                        height: 12,
                                                      ),
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: OutlinedButton(
                                                              onPressed: () =>
                                                                  _reject(o),
                                                              style: OutlinedButton.styleFrom(
                                                                foregroundColor:
                                                                    Colors
                                                                        .red
                                                                        .shade700,
                                                              ),
                                                              child: const Text(
                                                                'Reject',
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 10,
                                                          ),
                                                          Expanded(
                                                            flex: 2,
                                                            child: FilledButton(
                                                              onPressed: () =>
                                                                  _approve(o),
                                                              style: FilledButton.styleFrom(
                                                                backgroundColor:
                                                                    accent,
                                                              ),
                                                              child: const Text(
                                                                'Accept & navigate',
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }
}

class _VendorOrderDetailSection extends StatelessWidget {
  const _VendorOrderDetailSection({required this.title, required this.child});

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
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _VendorOrderKv extends StatelessWidget {
  const _VendorOrderKv(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _VendorOrderStatusChip extends StatelessWidget {
  const _VendorOrderStatusChip({
    required this.status,
    required this.label,
    required this.accent,
    required this.needsApproval,
  });

  final String status;
  final String label;
  final Color accent;
  final bool needsApproval;

  @override
  Widget build(BuildContext context) {
    final color = needsApproval ? Colors.amber.shade800 : accent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.18),
            color.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            needsApproval
                ? Icons.pending_actions_rounded
                : Icons.verified_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  needsApproval ? 'Vendor approval required' : 'Status',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: Colors.grey.shade700),
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (status != label)
                  Text(
                    'API: $status',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
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

class _VendorPaymentBanner extends StatelessWidget {
  const _VendorPaymentBanner({required this.order});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final payOnDelivery = orderIsPayOnDelivery(order);
    final bg = payOnDelivery ? Colors.orange.shade50 : Colors.green.shade50;
    final fg = payOnDelivery ? Colors.orange.shade900 : Colors.green.shade900;
    final icon = payOnDelivery
        ? Icons.payments_outlined
        : Icons.verified_rounded;
    final title = payOnDelivery ? 'Pay on delivery' : 'Already paid';
    final body = payOnDelivery
        ? 'Collect cash or MoMo from the customer when you deliver. Do not treat this as a Paystack payment.'
        : 'This customer paid online with Paystack before you accept.';

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: TextStyle(
                      color: fg,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VendorOrderApprovalActions extends StatefulWidget {
  const _VendorOrderApprovalActions({
    required this.onApprove,
    required this.onReject,
  });

  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;

  @override
  State<_VendorOrderApprovalActions> createState() =>
      _VendorOrderApprovalActionsState();
}

class _VendorOrderApprovalActionsState
    extends State<_VendorOrderApprovalActions> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final accent = roleAccent(UserRole.vendor);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(14),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'You must accept this order before you can prepare, ship, or mark it delivered. Accepting opens driving directions to the customer in Ho.',
              style: TextStyle(fontWeight: FontWeight.w600, height: 1.35),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          await widget.onReject();
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Reject'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          await widget.onApprove();
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Accept & navigate'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _VendorOrderStatusSave extends StatefulWidget {
  const _VendorOrderStatusSave({
    required this.api,
    required this.token,
    required this.orderNumber,
    required this.rawStatus,
    required this.onSaved,
    this.onNavigate,
  });

  final VendorApi api;
  final String token;
  final String orderNumber;
  final String? rawStatus;
  final ValueChanged<String> onSaved;
  final VoidCallback? onNavigate;

  @override
  State<_VendorOrderStatusSave> createState() => _VendorOrderStatusSaveState();
}

class _VendorOrderStatusSaveState extends State<_VendorOrderStatusSave> {
  /// Fulfillment statuses after vendor approval — pending is not offered here.
  static const _statuses = [
    'processing',
    'out_for_delivery',
    'delivered',
    'cancelled',
  ];

  late String _sel;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.rawStatus?.toLowerCase();
    _sel = r != null && _statuses.contains(r) ? r : _statuses.first;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(14),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'Order approved. Update fulfillment status as you prepare and deliver.',
              style: TextStyle(fontWeight: FontWeight.w600, height: 1.35),
            ),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButton<String>(
          isExpanded: true,
          value: _sel,
          hint: const Text('Fulfillment status'),
          items: _statuses
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: _saving ? null : (v) => setState(() => _sel = v ?? _sel),
        ),
        const SizedBox(height: 14),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: roleAccent(UserRole.vendor),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  try {
                    await widget.api.patchOrder(
                      widget.token,
                      widget.orderNumber,
                      {'status': _sel},
                    );
                    if (_sel == 'out_for_delivery' || _sel == 'shipped') {
                      try {
                        final pos = await const DeviceLocationService()
                            .tryGetCurrentPosition();
                        if (pos != null) {
                          await widget.api.updateCourierLocation(
                            widget.token,
                            widget.orderNumber,
                            latitude: pos.latitude,
                            longitude: pos.longitude,
                          );
                        }
                      } catch (_) {}
                    }
                    widget.onSaved(_sel);
                  } on ApiException catch (e) {
                    if (mounted) showErrorSnackBar(context, e.message);
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: _saving
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Update status'),
        ),
        if (widget.onNavigate != null) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _saving ? null : widget.onNavigate,
            icon: const Icon(Icons.navigation_rounded),
            label: const Text('Directions to customer'),
          ),
        ],
      ],
    );
  }
}

class _ShareDeliveryLinkButton extends StatefulWidget {
  const _ShareDeliveryLinkButton({
    required this.api,
    required this.token,
    required this.orderNumber,
    required this.order,
  });

  final VendorApi api;
  final String token;
  final String orderNumber;
  final Map<String, dynamic> order;

  @override
  State<_ShareDeliveryLinkButton> createState() =>
      _ShareDeliveryLinkButtonState();
}

class _ShareDeliveryLinkButtonState extends State<_ShareDeliveryLinkButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: _busy
          ? null
          : () async {
              setState(() => _busy = true);
              try {
                await shareVendorDeliveryLink(
                  api: widget.api,
                  token: widget.token,
                  orderNumber: widget.orderNumber,
                  order: widget.order,
                );
              } on ApiException catch (e) {
                if (!context.mounted) return;
                showErrorSnackBar(context, e.message);
              } catch (e) {
                if (!context.mounted) return;
                showErrorSnackBar(
                  context,
                  'Could not share the delivery link. Try again.',
                );
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
      icon: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.ios_share_rounded),
      label: Text(_busy ? 'Creating link…' : 'Share delivery link'),
    );
  }
}
