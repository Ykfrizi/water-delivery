import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/money/currency.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/vendor/data/vendor_api.dart';

/// Vendor wallet: live Paystack earnings and bank / MoMo withdrawals.
class VendorWalletScreen extends StatefulWidget {
  const VendorWalletScreen({super.key});

  @override
  State<VendorWalletScreen> createState() => _VendorWalletScreenState();
}

class _VendorWalletScreenState extends State<VendorWalletScreen> {
  Map<String, dynamic> _wallet = {};
  List<Map<String, dynamic>> _rows = [];
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
    final api = VendorApi(context.read<Dio>());
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final wallet = await api.getWallet(token);
      final rows = await api.listWithdrawals(token);
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _rows = rows;
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

  num get _available =>
      num.tryParse(_wallet['available']?.toString() ?? '') ?? 0;

  Future<void> _request() async {
    final available = _available;
    final draft = await Navigator.of(context, rootNavigator: true)
        .push<_WithdrawDraft>(
      MaterialPageRoute<_WithdrawDraft>(
        fullscreenDialog: true,
        builder: (_) => _VendorWithdrawPage(available: available),
      ),
    );
    if (!mounted || draft == null) return;

    if (draft.amount <= 0) {
      showErrorSnackBar(context, 'Enter a valid amount.');
      return;
    }
    if (draft.amount > available + 0.009) {
      showErrorSnackBar(
        context,
        'You requested ${formatMoney(draft.amount)} but your available balance is ${formatMoney(available)}. You cannot withdraw more than what has been paid into your account.',
      );
      return;
    }

    final token = context.read<AuthController>().session?.token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      await VendorApi(context.read<Dio>()).requestWithdrawal(
        token,
        amount: draft.amount,
        method: draft.method,
        bankName: draft.method == 'bank' ? draft.bankName : null,
        accountName: draft.method == 'bank' ? draft.accountName : null,
        accountNumber: draft.method == 'bank' ? draft.accountNumber : null,
        momoNetwork: draft.method == 'mobile_money' ? draft.network : null,
        momoNumber: draft.method == 'mobile_money' ? draft.momoNumber : null,
        momoName: draft.method == 'mobile_money' ? draft.momoName : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Withdrawal requested. Admin will mark it paid after sending.',
          ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = roleAccent(UserRole.vendor);

    return Scaffold(
      body: Container(
          decoration: roleGradientDecoration(UserRole.vendor),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BrandHeader(
                  title: 'Withdraw',
                  subtitle: 'Cash out Paystack earnings by bank or MoMo',
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
                            color: accent,
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                Material(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          formatMoney(_available),
                                          style: theme.textTheme.headlineMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w900,
                                                color: accent,
                                              ),
                                        ),
                                        const Text('Available to withdraw'),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Earned ${formatMoneyDynamic(_wallet['earned'])} · '
                                          'Pending ${formatMoneyDynamic(_wallet['pending_withdrawals'])} · '
                                          'Paid out ${formatMoneyDynamic(_wallet['paid_withdrawals'])}',
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                            height: 1.35,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        FilledButton.icon(
                                          onPressed: _busy ? null : _request,
                                          icon: const Icon(
                                            Icons.account_balance_wallet_rounded,
                                          ),
                                          label: const Text('Withdraw'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Requests',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                if (_rows.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 24),
                                    child: Center(
                                      child: Text('No withdrawals yet'),
                                    ),
                                  ),
                                for (final row in _rows)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Material(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      child: ListTile(
                                        title: Text(
                                          formatMoneyDynamic(row['amount']),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        subtitle: Text(
                                          [
                                            row['status']?.toString() ?? '',
                                            row['destination']?.toString() ??
                                                '',
                                          ].where((s) => s.isNotEmpty).join(' · '),
                                        ),
                                      ),
                                    ),
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

class _WithdrawDraft {
  const _WithdrawDraft({
    required this.amount,
    required this.method,
    required this.network,
    required this.momoName,
    required this.momoNumber,
    required this.bankName,
    required this.accountName,
    required this.accountNumber,
  });

  final double amount;
  final String method;
  final String network;
  final String momoName;
  final String momoNumber;
  final String bankName;
  final String accountName;
  final String accountNumber;
}

class _VendorWithdrawPage extends StatefulWidget {
  const _VendorWithdrawPage({required this.available});

  final num available;

  @override
  State<_VendorWithdrawPage> createState() => _VendorWithdrawPageState();
}

class _VendorWithdrawPageState extends State<_VendorWithdrawPage> {
  final _amountCtrl = TextEditingController();
  final _bankName = TextEditingController();
  final _accountName = TextEditingController();
  final _accountNumber = TextEditingController();
  final _momoName = TextEditingController();
  final _momoNumber = TextEditingController();
  String _method = 'mobile_money';
  String _network = 'MTN';

  @override
  void dispose() {
    _amountCtrl.dispose();
    _bankName.dispose();
    _accountName.dispose();
    _accountNumber.dispose();
    _momoName.dispose();
    _momoNumber.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = num.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      showErrorSnackBar(context, 'Enter a valid amount.');
      return;
    }
    if (_method == 'mobile_money') {
      if (_momoName.text.trim().length < 2) {
        showErrorSnackBar(context, 'Enter the MoMo account name.');
        return;
      }
      final phoneErr = AuthValidators.phone(_momoNumber.text);
      if (phoneErr != null) {
        showErrorSnackBar(context, phoneErr);
        return;
      }
    } else {
      if (_bankName.text.trim().length < 2) {
        showErrorSnackBar(context, 'Enter the bank name.');
        return;
      }
      if (_accountName.text.trim().length < 2) {
        showErrorSnackBar(context, 'Enter the account name.');
        return;
      }
      if (_accountNumber.text.trim().length < 6) {
        showErrorSnackBar(context, 'Enter a valid account number.');
        return;
      }
    }
    Navigator.pop(
      context,
      _WithdrawDraft(
        amount: amount.toDouble(),
        method: _method,
        network: _network,
        momoName: _momoName.text.trim(),
        momoNumber: _momoNumber.text.trim(),
        bankName: _bankName.text.trim(),
        accountName: _accountName.text.trim(),
        accountNumber: _accountNumber.text.trim(),
      ),
    );
  }

  Widget _methodTile({
    required String value,
    required String title,
    required String subtitle,
  }) {
    final selected = _method == value;
    final accent = roleAccent(UserRole.vendor);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => setState(() => _method = value),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? accent : const Color(0x33000000),
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: selected ? accent : kOnLightMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: kOnLight,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(color: kOnLightMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = roleAccent(UserRole.vendor);
    return Theme(
      data: vendorAppTheme(),
      child: Scaffold(
        body: Container(
          decoration: roleGradientDecoration(UserRole.vendor),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
                  child: Row(
                    children: [
                      HeaderIconButton(
                        icon: Icons.close_rounded,
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Cancel',
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: BrandHeader(
                          title: 'Withdraw money',
                          subtitle: 'Cash out Paystack earnings',
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: ListView(
                      children: [
                        Text(
                          'Available: ${formatMoney(widget.available)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Only Paystack-paid orders count. You cannot request more than this balance.',
                          style: TextStyle(
                            height: 1.35,
                            fontSize: 13,
                            color: kOnLightMuted,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _amountCtrl,
                          style: const TextStyle(color: kOnLight),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Amount (GHS)',
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Payout method',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: kOnLight,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _methodTile(
                          value: 'mobile_money',
                          title: 'Mobile money',
                          subtitle: 'MTN, Telecel, or AirtelTigo',
                        ),
                        _methodTile(
                          value: 'bank',
                          title: 'Bank account',
                          subtitle: 'Transfer to a Ghana bank account',
                        ),
                        if (_method == 'mobile_money') ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Network',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: kOnLight,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final n in const [
                                'MTN',
                                'Telecel',
                                'AirtelTigo',
                              ])
                                HeaderFilterChip(
                                  label: n,
                                  selected: _network == n,
                                  onSelected: (_) =>
                                      setState(() => _network = n),
                                  accent: accent,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _momoName,
                            style: const TextStyle(color: kOnLight),
                            decoration: const InputDecoration(
                              labelText: 'Account name',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _momoNumber,
                            style: const TextStyle(color: kOnLight),
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'MoMo number',
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _bankName,
                            style: const TextStyle(color: kOnLight),
                            decoration: const InputDecoration(
                              labelText: 'Bank name',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _accountName,
                            style: const TextStyle(color: kOnLight),
                            decoration: const InputDecoration(
                              labelText: 'Account name',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _accountNumber,
                            style: const TextStyle(color: kOnLight),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Account number',
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _submit,
                          child: const Text('Request payout'),
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
