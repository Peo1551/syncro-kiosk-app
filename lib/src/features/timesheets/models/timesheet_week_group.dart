import 'timesheet_entry.dart';

class TimesheetWeekGroup {
  const TimesheetWeekGroup({
    required this.weekStart,
    required this.entries,
    required this.payableMinutes,
    required this.scheduledMinutes,
    required this.hasCompleteScheduledTarget,
  });

  final DateTime? weekStart;
  final List<TimesheetEntry> entries;
  final int payableMinutes;
  final int scheduledMinutes;
  final bool hasCompleteScheduledTarget;

  DateTime? get weekEnd => weekStart?.add(const Duration(days: 6));

  int get varianceMinutes => payableMinutes - scheduledMinutes;

  String get label {
    final start = weekStart;
    final end = weekEnd;
    if (start == null || end == null) return 'Other dates';
    return 'Week ${_formatDate(start)} - ${_formatDate(end)}';
  }

  String get payableLabel => _formatMinutes(payableMinutes);

  String get scheduledLabel =>
      hasCompleteScheduledTarget ? _formatMinutes(scheduledMinutes) : '--:--';

  String get varianceLabel {
    if (!hasCompleteScheduledTarget) return '--:--';
    if (varianceMinutes == 0) return '00:00';
    final prefix = varianceMinutes > 0 ? '+' : '-';
    return '$prefix${_formatMinutes(varianceMinutes.abs())}';
  }
}

List<TimesheetWeekGroup> groupTimesheetEntriesByWeek(
  Iterable<TimesheetEntry> entries,
) {
  final buckets = <DateTime?, List<TimesheetEntry>>{};
  for (final entry in entries) {
    final date = _parseWorkDate(entry.workDate);
    final weekStart = date?.subtract(
      Duration(days: date.weekday - DateTime.monday),
    );
    buckets.putIfAbsent(weekStart, () => <TimesheetEntry>[]).add(entry);
  }

  final groups = buckets.entries.map((bucket) {
    var payableMinutes = 0;
    var scheduledMinutes = 0;
    var hasCompleteScheduledTarget = true;
    for (final entry in bucket.value) {
      payableMinutes += _payableMinutesForSummary(entry);
      if (entry.hasScheduledTarget) {
        scheduledMinutes += entry.scheduledMinutes;
      } else {
        hasCompleteScheduledTarget = false;
      }
    }
    return TimesheetWeekGroup(
      weekStart: bucket.key,
      entries: List<TimesheetEntry>.unmodifiable(bucket.value),
      payableMinutes: payableMinutes,
      scheduledMinutes: scheduledMinutes,
      hasCompleteScheduledTarget: hasCompleteScheduledTarget,
    );
  }).toList();

  groups.sort((left, right) {
    final leftStart = left.weekStart;
    final rightStart = right.weekStart;
    if (leftStart == null) return rightStart == null ? 0 : 1;
    if (rightStart == null) return -1;
    return rightStart.compareTo(leftStart);
  });
  return groups;
}

DateTime? _parseWorkDate(String raw) {
  final text = raw.trim();
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(text);
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return null;
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

int _payableMinutesForSummary(TimesheetEntry entry) {
  if (entry.payableMinutes > 0) return entry.payableMinutes;
  final match = RegExp(r'^(\d+):(\d{2})$').firstMatch(entry.totalHours.trim());
  if (match == null) return 0;
  final hours = int.tryParse(match.group(1)!);
  final minutes = int.tryParse(match.group(2)!);
  if (hours == null || minutes == null || minutes > 59) return 0;
  return (hours * 60) + minutes;
}

String _formatDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day/$month/${value.year}';
}

String _formatMinutes(int minutes) {
  final safeMinutes = minutes < 0 ? 0 : minutes;
  final hours = safeMinutes ~/ 60;
  final remainder = safeMinutes % 60;
  return '${hours.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
}
