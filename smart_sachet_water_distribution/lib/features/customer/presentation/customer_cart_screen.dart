import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/core/network/api_exception.dart';
import 'package:smart_sachet_water_distribution/core/cache/app_cache.dart';
import 'package:smart_sachet_water_distribution/core/location/device_location_service.dart';
import 'package:smart_sachet_water_distribution/core/money/currency.dart';
import 'package:smart_sachet_water_distribution/core/support/support_contact.dart';
import 'package:smart_sachet_water_distribution/core/validation/auth_validators.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/data/customer_api.dart';
import 'package:smart_sachet_water_distribution/features/customer/domain/cart_line.dart';
import 'package:smart_sachet_water_distribution/features/customer/domain/order_display.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/cart_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/paystack_checkout_screen.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/paystack_payment_flow.dart';
import 'package:smart_sachet_water_distribution/features/maps/domain/service_area.dart';

enum _CheckoutOutcome { cancel, confirm }

/// GET /customer/cart · PATCH quantities · DELETE lines · POST checkout
class CustomerCartScreen extends StatefulWidget {
  const CustomerCartScreen({
    super.key,
    this.isActive = true,
  });

  /// When used inside [IndexedStack], set true only for the selected tab so
  /// the cart reloads after items are added elsewhere.
  final bool isActive;

  @override
  State<CustomerCartScreen> createState() => _CustomerCartScreenState();
}

