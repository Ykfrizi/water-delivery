import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/cache/app_cache.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/support/support_contact.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/data/customer_api.dart';
import 'package:smart_sachet_water_distribution/features/customer/domain/order_display.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/customer_order_detail_screen.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/explore_vendors_screen.dart';
import 'package:smart_sachet_water_distribution/features/support/presentation/help_support_screen.dart';

/// GET /customer/me refresh + optional PATCH /customer/me (backend-dependent).
class CustomerAccountScreen extends StatefulWidget {
  const CustomerAccountScreen({
    super.key,
    required this.onOpenProducts,
    required this.onOpenCart,
    required this.onOpenOrders,
    this.autoOpenEditProfile = false,
    this.onAutoOpenConsumed,
  });

  final VoidCallback onOpenProducts;
  final VoidCallback onOpenCart;
  final VoidCallback onOpenOrders;

  /// When true (e.g. arriving from checkout), open the profile editor once.
  final bool autoOpenEditProfile;
  final VoidCallback? onAutoOpenConsumed;

  @override
  State<CustomerAccountScreen> createState() => _CustomerAccountScreenState();
}

class _CustomerAccountScreenState extends State<CustomerAccountScreen> {
  Map<String, dynamic>? _remoteProfile;
  List<Map<String, dynamic>> _recentOrders = [];
  List<Map<String, dynamic>> _reviewableOrders = [];
  Map<String, String> _delivery = const {};
  bool _loading = false;
  bool _voucherBusy = false;
  String? _voucherHint;
  final _voucherCtrl = TextEditingController();

