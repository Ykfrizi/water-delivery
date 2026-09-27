import 'package:flutter/material.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/features/admin/presentation/admin_map_screen.dart';
import 'package:smart_sachet_water_distribution/features/admin/presentation/admin_money_screen.dart';
import 'package:smart_sachet_water_distribution/features/admin/presentation/admin_reports_screen.dart';
import 'package:smart_sachet_water_distribution/features/admin/presentation/admin_vendors_screen.dart';
import 'package:smart_sachet_water_distribution/features/admin/presentation/admin_vouchers_screen.dart';

class AdminShellScreen extends StatefulWidget {
  const AdminShellScreen({super.key});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: IndexedStack(
          index: _index,
          children: const [
            AdminVendorsScreen(),
            AdminMoneyScreen(),
            AdminVouchersScreen(),
            AdminReportsScreen(),
            AdminMapScreen(key: ValueKey('admin_map_live')),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: kAdminNavy,
          indicatorColor: kAdminCyan.withValues(alpha: 0.28),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront_rounded),
              label: 'Vendors',
              tooltip: 'Approve or reject vendors',
            ),
            NavigationDestination(
              icon: Icon(Icons.payments_outlined),
              selectedIcon: Icon(Icons.payments_rounded),
              label: 'Money',
              tooltip: 'Paid Paystack transactions and vendor payouts',
            ),
            NavigationDestination(
              icon: Icon(Icons.local_offer_outlined),
              selectedIcon: Icon(Icons.local_offer_rounded),
              label: 'Vouchers',
              tooltip: 'Create discount voucher numbers',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights_rounded),
              label: 'Reports',
              tooltip: 'Operations report breakdown',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map_rounded),
              label: 'Map',
              tooltip: 'Vendor and customer map',
            ),
          ],
        ),
    );
  }
}