class _CustomerCartScreenState extends State<CustomerCartScreen> {
  Map<String, dynamic> _cartRoot = {};
  List<CartLine> _lines = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  num? get _cartSubtotal {
    if (_lines.any((line) => line.unitPrice == null)) return null;
    return _lines.fold<num>(
      0,
      (total, line) => total + line.unitPrice! * line.quantity,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isActive) _load();
    });
  }

  @override
  void didUpdateWidget(covariant CustomerCartScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isActive) _load();
      });
    }
  }

  Future<void> _load() async {
    final auth = context.read<AuthController>();
    final token = auth.session?.token;
    if (token == null) return;

    final api = CustomerApi(context.read<Dio>());
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final root = await api.getCart(token);
      if (!mounted) return;
      setState(() {
        _cartRoot = root;
        _lines = cartLinesFromResponse(root);
        _loading = false;
      });
      if (mounted) context.read<CartController>().applyFetchedCart(root);
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

  Future<void> _setQty(CartLine line, int q) async {
    if (q < 1) {
      await _remove(line);
      return;
    }
    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      final api = CustomerApi(context.read<Dio>());
      await api.updateCartItem(token, line.id, quantity: q);
      if (!mounted) return;
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(CartLine line) async {
    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      final api = CustomerApi(context.read<Dio>());
      await api.removeCartItem(token, line.id);
      if (!mounted) return;
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (c) => AlertDialog(
        title: const Text('Clear cart?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final auth = context.read<AuthController>();
    final token = auth.token;
    if (token == null) return;
    setState(() => _busy = true);
    try {
      final api = CustomerApi(context.read<Dio>());
      await api.clearCart(token);
      if (!mounted) return;
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkout() async {
    final invalidLine = _lines.where(
      (line) =>
          line.quantity < kMinCartItemQuantity ||
          line.quantity > kMaxCartItemQuantity,
    );
    if (invalidLine.isNotEmpty) {
      showErrorSnackBar(
        context,
        'Each item must have a quantity between $kMinCartItemQuantity and '
            '$kMaxCartItemQuantity.',
      );
      return;
    }

    final locationService = const DeviceLocationService();
    final permissionIssue = await locationService.ensureReady();
    if (permissionIssue != null && mounted) {
      showErrorSnackBar(context, permissionIssue);
      return;
    }
    final position = await locationService.tryGetCurrentPosition();
    if (position == null || !mounted) {
      if (mounted) {
        showErrorSnackBar(
          context,
          'Turn on location and try again. We cannot calculate delivery fees without your GPS.',
        );
      }
      return;
    }
    if (!ServiceArea.contains(position.latitude, position.longitude)) {
      showErrorSnackBar(context, ServiceArea.outsideAreaMessage);
      return;
    }
    final deliveryFee = ServiceArea.isOutskirts(
      position.latitude,
      position.longitude,
    )
        ? kOutskirtsDeliveryFeeGhs
        : kDeliveryFeeGhs;

    final auth = context.read<AuthController>();
    final userId = auth.session?.user.id ?? '';
    final profilePhone = SupportContact.customerPhoneOrEmpty(
      auth.session?.user.phone,
    );
    final saved = await AppCache.getDeliveryAddress(userId);
    if (!mounted) return;

    var checkoutLine1 = (saved['line1'] ?? '').trim();
    var checkoutCity = (saved['city'] ?? '').trim();
    var checkoutPhone = SupportContact.customerPhoneOrEmpty(
      (saved['phone'] ?? '').trim().isNotEmpty ? saved['phone'] : profilePhone,
    );
    final hasSavedAddress =
        AuthValidators.addressLine(checkoutLine1) == null &&
        AuthValidators.city(checkoutCity) == null &&
        AuthValidators.phone(checkoutPhone) == null;

    if (!hasSavedAddress) {
      final draft = await showModalBottomSheet<_DeliveryAddressDraft>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (ctx) => _NewCustomerAddressSheet(
          initialPhone: profilePhone,
        ),
      );
      if (draft == null || !mounted) return;
      checkoutLine1 = draft.line1;
      checkoutCity = draft.city;
      checkoutPhone = draft.phone;
      if (userId.isNotEmpty) {
        await AppCache.putDeliveryAddress(
          userId: userId,
          line1: checkoutLine1,
          city: checkoutCity,
          phone: checkoutPhone,
        );
      }
    }

    final notesCtrl = TextEditingController();
    // paystack | cash_on_delivery
    var paymentMethod = 'paystack';

    final go = await showDialog<_CheckoutOutcome>(
      context: context,
      useRootNavigator: true,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget payChoice({
            required String value,
            required String title,
            required String subtitle,
          }) {
            final selected = paymentMethod == value;
            return InkWell(
              onTap: () => setDialogState(() => paymentMethod = value),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      color: kCustomerBlue,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
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
            );
          }

          return AlertDialog(
            title: const Text('Checkout & pay'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$checkoutLine1\n$checkoutCity · $checkoutPhone',
                    style: const TextStyle(
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: kOnLight,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesCtrl,
                    style: const TextStyle(color: kOnLight),
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  if (_cartSubtotal != null) ...[
                    _CheckoutAmountRow(
                      label: 'Items',
                      amount: formatMoney(_cartSubtotal),
                    ),
                    _CheckoutAmountRow(
                      label: 'Delivery fee',
                      amount: formatMoney(deliveryFee),
                    ),
                    const _CheckoutAmountRow(
                      label: 'Platform service fee',
                      amount: 'GHS 1',
                    ),
                    const Divider(height: 16),
                    _CheckoutAmountRow(
                      label: 'Total',
                      amount: formatMoney(
                        _cartSubtotal! + deliveryFee + kPlatformServiceFeeGhs,
                      ),
                      bold: true,
                    ),
                    const SizedBox(height: 8),
                  ],
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.location_on_rounded,
                      color: kCustomerBlue,
                    ),
                    title: Text(
                      'Live location required',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      'Turn on your phone\'s location. You cannot checkout without it.',
                      style: TextStyle(color: kOnLightMuted),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Payment method',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  payChoice(
                    value: 'paystack',
                    title: 'Pay with Paystack',
                    subtitle: 'Card · Mobile Money · Bank',
                  ),
                  payChoice(
                    value: 'cash_on_delivery',
                    title: 'Pay on delivery',
                    subtitle: 'Pay cash / MoMo when the order arrives',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, _CheckoutOutcome.cancel),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, _CheckoutOutcome.confirm),
                child: Text(
                  paymentMethod == 'paystack'
                      ? 'Place order & pay'
                      : 'Place order',
                ),
              ),
            ],
          );
        },
      ),
    );
    if (go != _CheckoutOutcome.confirm) {
      notesCtrl.dispose();
      return;
    }

    final selectedPayment = paymentMethod;
    final token = auth.token;
    if (token == null) {
      notesCtrl.dispose();
      return;
    }
    setState(() => _busy = true);
    try {
      final api = CustomerApi(context.read<Dio>());

      final addr = {
        'line1': checkoutLine1,
        'city': checkoutCity,
        'phone': checkoutPhone,
      };

      double? latitude;
      double? longitude;
      latitude = position.latitude;
      longitude = position.longitude;

      if (!ServiceArea.cityIsAllowed(checkoutCity)) {
        if (mounted) showErrorSnackBar(context, ServiceArea.outsideAreaMessage);
        return;
      }
      if (latitude != null &&
          longitude != null &&
          !ServiceArea.contains(latitude, longitude)) {
        if (mounted) showErrorSnackBar(context, ServiceArea.outsideAreaMessage);
        return;
      }
      if (latitude == null || longitude == null) {
        if (mounted) {
          showErrorSnackBar(
            context,
            'Turn on location in Ho so the rider can navigate to you.',
          );
        }
        return;
      }

      final savedVoucher = await AppCache.getVoucherCode(
        token.hashCode.toRadixString(16),
      );
      final checkoutResult = await api.checkout(
        token,
        notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        phone: checkoutPhone,
        voucherCode: savedVoucher,
        shippingAddress: addr,
        latitude: latitude,
        longitude: longitude,
        paymentMethod: selectedPayment,
        deliveryFee: deliveryFee,
        serviceFee: kPlatformServiceFeeGhs,
        vendorCommissionRate: kVendorCommissionRate,
        adminDeliveryShareRate: kAdminDeliveryShareRate,
        riderDeliveryShareRate: kRiderDeliveryShareRate,
        callbackUrl: selectedPayment == 'paystack'
            ? PaystackCheckoutScreen.callbackUrl
            : null,
      );
      if (!mounted) return;

      if (selectedPayment == 'paystack') {
        await _startPaystackPayment(api, token, checkoutResult);
      } else {
        final numbers = orderNumbersFromCheckout(checkoutResult);
        final label = numbers.isEmpty
            ? 'Order placed'
            : numbers.length == 1
            ? 'Order #${numbers.first} placed'
            : 'Orders placed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label — pay on delivery.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      if (!mounted) return;
      await _load();
      context.read<CartController>().refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e.message);
      await _load();
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e.toString());
      await _load();
    } finally {
      notesCtrl.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startPaystackPayment(
    CustomerApi api,
    String token,
    Map<String, dynamic> checkoutResult,
  ) async {
    final orderNumbers = orderNumbersFromCheckout(checkoutResult);
    if (orderNumbers.isEmpty) {
      showErrorSnackBar(
        context,
        'Order placed, but the API did not return an order number for Paystack.',
      );
      return;
    }

    await runPaystackPaymentFlow(
      context: context,
      api: api,
      token: token,
      orderNumber: orderNumbers.first,
      orderNumbers: orderNumbers,
      checkoutOrInitPayload: checkoutResult,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
        decoration: authGradientDecoration(),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BrandHeader(
                title: 'Your cart',
                subtitle: 'Review items before checkout',
              ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  decoration: BoxDecoration(
                    color: kCustomerGray,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
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
                        : _lines.isEmpty
                        ? Center(
                            child: Text(
                              'Cart is empty\nBrowse vendors in Explore.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              if (_busy)
                                const LinearProgressIndicator(minHeight: 2),
                              Expanded(
                                child: RefreshIndicator(
                                  onRefresh: _load,
                                  child: ListView.builder(
                                    physics:
                                        const AlwaysScrollableScrollPhysics(),
                                    padding: const EdgeInsets.all(16),
                                    itemCount: _lines.length,
                                    itemBuilder: (context, i) {
                                      final line = _lines[i];
                                      return Card(
                                        margin: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            12,
                                            8,
                                            8,
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Text(
                                                line.title,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  color: kOnLight,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Qty ${line.quantity} · ${line.priceLabel}',
                                                style: const TextStyle(
                                                  color: kOnLightMuted,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  Text(
                                                    line.lineTotalLabel,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: kCustomerBlue,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  IconButton(
                                                    onPressed: _busy
                                                        || line.quantity <=
                                                            kMinCartItemQuantity
                                                        ? null
                                                        : () => _setQty(
                                                            line,
                                                            line.quantity - 1,
                                                          ),
                                                    icon: const Icon(
                                                      Icons
                                                          .remove_circle_outline,
                                                    ),
                                                  ),
                                                  IconButton(
                                                    onPressed: _busy
                                                      || line.quantity >=
                                                        kMaxCartItemQuantity
                                                        ? null
                                                        : () => _setQty(
                                                            line,
                                                            line.quantity + 1,
                                                          ),
                                                    icon: const Icon(
                                                      Icons.add_circle_outline,
                                                    ),
                                                  ),
                                                  IconButton(
                                                    onPressed: _busy
                                                        ? null
                                                        : () => _remove(line),
                                                    icon: const Icon(
                                                      Icons.delete_outline,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  12,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (_cartRoot['totals_by_currency'] !=
                                            null ||
                                        _cartRoot['totals'] != null ||
                                        _cartRoot['total'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: Text(
                                          prettyTotals(
                                            _cartRoot['totals_by_currency'] ??
                                                _cartRoot['totals'] ??
                                                _cartRoot['total'],
                                          ),
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color: kCustomerBlue,
                                              ),
                                        ),
                                      ),
                                    Row(
                                      children: [
                                        TextButton(
                                          onPressed: _busy ? null : _clear,
                                          child: const Text('Clear cart'),
                                        ),
                                        const Spacer(),
                                        FilledButton(
                                          onPressed: (_busy || _lines.isEmpty)
                                              ? null
                                              : _checkout,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: kCustomerBlue,
                                          ),
                                          child: const Text('Checkout'),
                                        ),
                                      ],
                                    ),
                                  ],
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
    );
  }
}

class _CheckoutAmountRow extends StatelessWidget {
  const _CheckoutAmountRow({
    required this.label,
    required this.amount,
    this.bold = false,
  });

  final String label;
  final String amount;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: kOnLight,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text(amount, style: style),
        ],
      ),
    );
  }
}

class _DeliveryAddressDraft {
  const _DeliveryAddressDraft({
    required this.line1,
    required this.city,
    required this.phone,
  });

  final String line1;
  final String city;
  final String phone;
}

class _NewCustomerAddressSheet extends StatefulWidget {
  const _NewCustomerAddressSheet({required this.initialPhone});

  final String initialPhone;

  @override
  State<_NewCustomerAddressSheet> createState() =>
      _NewCustomerAddressSheetState();
}

class _NewCustomerAddressSheetState extends State<_NewCustomerAddressSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _line1;
  late final TextEditingController _city;
  late final TextEditingController _phone;

  @override
  void initState() {
    super.initState();
    _line1 = TextEditingController();
    _city = TextEditingController(text: 'Ho');
    _phone = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    _line1.dispose();
    _city.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final phone = SupportContact.customerPhoneOrEmpty(_phone.text);
    if (SupportContact.isReservedSupportPhone(_phone.text) || phone.isEmpty) {
      showErrorSnackBar(
        context,
        'Enter your own phone number, not the support line.',
      );
      return;
    }
    Navigator.pop(
      context,
      _DeliveryAddressDraft(
        line1: _line1.text.trim(),
        city: _city.text.trim(),
        phone: phone,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const Text(
                'Delivery address',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: kOnLight,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Where should we drop off this order?',
                style: TextStyle(color: kOnLightMuted, height: 1.35),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _line1,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                style: const TextStyle(color: kOnLight),
                decoration: const InputDecoration(
                  labelText: 'Street address',
                  hintText: 'House number, street, landmark',
                  prefixIcon: Icon(Icons.home_outlined),
                ),
                validator: AuthValidators.addressLine,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _city,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                style: const TextStyle(color: kOnLight),
                decoration: const InputDecoration(
                  labelText: 'City',
                  hintText: 'Ho',
                  prefixIcon: Icon(Icons.location_city_outlined),
                ),
                validator: AuthValidators.city,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                style: const TextStyle(color: kOnLight),
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: '024 123 4567',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: AuthValidators.phone,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(backgroundColor: kCustomerBlue),
                child: const Text('Continue to payment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

