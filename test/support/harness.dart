import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncro_kiosk/src/app/kiosk_app.dart';
import 'package:syncro_kiosk/src/app/kiosk_controller.dart';
import 'package:syncro_kiosk/src/core/http/api_client.dart';
import 'package:syncro_kiosk/src/kiosk/tablet.dart';
import 'package:syncro_kiosk/src/kiosk/tablet_store.dart';

import 'fake_server.dart';

TabletPairing savedPairing() => TabletPairing(
  accessToken: goodToken,
  tabletUuid: 'uuid-1',
  tablet: TabletInfo.fromJson(tabletJson),
);

Future<KioskController> launch(
  WidgetTester tester,
  FakeServer server, {
  TabletStore? store,
  DateTime? today,
  Size size = const Size(1280, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = KioskController(
    client: ApiClient(transport: server),
    store: store ?? MemoryTabletStore(pairing: savedPairing()),
    appVersion: '1.0.0+1',
  );
  await tester.pumpWidget(
    SyncroKioskApp(
      controller: controller,
      today: today ?? DateTime(2026, 10, 9),
    ),
  );
  await tester.runAsync(controller.start);
  await settle(tester);
  return controller;
}

/// Lets fake requests finish and frames settle without waiting on
/// never-ending spinners.
Future<void> settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> finish(WidgetTester tester, KioskController c) async {
  c.dispose();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Future<void> typeDigits(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.byKey(Key('key-$d')));
    await tester.pump();
  }
}

Future<void> signInWithPin(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('wake-sign-in')));
  await settle(tester);
  await typeDigits(tester, '1234');
  await tester.tap(find.byKey(const Key('sign-in-next')));
  await tester.pump();
  expect(find.text('PIN'), findsOneWidget);
  await typeDigits(tester, '9876');
  await tester.tap(find.byKey(const Key('sign-in-next')));
  await settle(tester, 10);
}

/// Loads the Roboto files that ship with the Flutter SDK, so layout tests
/// measure text as the Android tablet draws it rather than with the test
/// font (where every letter is a full square and text is about twice as
/// wide). Returns false when the SDK fonts cannot be found.
Future<bool> loadDeviceFonts() async {
  final roots = <String>[
    if (Platform.environment['FLUTTER_ROOT'] != null)
      Platform.environment['FLUTTER_ROOT']!,
  ];
  // .../flutter/bin/cache/artifacts/engine/<platform>/flutter_tester
  final exe = File(Platform.resolvedExecutable).parent;
  roots.add(exe.parent.parent.parent.parent.parent.path);
  for (final root in roots) {
    final dir = Directory('$root/bin/cache/artifacts/material_fonts');
    if (!dir.existsSync()) continue;
    final loader = FontLoader('Roboto');
    for (final name in const [
      'Roboto-Regular.ttf',
      'Roboto-Medium.ttf',
      'Roboto-Bold.ttf',
      'Roboto-Black.ttf',
    ]) {
      final file = File('${dir.path}/$name');
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
    return true;
  }
  return false;
}
