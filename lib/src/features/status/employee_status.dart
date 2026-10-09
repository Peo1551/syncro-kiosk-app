import '../../config/app_config.dart';
import '../../core/http/api_client.dart';
import '../../core/session.dart';

/// The employee's mobile app group switches, as /employee/status-json.php
/// returns them in mobile_permissions. Missing keys take the server's own
/// defaults (leave_app_mobile_permissions_defaults).
class MobilePermissions {
  const MobilePermissions(this.values);

  final Map<String, bool> values;

  static const Map<String, bool> serverDefaults = {
    'allow_mobile_login': true,
    'request_holiday': true,
    'request_sickness': false,
    'request_absence': false,
    'request_training': false,
    'request_other': false,
    'allow_sub_types': true,
    'allow_attachment': false,
    'view_time_sheet': false,
    'sign_time_sheet': false,
    'view_team_leave': false,
    'view_company_leave': false,
  };

  factory MobilePermissions.fromJson(Object? raw) {
    final values = <String, bool>{...serverDefaults};
    if (raw is Map) {
      raw.forEach((key, value) {
        final parsed = _toBool(value);
        if (parsed != null) values[key.toString()] = parsed;
      });
    }
    return MobilePermissions(values);
  }

  bool flag(String key) => values[key] ?? serverDefaults[key] ?? false;

  bool get allowAttachment => flag('allow_attachment');
  bool get viewTimeSheet => flag('view_time_sheet');
  bool get signTimeSheet => flag('sign_time_sheet');

  static bool? _toBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = (value ?? '').toString().trim().toLowerCase();
    if (text == '1' || text == 'true' || text == 'yes') return true;
    if (text == '0' || text == 'false' || text == 'no') return false;
    return null;
  }
}

class EmployeeStatus {
  const EmployeeStatus({
    required this.firstName,
    required this.lastName,
    required this.displayName,
    required this.permissions,
  });

  final String firstName;
  final String lastName;
  final String displayName;
  final MobilePermissions permissions;

  factory EmployeeStatus.fromJson(Map<String, dynamic> json) {
    final employee = json['employee'] is Map
        ? (json['employee'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    String text(Object? a, Object? b) {
      final first = (a ?? '').toString().trim();
      return first.isNotEmpty ? first : (b ?? '').toString().trim();
    }

    return EmployeeStatus(
      firstName: text(employee['first_name'], json['first_name']),
      lastName: text(employee['last_name'], json['last_name']),
      displayName: text(employee['display_name'], json['display_name']),
      permissions: MobilePermissions.fromJson(json['mobile_permissions']),
    );
  }
}

class EmployeeStatusApi {
  const EmployeeStatusApi({required AppSession session, required ApiClient client})
    : _session = session,
      _client = client;

  final AppSession _session;
  final ApiClient _client;

  Future<EmployeeStatus> fetch() async {
    final json = await _client.getJson(
      path: AppConfig.statusPath,
      cookieHeader: _session.cookieHeader,
    );
    return EmployeeStatus.fromJson(json);
  }
}
