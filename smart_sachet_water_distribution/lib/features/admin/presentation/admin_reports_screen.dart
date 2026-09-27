import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/features/admin/data/admin_reports_api.dart';
import 'package:smart_sachet_water_distribution/features/admin/domain/admin_operations_report.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';

const _kAdminDeep = kAdminGreenDeep;
const _kAdminCrimson = kAdminGreen;

/// Admin operations report with status, vendor, and revenue breakdowns.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  AdminOperationsReport? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = context.read<AuthController>().session?.token;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await AdminReportsApi(context.read<Dio>()).loadReport(token);
      if (!mounted) return;
      setState(() {
        _report = report;
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
    final theme = Theme.of(context);
    final greeting = context.select<AuthController, String>(
      (a) => a.session?.user.greeting ?? 'Hello!',
    );

    return Scaffold(
        backgroundColor: _kAdminDeep,
        body: Container(
          decoration: roleGradientDecoration(UserRole.admin),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BrandHeader(
                  title: greeting,
                  subtitle: 'Reports · orders, vendors & revenue',
                  actions: [
                    HeaderIconButton(
                      icon: Icons.refresh_rounded,
                      onPressed: _loading ? null : _load,
                      tooltip: 'Refresh',
                    ),
                  ],
                ),
                Expanded(
                  child: RefreshIndicator(
                    color: _kAdminCrimson,
                    backgroundColor: Colors.white,
                    onRefresh: _load,
                    child: _buildBody(theme),
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading && _report == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator(color: Colors.white)),
        ],
      );
    }
    if (_error != null && _report == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 12),
          Center(
            child: FilledButton(
              onPressed: _load,
              style: FilledButton.styleFrom(backgroundColor: _kAdminCrimson),
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    final report = _report!;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        if (report.sourceNote.trim().isNotEmpty) ...[
          Text(
            report.sourceNote,
            style: theme.textTheme.labelMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: 'Orders',
                value: '${report.totalOrders}',
                caption: '${report.pendingApprovals} need approval',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _KpiCard(
                label: 'Revenue',
                value: report.revenueLabel,
                caption: 'Excl. cancelled',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _KpiCard(
                label: 'Vendors',
                value: '${report.totalVendors}',
                caption: '${report.approvedVendors} active',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _KpiCard(
                label: 'Delivered',
                value: '${report.deliveredOrders}',
                caption: '${report.cancelledOrders} cancelled',
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _BreakdownCard(
          title: 'Orders by status',
          subtitle: 'Full pipeline breakdown',
          total: report.totalOrders,
          items: report.ordersByStatus,
          emptyText: 'No orders to break down yet.',
        ),
        const SizedBox(height: 12),
        _BreakdownCard(
          title: 'Orders by vendor',
          subtitle: 'Which stores are fulfilling demand',
          total: report.totalOrders,
          items: report.ordersByVendor,
          emptyText: 'No vendor order activity yet.',
          showAmount: true,
        ),
        const SizedBox(height: 12),
        _BreakdownCard(
          title: 'Vendors by approval',
          subtitle: 'Marketplace readiness',
          total: report.totalVendors,
          items: report.vendorsByStatus,
          emptyText: 'No vendors registered yet.',
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.caption,
  });

  final String label;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              caption,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.title,
    required this.subtitle,
    required this.total,
    required this.items,
    required this.emptyText,
    this.showAmount = false,
  });

  final String title;
  final String subtitle;
  final int total;
  final List<ReportBreakdownItem> items;
  final String emptyText;
  final bool showAmount;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
            const SizedBox(height: 14),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  emptyText,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            else
              ...items.map((item) {
                final share = item.shareOf(total);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.label,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(
                            '${item.count}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(share * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      if (showAmount && item.amount != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.amountLabel,
                          style: const TextStyle(
                            color: _kAdminCrimson,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: share.clamp(0.0, 1.0),
                          minHeight: 8,
                          backgroundColor: kAdminIce,
                          color: _kAdminCrimson,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
