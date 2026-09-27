import 'package:flutter/material.dart';
import 'package:smart_sachet_water_distribution/app/brand.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';

/// Frosted panel used on gradient backgrounds.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.borderRadius = 20,
    this.opacity = 0.14,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double borderRadius;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    return Material(
      color: Colors.white.withValues(alpha: opacity),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Soft white content sheet that sits over a gradient.
class SoftSheet extends StatelessWidget {
  const SoftSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 18, 16, 24),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 0,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: kOnLight),
        child: IconTheme.merge(
          data: const IconThemeData(color: kOnLightMuted),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Compact tonal icon button for gradient headers.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = IconButton.filledTonal(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.16),
        foregroundColor: Colors.white,
      ),
      icon: Icon(icon),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Filter chip on gradient headers. White fill + dark ink so labels stay
/// readable whether or not the chip is selected.
class HeaderFilterChip extends StatelessWidget {
  const HeaderFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.accent,
    this.showCheckmark = true,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final Color? accent;
  final bool showCheckmark;

  @override
  Widget build(BuildContext context) {
    final ink = accent ?? Theme.of(context).colorScheme.primary;
    final color = selected ? ink : kOnLight;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: showCheckmark,
      checkmarkColor: ink,
      backgroundColor: Colors.white,
      selectedColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      side: BorderSide(
        color: selected ? ink : const Color(0x33000000),
        width: selected ? 1.6 : 1,
      ),
    );
  }
}

/// App logo asset — used everywhere for brand consistency.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 40,
    this.radius,
    this.showShadow = false,
  });

  static const assetPath = 'assets/branding/app_icon.png';

  final double size;
  final double? radius;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? size * 0.22;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        assetPath,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => ColoredBox(
          color: roleAccent(UserRole.customer),
          child: Icon(
            Icons.water_drop_rounded,
            color: Colors.white,
            size: size * 0.55,
          ),
        ),
      ),
    );
  }
}

/// Brand wordmark used on welcome / splash / headers.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.light = true,
    this.compact = false,
    this.showTagline = true,
    this.logoOnly = false,
  });

  final bool light;
  final bool compact;
  final bool showTagline;
  final bool logoOnly;

  @override
  Widget build(BuildContext context) {
    final color = light ? Colors.white : const Color(0xFF0D161C);
    final logo = AppLogo(size: compact ? 36 : 52, showShadow: !compact);
    if (logoOnly) return logo;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        SizedBox(width: compact ? 10 : 14),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppBrand.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                  height: 1.05,
                  fontSize: compact ? 17 : 24,
                ),
              ),
              if (!compact && showTagline)
                Text(
                  'Clean water, delivered',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color.withValues(alpha: 0.78),
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Shared gradient page header with logo + title row.
class BrandHeader extends StatelessWidget {
  const BrandHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.showBrandName = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showBrandName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppLogo(size: 42, showShadow: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showBrandName)
                  Text(
                    AppBrand.name,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                ],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Live status banner for schedule / activity states.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.active,
    required this.activeTitle,
    required this.idleTitle,
    this.subtitle,
    this.trailing,
  });

  final bool active;
  final String activeTitle;
  final String idleTitle;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final bg = active ? const Color(0xFFE8F8EF) : const Color(0xFFFFF4E5);
    final fg = active ? const Color(0xFF1B5E20) : const Color(0xFFE65100);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: fg.withValues(alpha: 0.12)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 6, 10, 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: fg.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            active ? Icons.bolt_rounded : Icons.schedule_rounded,
            color: fg,
          ),
        ),
        title: Text(
          active ? activeTitle : idleTitle,
          style: TextStyle(fontWeight: FontWeight.w800, color: fg),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: TextStyle(color: fg.withValues(alpha: 0.85)),
              ),
        trailing: trailing,
      ),
    );
  }
}

/// White content card with optional title row.
class ContentCard extends StatelessWidget {
  const ContentCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 14),
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title!,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 14),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Tappable date/time row used in schedules.
class PickerRow extends StatelessWidget {
  const PickerRow({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
