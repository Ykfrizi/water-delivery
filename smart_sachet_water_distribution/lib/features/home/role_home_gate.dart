import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/features/admin/presentation/admin_shell_screen.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/customer/presentation/customer_shell_screen.dart';
import 'package:smart_sachet_water_distribution/features/vendor/presentation/vendor_pending_approval_screen.dart';
import 'package:smart_sachet_water_distribution/features/vendor/presentation/vendor_shell_screen.dart';

/// Routes signed-in users to the correct shell by persona (handoff: separate tokens per role).
class RoleHomeGate extends StatelessWidget {
  const RoleHomeGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.read<AuthController>().session;
    if (session == null) {
      return const SizedBox.shrink();
    }
    final role = session.role;

    // Theme lives here — not inside shell [State.build] — so the keyboard
    // cannot deactivate [InheritedTheme] while a dialog/page still depends
    // on it (`_dependents.isEmpty`).
    return RoleThemeScope(
      role: role,
      child: switch (role) {
        UserRole.customer => const CustomerShellScreen(),
        UserRole.vendor => session.user.canAccessVendorDashboard
            ? const VendorShellScreen()
            : const VendorPendingApprovalScreen(),
        UserRole.admin => const AdminShellScreen(),
      },
    );
  }
}
