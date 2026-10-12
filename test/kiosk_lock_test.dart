import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncro_kiosk/src/kiosk/kiosk_service.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';
import 'tablet_layout_test.dart' show addTabletData;

/// Stands in for MainActivity's kiosk channel.
class FakeAndroidKiosk {
  FakeAndroidKiosk({
    this.owner = false,
    this.state = 'none',
    this.canReturn = false,
    this.homeApp = false,
  });

  bool owner;
  String state;
  bool suspended = false;
  bool canReturn;
  bool homeApp;
  final calls = <String>[];
  final args = <String, List<Object?>>{};

  Map<String, Object?> get status => {
    'lockTaskActive': state != 'none',
    'lockTaskPermitted': owner,
    'lockState': state,
    'isDeviceOwner': owner,
    'suspended': suspended,
    'canReturn': canReturn,
    'isHomeApp': homeApp,
  };

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    (args[call.method] ??= []).add(call.arguments);
    switch (call.method) {
      case 'status':
        return status;
      case 'isDeviceOwner':
        return owner;
      case 'lockState':
        return state;
      case 'startLockTask':
        state = owner ? 'locked' : 'pinned';
        return status;
      case 'exitKioskMode':
        suspended = true;
        state = 'none';
        return status;
      case 'resumeKioskMode':
        suspended = false;
        state = owner ? 'locked' : 'pinned';
        return status;
      case 'setHomeApp':
        homeApp = (call.arguments as Map)['enabled'] == true;
        return status;
      case 'openOverlaySettings':
        canReturn = true;
        return status;
      case 'isHomeApp':
        return homeApp;
      case 'releaseDeviceOwner':
        if (owner) {
          state = 'none';
          owner = false;
        }
        return status;
    }
    return null;
  }

  int count(String method) => calls.where((c) => c == method).length;
}

FakeAndroidKiosk installFake(FakeAndroidKiosk fake) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  KioskService.isAndroid = () => true;
  final softKiosk = KioskService.softKiosk;
  KioskService.softKiosk = () async {};
  messenger.setMockMethodCallHandler(KioskService.channel, fake.handle);
  addTearDown(() {
    KioskService.softKiosk = softKiosk;
    messenger.setMockMethodCallHandler(KioskService.channel, null);
    KioskService.isAndroid = () => false;
  });
  return fake;
}

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('wake-settings')));
  await settle(tester);
  await typeDigits(tester, '1234');
  await tester.tap(find.byKey(const Key('admin-pin-submit')));
  await settleKiosk(tester);
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pump();
  await tester.tap(find.byKey(Key(key)));
}

