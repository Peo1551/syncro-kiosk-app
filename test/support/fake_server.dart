import 'dart:async';
import 'dart:convert';

import 'package:syncro_kiosk/src/core/http/transport.dart';

typedef Handler =
    FutureOr<TransportResponse> Function(TransportRequest request);

/// Answers requests by path. Unknown paths get a 404.
class FakeServer implements HttpTransport {
  final Map<String, Handler> routes = {};
  final List<TransportRequest> requests = [];

  void on(String path, Handler handler) => routes[path] = handler;

  void json(
    String path,
    Object body, {
    int status = 200,
    Map<String, List<String>> headers = const {},
  }) {
    on(
      path,
      (_) => TransportResponse.text(status, jsonEncode(body), headers: headers),
    );
  }

  List<TransportRequest> to(String path) =>
      requests.where((r) => r.uri.path == path).toList();

  @override
  Future<TransportResponse> send(TransportRequest request) async {
    requests.add(request);
    final handler = routes[request.uri.path];
    if (handler == null) {
      return TransportResponse.text(404, '{"ok":false,"error":"Not found"}');
    }
    return handler(request);
  }
}

const tabletJson = {
  'kiosk_tablet_id': 7,
  'tablet_name': 'Front door',
  'company_name': 'Computime',
  'site_id': 3,
  'site_name': 'Head Office',
  'idle_seconds': 45,
  'admin_pin_set': true,
  'server_time_utc': '2026-10-09T10:00:00Z',
};

const goodToken = 'abcdefghijklmnopqrstuvwxyz012345';

/// A server where pairing, heartbeat and sign-in work.
FakeServer workingServer() {
  final server = FakeServer();
  server.json('/kiosk/api/pair.php', {
    'ok': true,
    'access_token': goodToken,
    'tablet': tabletJson,
  });
  server.json('/kiosk/api/heartbeat.php', {'ok': true, 'tablet': tabletJson});
  server.json('/kiosk/api/admin-pin.php', {'ok': true});
  server.json('/kiosk/api/unpair.php', {'ok': true});
  server.json('/kiosk/api/sign-out.php', {'ok': true});
  server.json(
    '/kiosk/api/sign-in.php',
    {
      'ok': true,
      'csrf': 'csrf-1',
      'session': {
        'company_id': 1,
        'employee_id': 42,
        'first_name': 'Sam',
        'last_name': 'Taylor',
      },
      'idle_seconds': 120,
    },
    headers: {
      'set-cookie': ['PHPSESSID=sess-1; path=/; HttpOnly; Secure'],
    },
  );
  return server;
}

/// Employee endpoints for a signed-in employee.
void addEmployeeEndpoints(
  FakeServer server, {
  Map<String, Object?> permissions = const {},
  bool onFlexi = false,
  List<Map<String, Object?>> timesheetRows = const [],
}) {
  server.json('/employee/status-json.php', {
    'ok': true,
    'employee': {
      'employee_id': 42,
      'first_name': 'Sam',
      'last_name': 'Taylor',
      'display_name': 'Sam Taylor',
    },
    'mobile_permissions': {'allow_mobile_login': true, ...permissions},
  });
  server.json('/employee/api/leave-requests.php', {
    'ok': true,
    'groups': [
      {
        'group_id': 'HOL',
        'group_ref': 'HOL',
        'name': 'Holiday',
        'mode': 'DAY',
        'subtypes': [
          {'subtype_id': 5, 'name': 'Annual leave', 'is_default': 1},
        ],
      },
    ],
    'requests': [],
  });
  server.json('/employee/api/upcoming-leave.php', {
    'ok': true,
    'permissions': {'view_team_leave': false, 'view_company_leave': false},
    'team': [],
    'company': [],
  });
  server.json('/employee/api/holiday-summary.php', {
    'ok': true,
    'year_start': '2026-01-01',
    'year_end': '2026-12-31',
    'unit': 'DAYS',
    'total_entitlement': 25,
    'booked': 5,
    'balance': 20,
  });
  server.json(
    '/employee/api/flexi-summary.php',
    onFlexi
        ? {
            'ok': true,
            'on_flexi': true,
            'balance': {'minutes': 90, 'text': '+1:30'},
          }
        : {'ok': true, 'on_flexi': false},
  );
  server.json('/employee/api/timesheets.php', {
    'ok': true,
    'rows': timesheetRows,
  });
  server.json('/employee/api/timesheet-approve.php', {'ok': true});
}
