import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/money/currency.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/vendor/data/vendor_api.dart';
import 'package:smart_sachet_water_distribution/features/vendor/domain/vendor_settlement.dart';

class VendorSettlementScreen extends StatefulWidget {
  const VendorSettlementScreen({super.key});

  @override
  State<VendorSettlementScreen> createState() => _VendorSettlementScreenState();
}

class _VendorSettlementScreenState extends State<VendorSettlementScreen> {
  VendorSettlement? _settlement;
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
      final orders = await VendorApi(context.read<Dio>()).listOrders(
        token,
        from: _dateText(DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1))),
        to: _dateText(DateTime.now()),
        perPage: 100,
      );
      if (!mounted) return;
      setState(() {
        _settlement = VendorSettlement.fromOrders(orders);
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
    final settlement = _settlement;
    return Scaffold(
      body: Container(
        decoration: roleGradientDecoration(UserRole.vendor),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BrandHeader(
                title: 'Settlement invoice',
                subtitle: 'Weekly cash reconciliation',
                actions: [
                  HeaderIconButton(
                    icon: Icons.refresh_rounded,
                    onPressed: _loading ? null : _load,
                    tooltip: 'Refresh',
                  ),
                ],
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  decoration: BoxDecoration(
                    color: kVendorMint,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? _ErrorView(message: _error!, onRetry: _load)
                      : settlement == null
                      ? const Center(child: Text('No settlement data'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              _InvoiceCard(settlement: settlement),
                              const SizedBox(height: 12),
                              const Text(
                                'Cash handling',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'The vendor keeps physical cash collected from customers and brings it to the depot. Paystack collections are already digital and can offset the commission invoice.',
                              ),
                            ],
                          ),
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

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.settlement});

  final VendorSettlement settlement;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Week of ${_dateText(settlement.from)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            _Row(label: 'Cash orders (${settlement.cashOrders})', value: formatMoney(settlement.cashSales)),
            _Row(label: 'Paystack orders (${settlement.prepaidOrders})', value: formatMoney(settlement.prepaidSales)),
            const Divider(height: 22),
            _Row(label: 'Gross sales', value: settlement.grossSalesLabel, bold: true),
            _Row(label: 'Commission rate', value: '5%'),
            _Row(label: 'Commission due', value: settlement.commissionDueLabel, bold: true),
            _Row(label: 'Paystack commission offset', value: formatMoney(settlement.prepaidCommissionOffset)),
            const Divider(height: 22),
            _Row(label: 'Cash commission payable', value: settlement.cashCommissionDueLabel, bold: true),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      color: kOnLight,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}

String _dateText(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
