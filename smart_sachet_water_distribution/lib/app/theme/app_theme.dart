import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';

/// Customer primary from the home mockup (deep royal blue).
const Color kCustomerBlue = Color(0xFF1565C0);
const Color kCustomerBlueDeep = Color(0xFF0A2E6B);
const Color kCustomerBlueSoft = Color(0xFF42A5F5);
const Color kCustomerGray = Color(0xFFF5F7FA);
const Color kOnLight = Color(0xFF1A1A1A);
const Color kOnLightMuted = Color(0xFF546E7A);

/// Kept so older customer screens still compile.
const Color kCustomerTeal = kCustomerBlue;
const Color kCustomerTealDeep = kCustomerBlueDeep;
const Color kCustomerTealSoft = kCustomerBlueSoft;

/// Vendor — muted forest green (business dashboard, not neon).
const Color kVendorGreen = Color(0xFF0E6B4F);
const Color kVendorGreenDeep = Color(0xFF0B241C);
const Color kVendorGreenSoft = Color(0xFF3E7A65);
const Color kVendorMint = Color(0xFFF3F5F4);

/// Admin — DentaCare navy background + cyan actions.
const Color kAdminCyan = Color(0xFF00D1FF);
const Color kAdminNavy = Color(0xFF0A1628);
const Color kAdminNavyMid = Color(0xFF152A4A);
const Color kAdminCyanSoft = Color(0xFF5CE1F5);
const Color kAdminIce = Color(0xFFE8F4FC);

/// Older admin screens still use these names.
const Color kAdminGreen = kAdminCyan;
const Color kAdminGreenDeep = kAdminNavy;
const Color kAdminGreenSoft = kAdminCyanSoft;

Color roleAccent(UserRole role) => switch (role) {
        UserRole.customer => kCustomerBlue,
      UserRole.vendor => kVendorGreen,
      UserRole.admin => kAdminGreen,
    };

Color roleAccentDeep(UserRole role) => switch (role) {
        UserRole.customer => kCustomerBlueDeep,
      UserRole.vendor => kVendorGreenDeep,
      UserRole.admin => kAdminGreenDeep,
    };

Color roleAccentSoft(UserRole role) => switch (role) {
        UserRole.customer => kCustomerBlueSoft,
      UserRole.vendor => kVendorGreenSoft,
      UserRole.admin => kAdminGreenSoft,
    };

/// Full-bleed role gradient used across homes, auth, and shells.
BoxDecoration roleGradientDecoration(UserRole role) {
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: switch (role) {
        UserRole.customer => const [
            Color(0xFF1E88E5),
            kCustomerBlue,
            kCustomerBlueDeep,
          ],
        UserRole.vendor => const [
            Color(0xFF1A4D3E),
            Color(0xFF12382D),
            kVendorGreenDeep,
          ],
        UserRole.admin => const [
            Color(0xFF3D6FA8),
            kAdminNavyMid,
            kAdminNavy,
          ],
      },
      stops: const [0.0, 0.55, 1.0],
    ),
  );
}

BoxDecoration authGradientDecoration() =>
    roleGradientDecoration(UserRole.customer);

ThemeData? _cachedCustomerTheme;
ThemeData? _cachedVendorTheme;
ThemeData? _cachedAdminTheme;

/// Stable [ThemeData] per role so nested [Theme] widgets do not crash
/// dialogs (`_dependents.isEmpty`).
ThemeData roleAppTheme(UserRole role) => switch (role) {
      UserRole.customer =>
        _cachedCustomerTheme ??= buildAppTheme(accentRole: UserRole.customer),
      UserRole.vendor =>
        _cachedVendorTheme ??= buildAppTheme(accentRole: UserRole.vendor),
      UserRole.admin =>
        _cachedAdminTheme ??= buildAppTheme(accentRole: UserRole.admin),
    };

ThemeData customerAppTheme() => roleAppTheme(UserRole.customer);
ThemeData vendorAppTheme() => roleAppTheme(UserRole.vendor);
ThemeData adminAppTheme() => roleAppTheme(UserRole.admin);

/// Holds a role [Theme] outside screens that [State.setState] on every
/// keystroke. Putting [Theme] in those screens' [State.build] deactivates
/// [InheritedTheme] while the keyboard overlay still depends on it
/// (`_dependents.isEmpty` at framework.dart:6268).
class RoleThemeScope extends StatefulWidget {
  const RoleThemeScope({
    super.key,
    required this.role,
    required this.child,
  });

  final UserRole role;
  final Widget child;

  @override
  State<RoleThemeScope> createState() => _RoleThemeScopeState();
}

class _RoleThemeScopeState extends State<RoleThemeScope> {
  late final ThemeData _theme = roleAppTheme(widget.role);

  @override
  Widget build(BuildContext context) {
    return Theme(data: _theme, child: widget.child);
  }
}

MaterialPageRoute<T> roleThemedRoute<T extends Object?>({
  required UserRole role,
  required WidgetBuilder builder,
}) {
  return MaterialPageRoute<T>(
    builder: (context) => RoleThemeScope(
      role: role,
      child: builder(context),
    ),
  );
}

