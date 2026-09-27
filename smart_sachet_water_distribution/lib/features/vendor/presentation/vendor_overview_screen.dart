import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/core/location/device_location_service.dart';
import 'package:smart_sachet_water_distribution/core/money/currency.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/vendor/data/vendor_api.dart';
import 'package:smart_sachet_water_distribution/features/vendor/domain/vendor_operations_report.dart';
import 'package:smart_sachet_water_distribution/features/vendor/domain/vendor_order_status.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/features/support/presentation/help_support_screen.dart';
import 'package:smart_sachet_water_distribution/features/vendor/presentation/vendor_account_screen.dart';

/// Snapshot cards: orders, catalog size, delivery zones (handoff §3).
class VendorOverviewScreen extends StatefulWidget {
  const VendorOverviewScreen({
    super.key,
    required this.onOpenOrders,
    required this.onOpenMap,
    required this.onOpenProducts,
    required this.onOpenWithdrawals,
  });

  final VoidCallback onOpenOrders;
  final VoidCallback onOpenMap;
  final VoidCallback onOpenProducts;
  final VoidCallback onOpenWithdrawals;

  @override
  State<VendorOverviewScreen> createState() => _VendorOverviewScreenState();
}

class _VendorOverviewScreenState extends State<VendorOverviewScreen> {
  bool _loading = true;
  String? _error;
  String? _partialWarning;
  int _orderCount = 0;
  int _pendingApprovals = 0;
  int _productCount = 0;
  int _zoneCount = 0;
  int _activeOrders = 0;
  VendorReportPeriod _period = VendorReportPeriod.today;
  List<Map<String, dynamic>> _orders = const [];
  VendorOperationsReport? _report;
  Map<String, dynamic>? _wallet;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) return;
    final api = VendorApi(context.read<Dio>());
    setState(() {
      _loading = true;
      _error = null;
      _partialWarning = null;
    });

    final failed = <String>[];
    var orders = <Map<String, dynamic>>[];
    var products = <Map<String, dynamic>>[];
    var zones = <Map<String, dynamic>>[];

    try {
      orders = await api.listOrders(token, perPage: 100);
      orders = orders.where(orderIsPaidForVendor).toList();
    } catch (_) {
      failed.add('orders');
    }
    try {
      products = await api.listProducts(token);
    } catch (_) {
      failed.add('products');
    }
    try {
      zones = await api.listZones(token);
    } catch (_) {
      failed.add('zones');
    }
    Map<String, dynamic>? wallet;
    try {
      wallet = await api.getWallet(token);
    } catch (_) {}

    if (!mounted) return;

    if (failed.length == 3) {
      setState(() {
        _error =
            'Could not load dashboard (orders, products, zones). Check API URL and login.';
        _loading = false;
      });
      return;
    }

    final active = orders.where((o) {
      final s = o['status']?.toString().toLowerCase() ?? '';
      return s == 'pending' ||
          s == 'processing' ||
          s == 'confirmed' ||
          s == 'preparing';
    }).length;
    final pendingApprovals = orders.where((o) {
      final s = o['status']?.toString().toLowerCase() ?? '';
      return s == 'pending' ||
          s == 'awaiting_approval' ||
          s == 'awaiting_vendor' ||
          s == 'new';
    }).length;

    setState(() {
      _orders = orders;
      _orderCount = orders.length;
      _activeOrders = active;
      _pendingApprovals = pendingApprovals;
      _productCount = products.length;
      _zoneCount = zones.length;
      _report = VendorOperationsReport.fromData(
        orders: orders,
        productCount: products.length,
        zoneCount: zones.length,
        period: _period,
      );
      _wallet = wallet;
      _partialWarning = failed.isEmpty
          ? null
          : 'Could not refresh: ${failed.join(", ")}. Pull to retry.';
      _loading = false;
    });
  }

  Future<void> _editStoreProfile() async {
    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) return;
    final api = VendorApi(context.read<Dio>());
    Map<String, dynamic> profile;
    try {
      profile = await api.getProfile(token);
    } on ApiException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
      return;
    }

    final businessCtrl =
        TextEditingController(text: profile['business_name']?.toString() ?? '');
    final nameCtrl = TextEditingController(text: profile['name']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: profile['phone']?.toString() ?? '');
    final latCtrl = TextEditingController(
      text: (profile['latitude'] ?? profile['lat'])?.toString() ?? '',
    );
    final lngCtrl = TextEditingController(
      text: (profile['longitude'] ?? profile['lng'])?.toString() ?? '',
    );
    var locating = false;

    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Store profile'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: businessCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Business name',
                      hintText: 'Optional · handoff vendor register',
                    ),
                  ),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Your name'),
                  ),
                  TextField(
                    controller: phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Phone'),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: locating
                        ? null
                        : () async {
                            setDialogState(() => locating = true);
                            final pos = await const DeviceLocationService()
                                .getPositionOrExplain(context);
                            if (pos != null) {
                              latCtrl.text = pos.latitudeLabel;
                              lngCtrl.text = pos.longitudeLabel;
                            }
                            if (context.mounted) {
                              setDialogState(() => locating = false);
                            }
                          },
                    icon: locating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded),
                    label: Text(
                      locating ? 'Reading GPS…' : 'Use my location',
                    ),
                  ),
                  TextField(
                    controller: latCtrl,
                    decoration: const InputDecoration(labelText: 'Latitude'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                  TextField(
                    controller: lngCtrl,
                    decoration: const InputDecoration(labelText: 'Longitude'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    void disposeCtrls() {
      businessCtrl.dispose();
      nameCtrl.dispose();
      phoneCtrl.dispose();
      latCtrl.dispose();
      lngCtrl.dispose();
    }

    if (ok != true) {
      disposeCtrls();
      return;
    }

    try {
      await api.updateProfile(
        token,
        {
          if (businessCtrl.text.trim().isNotEmpty)
            'business_name': businessCtrl.text.trim(),
          if (nameCtrl.text.trim().isNotEmpty) 'name': nameCtrl.text.trim(),
          if (phoneCtrl.text.trim().isNotEmpty) 'phone': phoneCtrl.text.trim(),
          if (latCtrl.text.trim().isNotEmpty)
            'latitude': double.tryParse(latCtrl.text.trim()),
          if (lngCtrl.text.trim().isNotEmpty)
            'longitude': double.tryParse(lngCtrl.text.trim()),
        },
      );
      disposeCtrls();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile saved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } on ApiException catch (e) {
      disposeCtrls();
      if (mounted) showErrorSnackBar(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final greeting = context.select<AuthController, String>(
      (a) => a.session?.user.greeting ?? 'Hello!',
    );
    final name = context.select<AuthController, String>(
      (a) => a.session?.user.name ?? '',
    );

    return Container(
      decoration: roleGradientDecoration(UserRole.vendor),
      child: SafeArea(
        child: RefreshIndicator(
          color: Colors.white,
          backgroundColor: roleAccent(UserRole.vendor),
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: BrandHeader(
                  title: greeting,
                  subtitle: [
                    if (name.trim().isNotEmpty &&
                        name.trim().toLowerCase() != 'user')
                      name,
                  ].join(' · '),
                  actions: [
                    HeaderIconButton(
                      icon: Icons.support_agent_outlined,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const HelpSupportScreen(
                              role: UserRole.vendor,
                            ),
                          ),
                        );
                      },
                      tooltip: 'Help & support',
                    ),
                    HeaderIconButton(
                      icon: Icons.person_pin_circle_outlined,
                      onPressed: widget.onOpenMap,
                      tooltip: 'Customer map',
                    ),
                    HeaderIconButton(
                      icon: Icons.storefront_outlined,
                      onPressed: _loading
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => VendorAccountScreen(
                                    pendingApprovals: _pendingApprovals,
                                    walletAvailableLabel: formatMoneyDynamic(
                                      _wallet?['available'],
                                    ),
                                    onOpenOrders: widget.onOpenOrders,
                                    onOpenMap: widget.onOpenMap,
                                    onOpenProducts: widget.onOpenProducts,
                                    onOpenWithdrawals: widget.onOpenWithdrawals,
                                    onEditStoreProfile: _editStoreProfile,
                                  ),
                                ),
                              );
                            },
                      tooltip: 'Account',
                    ),
                    HeaderIconButton(
                      icon: Icons.logout_rounded,
                      onPressed: () =>
                          context.read<AuthController>().logout(),
                      tooltip: 'Sign out',
                    ),
                  ],
                ),
              ),
              if (_partialWarning != null && !_loading && _error == null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      _partialWarning!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.amber.shade200,
                      ),
                    ),
                  ),
                ),
              if (_loading)
                const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                )
              else if (_error != null)
                SliverFillRemaining(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _load, child: const Text('Retry')),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _StatGlassCard(
                                icon: Icons.pending_actions_rounded,
                                label: 'To approve',
                                value: '$_pendingApprovals',
                                caption: 'awaiting your OK',
                                onTap: widget.onOpenOrders,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatGlassCard(
                                icon: Icons.receipt_long_rounded,
                                label: 'Pipeline',
                                value: '$_activeOrders',
                                caption: 'of $_orderCount orders',
                                onTap: widget.onOpenOrders,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _StatGlassCard(
                                icon: Icons.inventory_2_rounded,
                                label: 'SKU count',
                                value: '$_productCount',
                                caption: 'products live',
                                onTap: widget.onOpenProducts,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StatGlassCard(
                                icon: Icons.account_balance_wallet_rounded,
                                label: 'Withdraw',
                                value: formatMoneyDynamic(_wallet?['available']),
                                caption: 'available to cash out',
                                onTap: widget.onOpenWithdrawals,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _StatGlassCard(
                          icon: Icons.person_pin_circle_rounded,
                          label: 'Customer map',
                          value: 'GPS',
                          caption: 'See who ordered & where to deliver',
                          wide: true,
                          onTap: widget.onOpenMap,
                        ),
                        if (_report != null) ...[
                          const SizedBox(height: 22),
                          _VendorStoreReport(
                            report: _report!,
                            period: _period,
                            onPeriodChanged: (period) {
                              setState(() {
                                _period = period;
                                _report = VendorOperationsReport.fromData(
                                  orders: _orders,
                                  productCount: _productCount,
                                  zoneCount: _zoneCount,
                                  period: period,
                                );
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatGlassCard extends StatelessWidget {
  const _StatGlassCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    required this.onTap,
    this.wide = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final VoidCallback onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.all(wide ? 18 : 14),
          child: wide
              ? Row(
                  children: [
                    Icon(icon, color: Colors.white, size: 32),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: Colors.white.withValues(alpha: 0.75),
                              )),
                          Text(
                            value,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            caption,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.7)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: Colors.white, size: 26),
                    const SizedBox(height: 10),
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    Text(
                      value,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      caption,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _VendorStoreReport extends StatefulWidget {
  const _VendorStoreReport({
    required this.report,
    required this.period,
    required this.onPeriodChanged,
  });

  final VendorOperationsReport report;
  final VendorReportPeriod period;
  final ValueChanged<VendorReportPeriod> onPeriodChanged;

  @override
  State<_VendorStoreReport> createState() => _VendorStoreReportState();
}

class _VendorStoreReportState extends State<_VendorStoreReport> {
  late DateTime _now;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = roleAccent(UserRole.vendor);
    final report = widget.report;
    final paystackTotal = report.paystackStatus.fold<int>(
      0,
      (n, s) => n + s.count,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Store report',
          style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white.withValues(alpha: 0.9),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          formatReportDateTime(_now),
          style: theme.textTheme.titleSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          '${report.period.label} · ${report.totalOrders} orders',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final period in VendorReportPeriod.values)
              HeaderFilterChip(
                label: period.label,
                selected: widget.period == period,
                onSelected: (_) => widget.onPeriodChanged(period),
                accent: accent,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Estimated revenue',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                report.revenueLabel,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Excludes cancelled · ${report.deliveredOrders} delivered · '
                '${report.cancelledOrders} cancelled',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                      label: 'Out for delivery',
                      value: '${report.outForDelivery}',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniStat(
                      label: 'Catalog SKUs',
                      value: '${report.productCount}',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MiniStat(
                      label: 'Zones',
                      value: '${report.zoneCount}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Paystack', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Collected ${report.paystackPaidLabel} · '
                '${report.paystackPaidCount} paid · '
                '${report.paystackPendingCount} pending',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (report.paystackStatus.isEmpty)
                Text(
                  'No Paystack checkouts in ${report.period.label.toLowerCase()}.',
                  style: theme.textTheme.bodyMedium,
                )
              else ...[
                for (final slice in report.paystackStatus)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                slice.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text('${slice.count}'),
                          ],
                        ),
                        if (slice.amountLabel.isNotEmpty)
                          Text(
                            slice.amountLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: slice.shareOf(paystackTotal),
                            minHeight: 8,
                            backgroundColor: accent.withValues(alpha: 0.12),
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (report.recentPaystack.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Recent Paystack payments',
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  for (final p in report.recentPaystack)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.orderLabel,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  p.reference,
                                  style: theme.textTheme.bodySmall,
                                ),
                                Text(
                                  p.at == null
                                      ? p.status
                                      : '${p.status} · ${formatReportDateTime(p.at!)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            p.amountLabel,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _BreakdownCard(
          title: 'Orders by date',
          accent: accent,
          total: report.totalOrders,
          slices: report.ordersByDay,
        ),
        const SizedBox(height: 12),
        _BreakdownCard(
          title: 'Orders by status',
          accent: accent,
          total: report.totalOrders,
          slices: report.ordersByStatus,
        ),
        const SizedBox(height: 12),
        _BreakdownCard(
          title: 'Payment method',
          accent: accent,
          total: report.totalOrders,
          slices: report.ordersByPayment,
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.title,
    required this.accent,
    required this.total,
    required this.slices,
  });

  final String title;
  final Color accent;
  final int total;
  final List<VendorReportSlice> slices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '$total orders in this snapshot',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (slices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No orders yet — this report fills in as customers place orders.',
                style: theme.textTheme.bodyMedium,
              ),
            )
          else
            ...slices.map(
              (slice) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            slice.label,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          '${slice.count}',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (slice.amountLabel.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        slice.amountLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: slice.shareOf(total),
                        minHeight: 8,
                        backgroundColor: accent.withValues(alpha: 0.12),
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
