import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncro_kiosk/src/features/work/request_sent_page.dart';
import 'package:syncro_kiosk/src/kiosk/tablet_store.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

void main() {
  testWidgets('pair screen: 6-digit keypad pairs and shows the wake screen', (
    tester,
  ) async {
    final server = workingServer();
    final store = MemoryTabletStore();
    final c = await launch(tester, server, store: store);
    expect(find.text('Pair this tablet'), findsOneWidget);
    expect(
      find.text(
        'In Syncro Connect, open Settings › Syncro Kiosk and choose Pair a tablet.',
      ),
      findsOneWidget,
    );
    await typeDigits(tester, '12345');
    await tester.tap(find.byKey(const Key('pair-submit')));
    await tester.pump();
    expect(find.text('Enter the 6-digit pairing code.'), findsOneWidget);
    await typeDigits(tester, '6');
    await tester.tap(find.byKey(const Key('pair-submit')));
    await settle(tester);
    expect(find.text('Computime · Head Office'), findsOneWidget);
    expect(find.text('Tap your card or touch here to sign in'), findsOneWidget);
    expect(store.pairing, isNotNull);
    await finish(tester, c);
  });

  testWidgets('pair screen shows the server error inline', (tester) async {
    final server = workingServer();
    server.json('/kiosk/api/pair.php', {
      'ok': false,
      'code': 'KIOSK_CODE_INVALID',
      'error': 'That pairing code is wrong or has expired.',
    }, status: 401);
    final c = await launch(tester, server, store: MemoryTabletStore());
    await typeDigits(tester, '000000');
    await tester.tap(find.byKey(const Key('pair-submit')));
    await settle(tester);
    expect(
      find.text('That pairing code is wrong or has expired.'),
      findsOneWidget,
    );
    await finish(tester, c);
  });

  testWidgets('sign in with clock number and PIN, see home, sign out', (
    tester,
  ) async {
    final server = workingServer();
    addEmployeeEndpoints(server);
    final c = await launch(tester, server);
    await signInWithPin(tester);
    expect(find.text('Sam Taylor'), findsOneWidget);
    expect(find.text('ST'), findsOneWidget);
    expect(find.textContaining('Signing out in 1:'), findsOneWidget);
    expect(find.byKey(const Key('tile-requestLeave')), findsOneWidget);
    expect(find.byKey(const Key('tile-requestHistory')), findsOneWidget);
    expect(find.byKey(const Key('tile-upcomingLeave')), findsOneWidget);
    expect(find.byKey(const Key('tile-myEntitlement')), findsOneWidget);
    expect(find.byKey(const Key('tile-myClockingHub')), findsNothing);
    expect(find.byKey(const Key('tile-myFlexi')), findsNothing);
    expect(find.textContaining('Clock in'), findsNothing);
    expect(find.textContaining('Clock out'), findsNothing);

    await tester.tap(find.byKey(const Key('sign-out')));
    await settle(tester);
    expect(find.text("You're signed out"), findsOneWidget);
    expect(server.to('/kiosk/api/sign-out.php'), hasLength(1));
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    expect(find.text('Tap your card or touch here to sign in'), findsOneWidget);
    await finish(tester, c);
  });

  testWidgets('sign-in error is shown inline', (tester) async {
    final server = workingServer();
    server.json('/kiosk/api/sign-in.php', {
      'ok': false,
      'code': 'KIOSK_PIN_WRONG',
      'error': 'Clock number or PIN is not right.',
    }, status: 401);
    final c = await launch(tester, server);
    await signInWithPin(tester);
    expect(find.text('Clock number or PIN is not right.'), findsOneWidget);
    expect(find.text('Tap your card'), findsOneWidget);
    await finish(tester, c);
  });

  testWidgets('flexi and timesheet tiles follow the group and flexi-summary', (
    tester,
  ) async {
    final server = workingServer();
    addEmployeeEndpoints(
      server,
      permissions: {'view_time_sheet': true},
      onFlexi: true,
    );
    final c = await launch(tester, server);
    await signInWithPin(tester);
    expect(find.byKey(const Key('tile-myClockingHub')), findsOneWidget);
    expect(find.byKey(const Key('tile-myFlexi')), findsOneWidget);

    await tester.tap(find.byKey(const Key('tile-requestLeave')));
    await settle(tester);
    expect(find.text('Leave type'), findsOneWidget);
    expect(find.text('Holiday'), findsWidgets);
    expect(
      find.text('Take photo'),
      findsNothing,
      reason: 'allow_attachment is off',
    );
    await tester.tap(find.byKey(const Key('page-back')));
    await settle(tester);
    expect(find.text('What would you like to do?'), findsOneWidget);
    await finish(tester, c);
  });

  testWidgets(
    'countdown pill turns amber in the last 15 seconds and signs out at zero',
    (tester) async {
      final server = workingServer();
      addEmployeeEndpoints(server);
      final c = await launch(tester, server);
      await signInWithPin(tester);
      Color pillBorder() {
        final box = tester.widget<AnimatedContainer>(
          find.byKey(const Key('idle-pill')),
        );
        return ((box.decoration! as BoxDecoration).border! as Border).top.color;
      }

      expect(pillBorder(), isNot(const Color(0xFFF59E0B)));
      await tester.pump(Duration(seconds: c.idle.remaining.value - 12));
      await tester.pump();
      expect(find.text('Signing out in 0:12'), findsOneWidget);
      expect(pillBorder(), const Color(0xFFF59E0B));
      await tester.pump(const Duration(seconds: 12));
      await settle(tester);
      expect(find.text("You're signed out"), findsOneWidget);
      await finish(tester, c);
    },
  );

  testWidgets('required task: Continue is locked until hours are confirmed', (
    tester,
  ) async {
    final server = workingServer();
    addEmployeeEndpoints(
      server,
      permissions: {'view_time_sheet': true, 'sign_time_sheet': true},
      timesheetRows: [
        {
          'session_id': 77,
          'work_date': '2026-09-29',
          'status': 'action',
          'requires_approval': true,
          'clock_in': '08:00',
          'clock_out': '16:30',
          'payable_hhmm': '08:00',
        },
      ],
    );
    final c = await launch(tester, server);
    await signInWithPin(tester);
    expect(
      find.text('Confirm your hours for Mon 28 Sep – Sun 4 Oct'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('tile-requestLeave')), findsNothing);
    final cont = tester.widget<FilledButton>(
      find.byKey(const Key('task-continue')),
    );
    expect(cont.onPressed, isNull);

    await tester.tap(find.byKey(const Key('task-confirm')));
    await settle(tester);
    expect(
      server.to('/employee/api/timesheet-approve.php').single.bodyText,
      '{"session_id":77}',
    );
    expect(find.text('Thank you. Your hours are confirmed.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('task-continue')));
    await settle(tester);
    expect(find.byKey(const Key('tile-requestLeave')), findsOneWidget);
    await finish(tester, c);
  });

  testWidgets('required task: Something is wrong goes on to home', (
    tester,
  ) async {
    final server = workingServer();
    addEmployeeEndpoints(
      server,
      permissions: {'view_time_sheet': true, 'sign_time_sheet': true},
      timesheetRows: [
        {
          'session_id': 77,
          'work_date': '2026-09-30',
          'status': 'action',
          'requires_approval': true,
        },
      ],
    );
    final c = await launch(tester, server);
    await signInWithPin(tester);
    await tester.tap(find.byKey(const Key('task-wrong')));
    await settle(tester);
    expect(find.byKey(const Key('tile-requestLeave')), findsOneWidget);
    expect(server.to('/employee/api/timesheet-approve.php'), isEmpty);
    await finish(tester, c);
  });

  testWidgets('no app access: sign-in shows the server reason', (tester) async {
    final server = workingServer();
    addEmployeeEndpoints(server);
    server.json('/employee/status-json.php', {
      'ok': false,
      'message':
          'This account no longer has mobile app access. Please speak to your manager.',
    }, status: 403);
    final c = await launch(tester, server);
    await signInWithPin(tester);
    expect(
      find.textContaining('no longer has mobile app access'),
      findsOneWidget,
    );
    expect(c.session, isNull);
    expect(server.to('/kiosk/api/sign-out.php'), hasLength(1));
    await finish(tester, c);
  });

  testWidgets('admin: PIN then settings, back to kiosk', (tester) async {
    final server = workingServer();
    final c = await launch(tester, server);
    await tester.tap(find.byKey(const Key('wake-settings')));
    await settle(tester);
    expect(find.text('Tablet settings'), findsOneWidget);
    await typeDigits(tester, '1234');
    await tester.tap(find.byKey(const Key('admin-pin-submit')));
    await settle(tester);
    expect(find.text('Computime'), findsOneWidget);
    expect(find.text('Front door'), findsOneWidget);
    expect(find.text('Head Office'), findsOneWidget);
    expect(find.text('1.0.0+1'), findsOneWidget);
    expect(find.byKey(const Key('admin-unpair')), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin-back')));
    await settle(tester);
    expect(find.text('Tap your card or touch here to sign in'), findsOneWidget);
    await finish(tester, c);
  });

  testWidgets('admin: unpair asks for the PIN again and returns to Pair', (
    tester,
  ) async {
    final server = workingServer();
    final store = MemoryTabletStore(pairing: savedPairing());
    final c = await launch(tester, server, store: store);
    await tester.tap(find.byKey(const Key('wake-settings')));
    await settle(tester);
    await typeDigits(tester, '1234');
    await tester.tap(find.byKey(const Key('admin-pin-submit')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('admin-unpair')));
    await settle(tester);
    expect(find.text('Unpair this tablet'), findsOneWidget);
    await typeDigits(tester, '1234');
    await tester.tap(find.byKey(const Key('admin-pin-submit')));
    await settle(tester);
    expect(server.to('/kiosk/api/unpair.php'), hasLength(1));
    expect(store.pairing, isNull);
    expect(find.text('Pair this tablet'), findsOneWidget);
    await finish(tester, c);
  });

  testWidgets('unlicensed tablet shows the blocking screen', (tester) async {
    final server = workingServer();
    server.json('/kiosk/api/heartbeat.php', {
      'ok': false,
      'code': 'KIOSK_UNLICENSED',
      'error': 'Not active.',
    }, status: 403);
    final c = await launch(tester, server);
    await settle(tester);
    expect(
      find.text('Syncro Kiosk is not active for this company'),
      findsOneWidget,
    );
    await finish(tester, c);
  });

  testWidgets('a sent leave request ends on Request sent, then signs out', (
    tester,
  ) async {
    final server = workingServer();
    addEmployeeEndpoints(server);
    final c = await launch(tester, server);
    await signInWithPin(tester);
    await tester.tap(find.byKey(const Key('tile-requestLeave')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('leave-date-from')));
    await settle(tester);
    await tester.tap(find.text('20').first);
    await tester.pump();
    await tester.tap(find.text('OK'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('leave-submit')));
    await settle(tester);
    final create = server
        .to('/employee/api/leave-requests.php')
        .where((r) => r.method == 'POST')
        .single;
    expect(create.headers['x-csrf-token'], 'csrf-1');
    expect(create.headers['cookie'], 'PHPSESSID=sess-1');
    expect(
      String.fromCharCodes(create.body!),
      contains('name="action"\r\n\r\ncreate'),
    );
    expect(find.text('Request sent'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    await settle(tester);
    expect(find.text("You're signed out"), findsOneWidget);
    expect(c.session, isNull);
    await finish(tester, c);
  });

  testWidgets('request sent: auto sign-out countdown from 8', (tester) async {
    var signedOut = 0;
    var other = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RequestSentPage(
          onDoSomethingElse: () => other++,
          onSignOut: () => signedOut++,
        ),
      ),
    );
    expect(find.text('Request sent'), findsOneWidget);
    expect(find.text('Sign out now (8)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Sign out now (5)'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(signedOut, 1);
    expect(other, 0);
  });

  testWidgets('request sent: Do something else stops the countdown', (
    tester,
  ) async {
    var signedOut = 0;
    var other = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RequestSentPage(
          onDoSomethingElse: () => other++,
          onSignOut: () => signedOut++,
        ),
      ),
    );
    await tester.tap(find.text('Do something else'));
    await tester.pump(const Duration(seconds: 10));
    expect(other, 1);
    expect(signedOut, 0);
    unawaited(Future<void>.value());
  });
}
