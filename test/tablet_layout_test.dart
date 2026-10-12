// The signed-in screens on the real tablet: 1920x1200 px at the densities it
// runs at, with the system bars showing. Text is measured with Roboto, as on
// the device. Forms must fit without scrolling and no text may be cut off.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'feature_screens_test.dart' show iso;
import 'support/fake_server.dart';
import 'support/harness.dart';

void addTabletData(FakeServer server) {
  final now = DateTime.now();
  final requests = <Map<String, Object?>>[
    {
      'request_id': 1,
      'date_from': iso(DateTime(now.year, now.month, now.day + 20)),
      'date_to': iso(DateTime(now.year, now.month, now.day + 24)),
      'group_name': 'Holiday',
      'subtype_name': 'Annual leave',
      'status': 'approved',
      'status_label': 'Approved',
      'removal_status': 'rejected',
      'removal_status_label': 'Removal Rejected',
      'days': 5,
      'is_requested': 1,
    },
    {
      'request_id': 2,
      'date_from': iso(DateTime(now.year, now.month, now.day + 40)),
      'date_to': iso(DateTime(now.year, now.month, now.day + 40)),
      'group_name': 'Sickness',
      'subtype_name': 'Medical appointment',
      'status': 'pending',
      'status_label': 'Pending',
      'removal_status': 'pending',
      'removal_status_label': 'Removal Pending',
      'days': 0.5,
      'day_part': 'AM',
      'is_requested': 1,
    },
    for (var i = 0; i < 13; i++)
      {
        'request_id': 10 + i,
        'date_from': iso(DateTime(now.year, now.month - 1, 1 + i)),
        'date_to': iso(DateTime(now.year, now.month - 1, 1 + i)),
        'group_name': 'Holiday',
        'status': 'approved',
        'status_label': 'Approved',
        'days': 1,
        'is_requested': 1,
      },
    for (var i = 0; i < 3; i++)
      {
        'request_id': 30 + i,
        'date_from': iso(DateTime(now.year, now.month - 2, 3 + i)),
        'date_to': iso(DateTime(now.year, now.month - 2, 4 + i)),
        'group_name': 'Training',
        'status': 'rejected',
        'status_label': 'Rejected',
        'days': 2,
        'is_requested': 1,
      },
  ];
  server.json('/employee/api/leave-requests.php', {
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
      {
        'group_id': 'SICK',
        'group_ref': 'SICK',
        'name': 'Sickness',
        'allow_alternate_subtypes': 1,
        'subtypes': [
          {'subtype_id': 11, 'name': 'Illness', 'is_default': 1},
          {'subtype_id': 12, 'name': 'Medical appointment'},
          {'subtype_id': 13, 'name': 'Dependant care'},
        ],
      },
      {
        'group_id': 'ABS',
        'group_ref': 'ABS',
        'name': 'Absence',
        'subtypes': [
          {'subtype_id': 41, 'name': 'Absence', 'is_default': 1},
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
    'requests': requests,
  });
  server.json('/employee/api/holiday-summary.php', {
    'ok': true,
    'year': {'start': '2026-01-01', 'end': '2026-12-31'},
    'entitlement': {'unit': 'DAYS'},
    'totals': {
      'total_entitlement': {'days': 25},
      'taken': {'days': 17.5},
      'balance': {'days': 7.5},
    },
  });
}

List<Map<String, Object?>> weekOfClockings(DateTime monday) => [
  for (var i = 0; i < 7; i++)
    {
      'session_id': 100 + i,
      'work_date': iso(DateTime(monday.year, monday.month, monday.day + i)),
      'status': 'action',
      'requires_approval': true,
      'clock_in': '07:5$i',
      'clock_out': '17:30',
      'payable_hhmm': '09:00',
      'payable_minutes': 540,
      'scheduled_minutes': 480,
      'rates': [
        {'label': 'Basic', 'minutes': 480},
        {'label': 'Time and a half', 'minutes': 60},
      ],
    },
];

void main() {
  setUpAll(() async {
    expect(await loadDeviceFonts(), isTrue, reason: 'Roboto from the SDK');
  });

  for (final device in tabletSetups) {
    testWidgets('Request Leave fits on ${device.name}', (tester) async {
      final server = workingServer();
      addEmployeeEndpoints(server, permissions: {'allow_attachment': true});
      addTabletData(server);
      final c = await launchOn(tester, server, device);
      await signInWithPin(tester);
      expectNothingTruncated(tester, where: 'home');
      await tester.tap(find.byKey(const Key('tile-requestLeave')));
      await settle(tester);

      final chips = [
        for (final id in ['HOL', 'SICK', 'ABS', 'TRN', 'OTH'])
          tester.getRect(find.byKey(Key('leave-group-$id'))),
      ];
      expect(
        chips.map((r) => r.top).toSet(),
        hasLength(1),
        reason: 'all leave types on one row',
      );
      expect(
        find.byKey(const Key('leave-submit')).hitTestable(),
        findsOneWidget,
      );
      expectNothingScrolls(tester, where: 'Request Leave (holiday)');
      expectNothingTruncated(tester, where: 'Request Leave (holiday)');
      expect(find.byKey(const Key('leave-daypart-PART')), findsNothing);
      expect(
        find.textContaining('only available with an hourly'),
        findsNothing,
      );

      // The busiest form: subtypes, Part day times and a photo button.
      await tester.tap(find.byKey(const Key('leave-group-SICK')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('leave-daypart-PART')));
      await settle(tester);
      expect(find.byKey(const Key('leave-time-from')), findsOneWidget);
      expect(find.byKey(const Key('leave-subtype-12')), findsOneWidget);
      expect(find.byKey(const Key('leave-photo')), findsOneWidget);
      expect(
        find.byKey(const Key('leave-submit')).hitTestable(),
        findsOneWidget,
      );
      expectNothingScrolls(tester, where: 'Request Leave (busiest)');
      expectNothingTruncated(tester, where: 'Request Leave (busiest)');
      await finish(tester, c);
    });

    testWidgets('leave lists and entitlement on ${device.name}', (
      tester,
    ) async {
      final server = workingServer();
      addEmployeeEndpoints(server);
      addTabletData(server);
      final c = await launchOn(tester, server, device);
      await signInWithPin(tester);

      await tester.tap(find.byKey(const Key('tile-requestHistory')));
      await settle(tester);
      final filters = [
        for (final f in ['all', 'pending', 'approved', 'rejected'])
          tester.getRect(find.byKey(Key('history-filter-$f'))),
      ];
      expect(
        filters.map((r) => r.top).toSet(),
        hasLength(1),
        reason: 'filter chips on one row',
      );
      expect(find.text('All (18)'), findsOneWidget);
      expect(find.text('Removal Rejected'), findsWidgets);
      expectNothingTruncated(tester, where: 'Request History');
      await tester.tap(find.byKey(const Key('history-row-1')));
      await settle(tester);
      expectNothingTruncated(tester, where: 'Request History details');
      await tester.tap(find.byKey(const Key('page-back')));
      await settle(tester);

      await tester.tap(find.byKey(const Key('tile-upcomingLeave')));
      await settle(tester);
      expectNothingTruncated(tester, where: 'Upcoming Leave');
      await tester.tap(find.byKey(const Key('page-back')));
      await settle(tester);

      await tester.tap(find.byKey(const Key('tile-myEntitlement')));
      await settle(tester);
      expect(find.text('Live balance'), findsOneWidget);
      expectNothingScrolls(tester, where: 'My Entitlement');
      expectNothingTruncated(tester, where: 'My Entitlement');
      await finish(tester, c);
    });

    testWidgets('clocking, flexi and hours check on ${device.name}', (
      tester,
    ) async {
      final now = DateTime.now();
      final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
      final server = workingServer();
      addEmployeeEndpoints(
        server,
        permissions: {'view_time_sheet': true},
        onFlexi: true,
        timesheetRows: weekOfClockings(monday),
      );
      addTabletData(server);
      final c = await launchOn(tester, server, device);
      await signInWithPin(tester);
      await tester.tap(find.byKey(const Key('tile-myClockingHub')));
      await settle(tester);
      expect(find.byKey(const Key('timesheet-row-6')), findsOneWidget);
      expectNothingScrolls(tester, where: 'My Clocking Hub');
      expectNothingTruncated(tester, where: 'My Clocking Hub');
      await tester.tap(find.byKey(const Key('timesheet-row-2')));
      await settle(tester);
      expectNothingTruncated(tester, where: 'My Clocking Hub day');
      await tester.tap(find.byKey(const Key('page-back')));
      await settle(tester);

      await tester.tap(find.byKey(const Key('tile-myFlexi')));
      await settle(tester);
      expectNothingTruncated(tester, where: 'My Flexi');
      await finish(tester, c);

      // launch() fixes today at Fri 9 Oct 2026, so the week to confirm is
      // Mon 28 Sep to Sun 4 Oct.
      final lastMonday = DateTime(2026, 9, 28);
      final taskServer = workingServer();
      addEmployeeEndpoints(
        taskServer,
        permissions: {'view_time_sheet': true, 'sign_time_sheet': true},
        timesheetRows: weekOfClockings(lastMonday),
      );
      final c2 = await launchOn(tester, taskServer, device);
      await signInWithPin(tester);
      expect(find.byKey(const Key('required-task-title')), findsOneWidget);
      expect(find.byKey(const Key('task-day-6')), findsOneWidget);
      expectNothingScrolls(tester, where: 'Confirm hours');
      expectNothingTruncated(tester, where: 'Confirm hours');
      await finish(tester, c2);
    });
  }
}
