import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/core/location/device_location_service.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/cart_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/customer_account_screen.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/customer_cart_screen.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/customer_home_screen.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/customer_orders_screen.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/customer_products_screen.dart';

/// Bottom navigation: Home · Products · Cart · Orders · You
class CustomerShellScreen extends StatefulWidget {
  const CustomerShellScreen({super.key});

  @override
  State<CustomerShellScreen> createState() => _CustomerShellScreenState();
}

class _CustomerShellScreenState extends State<CustomerShellScreen> {
  int _index = 0;
  bool _openEditProfile = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CartController>().refresh();
      const DeviceLocationService().ensureReady(openSettingsIfDisabled: false);
    });
  }

  void _go(int i) {
    if (_index == i && !_openEditProfile) return;
    setState(() {
      _index = i;
      if (i != 4) _openEditProfile = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = roleAccent(UserRole.customer);

    return Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            CustomerHomeScreen(
              key: const PageStorageKey('home'),
              isActive: _index == 0,
              onOpenProducts: () => _go(1),
              onOpenCart: () => _go(2),
              onOpenOrders: () => _go(3),
            ),
            const CustomerProductsScreen(key: PageStorageKey('products')),
            CustomerCartScreen(
              key: const PageStorageKey('cart'),
              isActive: _index == 2,
            ),
            CustomerOrdersScreen(
              key: const PageStorageKey('orders'),
              isActive: _index == 3,
            ),
            CustomerAccountScreen(
              key: const PageStorageKey('account'),
              onOpenProducts: () => _go(1),
              onOpenCart: () => _go(2),
              onOpenOrders: () => _go(3),
              autoOpenEditProfile: _openEditProfile,
              onAutoOpenConsumed: () {
                if (!_openEditProfile) return;
                setState(() => _openEditProfile = false);
              },
            ),
          ],
        ),
        bottomNavigationBar: _CustomerNavBar(
          index: _index,
          accent: accent,
          onSelect: _go,
        ),
    );
  }
}

class _CustomerNavBar extends StatelessWidget {
  const _CustomerNavBar({
    required this.index,
    required this.accent,
    required this.onSelect,
  });

  final int index;
  final Color accent;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final cartCount = context.select<CartController, int>((c) => c.itemCount);

    return NavigationBar(
      selectedIndex: index,
      onDestinationSelected: onSelect,
      backgroundColor: kCustomerBlueDeep,
      indicatorColor: Colors.white.withValues(alpha: 0.18),
      destinations: [
        const NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Home',
          tooltip: 'Customer dashboard',
        ),
        const NavigationDestination(
          icon: Icon(Icons.inventory_2_outlined),
          selectedIcon: Icon(Icons.inventory_2_rounded),
          label: 'Products',
          tooltip: 'All marketplace products',
        ),
        NavigationDestination(
          icon: Badge(
            isLabelVisible: cartCount > 0,
            label: Text('$cartCount'),
            child: const Icon(Icons.shopping_bag_outlined),
          ),
          selectedIcon: Badge(
            isLabelVisible: cartCount > 0,
            label: Text('$cartCount'),
            child: const Icon(Icons.shopping_bag_rounded),
          ),
          label: 'Cart',
          tooltip: 'Your cart',
        ),
        const NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          selectedIcon: Icon(Icons.receipt_long_rounded),
          label: 'Orders',
          tooltip: 'Your orders',
        ),
        const NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded),
          label: 'You',
          tooltip: 'Account',
        ),
      ],
    );
  }
}
