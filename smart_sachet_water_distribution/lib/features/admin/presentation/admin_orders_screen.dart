import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/admin/data/admin_orders_api.dart';
import 'package:smart_sachet_water_distribution/features/admin/domain/admin_order_summary.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';

const _kAdminDeep = kAdminGreenDeep;
const _kAdminCrimson = kAdminGreen;
const _kAdminRose = kAdminGreenSoft;

/// Admin shell — orders table & updates (handoff §4).
class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  List<AdminOrderSummary> _orders = [];
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();

  static const _statusFilters = <String?>[
    null,
    'pending',
    'processing',
    'shipped',
    'delivered',
    'cancelled',
  ];

  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = AdminOrdersApi(context.read<Dio>());
    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await api.listOrders(
        token,
        status: _statusFilter,
        orderNumber: _searchCtrl.text.trim().isEmpty
            ? null
            : _searchCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _orders = list;
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

  @override
  Widget build(BuildContext context) {
    final email = context.select<AuthController, String>(
      (a) => a.session?.user.email ?? '',
    );
    final busy = context.select<AuthController, bool>((a) => a.busy);
    final theme = adminAppTheme();

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: _kAdminDeep,
        body: Container(
          decoration: roleGradientDecoration(UserRole.admin),
          child: Stack(
            children: [
              Positioned(
                top: -80,
                right: -60,
                child: IgnorePointer(
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kAdminRose.withValues(alpha: 0.08),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 120,
                left: -40,
                child: IgnorePointer(
                  child: Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kAdminCrimson.withValues(alpha: 0.06),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AdminHeroBar(
                      theme: theme,
                      sessionEmail: email,
                      busy: busy,
                      onLogout: () => context.read<AuthController>().logout(),
                      orderCount: _loading ? null : _orders.length,
                      hasError: _error != null,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: _GlassSearchBar(
                        controller: _searchCtrl,
                        loading: _loading,
                        onSearch: _load,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SizedBox(
                        height: 42,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _statusFilters.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final s = _statusFilters[i];
                            final selected = _statusFilter == s;
                            final label = s == null
                                ? 'All orders'
                                : _chipLabel(s);
                            return _FilterPill(
                              label: label,
                              selected: selected,
                              onTap: () {
                                setState(() => _statusFilter = s);
                                _load();
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        color: _kAdminCrimson,
                        backgroundColor: Colors.white,
                        displacement: 48,
                        strokeWidth: 2.5,
                        onRefresh: _load,
                        child: _buildBody(theme),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading && _orders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.22),
          Center(
            child: Column(
              children: [
                SizedBox(
                  width: 52,
                  height: 52,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white.withValues(alpha: 0.95),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Loading orders…',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [_ErrorCard(message: _error!, onRetry: _load)],
      );
    }
    if (_orders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 32),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: Colors.white.withValues(alpha: 0.08),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  child: Icon(
                    Icons.receipt_long_rounded,
                    size: 44,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'No orders match',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Try another filter or search by order number.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.65),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      itemCount: _orders.length,
      itemBuilder: (context, i) {
        final o = _orders[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _OrderCard(
            order: o,
            onTap: o.orderNumber.isEmpty ? null : () => _openDetail(context, o),
          ),
        );
      },
    );
  }

  Future<void> _openDetail(BuildContext context, AdminOrderSummary o) async {
    final dio = context.read<Dio>();
    final api = AdminOrdersApi(dio);
    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.58,
            minChildSize: 0.38,
            maxChildSize: 0.94,
            builder: (context, scroll) {
              return Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 24,
                      offset: Offset(0, -4),
                      color: Color(0x40000000),
                    ),
                  ],
                ),
                child: FutureBuilder<Map<String, dynamic>>(
                  future: api.getOrder(token, o.orderNumber),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(
                            color: _kAdminCrimson,
                          ),
                        ),
                      );
                    }
                    if (snap.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: _kAdminCrimson,
                              size: 40,
                            ),
                            const SizedBox(height: 12),
                            Text(snap.error.toString()),
                          ],
                        ),
                      );
                    }
                    final data = snap.data ?? {};
                    return ListView(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                o.title,
                                style: Theme.of(ctx).textTheme.headlineSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF1A1A1A),
                                    ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close_rounded),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black.withValues(
                                  alpha: 0.06,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (o.status != null || data['status'] != null) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _StatusPill(
                              status: data['status']?.toString() ?? o.status!,
                              compact: false,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          'Payload',
                          style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF424242),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF263238),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.06),
                            ),
                          ),
                          child: SelectableText(
                            _prettyJson(data),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              height: 1.45,
                              color: Color(0xFFECEFF1),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        _AdminStatusPatch(
                          token: token,
                          orderNumber: o.orderNumber,
                          current: data['status']?.toString() ?? o.status,
                          api: api,
                          onPatched: () {
                            Navigator.pop(ctx);
                            _load();
                          },
                        ),
                      ],
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}

String _chipLabel(String s) {
  return s[0].toUpperCase() + s.substring(1);
}

