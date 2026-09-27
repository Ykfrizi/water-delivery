import 'package:flutter/material.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/vendor/presentation/vendor_customers_map_screen.dart';
import 'package:smart_sachet_water_distribution/features/vendor/presentation/vendor_orders_screen.dart';
import 'package:smart_sachet_water_distribution/features/vendor/presentation/vendor_overview_screen.dart';
import 'package:smart_sachet_water_distribution/features/vendor/presentation/vendor_products_screen.dart';
import 'package:smart_sachet_water_distribution/features/vendor/presentation/vendor_settlement_screen.dart';
import 'package:smart_sachet_water_distribution/features/vendor/presentation/vendor_wallet_screen.dart';

class VendorShellScreen extends StatefulWidget {
  const VendorShellScreen({super.key});

  @override
  State<VendorShellScreen> createState() => _VendorShellScreenState();
}

class _VendorShellScreenState extends State<VendorShellScreen> {
  int _index = 0;

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final accent = roleAccent(UserRole.vendor);

    return Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            VendorOverviewScreen(
              key: const PageStorageKey('v_overview'),
              onOpenOrders: () => _go(1),
              onOpenMap: () => _go(2),
              onOpenProducts: () => _go(3),
              onOpenWithdrawals: () => _go(4),
            ),
            VendorOrdersScreen(
              key: const PageStorageKey('v_orders'),
              onOpenCustomerMap: () => _go(2),
            ),
            const VendorCustomersMapScreen(key: ValueKey('v_map_live')),
            const VendorProductsScreen(key: PageStorageKey('v_products')),
            const VendorWalletScreen(key: PageStorageKey('v_withdraw')),
            const VendorSettlementScreen(key: PageStorageKey('v_settlement')),
          ],
        ),
        bottomNavigationBar: _VendorNavBar(
          index: _index,
          accent: accent,
          onSelect: _go,
        ),
    );
  }
}

class _VendorNavBar extends StatelessWidget {
  const _VendorNavBar({
    required this.index,
    required this.accent,
    required this.onSelect,
  });

  final int index;
  final Color accent;
  final ValueChanged<int> onSelect;

  static const _items = <({
    IconData icon,
    IconData selectedIcon,
    String label,
  })>[
    (
      icon: Icons.dashboard_outlined,
      selectedIcon: Icons.dashboard_rounded,
      label: 'Home',
    ),
    (
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      label: 'Orders',
    ),
    (
      icon: Icons.person_pin_circle_outlined,
      selectedIcon: Icons.person_pin_circle_rounded,
      label: 'Customers',
    ),
    (
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2_rounded,
      label: 'Products',
    ),
    (
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet_rounded,
      label: 'Withdraw',
    ),
    (
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long_rounded,
      label: 'Settlement',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onSelect(i),
                    child: _VendorNavItem(
                      selected: index == i,
                      accent: accent,
                      icon: _items[i].icon,
                      selectedIcon: _items[i].selectedIcon,
                      label: _items[i].label,
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

class _VendorNavItem extends StatelessWidget {
  const _VendorNavItem({
    required this.selected,
    required this.accent,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final bool selected;
  final Color accent;
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = selected ? accent : const Color(0xFF6B7C86);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: 0.14) : null,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              selected ? selectedIcon : icon,
              color: color,
              size: 24,
            ),
          ),
          if (selected) ...[
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
