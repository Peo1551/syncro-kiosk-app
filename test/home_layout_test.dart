// The signed-in home on the real tablet (1920x1200 px at each density, with
// system bars): the greeting, the at-a-glance strip and the tile grid must
// fill the screen with no scrolling, no cut-off text and no gaps, for 4, 5
// and 6 tiles, and every tile must open its page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncro_kiosk/src/core/format.dart';

import 'feature_screens_test.dart' show iso;
import 'support/fake_server.dart';
import 'support/harness.dart';
import 'tablet_layout_test.dart' show addTabletData, weekOfClockings;

class _Case {
  const _Case(
    this.name,
    this.tiles, {
    this.clocking = false,
    this.flexi = false,
  });
  final String name;
  final List<String> tiles;
  final bool clocking;
  final bool flexi;
}

const _base = ['requestHistory', 'upcomingLeave', 'myEntitlement'];

const _cases = [
  _Case('4 tiles', _base),
  _Case('5 tiles with Clocking Hub', [
    ..._base,
    'myClockingHub',
  ], clocking: true),
  _Case('5 tiles with Flexi', [..._base, 'myFlexi'], flexi: true),
  _Case(
    '6 tiles',
    [..._base, 'myClockingHub', 'myFlexi'],
    clocking: true,
    flexi: true,
  ),
];

const _pageTitles = {
  'requestLeave': 'Request Leave',
  'requestHistory': 'Request History',
  'upcomingLeave': 'Upcoming Leave',
  'myEntitlement': 'My Entitlement',
  'myClockingHub': 'My Clocking Hub',
  'myFlexi': 'My Flexi',
};

void main() {
  setUpAll(() async {
    expect(await loadDeviceFonts(), isTrue, reason: 'Roboto from the SDK');
  });

  for (final device in tabletSetups) {
    for (final layout in _cases) {
      testWidgets('home with ${layout.name} on ${device.name}', (tester) async {
        final now = DateTime.now();
        final monday = DateTime(
          now.year,
          now.month,
          now.day - (now.weekday - 1),
        );
        final server = workingServer();
        addEmployeeEndpoints(
          server,
          permissions: {if (layout.clocking) 'view_time_sheet': true},
          onFlexi: layout.flexi,
          timesheetRows: weekOfClockings(monday),
        );
        addTabletData(server);
        final c = await launchOn(tester, server, device);
        await signInWithPin(tester);
        final where = 'home, ${layout.name}';

        // Greeting and the at-a-glance figures from the fake data.
        expect(find.textContaining('Sam'), findsWidgets);
        expect(find.byKey(const Key('home-greeting')), findsOneWidget);
        String stat(String id) => tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(Key('stat-$id-value')),
                matching: find.byType(Text),
              ),
            )
            .data!;
        expect(stat('holiday'), '7.50 days');
        expect(
          stat('next-leave'),
          shortDay(DateTime(now.year, now.month, now.day + 20)),
        );
        expect(stat('pending'), '1');
        if (layout.flexi) {
          expect(stat('flexi'), '+1:30');
        } else {
          expect(find.byKey(const Key('stat-flexi')), findsNothing);
        }
        expect(find.text('1 pending'), findsOneWidget);
        expect(find.text('13 approved · 4 rejected'), findsOneWidget);
        expect(find.text('2 in the next 12 months'), findsOneWidget);
        expect(find.text('7.50 days left'), findsOneWidget);
        expect(find.textContaining('Loading'), findsNothing);

        // Exactly the expected tiles, all on screen and tappable.
        final shown = [
          for (final id in _pageTitles.keys)
            if (find.byKey(Key('tile-$id')).evaluate().isNotEmpty) id,
        ];
        expect(shown, ['requestLeave', ...layout.tiles]);
        for (final id in shown) {
          expect(
            find.byKey(Key('tile-$id')).hitTestable(),
            findsOneWidget,
            reason: '$where: $id is not tappable',
          );
        }
        expectNothingScrolls(tester, where: where);
        expectNothingTruncated(tester, where: where);

        // The grid fills the screen: the primary tile reaches near the
        // bottom and the other tiles fill its height and a common width.
        final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
        final primary = tester.getRect(
          find.byKey(const Key('tile-requestLeave')),
        );
        expect(
          primary.bottom,
          greaterThan(screen.height - device.bars.bottom - 40),
          reason: '$where: empty band under the tiles',
        );
        final others = [
          for (final id in layout.tiles)
            tester.getRect(find.byKey(Key('tile-$id'))),
        ];
        double minOf(Iterable<double> v) => v.reduce((a, b) => a < b ? a : b);
        double maxOf(Iterable<double> v) => v.reduce((a, b) => a > b ? a : b);
        expect(minOf(others.map((r) => r.top)), closeTo(primary.top, 1));
        expect(maxOf(others.map((r) => r.bottom)), closeTo(primary.bottom, 1));
        final rightEdge = maxOf(others.map((r) => r.right));
        for (final rowTop in others.map((r) => r.top).toSet()) {
          final rowRight = maxOf(
            others.where((r) => r.top == rowTop).map((r) => r.right),
          );
          expect(rowRight, closeTo(rightEdge, 1), reason: '$where: gap in row');
        }
        expect(rightEdge, lessThanOrEqualTo(screen.width));

        // Every tile opens its page.
        for (final id in shown) {
          await tester.tap(find.byKey(Key('tile-$id')));
          await settle(tester);
          expect(
            tester.widget<Text>(find.byKey(const Key('page-title'))).data,
            _pageTitles[id],
          );
          await tester.tap(find.byKey(const Key('page-back')));
          await settle(tester);
        }

        // Once the Clocking Hub has loaded this week, its tile shows hours.
        if (layout.clocking) {
          expect(find.text('63h this week'), findsOneWidget);
          expectNothingTruncated(tester, where: '$where after Clocking Hub');
        }
        await finish(tester, c);
      });
    }
  }

  testWidgets('history with nothing pending leads with the decisions', (
    tester,
  ) async {
    final server = workingServer();
    addEmployeeEndpoints(server);
    addTabletData(server);
    server.json('/employee/api/leave-requests.php', {
      'ok': true,
      'groups': const [],
      'requests': [
        {
          'request_id': 1,
          'date_from': iso(DateTime.now().add(const Duration(days: 3))),
          'date_to': iso(DateTime.now().add(const Duration(days: 3))),
          'status': 'approved',
          'is_requested': 1,
        },
      ],
    });
    final c = await launch(tester, server);
    await signInWithPin(tester);
    expect(find.textContaining('Loading'), findsNothing);
    expect(find.text('No requests yet'), findsNothing);
    expect(find.text('1 approved · 0 rejected'), findsOneWidget);
    await finish(tester, c);
  });
}
