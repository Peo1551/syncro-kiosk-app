import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncro_kiosk/src/kiosk/kiosk_service.dart';

import 'support/fake_server.dart';
import 'support/harness.dart';

/// Stands in for MainActivity's kiosk channel.
class FakeAndroidKiosk {
  FakeAndroidKiosk({this.owner = false, this.state = 'none'});

  bool owner;
  String state;
  final calls = <String>[];

  Map<String, Object?> get status => {
    'lockTaskActive': state != 'none',
    'lockTaskPermitted': owner,
    'lockState': state,
    'isDeviceOwner': owner,
  };

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
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
        if (owner) state = 'none';
        return status;
      case 'resumeKioskMode':
        if (owner) state = 'locked';
        return status;
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
    });

    test('older reply with only lockTaskActive counts as pinned', () {
      final s = KioskStatus.fromAndroid({'lockTaskActive': true});
      expect(s.lockState, KioskLockState.pinned);
    });

    test('empty reply is off and not owner', () {
      final s = KioskStatus.fromAndroid(null);
      expect(s.isDeviceOwner, isFalse);
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
      expect(find.text('Off'), findsOneWidget);
      expect(
        find.text(
          'To lock this tablet fully, set it up as a dedicated kiosk (see setup guide).',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('admin-exit-kiosk')), findsNothing);
      expect(find.byKey(const Key('admin-release-tablet')), findsNothing);
      await tester.tap(find.byKey(const Key('admin-pin-tablet')));
      await settleKiosk(tester);
      expect(fake.count('startLockTask'), 1);
      expect(find.text('Screen pinning'), findsOneWidget);
      expect(find.byKey(const Key('admin-pin-tablet')), findsNothing);
      await tester.tap(find.byKey(const Key('admin-back')));
      await settleKiosk(tester);
      expect(fake.count('resumeKioskMode'), 0);
      expect(fake.count('exitKioskMode'), 0);
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

      await tester.tap(find.byKey(const Key('admin-exit-kiosk')));
      await settleKiosk(tester);
      expect(fake.state, 'none');
      expect(find.text('Off'), findsOneWidget);
      expect(find.byKey(const Key('admin-exit-kiosk')), findsNothing);
      // Still in settings and not re-locked.
      await settle(tester, 20);
      expect(fake.count('resumeKioskMode'), 0);
      expect(fake.state, 'none');

      await tester.tap(find.byKey(const Key('admin-back')));
      await settleKiosk(tester);
      expect(fake.count('resumeKioskMode'), 1);
      expect(fake.state, 'locked');
      await finish(tester, c);
    });

    testWidgets('dedicated tablet: release asks first', (tester) async {
      final fake = installFake(FakeAndroidKiosk(owner: true, state: 'locked'));
      final c = await launch(tester, workingServer());
      await openSettings(tester);

      await tester.tap(find.byKey(const Key('admin-release-tablet')));
      await settleKiosk(tester);
      expect(find.text('Release this tablet?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('admin-release-cancel')));
      await settleKiosk(tester);
      expect(fake.count('releaseDeviceOwner'), 0);

      await tester.tap(find.byKey(const Key('admin-release-tablet')));
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
}
