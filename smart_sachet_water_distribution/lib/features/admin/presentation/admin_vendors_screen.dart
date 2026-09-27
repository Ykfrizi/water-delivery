import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/admin/data/admin_vendors_api.dart';
import 'package:smart_sachet_water_distribution/features/admin/domain/admin_vendor_summary.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';

const _kAdminDeep = kAdminGreenDeep;
const _kAdminCrimson = kAdminGreen;

/// Admin vendor approval queue — approve or reject vendor accounts.
class AdminVendorsScreen extends StatefulWidget {
  const AdminVendorsScreen({super.key});

  @override
  State<AdminVendorsScreen> createState() => _AdminVendorsScreenState();
}

class _AdminVendorsScreenState extends State<AdminVendorsScreen> {
  List<AdminVendorSummary> _vendors = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final _searchCtrl = TextEditingController();

  static const _statusFilters = <String?>[
    null,
    'pending',
    'approved',
    'rejected',
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
    final api = AdminVendorsApi(context.read<Dio>());
    final token = context.read<AuthController>().token;
    if (token == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await api.listVendors(
        token,
        approvalStatus: _statusFilter,
        q: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _vendors = list;
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

  Future<void> _approve(AdminVendorSummary vendor) async {
    final ok = await _confirm(
      title: 'Approve vendor?',
      message:
          'Approve "${vendor.displayTitle}"${vendor.ghanaCardNumber != null ? ' (${vendor.ghanaCardNumber})' : ''} to access the vendor dashboard?',
      confirmLabel: 'Approve',
    );
    if (ok != true || !mounted) return;

    final token = context.read<AuthController>().token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      await AdminVendorsApi(
        context.read<Dio>(),
      ).approveVendor(token, vendor.slug);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${vendor.displayTitle} approved'),
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

  Future<void> _reject(AdminVendorSummary vendor) async {
    final ok = await _confirm(
      title: 'Reject vendor?',
      message: 'Block "${vendor.displayTitle}" from the marketplace?',
      confirmLabel: 'Reject',
      destructive: true,
    );
    if (ok != true || !mounted) return;

    final token = context.read<AuthController>().token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      await AdminVendorsApi(
        context.read<Dio>(),
      ).rejectVendor(token, vendor.slug);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${vendor.displayTitle} rejected'),
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

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFC62828),
                  )
                : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final greeting = context.select<AuthController, String>(
      (a) => a.session?.user.greeting ?? 'Hello!',
    );
    final name = context.select<AuthController, String>(
      (a) => a.session?.user.name ?? '',
    );
    final theme = Theme.of(context);

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
                subtitle: [
                  'Vendor approvals',
                  if (name.trim().isNotEmpty &&
                      name.trim().toLowerCase() != 'user')
                    name,
                ].join(' · '),
                actions: [
                  HeaderIconButton(
                    icon: Icons.logout_rounded,
                    onPressed: () => context.read<AuthController>().logout(),
                    tooltip: 'Sign out',
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search vendors…',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      onPressed: _loading ? null : _load,
                      icon: Icon(
                        Icons.search,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _statusFilters.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final s = _statusFilters[i];
                    final selected = _statusFilter == s;
                    final label = s ?? 'All';
                    return HeaderFilterChip(
                      selected: selected,
                      label: label,
                      onSelected: (_) {
                        setState(() => _statusFilter = s);
                        _load();
                      },
                      accent: _kAdminCrimson,
                    );
                  },
                ),
              ),
              if (_busy)
                const LinearProgressIndicator(
                  minHeight: 2,
                  color: _kAdminCrimson,
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
    if (_loading && _vendors.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.22),
          const Center(child: CircularProgressIndicator(color: Colors.white)),
        ],
      );
    }
    if (_error != null) {
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
    if (_vendors.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        children: [
          Text(
            'No vendors match this filter.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      itemCount: _vendors.length,
      itemBuilder: (context, i) {
        final v = _vendors[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _VendorApprovalCard(
            vendor: v,
            busy: _busy,
            onApprove: () => _approve(v),
            onReject: () => _reject(v),
          ),
        );
      },
    );
  }
}

class _VendorApprovalCard extends StatelessWidget {
  const _VendorApprovalCard({
    required this.vendor,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final AdminVendorSummary vendor;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  Color _statusColor() {
    if (vendor.isApproved) return Colors.green.shade600;
    if (vendor.isRejected) return const Color(0xFFC62828);
    return Colors.amber.shade700;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  child: const Icon(
                    Icons.storefront_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vendor.displayTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      if (vendor.email != null)
                        Text(
                          vendor.email!,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13,
                          ),
                        ),
                      if (vendor.ghanaCardNumber != null)
                        Text(
                          'Ghana Card: ${vendor.ghanaCardNumber}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      Text(
                        'Slug: ${vendor.slug}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor().withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _statusColor().withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    vendor.statusLabel,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (!vendor.isApproved)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : onApprove,
                      icon: const Icon(Icons.check_circle_outline, size: 20),
                      label: const Text('Approve'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                if (!vendor.isApproved && !vendor.isRejected)
                  const SizedBox(width: 10),
                if (!vendor.isRejected)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : onReject,
                      icon: const Icon(Icons.block_outlined, size: 20),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