ThemeData buildAppTheme({UserRole? accentRole}) {
  final role = accentRole ?? UserRole.customer;
  final seed = roleAccent(role);
  final isCustomer = role == UserRole.customer;
  final isVendor = role == UserRole.vendor;
  final isAdmin = role == UserRole.admin;
  final whiteChrome = isCustomer || isAdmin || isVendor;
  final radius = isAdmin || isVendor ? 24.0 : 16.0;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.light,
    primary: seed,
    surface: whiteChrome ? Colors.white : const Color(0xFFF7FBFC),
  ).copyWith(
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: isCustomer
        ? kCustomerGray
        : isVendor
            ? kVendorMint
            : const Color(0xFFF0F7F9),
    surfaceContainerHigh: isCustomer
        ? const Color(0xFFE0E0E0)
            : isAdmin
            ? kAdminIce
            : isVendor
                ? const Color(0xFFE6EBE9)
                : const Color(0xFFE4EEF2),
    onSurface: kOnLight,
    onSurfaceVariant: kOnLightMuted,
    outline: kOnLightMuted,
  );

  TextTheme textTheme;
  try {
    textTheme = GoogleFonts.plusJakartaSansTextTheme().apply(
      bodyColor: const Color(0xFF212121),
      displayColor: const Color(0xFF000000),
    );
  } catch (_) {
    textTheme = ThemeData.light().textTheme.apply(
      bodyColor: const Color(0xFF212121),
      displayColor: const Color(0xFF000000),
    );
  }

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: isVendor
        ? kVendorMint
        : whiteChrome
            ? Colors.white
            : const Color(0xFFE6F1F5),
    dividerColor: const Color(0x14000000),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: isAdmin,
      backgroundColor: isAdmin ? kAdminNavy : scheme.surface,
      foregroundColor: isAdmin ? Colors.white : scheme.onSurface,
      systemOverlayStyle:
          isAdmin ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.3,
        color: isAdmin ? Colors.white : scheme.onSurface,
      ),
      iconTheme: IconThemeData(
        color: isAdmin ? Colors.white : scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: isAdmin ? 2 : 0,
      color: Colors.white,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isAdmin ? 18 : 18),
        side: BorderSide(
          color: isAdmin ? Colors.transparent : const Color(0x10000000),
        ),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isAdmin || isVendor ? 24 : 12),
      ),
      side: const BorderSide(color: Color(0x33000000)),
      backgroundColor: Colors.white,
      selectedColor: Colors.white,
      disabledColor: const Color(0xFFEEEEEE),
      surfaceTintColor: Colors.transparent,
      checkmarkColor: seed,
      labelStyle: textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: kOnLight,
      ),
      secondaryLabelStyle: textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w800,
        color: kOnLight,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      elevation: 0,
      backgroundColor: isCustomer
          ? kCustomerBlueDeep
          : isAdmin
              ? kAdminNavy
              : Colors.white.withValues(alpha: 0.96),
      indicatorColor: isCustomer
          ? Colors.white.withValues(alpha: 0.18)
          : isAdmin
              ? kAdminCyan.withValues(alpha: 0.28)
              : seed.withValues(alpha: 0.16),
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.labelMedium?.copyWith(
          fontSize: isVendor ? 10.5 : null,
          height: isVendor ? 1.0 : null,
          letterSpacing: isVendor ? -0.2 : null,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          color: isCustomer
              ? (selected ? Colors.white : Colors.white70)
              : isAdmin
                  ? (selected ? kAdminCyan : Colors.white70)
                  : (selected ? seed : const Color(0xFF60717A)),
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: isCustomer
              ? (selected ? Colors.white : Colors.white70)
              : isAdmin
                  ? (selected ? kAdminCyan : Colors.white70)
                  : (selected ? seed : const Color(0xFF6B7C86)),
        );
      }),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 4,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      showDragHandle: true,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: seed,
      foregroundColor: isAdmin ? kAdminNavy : Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      iconColor: seed,
      textColor: kOnLight,
      subtitleTextStyle: textTheme.bodyMedium?.copyWith(color: kOnLightMuted),
      titleTextStyle: textTheme.titleMedium?.copyWith(
        color: kOnLight,
        fontWeight: FontWeight.w800,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return seed;
        return Colors.white;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return seed.withValues(alpha: 0.35);
        }
        return const Color(0xFFB0BEC5);
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isCustomer
          ? Colors.white
          : isAdmin
              ? kAdminIce
              : isVendor
                  ? const Color(0xFFF7F8F8)
                  : const Color(0xFFF7FBFC),
      hintStyle: textTheme.bodyMedium?.copyWith(color: kOnLightMuted),
      labelStyle: textTheme.bodyMedium?.copyWith(color: kOnLightMuted),
      prefixIconColor: kOnLightMuted,
      suffixIconColor: kOnLightMuted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: Color(0x14000000)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: seed, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: scheme.error),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: seed,
        foregroundColor: isAdmin ? kAdminNavy : Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isAdmin || isVendor ? 28 : 16),
        ),
        textStyle: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: seed,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        side: BorderSide(color: seed.withValues(alpha: isAdmin ? 0.7 : 0.35)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isAdmin || isVendor ? 28 : 16),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: seed,
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
  );
}