Color _statusAccent(String? status) {
  switch (status?.toLowerCase()) {
    case 'pending':
      return const Color(0xFFFFA726);
    case 'processing':
      return const Color(0xFF42A5F5);
    case 'shipped':
      return const Color(0xFFAB47BC);
    case 'delivered':
      return const Color(0xFF66BB6A);
    case 'cancelled':
      return const Color(0xFF78909C);
    default:
      return const Color(0xFFB0BEC5);
  }
}

class _AdminHeroBar extends StatelessWidget {
  const _AdminHeroBar({
    required this.theme,
    required this.sessionEmail,
    required this.busy,
    required this.onLogout,
    required this.orderCount,
    required this.hasError,
  });

  final ThemeData theme;
  final String sessionEmail;
  final bool busy;
  final VoidCallback onLogout;
  final int? orderCount;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 10, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.22),
                  Colors.white.withValues(alpha: 0.08),
                ],
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white.withValues(alpha: 0.95),
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OPERATIONS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.55),
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Admin dashboard',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
                if (sessionEmail.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    sessionEmail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                ],
                if (orderCount != null && !hasError) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Text(
                      '$orderCount ${orderCount == 1 ? 'order' : 'orders'}',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: busy ? null : onLogout,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.14),
              foregroundColor: Colors.white,
            ),
            icon: busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.logout_rounded),
          ),
        ],
      ),
    );
  }
}

class _GlassSearchBar extends StatelessWidget {
  const _GlassSearchBar({
    required this.controller,
    required this.loading,
    required this.onSearch,
  });

  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withValues(alpha: 0.11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: 'Search by order number…',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: Colors.white.withValues(alpha: 0.75),
                  size: 26,
                ),
              ),
              onSubmitted: (_) => onSearch(),
            ),
          ),
          FilledButton(
            onPressed: loading ? null : onSearch,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _kAdminCrimson,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _kAdminCrimson,
                    ),
                  )
                : Text(
                    'Search',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFFFFFFFF), Color(0xFFF5F5F5)],
                  )
                : null,
            color: selected ? null : Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: selected
                  ? Colors.white.withValues(alpha: 0.95)
                  : Colors.white.withValues(alpha: 0.15),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected
                  ? _kAdminDeep
                  : Colors.white.withValues(alpha: 0.88),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});

  final AdminOrderSummary order;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = _statusAccent(order.status);
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [accent, accent.withValues(alpha: 0.65)],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                order.title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1A1A1A),
                                ),
                              ),
                            ),
                            if (order.status != null)
                              _StatusPill(status: order.status!, compact: true),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (order.customerEmail != null)
                          _MetaRow(
                            icon: Icons.mail_outline_rounded,
                            text: order.customerEmail!,
                          ),
                        if (order.vendorSlug != null) ...[
                          const SizedBox(height: 6),
                          _MetaRow(
                            icon: Icons.storefront_outlined,
                            text: order.vendorSlug!,
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text(
                              'View details',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: _kAdminCrimson,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 18,
                              color: _kAdminCrimson,
                            ),
                          ],
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

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF757575)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF616161),
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.compact});

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = _statusAccent(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Text(
        status,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: const Color(0xFF263238),
          fontWeight: FontWeight.w800,
          fontSize: compact ? 11.5 : 12.5,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withValues(alpha: 0.1),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 48,
            color: Colors.white.withValues(alpha: 0.85),
          ),
          const SizedBox(height: 14),
          Text(
            'Couldn’t load orders',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.75),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _kAdminCrimson,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

String _prettyJson(Map<String, dynamic> data) {
  try {
    return JsonEncoder.withIndent('  ').convert(data);
  } catch (_) {
    return data.toString();
  }
}

class _AdminStatusPatch extends StatefulWidget {
  const _AdminStatusPatch({
    required this.token,
    required this.orderNumber,
    required this.current,
    required this.api,
    required this.onPatched,
  });

  final String token;
  final String orderNumber;
  final String? current;
  final AdminOrdersApi api;
  final VoidCallback onPatched;

  @override
  State<_AdminStatusPatch> createState() => _AdminStatusPatchState();
}

class _AdminStatusPatchState extends State<_AdminStatusPatch> {
  static const _choices = [
    'pending',
    'processing',
    'shipped',
    'delivered',
    'cancelled',
  ];

  late String? _value;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    _value = c != null && _choices.contains(c) ? c : _choices.first;
  }

  Future<void> _save() async {
    if (_value == null || widget.orderNumber.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.api.patchOrder(widget.token, widget.orderNumber, {
        'status': _value,
      });
      if (!mounted) return;
      widget.onPatched();
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e.message);
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_rounded, color: _kAdminCrimson),
              const SizedBox(width: 8),
              Text(
                'Update fulfillment status',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 14),
          DropdownButton<String>(
            isExpanded: true,
            value: _value ?? _choices.first,
            hint: const Text('Status'),
            items: _choices
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: _saving ? null : (v) => setState(() => _value = v),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: _kAdminCrimson,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Save changes'),
          ),
        ],
      ),
    );
  }
}
