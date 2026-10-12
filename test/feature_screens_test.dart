import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncro_kiosk/src/core/http/transport.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

String iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The busiest Request Leave form: several types, a choice of subtypes,
/// photos allowed and Part day picked (which adds the time buttons).
void addBusyLeaveConfig(FakeServer server) {
  server.json('/employee/api/leave-requests.php', {
    'ok': true,
    'groups': [
      {
        'group_id': 'SICK',
        'group_ref': 'SICK',
        'name': 'Sickness',
        'mode': 'DAY',
        'allow_alternate_subtypes': 1,
        'subtypes': [
          {'subtype_id': 11, 'name': 'Illness', 'is_default': 1},
          {'subtype_id': 12, 'name': 'Medical appointment'},
          {'subtype_id': 13, 'name': 'Dependant care'},
        ],
      },
      {
        'group_id': 'HOL',
        'group_ref': 'HOL',
        'name': 'Holiday',
        'mode': 'DAY',
        'subtypes': [
          {'subtype_id': 5, 'name': 'Annual leave', 'is_default': 1},
        ],
      },
      {
        'group_id': 'TRN',
        'group_ref': 'TRN',
        'name': 'Training',
        'subtypes': [
          {'subtype_id': 21, 'name': 'Course', 'is_default': 1},
        ],
      },
      {
        'group_id': 'OTH',
        'group_ref': 'OTH',
        'name': 'Other',
        'subtypes': [
          {'subtype_id': 31, 'name': 'Other', 'is_default': 1},
        ],
      },
    ],
    'requests': [],
  });
}

Future<void> openTile(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(Key('tile-$name')));
  await settle(tester);
}

