import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/money/currency.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/admin/data/admin_money_api.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';

const _kAdminDeep = kAdminGreenDeep;
const _kAdminCrimson = kAdminGreen;

enum _MoneyTab { payments, payouts }

/// Paystack-verified payments and vendor withdrawal requests.
class AdminMoneyScreen extends StatefulWidget {
  const AdminMoneyScreen({super.key});

  @override
  State<AdminMoneyScreen> createState() => _AdminMoneyScreenState();
}

class _AdminMoneyScreenState extends State<AdminMoneyScreen> {
  _MoneyTab _tab = _MoneyTab.payments;
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _payouts = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = context.read<AuthController>().session?.token;
    if (token == null) return;
    final api = AdminMoneyApi(context.read<Dio>());
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payments = await api.listPayments(token);
      final payouts = await api.listWithdrawals(token);
      if (!mounted) return;
      setState(() {
        _payments = payments;
        _payouts = payouts;
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

  Future<void> _flagPaid(Map<String, dynamic> row) async {
    final id = row['id'];
    if (id == null) return;
    final token = context.read<AuthController>().session?.token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      await AdminMoneyApi(context.read<Dio>()).completeWithdrawal(token, id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Marked as paid'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(Map<String, dynamic> row) async {
    final id = row['id'];
    if (id == null) return;
    final notesCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (c) => AlertDialog(
        title: const Text('Reject withdrawal?'),
        content: TextField(
          controller: notesCtrl,
          decoration: const InputDecoration(labelText: 'Note (optional)'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    final notes = notesCtrl.text;
    notesCtrl.dispose();
    if (ok != true) return;
    final token = context.read<AuthController>().session?.token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      await AdminMoneyApi(
        context.read<Dio>(),
      ).rejectWithdrawal(token, id, notes: notes);
      if (!mounted) return;
      await _load();
    } on ApiException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kAdminDeep,
      body: Container(
        decoration: roleGradientDecoration(UserRole.admin),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BrandHeader(
                title: 'Money',
                subtitle: _tab == _MoneyTab.payments
                    ? 'Paystack-verified paid transactions'
                    : 'Vendor withdrawals · flag when sent',
                actions: [
                  HeaderIconButton(
                    icon: Icons.refresh_rounded,
                    onPressed: _loading ? null : _load,
                    tooltip: 'Refresh',
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    HeaderFilterChip(
                      label: 'Paid ${_payments.length}',
                      selected: _tab == _MoneyTab.payments,
                      onSelected: (_) =>
                          setState(() => _tab = _MoneyTab.payments),
                      accent: _kAdminCrimson,
                      showCheckmark: false,
                    ),
                    HeaderFilterChip(
                      label: 'Payouts ${_payouts.length}',
                      selected: _tab == _MoneyTab.payouts,
                      onSelected: (_) =>
                          setState(() => _tab = _MoneyTab.payouts),
                      accent: _kAdminCrimson,
                      showCheckmark: false,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: _kAdminCrimson,
                          ),
                        )
                      : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!, textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed: _load,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          color: _kAdminCrimson,
                          onRefresh: _load,
                          child: _tab == _MoneyTab.payments
                              ? _paymentsList()
                              : _payoutsList(),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paymentsList() {
    if (_payments.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(child: Text('No Paystack-verified payments yet')),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(14),
      itemCount: _payments.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = _payments[i];
        final companies = (p['companies'] is List)
            ? (p['companies'] as List).map((e) => e.toString()).join(', ')
            : '';
        final products = (p['products'] is List)
            ? (p['products'] as List).map((e) => e.toString()).join(', ')
            : '';
        final customer = p['customer'];
        final buyer = customer is Map
            ? (customer['name'] ?? customer['email'])?.toString()
            : null;
        return Material(
          color: kAdminIce,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            title: Text(
              formatMoneyDynamic(p['amount']),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              [
                'Paid',
                if (companies.isNotEmpty) companies,
                if (products.isNotEmpty) products,
                if (buyer != null && buyer.isNotEmpty) buyer,
                p['reference']?.toString() ?? '',
              ].where((s) => s.isNotEmpty).join('\n'),
              style: const TextStyle(height: 1.35),
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  Widget _payoutsList() {
    if (_payouts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(child: Text('No withdrawal requests')),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(14),
      itemCount: _payouts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final row = _payouts[i];
        final status = row['status']?.toString() ?? 'pending';
        final vendor = row['vendor'];
        final shop = vendor is Map
            ? (vendor['business_name'] ?? vendor['slug'])?.toString()
            : null;
        final pending = status == 'pending';
        return Material(
          color: kAdminIce,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    formatMoneyDynamic(row['amount']),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    [
                      status,
                      ?shop,
                      row['destination']?.toString() ?? '',
                    ].where((s) => s.isNotEmpty).join(' · '),
                  ),
                  trailing: Chip(
                    label: Text(status),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                if (pending)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => _reject(row),
                          child: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: _busy ? null : () => _flagPaid(row),
                          child: const Text('Mark paid'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
