import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/brand.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/welcome_auth_screen.dart';
import 'package:smart_sachet_water_distribution/features/home/role_home_gate.dart';

class SmartSachetApp extends StatelessWidget {
  const SmartSachetApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuild MaterialApp only when the auth boundary changes. A new [key]
    // discards the old navigator (and any login/register routes) cleanly,
    // avoiding InheritedWidget `_dependents.isEmpty` crashes from tearing
    // down a nested navigator while Provider dependents are still rebuilding.
    final boundary = context.select<AuthController, String>((auth) {
      if (!auth.bootstrapComplete) return 'boot';
      if (auth.session == null) return 'guest';
      return 'signed-in';
    });

    return MaterialApp(
      key: ValueKey<String>(boundary),
      title: AppBrand.name,
      debugShowCheckedModeBanner: false,
      theme: customerAppTheme(),
      home: switch (boundary) {
        'boot' => const _BootSplash(),
        'signed-in' => const RoleHomeGate(),
        _ => const WelcomeAuthScreen(),
      },
    );
  }
}

class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: authGradientDecoration(),
        child: const SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandMark(),
                SizedBox(height: 28),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: Colors.white,
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