void main() {
  setUpAll(() async {
    expect(await loadDeviceFonts(), isTrue, reason: 'Roboto from the SDK');
  });

  testWidgets(
    'Request Leave: subtype chips only when the group allows a choice',
    (tester) async {
      final server = workingServer();
      addEmployeeEndpoints(server);
      addBusyLeaveConfig(server);
      final c = await launch(tester, server);
      await signInWithPin(tester);
      await openTile(tester, 'requestLeave');
      expect(find.byKey(const Key('leave-subtype')), findsOneWidget);
      expect(
        find.text('Take photo'),
        findsNothing,
        reason: 'allow_attachment is off',
      );

      await tester.tap(find.byKey(const Key('leave-group-HOL')));
      await settle(tester);
      expect(find.byKey(const Key('leave-subtype')), findsNothing);
      expect(find.byKey(const Key('leave-daypart-PART')), findsNothing);
      expect(
        find.text(
          'Part day holiday is only available with an hourly holiday entitlement.',
        ),
        findsNothing,
        reason: 'Part day is simply not offered; no note about it',
      );
      await finish(tester, c);
    },
  );

  testWidgets(
    'Request Leave: missing dates are reported in the summary panel',
    (tester) async {
      final server = workingServer();
      addEmployeeEndpoints(server);
      final c = await launch(tester, server);
      await signInWithPin(tester);
      await openTile(tester, 'requestLeave');
      await tester.tap(find.byKey(const Key('leave-submit')));
      await settle(tester);
      expect(find.text('Select a date range.'), findsOneWidget);
      expect(
        server
            .to('/employee/api/leave-requests.php')
            .where((r) => r.method == 'POST'),
        isEmpty,
      );
      await finish(tester, c);
    },
  );

  testWidgets('Request Leave: From date fills To and shows in words', (
    tester,
  ) async {
    final server = workingServer();
    addEmployeeEndpoints(server);
    final c = await launch(tester, server);
    await signInWithPin(tester);
    await openTile(tester, 'requestLeave');
    await tester.tap(find.byKey(const Key('leave-date-from')));
    await settle(tester);
    await tester.tap(find.text('20').first);
    await tester.pump();
    await tester.tap(find.text('OK'));
    await settle(tester);
    final now = DateTime.now();
    final chosen = DateTime(now.year, now.month, 20);
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final words =
        '${days[chosen.weekday - 1]} 20 ${months[chosen.month - 1]} ${chosen.year}';
    // On the From button, the To button and twice in the summary.
    expect(find.text(words), findsNWidgets(4));
    await finish(tester, c);
  });

  testWidgets('Request History: filter chips, details panel and cancel', (
    tester,
  ) async {
    final server = workingServer();
    addEmployeeEndpoints(server);
    server.on('/employee/api/leave-requests.php', (request) {
      if (request.method == 'POST') {
        return TransportResponse.text(200, jsonEncode({'ok': true}));
      }
      return TransportResponse.text(200, jsonEncode(_historyJson));
    });
    final c = await launch(tester, server);
    await signInWithPin(tester);
    await openTile(tester, 'requestHistory');

    expect(find.byKey(const Key('history-row-101')), findsOneWidget);
    expect(find.byKey(const Key('history-row-102')), findsOneWidget);
    expect(find.text('Tap a request to see its details.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('history-filter-rejected')));
    await settle(tester);
    expect(find.byKey(const Key('history-row-101')), findsNothing);
    await tester.tap(find.byKey(const Key('history-row-102')));
    await settle(tester);
    expect(find.byKey(const Key('request-cancel')), findsNothing);

    await tester.tap(find.byKey(const Key('history-filter-pending')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('history-row-101')));
    await settle(tester);
    expect(find.byKey(const Key('request-detail-101')), findsOneWidget);
    expect(find.text('Family visit'), findsOneWidget);
    expect(find.text('2 days'), findsWidgets);
    await tester.tap(find.byKey(const Key('request-cancel')));
    await settle(tester);
    final post = server
        .to('/employee/api/leave-requests.php')
        .where((r) => r.method == 'POST')
        .single;
    expect(
      String.fromCharCodes(post.body!),
      contains('name="action"\r\n\r\ncancel'),
    );
    await finish(tester, c);
  });

  testWidgets('Upcoming Leave: month headings and team tab', (tester) async {
    final now = DateTime.now();
    final soon = DateTime(now.year, now.month, now.day + 10);
    final server = workingServer();
    addEmployeeEndpoints(server, permissions: {'view_team_leave': true});
    server.json('/employee/api/leave-requests.php', {
      'ok': true,
      'groups': [],
      'requests': [
        {
          'request_id': 201,
          'date_from': iso(soon),
          'date_to': iso(soon),
          'group_name': 'Holiday',
          'status': 'approved',
          'status_label': 'Approved',
          'days': 1,
        },
      ],
    });
    server.json('/employee/api/upcoming-leave.php', {
      'ok': true,
      'permissions': {'view_team_leave': true, 'view_company_leave': false},
      'team': [
        {
          'date_from': iso(soon),
          'date_to': iso(soon),
          'group_name': 'Holiday',
          'people': [
            {
              'employee_id': 7,
              'name': 'Alex Green',
              'department_name': 'Stores',
            },
          ],
        },
      ],
      'company': [],
    });
    final c = await launch(tester, server);
    await signInWithPin(tester);
    await openTile(tester, 'upcomingLeave');
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    expect(find.text('${months[soon.month - 1]} ${soon.year}'), findsOneWidget);
    expect(find.byKey(const Key('upcoming-tab-1')), findsOneWidget);
    expect(find.byKey(const Key('upcoming-tab-2')), findsNothing);

    await tester.tap(find.byKey(const Key('upcoming-tab-1')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('upcoming-row-0')));
    await settle(tester);
    expect(find.text('Alex Green'), findsOneWidget);
    expect(find.text('Stores'), findsOneWidget);
    await finish(tester, c);
  });

  testWidgets('My Entitlement: stat cards from the holiday summary', (
    tester,
  ) async {
    final server = workingServer();
    addEmployeeEndpoints(server);
    server.json('/employee/api/holiday-summary.php', {
      'ok': true,
      'year': {'start': '2026-01-01', 'end': '2026-12-31'},
      'entitlement': {'unit': 'DAYS'},
      'totals': {
        'total_entitlement': {'days': 25},
        'taken': {'days': 5},
        'balance': {'days': 20},
      },
    });
    final c = await launch(tester, server);
    await signInWithPin(tester);
    await openTile(tester, 'myEntitlement');
    expect(
      find.descendant(
        of: find.byKey(const Key('stat-allowance')),
        matching: find.text('25.00 days'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('stat-remaining')),
        matching: find.text('20.00 days'),
      ),
      findsOneWidget,
    );
    expect(find.text('Thu 1 Jan 2026 to Thu 31 Dec 2026'), findsOneWidget);
    await finish(tester, c);
  });

  testWidgets('My Clocking Hub: one week at a time, totals on the right', (
    tester,
  ) async {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final server = workingServer();
    addEmployeeEndpoints(
      server,
      permissions: {'view_time_sheet': true},
      timesheetRows: [
        {
          'session_id': 9,
          'work_date': iso(monday),
          'status': 'payroll',
          'clock_in': '08:00',
          'clock_out': '16:30',
          'payable_hhmm': '08:00',
          'payable_minutes': 480,
          'rates': [
            {'label': 'Basic', 'minutes': 480},
          ],
        },
      ],
    );
    final c = await launch(tester, server);
    await signInWithPin(tester);
    await openTile(tester, 'myClockingHub');
    final first = server.to('/employee/api/timesheets.php').last.uri;
    expect(first.queryParameters['from'], iso(monday));
    expect(
      first.queryParameters['to'],
      iso(DateTime(monday.year, monday.month, monday.day + 6)),
    );
    expect(find.byKey(const Key('timesheet-row-0')), findsOneWidget);
    expect(find.byKey(const Key('timesheet-totals')), findsOneWidget);
    final next = tester.widget<OutlinedButton>(
      find.byKey(const Key('week-next')),
    );
    expect(next.onPressed, isNull, reason: 'no going past this week');

    await tester.tap(find.byKey(const Key('timesheet-row-0')));
    await settle(tester);
    expect(find.byKey(const Key('timesheet-day')), findsOneWidget);
    expect(find.text('Basic'), findsOneWidget);

    await tester.tap(find.byKey(const Key('week-prev')));
    await settle(tester);
    final prev = server.to('/employee/api/timesheets.php').last.uri;
    expect(
      prev.queryParameters['from'],
      iso(DateTime(monday.year, monday.month, monday.day - 7)),
    );
    expect(find.byKey(const Key('week-current')), findsOneWidget);
    await finish(tester, c);
  });

  testWidgets('My Flexi: balance card and period table', (tester) async {
    final server = workingServer();
    addEmployeeEndpoints(server, onFlexi: true);
    final c = await launch(tester, server);
    await signInWithPin(tester);
    await openTile(tester, 'myFlexi');
    expect(find.byKey(const ValueKey('flexi-balance')), findsOneWidget);
    expect(find.text('+1:30'), findsWidgets);
    expect(find.byKey(const Key('flexi-section-period')), findsOneWidget);
    await tester.tap(find.byKey(const Key('flexi-section-days')));
    await settle(tester);
    expect(
      find.text('Nothing has been counted in this period yet.'),
      findsOneWidget,
    );
    await finish(tester, c);
  });
}

const _historyJson = {
  'ok': true,
  'groups': [
    {
      'group_id': 'HOL',
      'group_ref': 'HOL',
      'name': 'Holiday',
      'subtypes': [
        {'subtype_id': 5, 'name': 'Annual leave', 'is_default': 1},
      ],
    },
  ],
  'requests': [
    {
      'request_id': 101,
      'date_from': '2026-11-02',
      'date_to': '2026-11-03',
      'group_name': 'Holiday',
      'subtype_name': 'Annual leave',
      'status': 'pending',
      'status_label': 'Pending',
      'days': 2,
      'notes': 'Family visit',
      'is_requested': 1,
    },
    {
      'request_id': 102,
      'date_from': '2026-09-14',
      'date_to': '2026-09-14',
      'group_name': 'Holiday',
      'status': 'rejected',
      'status_label': 'Rejected',
      'days': 1,
      'is_requested': 1,
    },
  ],
};
