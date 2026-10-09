import '../../core/format.dart';
import '../../core/http/api_client.dart';
import '../status/employee_status.dart';
import '../timesheets/data/timesheet_api.dart';
import '../timesheets/models/timesheet_entry.dart';

/// A Monday-to-Sunday week (UK working week).
class WeekRange {
  const WeekRange(this.start, this.end);

  final DateTime start;
  final DateTime end;

  String get label => '${shortDay(start)} – ${shortDay(end)}';

  bool contains(DateTime day) {
    final d = dateOnly(day);
    return !d.isBefore(start) && !d.isAfter(end);
  }
}

/// The week before the one containing [today].
WeekRange previousWeek(DateTime today) {
  final day = dateOnly(today);
  final thisMonday = day.subtract(Duration(days: day.weekday - 1));
  final start = thisMonday.subtract(const Duration(days: 7));
  return WeekRange(start, start.add(const Duration(days: 6)));
}

/// "Confirm your hours for (week)": last week's sessions still awaiting the
/// employee's own sign-off.
class TimesheetSignOffTask {
  const TimesheetSignOffTask({required this.week, required this.rows});

  final WeekRange week;

  /// Every row of the week, so the employee sees the whole week.
  final List<TimesheetEntry> rows;

  List<TimesheetEntry> get awaiting =>
      rows.where((row) => row.requiresApproval && row.sessionId > 0).toList();

  List<int> get sessionIds => awaiting.map((row) => row.sessionId).toList();
}

/// Pure rule: a task exists only when the group lets the employee sign their
/// timesheet and at least one of last week's sessions awaits them.
TimesheetSignOffTask? requiredSignOff({
  required MobilePermissions permissions,
  required List<TimesheetEntry> rows,
  required WeekRange week,
}) {
  if (!permissions.signTimeSheet) return null;
  final inWeek = rows.where((row) {
    final date = DateTime.tryParse(row.workDate.trim());
    return date != null && week.contains(date);
  }).toList();
  final task = TimesheetSignOffTask(week: week, rows: inWeek);
  return task.sessionIds.isEmpty ? null : task;
}

/// Loads the task, if any. A refused or failed timesheet read means there is
/// nothing the employee can do here, so they go straight to home; only a
/// session that has ended is passed on.
Future<TimesheetSignOffTask?> loadRequiredSignOff({
  required MobilePermissions permissions,
  required TimesheetApi api,
  required DateTime today,
}) async {
  if (!permissions.signTimeSheet) return null;
  final week = previousWeek(today);
  try {
    final rows = await api.fetch(from: week.start, to: week.end);
    return requiredSignOff(permissions: permissions, rows: rows, week: week);
  } on ApiException catch (e) {
    if (e.isAuthFailure) rethrow;
    return null;
  } catch (_) {
    return null;
  }
}
