import '../../../config/app_config.dart';
import '../../../core/http/api_client.dart';
import '../../../core/session.dart';
import '../models/timesheet_entry.dart';

class TimesheetApi {
  const TimesheetApi({required AppSession session, required ApiClient client})
    : _session = session,
      _client = client;

  final AppSession _session;
  final ApiClient _client;

  Future<List<TimesheetEntry>> fetch({
    required DateTime from,
    required DateTime to,
  }) async {
    final path =
        '${AppConfig.timesheetsPath}?from=${_fmtDate(from)}&to=${_fmtDate(to)}';
    final json = await _client.getJson(
      path: path,
      cookieHeader: _session.cookieHeader,
    );
    final rows = json['rows'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => TimesheetEntry.fromJson(row.cast<String, dynamic>()))
        .where((row) => row.sessionId > 0 || row.workDate.trim().isNotEmpty)
        .toList();
  }

  /// Signs off one session awaiting the employee's confirmation. The server
  /// moves it from 'action' to 'payroll' (timesheet-approve.php).
  Future<void> approve(int sessionId) async {
    final json = await _client.postJsonBody(
      path: AppConfig.timesheetApprovePath,
      cookieHeader: _session.cookieHeader,
      csrfToken: _session.csrf,
      body: {'session_id': sessionId},
    );
    if (json['ok'] != true) {
      throw ApiException(
        (json['error'] ?? json['message'] ?? 'Could not confirm your hours.')
            .toString(),
      );
    }
  }

  String _fmtDate(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