  String get _cacheHint =>
      (context.read<AuthController>().session?.token.hashCode ?? 0)
          .toRadixString(16);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didUpdateWidget(covariant CustomerAccountScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoOpenEditProfile && !oldWidget.autoOpenEditProfile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onAutoOpenConsumed?.call();
        _editProfile();
      });
    }
  }

  @override
  void dispose() {
    _voucherCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedVoucher() async {
    final saved = await AppCache.getVoucherCode(_cacheHint);
    if (!mounted) return;
    _voucherCtrl.text = saved ?? '';
  }

  Future<Map<String, dynamic>?> _previewVoucher(String code) async {
    final token = context.read<AuthController>().session?.token;
    if (token == null) return null;
    return CustomerApi(context.read<Dio>()).previewVoucher(
      token,
      code: code,
    );
  }

  Future<void> _saveVoucher() async {
    final code = _voucherCtrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      await _clearVoucher();
      return;
    }
    setState(() {
      _voucherBusy = true;
      _voucherHint = null;
    });
    try {
      final preview = await _previewVoucher(code);
      if (preview == null) {
        if (mounted) {
          showErrorSnackBar(context, 'Could not check this voucher. Try again.');
        }
        return;
      }
      await AppCache.putVoucherCode(_cacheHint, code);
      if (!mounted) return;
      setState(() {
        _voucherCtrl.text = code;
        _voucherHint = '$code saved · applied automatically at checkout';
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _voucherHint = e.message);
        showErrorSnackBar(context, e.message);
      }
    } finally {
      if (mounted) setState(() => _voucherBusy = false);
    }
  }

  Future<void> _clearVoucher() async {
    await AppCache.putVoucherCode(_cacheHint, null);
    if (!mounted) return;
    setState(() {
      _voucherCtrl.clear();
      _voucherHint = 'Voucher removed';
    });
  }

  Future<void> _refresh() async {
    final session = context.read<AuthController>().session;
    if (session == null) return;
    final token = session.token;
    final userId = session.user.id;
    final api = CustomerApi(context.read<Dio>());
    setState(() => _loading = true);
    try {
      final m = await api.getMe(token);
      var recentOrders = <Map<String, dynamic>>[];
      var reviewableOrders = <Map<String, dynamic>>[];
      try {
        recentOrders = await api.listOrders(token, perPage: 30);
        final seenVendors = <String>{};
        for (final order in recentOrders) {
          if (!orderIsDelivered(order)) continue;
          final slug = orderVendorSlug(order);
          if (slug == null || slug.isEmpty || !seenVendors.add(slug)) continue;
          reviewableOrders.add(order);
        }
      } catch (_) {}
      if (!mounted) return;
      final delivery = await AppCache.getDeliveryAddress(userId);
      if (!mounted) return;
      setState(() {
        _remoteProfile = m;
        _recentOrders = recentOrders;
        _reviewableOrders = reviewableOrders;
        _delivery = delivery;
        _loading = false;
      });
      await _loadSavedVoucher();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showErrorSnackBar(context, e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showErrorSnackBar(context, e.toString());
    }
  }

  String _orderLabel(Map<String, dynamic> o) {
    final n = o['order_number'] ?? o['orderNumber'] ?? o['id'];
    return n == null ? 'Order' : '#$n';
  }

  String _orderStatusLabel(Map<String, dynamic> o) {
    final s = o['status']?.toString().toLowerCase() ?? '';
    if (s == 'pending' ||
        s == 'awaiting_approval' ||
        s == 'awaiting_vendor' ||
        s == 'new') {
      return 'Awaiting vendor approval';
    }
    return o['status']?.toString() ?? '—';
  }

  Future<void> _openOrder(Map<String, dynamic> summary) async {
    final num = (summary['order_number'] ??
            summary['orderNumber'] ??
            summary['id'])
        ?.toString();
    if (num == null || num.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerOrderDetailScreen(
          orderNumber: num,
          summaryRow: summary,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _editProfile() async {
    final auth = context.read<AuthController>();
    final session = auth.session;
    if (session == null) return;
    final saved = await AppCache.getDeliveryAddress(session.user.id);
    if (!mounted) return;

    final draft = await Navigator.of(context, rootNavigator: true)
        .push<_ProfileDraft>(
      roleThemedRoute(
        role: UserRole.customer,
        builder: (_) => _CustomerEditProfilePage(
          name: _remoteProfile?['name']?.toString() ?? session.user.name,
          email: _remoteProfile?['email']?.toString() ?? session.user.email,
          phone: SupportContact.customerPhoneOrEmpty(
            (saved['phone'] ?? '').trim().isNotEmpty
                ? saved['phone']
                : (_remoteProfile?['phone']?.toString() ?? session.user.phone),
          ),
          line1: saved['line1'] ?? '',
          city: (saved['city'] ?? '').trim().isNotEmpty ? saved['city']! : 'Ho',
        ),
      ),
    );
    if (draft == null || !mounted) return;

    if (SupportContact.isReservedSupportPhone(draft.phone)) {
      showErrorSnackBar(
        context,
        'Enter your own phone number, not the support line.',
      );
      return;
    }
    final phoneError = AuthValidators.phone(draft.phone);
    if (phoneError != null) {
      showErrorSnackBar(context, phoneError);
      return;
    }
    final addrError = AuthValidators.addressLine(draft.line1);
    if (addrError != null) {
      showErrorSnackBar(context, addrError);
      return;
    }
    final cityError = AuthValidators.city(draft.city);
    if (cityError != null) {
      showErrorSnackBar(context, cityError);
      return;
    }

    try {
      await AppCache.putDeliveryAddress(
        userId: session.user.id,
        line1: draft.line1,
        city: draft.city,
        phone: draft.phone,
      );
      if (!mounted) return;
      await CustomerApi(context.read<Dio>()).updateMe(
        session.token,
        {
          'name': draft.name,
          'email': draft.email,
          'phone': draft.phone,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile and delivery address saved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) showErrorSnackBar(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<AuthController>().session;
    if (session == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);

    final name =
        _remoteProfile?['name']?.toString().trim().isNotEmpty == true
            ? _remoteProfile!['name'].toString()
            : session.user.name;
    final email =
        _remoteProfile?['email']?.toString().trim().isNotEmpty == true
            ? _remoteProfile!['email'].toString()
            : session.user.email;
    final phone = SupportContact.customerPhoneOrEmpty(
      (_delivery['phone'] ?? '').trim().isNotEmpty
          ? _delivery['phone']
          : (_remoteProfile?['phone']?.toString() ?? session.user.phone),
    );
    final deliveryLine = _delivery['line1'] ?? '';
    final deliveryCity = _delivery['city'] ?? '';

    final rawName = name.trim();
    final shortName =
        rawName.isEmpty ? 'there' : rawName.split(RegExp(r'\s+')).first;

    return Container(
        decoration: authGradientDecoration(),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BrandHeader(
                  title: 'Account',
                  subtitle: 'Hi $shortName · manage your profile',
                  actions: [
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else
                      HeaderIconButton(
                        icon: Icons.refresh_rounded,
                        onPressed: _refresh,
                        tooltip: 'Refresh from API',
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shortName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        email,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        phone.isNotEmpty
                            ? phone
                            : 'Add a phone number so vendors can call you',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                      ),
                      if (deliveryLine.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          [
                            deliveryLine,
                            if (deliveryCity.isNotEmpty) deliveryCity,
                          ].join(', '),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.88),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  elevation: 2,
                  child: InkWell(
                    onTap: _editProfile,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: kCustomerBlue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.location_on_rounded,
                              color: kCustomerBlue,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Delivery address',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: kOnLight,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  deliveryLine.isNotEmpty
                                      ? [
                                          deliveryLine,
                                          if (deliveryCity.isNotEmpty)
                                            deliveryCity,
                                          if (phone.isNotEmpty) phone,
                                        ].join(' · ')
                                      : 'Add your address and phone. Checkout uses this.',
                                  style: const TextStyle(color: kOnLightMuted),
                                ),
                              ],
                            ),
                          ),
                          const Text(
                            'Edit',
                            style: TextStyle(
                              color: kCustomerBlue,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Quick actions',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _ProfileActionTile(
                        icon: Icons.inventory_2_rounded,
                        label: 'Shop products',
                        onTap: widget.onOpenProducts,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ProfileActionTile(
                        icon: Icons.explore_rounded,
                        label: 'Find vendors',
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ExploreVendorsScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _ProfileActionTile(
                        icon: Icons.shopping_bag_rounded,
                        label: 'View cart',
                        onTap: widget.onOpenCart,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ProfileActionTile(
                        icon: Icons.local_shipping_outlined,
                        label: 'Track orders',
                        onTap: widget.onOpenOrders,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Recent orders',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onOpenOrders,
                      style: TextButton.styleFrom(foregroundColor: Colors.white),
                      child: const Text('All'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_recentOrders.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'No orders yet — start shopping.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  )
                else
                  ..._recentOrders.take(3).map((o) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(16),
                        child: ListTile(
                          onTap: () => _openOrder(o),
                          leading: CircleAvatar(
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.18),
                            child: const Icon(
                              Icons.receipt_long_rounded,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            _orderLabel(o),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text(
                            _orderStatusLabel(o),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 20),
                Text(
                  'Reviews',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                if (_reviewableOrders.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'After a shop marks your water as delivered, you can rate them here.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        height: 1.35,
                      ),
                    ),
                  )
                else
                  ..._reviewableOrders.map((o) {
                    final shop =
                        orderVendorName(o) ?? 'this shop';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        child: ListTile(
                          onTap: () => _openOrder(o),
                          leading: CircleAvatar(
                            backgroundColor: kCustomerBlue.withValues(
                              alpha: 0.12,
                            ),
                            child: Icon(
                              Icons.star_rounded,
                              color: Colors.amber.shade700,
                            ),
                          ),
                          title: Text(
                            'Rate $shop',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: kOnLight,
                            ),
                          ),
                          subtitle: Text(
                            '${_orderLabel(o)} · tap to leave a review',
                            style: const TextStyle(color: kOnLightMuted),
                          ),
                          trailing: const Icon(
                            Icons.chevron_right_rounded,
                            color: kOnLightMuted,
                          ),
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Voucher',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Save a discount code here. It is applied when you checkout.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _voucherCtrl,
                        enabled: !_voucherBusy,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(
                          color: kOnLight,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                        cursorColor: kCustomerBlue,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          labelText: 'Voucher number',
                          hintText: 'SAVE10',
                          labelStyle: const TextStyle(color: kOnLightMuted),
                          hintStyle: TextStyle(
                            color: kOnLightMuted.withValues(alpha: 0.7),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: kCustomerBlue,
                              width: 2,
                            ),
                          ),
                          disabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      if (_voucherHint != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _voucherHint!,
                          style: TextStyle(
                            color: _voucherHint!.toLowerCase().contains('saved')
                                ? const Color(0xFFB9F6CA)
                                : Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _voucherBusy ? null : _saveVoucher,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Text(
                                _voucherBusy ? 'Saving…' : 'Save voucher',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton(
                            onPressed: _voucherBusy ? null : _clearVoucher,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const HelpSupportScreen(
                          role: UserRole.customer,
                        ),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.support_agent_rounded),
                  label: const Text('Help & support'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _editProfile,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit profile & address'),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => context.read<AuthController>().logout(),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: kCustomerBlue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
    );
  }
}

class _ProfileActionTile extends StatelessWidget {
  const _ProfileActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kCustomerBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: kCustomerBlue, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: kOnLight,
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

class _ProfileDraft {
  const _ProfileDraft({
    required this.name,
    required this.email,
    required this.phone,
    required this.line1,
    required this.city,
  });

  final String name;
  final String email;
  final String phone;
  final String line1;
  final String city;
}

class _CustomerEditProfilePage extends StatefulWidget {
  const _CustomerEditProfilePage({
    required this.name,
    required this.email,
    required this.phone,
    required this.line1,
    required this.city,
  });

  final String name;
  final String email;
  final String phone;
  final String line1;
  final String city;

  @override
  State<_CustomerEditProfilePage> createState() =>
      _CustomerEditProfilePageState();
}

class _CustomerEditProfilePageState extends State<_CustomerEditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _line1;
  late final TextEditingController _city;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.name);
    _email = TextEditingController(text: widget.email);
    _phone = TextEditingController(text: widget.phone);
    _line1 = TextEditingController(text: widget.line1);
    _city = TextEditingController(text: widget.city);
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _line1.dispose();
    _city.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final phone = _phone.text.trim();
    if (SupportContact.isReservedSupportPhone(phone)) {
      showErrorSnackBar(
        context,
        'Enter your own phone number, not the support line.',
      );
      return;
    }
    Navigator.pop(
      context,
      _ProfileDraft(
        name: _name.text.trim(),
        email: _email.text.trim(),
        phone: phone,
        line1: _line1.text.trim(),
        city: _city.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accent = kCustomerBlue;

    return Scaffold(
      body: Container(
        decoration: roleGradientDecoration(UserRole.customer),
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
                        title: 'Edit address',
                        subtitle: 'Profile and delivery details',
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      elevation: 8,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Your details',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: kOnLight,
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _name,
                                textCapitalization: TextCapitalization.words,
                                style: const TextStyle(color: kOnLight),
                                decoration: const InputDecoration(
                                  labelText: 'Name',
                                  prefixIcon: Icon(Icons.person_outline_rounded),
                                ),
                                validator: (v) =>
                                    AuthValidators.name(v, label: 'Name'),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                style: const TextStyle(color: kOnLight),
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: Icon(Icons.mail_outline_rounded),
                                ),
                                validator: AuthValidators.email,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _line1,
                                textCapitalization: TextCapitalization.words,
                                style: const TextStyle(color: kOnLight),
                                decoration: const InputDecoration(
                                  labelText: 'Delivery address',
                                  hintText: 'House number, street, landmark',
                                  prefixIcon: Icon(Icons.home_outlined),
                                ),
                                validator: AuthValidators.addressLine,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _city,
                                textCapitalization: TextCapitalization.words,
                                style: const TextStyle(color: kOnLight),
                                decoration: const InputDecoration(
                                  labelText: 'City',
                                  hintText: 'Ho',
                                  prefixIcon: Icon(Icons.location_city_outlined),
                                ),
                                validator: AuthValidators.city,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _phone,
                                keyboardType: TextInputType.phone,
                                style: const TextStyle(color: kOnLight),
                                decoration: const InputDecoration(
                                  labelText: 'Phone number',
                                  hintText: '024 123 4567',
                                  prefixIcon: Icon(Icons.phone_outlined),
                                ),
                                validator: AuthValidators.phone,
                              ),
                              const SizedBox(height: 22),
                              FilledButton(
                                onPressed: _save,
                                style: FilledButton.styleFrom(
                                  backgroundColor: accent,
                                ),
                                child: const Text('Save address'),
                              ),
                            ],
                          ),
                        ),
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
}