/// Platform-channel replies (wake lock, kiosk) need real async time.
Future<void> settleKiosk(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await settle(tester);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KioskStatus.fromAndroid', () {
    test('device owner and locked', () {
      final s = KioskStatus.fromAndroid({
        'isDeviceOwner': true,
        'lockState': 'locked',
      });
      expect(s.isDeviceOwner, isTrue);
      expect(s.lockState, KioskLockState.locked);
      expect(s.lockTaskActive, isTrue);
      expect(s.lockState.label, 'Locked (dedicated device)');
    });

    test('normal tablet with screen pinning', () {
      final s = KioskStatus.fromAndroid({
        'isDeviceOwner': false,
        'lockState': 'pinned',
        'lockTaskActive': true,
      });
      expect(s.isDeviceOwner, isFalse);
      expect(s.lockState.label, 'Screen pinning');
      expect(s.message, contains('set it up as a dedicated kiosk'));
      expect(s.canReturn, isFalse);
      expect(s.isHomeApp, isFalse);
      expect(s.suspended, isFalse);
    });

    test('reopen permission, home screen and exit are read', () {
      final s = KioskStatus.fromAndroid({
        'isDeviceOwner': false,
        'lockState': 'none',
        'suspended': true,
        'canReturn': true,
        'isHomeApp': true,
      });
      expect(s.canReturn, isTrue);
      expect(s.isHomeApp, isTrue);
      expect(s.suspended, isTrue);
      expect(s.message, KioskStatus.exitedMessage);
    });

    test('non-true values count as false', () {
      final s = KioskStatus.fromAndroid({'canReturn': 1, 'isHomeApp': 'yes'});
      expect(s.canReturn, isFalse);
      expect(s.isHomeApp, isFalse);
    });

    test('older reply with only lockTaskActive counts as pinned', () {
      final s = KioskStatus.fromAndroid({'lockTaskActive': true});
      expect(s.lockState, KioskLockState.pinned);
    });

    test('empty reply is off and not owner', () {
      final s = KioskStatus.fromAndroid(null);
      expect(s.isDeviceOwner, isFalse);
      expect(s.canReturn, isFalse);
      expect(s.isHomeApp, isFalse);
      expect(s.lockState, KioskLockState.none);
      expect(s.lockState.label, 'Off');
    });

    test('unknown state parses as none', () {
      expect(KioskLockState.parse('weird'), KioskLockState.none);
    });
  });

  group('KioskService channel wrapper', () {
    test('reads owner and lock state', () async {
      installFake(FakeAndroidKiosk(owner: true, state: 'locked'));
      expect(await KioskService.isDeviceOwner(), isTrue);
      expect(await KioskService.lockState(), KioskLockState.locked);
    });

    test('exit, resume and release on a dedicated tablet', () async {
      final fake = installFake(FakeAndroidKiosk(owner: true, state: 'locked'));
      var s = await KioskService.exitKioskMode();
      expect(s.lockState, KioskLockState.none);
      expect(s.isDeviceOwner, isTrue);
      s = await KioskService.resumeKioskMode();
      expect(s.lockState, KioskLockState.locked);
      s = await KioskService.releaseDeviceOwner();
      expect(s.isDeviceOwner, isFalse);
      expect(s.lockState, KioskLockState.none);
      expect(fake.count('releaseDeviceOwner'), 1);
    });

    test('external activity: begin, then end even when it fails', () async {
      final fake = installFake(FakeAndroidKiosk(state: 'pinned'));
      final value = await KioskService.duringExternalActivity(
        () async => 7,
        unpin: true,
      );
      expect(value, 7);
      expect(fake.args['beginExternalActivity'], [
        {'unpin': true},
      ]);
      expect(fake.count('endExternalActivity'), 1);
      await expectLater(
        KioskService.duringExternalActivity<void>(
          () async => throw StateError('camera'),
        ),
        throwsStateError,
      );
      expect(fake.calls.sublist(fake.calls.length - 2), [
        'beginExternalActivity',
        'endExternalActivity',
      ]);
    });

    test('home screen and reopen permission calls', () async {
      final fake = installFake(FakeAndroidKiosk());
      var s = await KioskService.setHomeApp(true);
      expect(s.isHomeApp, isTrue);
      expect(await KioskService.isHomeApp(), isTrue);
      s = await KioskService.setHomeApp(false);
      expect(s.isHomeApp, isFalse);
      expect(fake.args['setHomeApp'], [
        {'enabled': true},
        {'enabled': false},
      ]);
      s = await KioskService.openReturnPermission();
      expect(s.canReturn, isTrue);
    });

    test('channel failure falls back to not owner', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      KioskService.isAndroid = () => true;
      messenger.setMockMethodCallHandler(
        KioskService.channel,
        (_) async => throw PlatformException(code: 'boom'),
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(KioskService.channel, null);
        KioskService.isAndroid = () => false;
      });
      expect(await KioskService.isDeviceOwner(), isFalse);
      expect(await KioskService.lockState(), KioskLockState.none);
      final s = await KioskService.status();
      expect(s.isDeviceOwner, isFalse);
    });

    test('not Android: never calls the channel', () async {
      final fake = FakeAndroidKiosk(owner: true);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(KioskService.channel, fake.handle);
      addTearDown(
        () => messenger.setMockMethodCallHandler(KioskService.channel, null),
      );
      KioskService.isAndroid = () => false;
      expect(await KioskService.isDeviceOwner(), isFalse);
      await KioskService.exitKioskMode();
      await KioskService.duringExternalActivity(() async {}, unpin: true);
      await KioskService.setAdminOpen(true);
      expect(fake.calls, isEmpty);
    });
  });

  group('tablet settings', () {
    testWidgets('normal tablet: pinning offered, no dedicated controls', (
      tester,
    ) async {
      final fake = installFake(FakeAndroidKiosk());
      final c = await launch(tester, workingServer());
      await openSettings(tester);
      expect(fake.args['setAdminOpen'], [
        {'open': true},
      ]);
      expect(find.text('Off'), findsOneWidget);
      expect(find.text(KioskStatus.dedicatedHint), findsOneWidget);
      // Not pinned but not exited either: the admin can still stop it.
      expect(find.byKey(const Key('admin-exit-kiosk')), findsOneWidget);
      expect(find.byKey(const Key('admin-release-tablet')), findsNothing);
      expect(find.text('Reopen if closed'), findsOneWidget);
      expect(find.text('Needs permission'), findsOneWidget);
      expect(find.text('Home screen'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('Allow kiosk to reopen itself'), findsOneWidget);
      expect(find.text('Make kiosk the home screen'), findsOneWidget);
      await tapKey(tester, 'admin-pin-tablet');
      await settleKiosk(tester);
      expect(fake.count('startLockTask'), 1);
      expect(find.text('Screen pinning'), findsOneWidget);
      expect(find.byKey(const Key('admin-pin-tablet')), findsNothing);
      await tapKey(tester, 'admin-back');
      await settleKiosk(tester);
      expect(fake.count('resumeKioskMode'), 0);
      expect(fake.count('exitKioskMode'), 0);
      expect(fake.args['setAdminOpen'], [
        {'open': true},
        {'open': false},
      ]);
      await finish(tester, c);
    });

    testWidgets('normal tablet: reopen permission and home screen', (
      tester,
    ) async {
      final fake = installFake(FakeAndroidKiosk(state: 'pinned'));
      final c = await launch(tester, workingServer());
      await openSettings(tester);

      await tapKey(tester, 'admin-allow-return');
      await settleKiosk(tester);
      expect(fake.count('openOverlaySettings'), 1);
      expect(find.text('On'), findsOneWidget);
      expect(find.byKey(const Key('admin-allow-return')), findsNothing);

      await tapKey(tester, 'admin-home-app');
      await settleKiosk(tester);
      expect(fake.args['setHomeApp'], [
        {'enabled': true},
      ]);
      expect(find.text('Syncro Kiosk'), findsWidgets);
      expect(find.text('Use normal home screen'), findsOneWidget);

      await tapKey(tester, 'admin-home-app');
      await settleKiosk(tester);
      expect(fake.args['setHomeApp']!.last, {'enabled': false});
      expect(find.text('Make kiosk the home screen'), findsOneWidget);

      // Coming back from Android settings refreshes what is shown.
      fake.homeApp = true;
      final before = fake.count('status');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settleKiosk(tester);
      expect(fake.count('status'), greaterThan(before));
      expect(find.text('Use normal home screen'), findsOneWidget);
      await finish(tester, c);
    });

    testWidgets('normal tablet: exit stays off until return', (tester) async {
      final fake = installFake(FakeAndroidKiosk(state: 'pinned'));
      final c = await launch(tester, workingServer());
      await openSettings(tester);
      await tapKey(tester, 'admin-exit-kiosk');
      await settleKiosk(tester);
      expect(fake.suspended, isTrue);
      expect(find.text(KioskStatus.exitedMessage), findsOneWidget);
      expect(find.byKey(const Key('admin-exit-kiosk')), findsNothing);
      await settle(tester, 20);
      expect(fake.count('resumeKioskMode'), 0);

      await tapKey(tester, 'admin-back');
      await settleKiosk(tester);
      expect(fake.count('resumeKioskMode'), 1);
      expect(fake.state, 'pinned');
      await finish(tester, c);
    });

    testWidgets('dedicated tablet: exit stays unlocked until return', (
      tester,
    ) async {
      final fake = installFake(FakeAndroidKiosk(owner: true, state: 'locked'));
      final c = await launch(tester, workingServer());
      await openSettings(tester);
      expect(find.text('Locked (dedicated device)'), findsOneWidget);
      expect(find.byKey(const Key('admin-kiosk-help')), findsNothing);
      expect(find.byKey(const Key('admin-pin-tablet')), findsNothing);
      expect(find.byKey(const Key('admin-release-tablet')), findsOneWidget);
      expect(find.text('Reopen if closed'), findsNothing);
      expect(find.text('Home screen'), findsNothing);
      expect(find.byKey(const Key('admin-allow-return')), findsNothing);
      expect(find.byKey(const Key('admin-home-app')), findsNothing);

      await tapKey(tester, 'admin-exit-kiosk');
      await settleKiosk(tester);
      expect(fake.state, 'none');
      expect(find.text('Off'), findsOneWidget);
      expect(find.byKey(const Key('admin-exit-kiosk')), findsNothing);
      // Still in settings and not re-locked.
      await settle(tester, 20);
      expect(fake.count('resumeKioskMode'), 0);
      expect(fake.state, 'none');

      await tapKey(tester, 'admin-back');
      await settleKiosk(tester);
      expect(fake.count('resumeKioskMode'), 1);
      expect(fake.state, 'locked');
      await finish(tester, c);
    });

    testWidgets('dedicated tablet: release asks first', (tester) async {
      final fake = installFake(FakeAndroidKiosk(owner: true, state: 'locked'));
      final c = await launch(tester, workingServer());
      await openSettings(tester);

      await tapKey(tester, 'admin-release-tablet');
      await settleKiosk(tester);
      expect(find.text('Release this tablet?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('admin-release-cancel')));
      await settleKiosk(tester);
      expect(fake.count('releaseDeviceOwner'), 0);

      await tapKey(tester, 'admin-release-tablet');
      await settleKiosk(tester);
      await tester.tap(find.byKey(const Key('admin-release-confirm')));
      await settleKiosk(tester);
      expect(fake.count('releaseDeviceOwner'), 1);
      expect(fake.owner, isFalse);
      expect(find.byKey(const Key('admin-release-tablet')), findsNothing);
      expect(find.byKey(const Key('admin-kiosk-help')), findsOneWidget);
      await finish(tester, c);
    });
  });

  testWidgets('leave photo: kiosk told to expect the camera, then not', (
    tester,
  ) async {
    final fake = installFake(FakeAndroidKiosk(state: 'pinned'));
    final server = workingServer();
    addEmployeeEndpoints(server, permissions: {'allow_attachment': true});
    addTabletData(server);
    final c = await launch(tester, server);
    await signInWithPin(tester);
    await tester.tap(find.byKey(const Key('tile-requestLeave')));
    await settle(tester);
    await tapKey(tester, 'leave-group-SICK');
    await settle(tester);
    expect(fake.count('beginExternalActivity'), 0);
    // No camera in a test: the picker fails, and the kiosk must still be
    // told the camera is finished.
    await tapKey(tester, 'leave-photo');
    await settleKiosk(tester);
    expect(fake.args['beginExternalActivity'], [
      {'unpin': true},
    ]);
    expect(fake.count('endExternalActivity'), 1);
    expect(
      fake.calls.indexOf('beginExternalActivity'),
      lessThan(fake.calls.indexOf('endExternalActivity')),
    );
    await finish(tester, c);
  });
}
