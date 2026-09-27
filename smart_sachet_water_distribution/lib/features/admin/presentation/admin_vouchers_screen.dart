import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/money/currency.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/admin/data/admin_vouchers_api.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';

const _kAdminDeep = kAdminGreenDeep;

class AdminVouchersScreen extends StatefulWidget {
  const AdminVouchersScreen({super.key});

  @override
  State<AdminVouchersScreen> createState() => _AdminVouchersScreenState();
}

class _AdminVouchersScreenState extends State<AdminVouchersScreen> {
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await AdminVouchersApi(context.read<Dio>()).list(token);
      if (!mounted) return;
      setState(() {
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

  Future<void> _create() async {
    final codeCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    final usesCtrl = TextEditingController();
    var type = 'percent';

    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialog) {
          return AlertDialog(
            title: const Text('New voucher'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Voucher number',
                      hintText: 'SAVE10',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Discount type',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      HeaderFilterChip(
                        label: 'Percent off',
                        selected: type == 'percent',
                        onSelected: (_) => setDialog(() => type = 'percent'),
                        accent: kAdminCyan,
                      ),
                      HeaderFilterChip(
                        label: 'Fixed amount (GHS)',
                        selected: type == 'fixed',
                        onSelected: (_) => setDialog(() => type = 'fixed'),
                        accent: kAdminCyan,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: valueCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: type == 'percent' ? 'Percent' : 'Amount (GHS)',
                      hintText: type == 'percent' ? '10' : '5',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: usesCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Max uses (optional)',
                      hintText: 'Leave blank for unlimited',
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
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );

    final code = codeCtrl.text.trim();
    final value = double.tryParse(valueCtrl.text.trim());
    final uses = int.tryParse(usesCtrl.text.trim());
    codeCtrl.dispose();
    valueCtrl.dispose();
    usesCtrl.dispose();
    if (ok != true) return;
    if (code.isEmpty || value == null || value <= 0) {
      if (mounted) {
        showErrorSnackBar(
          context,
          'Enter a voucher number and discount value.',
        );
      }
      return;
    }

    final token = context.read<AuthController>().session?.token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      await AdminVouchersApi(
        context.read<Dio>(),
      ).create(token, code: code, type: type, value: value, maxUses: uses);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Voucher $code created'),
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

  Future<void> _toggle(Map<String, dynamic> row) async {
    final id = row['id'];
    if (id == null) return;
    final token = context.read<AuthController>().session?.token;
    if (token == null) return;
    final active = row['is_active'] == true;
    try {
      await AdminVouchersApi(
        context.read<Dio>(),
      ).setActive(token, id, active: !active);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final id = row['id'];
    if (id == null) return;
    final token = context.read<AuthController>().session?.token;
    if (token == null) return;
    try {
      await AdminVouchersApi(context.read<Dio>()).delete(token, id);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
    }
  }

  String _valueLabel(Map<String, dynamic> row) {
    final type = row['type']?.toString();
    final value = num.tryParse(row['value']?.toString() ?? '') ?? 0;
    if (type == 'percent')
      return '${value.toString().replaceAll(RegExp(r'\.0+$'), '')}% off';
    return '${formatMoney(value)} off';
  }

  @override
  Widget build(BuildContext context) {
    final accent = roleAccent(UserRole.admin);

    return Scaffold(
      backgroundColor: _kAdminDeep,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _create,
        backgroundColor: accent,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New voucher'),
      ),
      body: Container(
        decoration: roleGradientDecoration(UserRole.admin),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BrandHeader(
                title: 'Vouchers',
                subtitle: 'Create codes that reduce checkout prices',
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
                    color: kAdminIce,
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
                          child: _rows.isEmpty
                              ? ListView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  children: const [
                                    SizedBox(height: 80),
                                    Center(child: Text('No vouchers yet')),
                                  ],
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    14,
                                    14,
                                    88,
                                  ),
                                  itemCount: _rows.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, i) {
                                    final row = _rows[i];
                                    final code = row['code']?.toString() ?? '—';
                                    final used =
                                        row['used_count']?.toString() ?? '0';
                                    final max = row['max_uses']?.toString();
                                    final active = row['is_active'] == true;
                                    return Material(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      child: ListTile(
                                        title: Text(
                                          code,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        subtitle: Text(
                                          '${_valueLabel(row)} · used $used'
                                          '${max != null ? ' / $max' : ''}'
                                          '${active ? '' : ' · off'}',
                                        ),
                                        trailing: Wrap(
                                          children: [
                                            IconButton(
                                              tooltip: active
                                                  ? 'Turn off'
                                                  : 'Turn on',
                                              onPressed: () => _toggle(row),
                                              icon: Icon(
                                                active
                                                    ? Icons.toggle_on_rounded
                                                    : Icons.toggle_off_outlined,
                                                color: active
                                                    ? accent
                                                    : Colors.grey,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Delete',
                                              onPressed: () => _delete(row),
                                              icon: const Icon(
                                                Icons.delete_outline_rounded,
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
            ],
          ),
        ),
      ),
    );
  }
}
