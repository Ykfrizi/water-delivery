/// Vendor settings for when new orders are approved automatically.
class VendorAutoApproveSchedule {
  const VendorAutoApproveSchedule({
    this.enabled = false,
    this.windowStart,
    this.windowEnd,
    this.weeklyEnabled = false,
    this.weeklyDays = const {},
    this.weeklyStartMinutes = 9 * 60,
    this.weeklyEndMinutes = 17 * 60,
  });

  /// Master switch — when false, nothing auto-approves.
  final bool enabled;

  /// One-time window (inclusive start, exclusive end).
  final DateTime? windowStart;
  final DateTime? windowEnd;

  /// Recurring weekly hours.
  final bool weeklyEnabled;

  /// Weekdays: DateTime.monday (1) … DateTime.sunday (7).
  final Set<int> weeklyDays;

  /// Minutes from midnight for recurring start/end (local time).
  final int weeklyStartMinutes;
  final int weeklyEndMinutes;

  bool get hasOneTimeWindow =>
      windowStart != null &&
      windowEnd != null &&
      windowStart!.isBefore(windowEnd!);

  bool get hasWeekly =>
      weeklyEnabled &&
      weeklyDays.isNotEmpty &&
      weeklyStartMinutes != weeklyEndMinutes;

  /// True when at least one usable schedule rule is configured.
  bool get hasAnySchedule => hasOneTimeWindow || hasWeekly;

  /// Whether [now] falls in an active approval period.
  ///
  /// Rules:
  /// - [enabled] must be true
  /// - at least one valid one-time and/or weekly schedule must be set
  /// - [now] must match the one-time window **or** the weekly hours (OR)
  /// - Enable alone never means always-on
  bool isActiveAt(DateTime now) {
    if (!enabled || !hasAnySchedule) return false;
    final local = now.toLocal();
    return _oneTimeActive(local) || _weeklyActive(local);
  }

  bool _oneTimeActive(DateTime local) {
    if (!hasOneTimeWindow) return false;
    final start = windowStart!.toLocal();
    final end = windowEnd!.toLocal();
    return !local.isBefore(start) && local.isBefore(end);
  }

  bool _weeklyActive(DateTime local) {
    if (!hasWeekly) return false;
    final mins = local.hour * 60 + local.minute;

    // Same-day range, e.g. 09:00 → 17:00
    if (weeklyStartMinutes < weeklyEndMinutes) {
      if (!weeklyDays.contains(local.weekday)) return false;
      return mins >= weeklyStartMinutes && mins < weeklyEndMinutes;
    }

    // Overnight range, e.g. 22:00 → 06:00:
    // - selected day from start until midnight
    // - following morning until end (counts as continuation of previous day)
    if (mins >= weeklyStartMinutes) {
      return weeklyDays.contains(local.weekday);
    }
    if (mins < weeklyEndMinutes) {
      final prev = local.weekday == DateTime.monday
          ? DateTime.sunday
          : local.weekday - 1;
      return weeklyDays.contains(prev);
    }
    return false;
  }

  /// One-time window ended (and should no longer drive approvals).
  bool get isOneTimeExpired {
    if (!hasOneTimeWindow) return false;
    return !DateTime.now().toLocal().isBefore(windowEnd!.toLocal());
  }

  VendorAutoApproveSchedule copyWith({
    bool? enabled,
    DateTime? windowStart,
    DateTime? windowEnd,
    bool clearWindow = false,
    bool? weeklyEnabled,
    Set<int>? weeklyDays,
    int? weeklyStartMinutes,
    int? weeklyEndMinutes,
  }) {
    return VendorAutoApproveSchedule(
      enabled: enabled ?? this.enabled,
      windowStart: clearWindow ? null : (windowStart ?? this.windowStart),
      windowEnd: clearWindow ? null : (windowEnd ?? this.windowEnd),
      weeklyEnabled: weeklyEnabled ?? this.weeklyEnabled,
      weeklyDays: weeklyDays ?? this.weeklyDays,
      weeklyStartMinutes: weeklyStartMinutes ?? this.weeklyStartMinutes,
      weeklyEndMinutes: weeklyEndMinutes ?? this.weeklyEndMinutes,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'window_start': windowStart?.toIso8601String(),
        'window_end': windowEnd?.toIso8601String(),
        'weekly_enabled': weeklyEnabled,
        'weekly_days': weeklyDays.toList()..sort(),
        'weekly_start_minutes': weeklyStartMinutes,
        'weekly_end_minutes': weeklyEndMinutes,
      };

  /// Fields suitable for PUT /vendor/profile (best-effort backend sync).
  Map<String, dynamic> toProfilePayload() => {
        'auto_approve_enabled': enabled,
        'auto_approve_starts_at': windowStart?.toIso8601String(),
        'auto_approve_ends_at': windowEnd?.toIso8601String(),
        'auto_approve_weekly_enabled': weeklyEnabled,
        'auto_approve_weekly_days': weeklyDays.toList()..sort(),
        'auto_approve_weekly_start_minutes': weeklyStartMinutes,
        'auto_approve_weekly_end_minutes': weeklyEndMinutes,
      };

  factory VendorAutoApproveSchedule.fromJson(Map<String, dynamic> json) {
    DateTime? parseDt(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString())?.toLocal();
    }

    bool asBool(dynamic v) {
      if (v == true || v == 1) return true;
      final s = v?.toString().trim().toLowerCase();
      return s == '1' || s == 'true' || s == 'yes' || s == 'on';
    }

    final daysRaw = json['weekly_days'] ?? json['auto_approve_weekly_days'];
    final days = <int>{};
    Iterable<dynamic> dayItems = const [];
    if (daysRaw is List) {
      dayItems = daysRaw;
    } else if (daysRaw is String && daysRaw.trim().isNotEmpty) {
      dayItems = daysRaw.split(RegExp(r'[,;\s]+'));
    }
    for (final d in dayItems) {
      final n = int.tryParse(d.toString());
      if (n != null && n >= 1 && n <= 7) days.add(n);
    }

    int minutes(dynamic v, int fallback) {
      final n = int.tryParse(v?.toString() ?? '');
      if (n == null) return fallback;
      return n.clamp(0, 24 * 60 - 1);
    }

    return VendorAutoApproveSchedule(
      enabled: asBool(json['enabled']) || asBool(json['auto_approve_enabled']),
      windowStart: parseDt(
        json['window_start'] ?? json['auto_approve_starts_at'],
      ),
      windowEnd: parseDt(
        json['window_end'] ?? json['auto_approve_ends_at'],
      ),
      weeklyEnabled: asBool(json['weekly_enabled']) ||
          asBool(json['auto_approve_weekly_enabled']),
      weeklyDays: days,
      weeklyStartMinutes: minutes(
        json['weekly_start_minutes'] ??
            json['auto_approve_weekly_start_minutes'],
        9 * 60,
      ),
      weeklyEndMinutes: minutes(
        json['weekly_end_minutes'] ?? json['auto_approve_weekly_end_minutes'],
        17 * 60,
      ),
    );
  }

  static String formatClock(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  static const weekdayLabels = <int, String>{
    DateTime.monday: 'Mon',
    DateTime.tuesday: 'Tue',
    DateTime.wednesday: 'Wed',
    DateTime.thursday: 'Thu',
    DateTime.friday: 'Fri',
    DateTime.saturday: 'Sat',
    DateTime.sunday: 'Sun',
  };
}
