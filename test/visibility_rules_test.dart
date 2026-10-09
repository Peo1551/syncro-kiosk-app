import 'package:flutter_test/flutter_test.dart';
import 'package:syncro_kiosk/src/core/http/api_client.dart';
import 'package:syncro_kiosk/src/core/session.dart';
import 'package:syncro_kiosk/src/features/flexi/models/flexi_summary.dart';
import 'package:syncro_kiosk/src/features/required_task/timesheet_sign_off.dart';
import 'package:syncro_kiosk/src/features/status/employee_status.dart';
import 'package:syncro_kiosk/src/features/timesheets/data/timesheet_api.dart';
import 'package:syncro_kiosk/src/features/timesheets/models/timesheet_entry.dart';
import 'package:syncro_kiosk/src/features/work/feature_visibility.dart';

import 'support/fake_server.dart';

TimesheetEntry row(String date, {int id = 1, String status = 'payroll', bool? requires}) =>
    TimesheetEntry.fromJson({
      'session_id': id,
      'work_date': date,
      'status': status,
      'requires_approval': ?requires,
    });

void main() {
  group('mobile permissions', () {
    test('missing keys take the server defaults', () {
      final p = MobilePermissions.fromJson(null);
      expect(p.flag('request_holiday'), isTrue);
      expect(p.allowAttachment, isFalse);
      expect(p.viewTimeSheet, isFalse);
      expect(p.signTimeSheet, isFalse);
    });

    test('accepts booleans, numbers and strings', () {
      final p = MobilePermissions.fromJson({
        'view_time_sheet': 1,
        'sign_time_sheet': 'true',
        'allow_attachment': true,
        'request_holiday': '0',
      });
      expect(p.viewTimeSheet, isTrue);
      expect(p.signTimeSheet, isTrue);
      expect(p.allowAttachment, isTrue);
      expect(p.flag('request_holiday'), isFalse);
    });

    test('status-json names and permissions', () {
      final s = EmployeeStatus.fromJson({
        'ok': true,
        'employee': {'first_name': 'Sam', 'last_name': 'Taylor', 'display_name': 'Sam T'},
        'mobile_permissions': {'view_time_sheet': true},
      });
      expect(s.displayName, 'Sam T');
      expect(s.permissions.viewTimeSheet, isTrue);
    });
  });

  group('feature tiles', () {
    final none = MobilePermissions.fromJson(const {});
    const onFlexi = FlexiSummary(onFlexi: true);

    test('leave tiles always show; no clock in or out', () {
      final f = visibleFeatures(permissions: none, flexi: null);
      expect(f, [
        KioskFeature.requestLeave,
        KioskFeature.requestHistory,
        KioskFeature.upcomingLeave,
        KioskFeature.myEntitlement,
      ]);
    });

    test('My Clocking Hub follows view_time_sheet', () {
      final f = visibleFeatures(
        permissions: MobilePermissions.fromJson({'view_time_sheet': true}),
        flexi: null,
      );
      expect(f, contains(KioskFeature.myClockingHub));
    });

    test('My Flexi only when on_flexi is true', () {
      expect(
        visibleFeatures(permissions: none, flexi: onFlexi),
        contains(KioskFeature.myFlexi),
      );
      expect(
        visibleFeatures(permissions: none, flexi: FlexiSummary.notOnFlexi),
        isNot(contains(KioskFeature.myFlexi)),
      );
      expect(
        FlexiSummary.shouldShow(FlexiSummary.fromJson({'ok': true, 'on_flexi': false})),
        isFalse,
      );
    });
  });

  group('required timesheet sign-off', () {
    final signer = MobilePermissions.fromJson({'view_time_sheet': true, 'sign_time_sheet': true});
    final week = previousWeek(DateTime(2026, 10, 9)); // Friday

    test('previous week is Monday to Sunday', () {
      expect(week.start, DateTime(2026, 9, 28));
      expect(week.end, DateTime(2026, 10, 4));
      expect(week.label, 'Mon 28 Sep – Sun 4 Oct');
      expect(previousWeek(DateTime(2026, 10, 5)).start, DateTime(2026, 9, 28));
      expect(previousWeek(DateTime(2026, 10, 4)).start, DateTime(2026, 9, 21));
    });

    test('a session awaiting sign-off last week is a task', () {
      final task = requiredSignOff(
        permissions: signer,
        rows: [
          row('2026-09-29', id: 10, status: 'action', requires: true),
          row('2026-09-30', id: 11),
          row('2026-10-06', id: 12, status: 'action', requires: true),
        ],
        week: week,
      );
      expect(task, isNotNull);
      expect(task!.sessionIds, [10]);
      expect(task.rows, hasLength(2));
    });

    test('status "action" alone also counts', () {
      expect(row('2026-09-29', status: 'action').requiresApproval, isTrue);
    });

    test('nothing awaiting, or no sign_time_sheet, means no task', () {
      expect(
        requiredSignOff(permissions: signer, rows: [row('2026-09-29')], week: week),
        isNull,
      );
      expect(
        requiredSignOff(
          permissions: MobilePermissions.fromJson({'view_time_sheet': true}),
          rows: [row('2026-09-29', status: 'action', requires: true)],
          week: week,
        ),
        isNull,
      );
    });

    test('loads last week from timesheets.php; a refusal means no task', () async {
      final server = workingServer();
      server.json('/employee/api/timesheets.php', {
        'ok': true,
        'rows': [
          {'session_id': 10, 'work_date': '2026-09-29', 'status': 'action', 'requires_approval': true},
        ],
      });
      final api = TimesheetApi(
        session: const AppSession(cookieHeader: 'c=1'),
        client: ApiClient(transport: server),
      );
      final task = await loadRequiredSignOff(
        permissions: signer,
        api: api,
        today: DateTime(2026, 10, 9),
      );
      expect(task!.sessionIds, [10]);
      expect(
        server.requests.single.uri.query,
        'from=2026-09-28&to=2026-10-04',
      );

      server.json('/employee/api/timesheets.php', {
        'ok': false,
        'error': 'Timesheet viewing is not enabled for your mobile app group.',
      }, status: 403);
      expect(
        await loadRequiredSignOff(permissions: signer, api: api, today: DateTime(2026, 10, 9)),
        isNull,
      );

      final calls = server.requests.length;
      expect(
        await loadRequiredSignOff(
          permissions: MobilePermissions.fromJson(const {}),
          api: api,
          today: DateTime(2026, 10, 9),
        ),
        isNull,
      );
      expect(server.requests.length, calls, reason: 'no call without sign_time_sheet');
    });

    test('approve posts each session id', () async {
      final server = workingServer();
      addEmployeeEndpoints(server);
      final api = TimesheetApi(
        session: const AppSession(cookieHeader: 'c=1', csrf: 'k'),
        client: ApiClient(transport: server),
      );
      await api.approve(10);
      final req = server.to('/employee/api/timesheet-approve.php').single;
      expect(req.bodyText, '{"session_id":10}');
      expect(req.headers['x-csrf-token'], 'k');
    });
  });
}
