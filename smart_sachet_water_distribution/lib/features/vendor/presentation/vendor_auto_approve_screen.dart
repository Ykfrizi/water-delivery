import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:smart_sachet_water_distribution/app/theme/app_theme.dart';
import 'package:smart_sachet_water_distribution/app/widgets/app_surface.dart';
import 'package:smart_sachet_water_distribution/features/auth/domain/user_role.dart';
import 'package:smart_sachet_water_distribution/features/auth/presentation/auth_controller.dart';
import 'package:smart_sachet_water_distribution/features/vendor/data/vendor_auto_approve_store.dart';
import 'package:smart_sachet_water_distribution/features/vendor/domain/vendor_auto_approve_schedule.dart';

/// Configure one-time window + weekly hours for automatic order approval.
class VendorAutoApproveScreen extends StatefulWidget {
  const VendorAutoApproveScreen({super.key});

  @override
  State<VendorAutoApproveScreen> createState() =>
      _VendorAutoApproveScreenState();
}

class _VendorAutoApproveScreenState extends State<VendorAutoApproveScreen> {
  late VendorAutoApproveSchedule _draft;
  var _saving = false;
  var _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthController>();
    final store = context.read<VendorAutoApproveStore>();
    final token = auth.session?.token;
    if (token != null) await store.load(token);
    if (!mounted) return;
    setState(() {
      _draft = store.schedule;
      _ready = true;
    });
  }

  String _fmtDateTime(DateTime? dt) {
    if (dt == null) return 'Tap to set';
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d · $hh:$mm';
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final initial = isStart
        ? (_draft.windowStart ?? DateTime.now())
        : (_draft.windowEnd ?? DateTime.now().add(const Duration(hours: 4)));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      _draft = isStart
          ? _draft.copyWith(windowStart: dt)
          : _draft.copyWith(windowEnd: dt);
    });
  }

  Future<void> _pickWeeklyTime({required bool isStart}) async {
    final minutes =
        isStart ? _draft.weeklyStartMinutes : _draft.weeklyEndMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (picked == null || !mounted) return;
    final value = picked.hour * 60 + picked.minute;
    setState(() {
      _draft = isStart
          ? _draft.copyWith(weeklyStartMinutes: value)
          : _draft.copyWith(weeklyEndMinutes: value);
    });
  }

  Future<void> _save() async {
    if (_draft.windowStart != null &&
        _draft.windowEnd != null &&
        !_draft.hasOneTimeWindow) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('One-time window end must be after start.'),
        ),
      );
      return;
    }
    if (_draft.enabled && !_draft.hasAnySchedule) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Set a one-time window and/or weekly hours before enabling.',
          ),
        ),
      );
      return;
    }
    if (_draft.weeklyEnabled && !_draft.hasWeekly) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Weekly schedule needs at least one day and different start/end times.',
          ),
        ),
      );
      return;
    }
    final token = context.read<AuthController>().session?.token;
    if (token == null) return;
    setState(() => _saving = true);
    try {
      await context.read<VendorAutoApproveStore>().save(token, _draft);
      if (!mounted) return;
      final nowActive = _draft.isActiveAt(DateTime.now());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !_draft.enabled
                ? 'Auto-approve schedule saved (currently stopped).'
                : nowActive
                    ? 'Auto-approve is ON now — pending orders will be approved.'
                    : 'Schedule saved — waiting for the next active window.',
          ),
        ),
      );
      Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _stopNow() async {
    final token = context.read<AuthController>().session?.token;
    if (token == null) return;
    setState(() {
      _draft = _draft.copyWith(enabled: false);
      _saving = true;
    });
    try {
      await context.read<VendorAutoApproveStore>().stop(token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Auto-approve stopped.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = vendorAppTheme();
    final accent = roleAccent(UserRole.vendor);
    final active = _ready && _draft.isActiveAt(DateTime.now());

    return Theme(
      data: theme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          body: Container(
            decoration: roleGradientDecoration(UserRole.vendor),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
                    child: Row(
                      children: [
                        HeaderIconButton(
                          icon: Icons.arrow_back_rounded,
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Back',
                        ),
                        const SizedBox(width: 8),
                        const AppLogo(size: 38, showShadow: true),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Auto-approve',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_ready && _draft.enabled)
                          TextButton(
                            onPressed: _saving ? null : _stopNow,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.14),
                            ),
                            child: const Text('Stop'),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: !_ready
                        ? const Center(
                            child: CircularProgressIndicator(color: Colors.white),
                          )
                        : SoftSheet(
                            padding: EdgeInsets.zero,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                              children: [
                                StatusBanner(
                                  active: active,
                                  activeTitle: 'Auto-approve is ON now',
                                  idleTitle: _draft.enabled
                                      ? 'Waiting for the next window'
                                      : 'Auto-approve is stopped',
                                  subtitle: active
                                      ? 'Pending orders are approved automatically.'
                                      : 'Enable and set a valid schedule below.',
                                ),
                                const SizedBox(height: 16),
                                ContentCard(
                                  title: 'Master switch',
                                  subtitle:
                                      'Only runs inside a one-time window and/or weekly hours.',
                                  child: SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    value: _draft.enabled,
                                    title: Text(
                                      _draft.enabled ? 'Enabled' : 'Disabled',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    subtitle: Text(
                                      _draft.hasAnySchedule
                                          ? 'Schedule rules are configured'
                                          : 'Add a schedule first',
                                    ),
                                    onChanged: (v) => setState(
                                      () =>
                                          _draft = _draft.copyWith(enabled: v),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                ContentCard(
                                  title: 'One-time window',
                                  subtitle:
                                      'Approve only between these local times.',
                                  trailing: _draft.hasOneTimeWindow
                                      ? IconButton(
                                          tooltip: 'Clear',
                                          onPressed: () => setState(
                                            () => _draft = _draft.copyWith(
                                              clearWindow: true,
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 20,
                                          ),
                                        )
                                      : null,
                                  child: Column(
                                    children: [
                                      PickerRow(
                                        label: 'Starts',
                                        value: _fmtDateTime(_draft.windowStart),
                                        icon: Icons.event_available_rounded,
                                        onTap: () =>
                                            _pickDateTime(isStart: true),
                                      ),
                                      const SizedBox(height: 10),
                                      PickerRow(
                                        label: 'Ends',
                                        value: _fmtDateTime(_draft.windowEnd),
                                        icon: Icons.event_busy_rounded,
                                        onTap: () =>
                                            _pickDateTime(isStart: false),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                ContentCard(
                                  title: 'Weekly hours',
                                  subtitle:
                                      'Recurring days · overnight ranges supported.',
                                  trailing: Switch(
                                    value: _draft.weeklyEnabled,
                                    onChanged: (v) => setState(
                                      () => _draft =
                                          _draft.copyWith(weeklyEnabled: v),
                                    ),
                                  ),
                                  child: AnimatedOpacity(
                                    duration: const Duration(milliseconds: 220),
                                    opacity: _draft.weeklyEnabled ? 1 : 0.45,
                                    child: IgnorePointer(
                                      ignoring: !_draft.weeklyEnabled,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              for (final day in VendorAutoApproveSchedule
                                                  .weekdayLabels.entries)
                                                FilterChip(
                                                  label: Text(day.value),
                                                  selected: _draft.weeklyDays
                                                      .contains(day.key),
                                                  onSelected: (sel) {
                                                    final next = {
                                                      ..._draft.weeklyDays,
                                                    };
                                                    if (sel) {
                                                      next.add(day.key);
                                                    } else {
                                                      next.remove(day.key);
                                                    }
                                                    setState(
                                                      () => _draft =
                                                          _draft.copyWith(
                                                        weeklyDays: next,
                                                      ),
                                                    );
                                                  },
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          PickerRow(
                                            label: 'Daily start',
                                            value: VendorAutoApproveSchedule
                                                .formatClock(
                                              _draft.weeklyStartMinutes,
                                            ),
                                            icon: Icons.wb_sunny_outlined,
                                            onTap: () =>
                                                _pickWeeklyTime(isStart: true),
                                          ),
                                          const SizedBox(height: 10),
                                          PickerRow(
                                            label: 'Daily end',
                                            value: VendorAutoApproveSchedule
                                                .formatClock(
                                              _draft.weeklyEndMinutes,
                                            ),
                                            icon: Icons.nights_stay_outlined,
                                            onTap: () =>
                                                _pickWeeklyTime(isStart: false),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 22),
                                FilledButton(
                                  onPressed: _saving ? null : _save,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: accent,
                                    minimumSize: const Size.fromHeight(52),
                                  ),
                                  child: _saving
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Text('Save schedule'),
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: _saving || !_draft.enabled
                                      ? null
                                      : _stopNow,
                                  icon: const Icon(Icons.stop_circle_outlined),
                                  label: const Text('Stop auto-approve now'),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
