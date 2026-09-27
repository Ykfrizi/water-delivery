import 'package:flutter_test/flutter_test.dart';
import 'package:smart_sachet_water_distribution/features/vendor/domain/vendor_auto_approve_schedule.dart';

void main() {
  group('VendorAutoApproveSchedule.isActiveAt', () {
    test('enable alone never activates without a schedule', () {
      const s = VendorAutoApproveSchedule(enabled: true);
      expect(s.hasAnySchedule, isFalse);
      expect(s.isActiveAt(DateTime(2026, 8, 9, 12)), isFalse);
    });

    test('one-time window is inclusive start, exclusive end', () {
      final s = VendorAutoApproveSchedule(
        enabled: true,
        windowStart: DateTime(2026, 8, 9, 10),
        windowEnd: DateTime(2026, 8, 9, 12),
      );
      expect(s.isActiveAt(DateTime(2026, 8, 9, 9, 59)), isFalse);
      expect(s.isActiveAt(DateTime(2026, 8, 9, 10)), isTrue);
      expect(s.isActiveAt(DateTime(2026, 8, 9, 11, 59)), isTrue);
      expect(s.isActiveAt(DateTime(2026, 8, 9, 12)), isFalse);
    });

    test('weekly same-day hours only match selected days', () {
      final s = VendorAutoApproveSchedule(
        enabled: true,
        weeklyEnabled: true,
        weeklyDays: {DateTime.monday, DateTime.wednesday},
        weeklyStartMinutes: 9 * 60,
        weeklyEndMinutes: 17 * 60,
      );
      // Monday 2026-08-10
      expect(s.isActiveAt(DateTime(2026, 8, 10, 9)), isTrue);
      expect(s.isActiveAt(DateTime(2026, 8, 10, 17)), isFalse);
      // Tuesday
      expect(s.isActiveAt(DateTime(2026, 8, 11, 12)), isFalse);
    });

    test('overnight weekly continues into next morning', () {
      final s = VendorAutoApproveSchedule(
        enabled: true,
        weeklyEnabled: true,
        weeklyDays: {DateTime.friday},
        weeklyStartMinutes: 22 * 60,
        weeklyEndMinutes: 6 * 60,
      );
      // Friday night
      expect(s.isActiveAt(DateTime(2026, 8, 14, 22, 30)), isTrue);
      // Saturday early morning continues Friday shift
      expect(s.isActiveAt(DateTime(2026, 8, 15, 5, 30)), isTrue);
      expect(s.isActiveAt(DateTime(2026, 8, 15, 6)), isFalse);
      // Saturday night — Saturday not selected
      expect(s.isActiveAt(DateTime(2026, 8, 15, 23)), isFalse);
    });

    test('one-time OR weekly either match activates', () {
      final s = VendorAutoApproveSchedule(
        enabled: true,
        windowStart: DateTime(2026, 8, 9, 8),
        windowEnd: DateTime(2026, 8, 9, 9),
        weeklyEnabled: true,
        weeklyDays: {DateTime.sunday},
        weeklyStartMinutes: 14 * 60,
        weeklyEndMinutes: 16 * 60,
      );
      // Inside one-time (Sunday morning)
      expect(s.isActiveAt(DateTime(2026, 8, 9, 8, 30)), isTrue);
      // Outside one-time, inside weekly
      expect(s.isActiveAt(DateTime(2026, 8, 9, 15)), isTrue);
      // Outside both
      expect(s.isActiveAt(DateTime(2026, 8, 9, 11)), isFalse);
    });

    test('disabled never activates even inside window', () {
      final s = VendorAutoApproveSchedule(
        enabled: false,
        windowStart: DateTime(2026, 8, 9, 8),
        windowEnd: DateTime(2026, 8, 9, 20),
      );
      expect(s.isActiveAt(DateTime(2026, 8, 9, 12)), isFalse);
    });
  });
}
